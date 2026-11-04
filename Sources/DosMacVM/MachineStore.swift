import Foundation

public actor MachineStore {
    public nonisolated let root: URL
    private let fm = FileManager.default
    public init(root: URL) throws {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }
    public static var defaultRoot: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DosMac/Machines") }
    public nonisolated func directory(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString) }

    public func machines() throws -> [Machine] {
        try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { !$0.lastPathComponent.hasPrefix(".") }.map { directory in
            let machine = try JSONDecoder().decode(Machine.self, from: Data(contentsOf: directory.appendingPathComponent("machine.json")))
            try machine.validate()
            guard directory.lastPathComponent == machine.id.uuidString else { throw VMError.invalid("Machine identity mismatch.") }
            return machine
        }.sorted { $0.createdAt < $1.createdAt }
    }

    public func save(_ machine: Machine) throws {
        try machine.validate()
        try JSONEncoder().encode(machine).write(to: directory(for: machine.id).appendingPathComponent("machine.json"), options: .atomic)
    }

    #if os(macOS)
    public func create(name: String, guest: GuestSystem) async throws -> Machine {
        guard let engine = QEMUInstallation.find() else { throw VMError.engineMissing }
        let machine = Machine(name: name, guest: guest, boot: guest.needsCD ? .cdrom : .floppy)
        try machine.validate()
        let staging = root.appendingPathComponent(".create-\(machine.id.uuidString)")
        try fm.createDirectory(at: staging.appendingPathComponent("Media"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        try await ChildProcess.run(engine.imageTool, arguments: ["create", "-f", "qcow2", staging.appendingPathComponent("disk.qcow2").path, "\(guest.diskMB)M"])
        try JSONEncoder().encode(machine).write(to: staging.appendingPathComponent("machine.json"))
        try fm.moveItem(at: staging, to: directory(for: machine.id))
        return machine
    }
    public func createWindows9x(guest: GuestSystem, iso: URL, bootDisk: URL, productKey: String, acceptedLicense: Bool) async throws -> Machine {
        guard guest.needsCD, let engine = QEMUInstallation.find() else { throw VMError.invalid("Windows 9x requires the managed PC engine.") }
        var machine = Machine(name: guest.title, guest: guest, boot: .floppy)
        machine.sharedDisk = true
        machine.sharedFolder = SharedFolderServer.executable() != nil
        machine.installation = InstallationRecord(recipeID: Windows9xRecipe.id(for: guest), stage: .windowsSetup, message: "Ready to prepare the new Windows hard disk.")
        let staging = root.appendingPathComponent(".create-\(machine.id.uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.createDirectory(at: staging.appendingPathComponent("Media"), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: staging) }
        let raw = staging.appendingPathComponent("system.raw")
        try SharedDiskImage.createSystemImage(at: raw)
        try await ChildProcess.run(engine.imageTool, arguments: ["convert", "-f", "raw", "-O", "qcow2", raw.path, staging.appendingPathComponent("disk.qcow2").path])
        try fm.removeItem(at: raw)
        let values = try iso.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) > 0, (values.fileSize ?? Int.max) <= 1024 * 1024 * 1024 else { throw VMError.invalid("Select a Windows installation ISO up to 1 GiB.") }
        let startup = try FAT12Disk(data: Data(contentsOf: bootDisk))
        for required in ["IO.SYS", "COMMAND.COM", "HIMEM.SYS", "OAKCDROM.SYS", "MSCDEX.EXE", "EBD.CAB", "EXTRACT.EXE", "FDISK.EXE"] {
            guard startup.fileNames.contains(required) else { throw VMError.invalid("Use the English Windows 98 SE OEM startup disk with CD-ROM support.") }
        }
        let boot = MachineMedia(name: "DosMac Windows startup disk", relativePath: "Media/\(UUID().uuidString).img", purpose: .dosSetup)
        let cd = MachineMedia(name: guest.title + " installation CD", relativePath: "Media/\(UUID().uuidString).iso", purpose: .windowsSetup)
        try startup.replacing(files: Windows9xRecipe.bootFiles(guest: guest, productKey: productKey, acceptedLicense: acceptedLicense, sharing: machine.sharedFolder == true)).write(to: staging.appendingPathComponent(boot.relativePath))
        try fm.copyItem(at: iso, to: staging.appendingPathComponent(cd.relativePath))
        machine.floppies = [boot]; machine.cdroms = [cd]
        try machine.validate()
        try Task.checkCancellation()
        try JSONEncoder().encode(machine).write(to: staging.appendingPathComponent("machine.json"))
        try fm.moveItem(at: staging, to: directory(for: machine.id))
        return machine
    }
    #endif

    public func importMedia(_ sources: [URL], into original: Machine, cdrom: Bool, purpose: MediaPurpose? = nil, names: [String]? = nil) throws -> Machine {
        var machine = original
        try machine.validate()
        guard sources.count + (cdrom ? machine.cdroms.count : machine.floppies.count) <= (cdrom ? 16 : 64) else { throw VMError.invalid("Too many disk images.") }
        var copied: [URL] = []
        do {
            if let names, names.count != sources.count { throw VMError.invalid("Media labels must match the image count.") }
            for (index, source) in sources.enumerated() {
                let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                let allowed = cdrom ? ["iso"] : ["img", "ima", "dsk"]
                guard values.isRegularFile == true, values.isSymbolicLink != true, allowed.contains(source.pathExtension.lowercased()), (values.fileSize ?? 0) > 0, (values.fileSize ?? 0) <= (cdrom ? 2 * 1024 * 1024 * 1024 : 3 * 1024 * 1024) else { throw VMError.invalid("Select a raw floppy image (up to 3 MiB) or ISO (up to 2 GiB).") }
                let id = UUID()
                let media = MachineMedia(id: id, name: names?[index] ?? source.lastPathComponent, relativePath: "Media/\(id.uuidString).\(source.pathExtension.lowercased())", purpose: purpose)
                let destination = directory(for: machine.id).appendingPathComponent(media.relativePath)
                try fm.copyItem(at: source, to: destination); copied.append(destination)
                if cdrom { machine.cdroms.append(media) } else { machine.floppies.append(media) }
            }
            try save(machine)
            return machine
        } catch { for path in copied { try? fm.removeItem(at: path) }; throw error }
    }

    public func createExchangeDisk(files sources: [URL], into machine: Machine) throws -> Machine {
        var files: [String: Data] = [:]
        for source in sources {
            let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 1_400_000 else { throw VMError.invalid("Choose regular files that fit on a 1.44 MB exchange floppy.") }
            let name = source.lastPathComponent.uppercased()
            guard name.range(of: "^[A-Z0-9_]{1,8}(\\.[A-Z0-9_]{1,3})?$", options: .regularExpression) != nil, files[name] == nil else { throw VMError.invalid("Exchange filenames must be unique DOS 8.3 names, for example LETTER.DOC.") }
            files[name] = try Data(contentsOf: source)
        }
        let image = try FAT12Disk.make(files: files)
        let temporary = fm.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).img")
        try image.write(to: temporary); defer { try? fm.removeItem(at: temporary) }
        return try importMedia([temporary], into: machine, cdrom: false, purpose: .exchange, names: ["Exchange floppy"])
    }

    /// Call only while stopped or after ejecting this floppy, so guest writes have been flushed.
    public func exportExchangeDisk(_ media: MachineMedia, from machine: Machine, to destination: URL) throws -> URL {
        guard media.purpose == .exchange, machine.floppies.contains(media) else { throw VMError.invalid("Select this machine's exchange floppy.") }
        let disk = try FAT12Disk(data: Data(contentsOf: directory(for: machine.id).appendingPathComponent(media.relativePath)))
        let output = destination.appendingPathComponent("DosMac-Exchange-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: output, withIntermediateDirectories: false)
        do {
            for name in disk.fileNames {
                guard name.range(of: "^[A-Z0-9_]{1,8}(\\.[A-Z0-9_]{1,3})?$", options: .regularExpression) != nil else { throw VMError.invalid("The guest disk contains an unsupported filename.") }
                if let bytes = try disk.file(name) { try bytes.write(to: output.appendingPathComponent(name), options: .withoutOverwriting) }
            }
            return output
        } catch { try? fm.removeItem(at: output); throw error }
    }
}
