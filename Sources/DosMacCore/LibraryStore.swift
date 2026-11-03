import Foundation

/// Owns an application-private library. Packages never select host mount paths.
public actor LibraryStore {
    public nonisolated let root: URL
    private let fm = FileManager.default

    public init(root: URL) throws {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: self.root.appendingPathComponent("Programs"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: self.root.appendingPathComponent("Exchange"), withIntermediateDirectories: true)
    }

    public static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DosMac", isDirectory: true)
    }

    public nonisolated var exchangeURL: URL { root.appendingPathComponent("Exchange", isDirectory: true) }
    public nonisolated func programURL(_ id: String) -> URL { root.appendingPathComponent("Programs").appendingPathComponent(id) }

    public func programs() throws -> [InstalledProgram] {
        try fm.contentsOfDirectory(at: root.appendingPathComponent("Programs"), includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .map { url in
                let program = try JSONDecoder().decode(InstalledProgram.self, from: Data(contentsOf: url.appendingPathComponent("installed.json")))
                try program.manifest.validate()
                guard program.id == url.lastPathComponent else { throw DosMacError.invalidPackage("library identifier mismatch") }
                return program
            }.sorted { $0.manifest.title.localizedStandardCompare($1.manifest.title) == .orderedAscending }
    }

    @discardableResult
    public func install(from package: URL) throws -> InstalledProgram {
        try rejectLink(package)
        let manifestURL = package.appendingPathComponent("manifest.json")
        try rejectLink(manifestURL)
        let manifestData = try Data(contentsOf: manifestURL)
        guard manifestData.count <= 64 * 1024 else { throw DosMacError.invalidPackage("manifest is too large") }
        let manifest = try JSONDecoder().decode(PackageManifest.self, from: manifestData)
        try manifest.validate()
        let destination = programURL(manifest.id)
        guard !fm.fileExists(atPath: destination.path) else { throw DosMacError.alreadyInstalled }
        let payload = package.appendingPathComponent("payload", isDirectory: true)
        try validatePayload(payload)
        let entry = payload.appendingPathComponent(manifest.executable.replacingOccurrences(of: "\\", with: "/"))
        guard (try? entry.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            throw DosMacError.invalidPackage("entry point is missing; path case must match payload")
        }
        for disk in manifest.floppyDisks ?? [] {
            guard (try? payload.appendingPathComponent(disk.imagePath).resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                throw DosMacError.invalidPackage("declared floppy image is missing")
            }
        }
        let staging = root.appendingPathComponent("Programs/.install-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        try fm.copyItem(at: payload, to: staging.appendingPathComponent("DriveC"))
        let provenance = package.appendingPathComponent("source-url.txt")
        if fm.fileExists(atPath: provenance.path) {
            try rejectLink(provenance)
            let source = try Data(contentsOf: provenance)
            guard source.count <= 8192 else { throw DosMacError.invalidPackage("source URL metadata too large") }
            try source.write(to: staging.appendingPathComponent("source-url.txt"))
        }
        let installed = InstalledProgram(manifest: manifest, installedAt: Date())
        try JSONEncoder().encode(installed).write(to: staging.appendingPathComponent("installed.json"), options: .atomic)
        try fm.moveItem(at: staging, to: destination)
        return installed
    }

    public func recordLaunch(_ program: InstalledProgram) throws {
        try program.manifest.validate()
        var updated = program
        updated.lastLaunchedAt = Date()
        try JSONEncoder().encode(updated).write(to: programURL(program.id).appendingPathComponent("installed.json"), options: .atomic)
    }

    public func floppyDisks(for program: InstalledProgram) throws -> [FloppyDisk] {
        try program.manifest.validate()
        let drive = programURL(program.id).appendingPathComponent("DriveC")
        let media = drive.appendingPathComponent("MEDIA")
        guard fm.fileExists(atPath: media.path) else { return [] }
        try rejectLink(media)
        let disks: [FloppyDisk]
        if let declared = program.manifest.floppyDisks { disks = declared }
        else {
            // Existing imports need no reinstallation to gain disk controls.
            let files = try fm.contentsOfDirectory(at: media, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.range(of: "^DISK[0-9]{2}\\.IMG$", options: .regularExpression) != nil }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            disks = try files.enumerated().map { index, file in
                guard file.lastPathComponent == String(format: "DISK%02d.IMG", index + 1), index < 32 else { throw DosMacError.invalidPackage("floppy images are not in a contiguous disk order") }
                return FloppyDisk(number: index + 1, imagePath: "MEDIA/\(file.lastPathComponent)", label: "Disk \(index + 1)")
            }
        }
        for disk in disks {
            let image = drive.appendingPathComponent(disk.imagePath)
            try rejectLink(image)
            guard try image.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw DosMacError.invalidPackage("floppy image is missing") }
        }
        return disks
    }

    public func entryPoints(for program: InstalledProgram) throws -> [String] {
        try program.manifest.validate()
        let drive = programURL(program.id).appendingPathComponent("DriveC")
        guard let files = fm.enumerator(at: drive, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return [] }
        var result: [String] = []
        for case let file as URL in files {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { files.skipDescendants(); continue }
            guard values.isRegularFile == true else { continue }
            let relative = file.standardizedFileURL.resolvingSymlinksInPath().pathComponents.dropFirst(drive.standardizedFileURL.resolvingSymlinksInPath().pathComponents.count).joined(separator: "/")
            var candidate = program.manifest
            candidate.executable = relative
            if (try? candidate.validate()) != nil { result.append(relative) }
        }
        return result.sorted()
    }

    public func updateStartup(_ program: InstalledProgram, executable: String, profile: MachineProfile, mode: StartupMode = .program) throws {
        if mode == .program {
            guard try entryPoints(for: program).contains(executable) else { throw DosMacError.invalidPackage("startup program is not on this program's C: drive") }
        }
        var manifest = program.manifest
        manifest.executable = executable
        manifest.profile = profile
        manifest.startupMode = mode
        if mode == .program, manifest.hasWindowsEntryPoint, manifest.title.hasSuffix(" · Setup") {
            manifest.title = String(manifest.title.dropLast(" · Setup".count))
            manifest.summary = "Installed Windows on this program's C: drive. Launch directly without the installation disks."
        }
        try manifest.validate()
        let updated = InstalledProgram(manifest: manifest, installedAt: program.installedAt, lastLaunchedAt: program.lastLaunchedAt)
        try JSONEncoder().encode(updated).write(to: programURL(program.id).appendingPathComponent("installed.json"), options: .atomic)
    }

    private func rejectLink(_ url: URL) throws {
        if try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw DosMacError.invalidPackage("symbolic links are not allowed")
        }
    }

    private func validatePayload(_ payload: URL) throws {
        try rejectLink(payload)
        guard try payload.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw DosMacError.invalidPackage("payload must be a directory") }
        var enumerationError: Error?
        guard let files = fm.enumerator(at: payload, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey], errorHandler: { _, error in
            enumerationError = error
            return false
        }) else { throw DosMacError.invalidPackage("cannot read payload") }
        var total = 0
        var count = 0
        var seen = Set<String>()
        for case let file as URL in files {
            let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true || values.isDirectory == true else { throw DosMacError.invalidPackage("only regular files and directories are allowed") }
            let relative = file.standardizedFileURL.resolvingSymlinksInPath().pathComponents.dropFirst(payload.standardizedFileURL.resolvingSymlinksInPath().pathComponents.count).joined(separator: "/")
            guard seen.insert(relative.lowercased()).inserted else { throw DosMacError.invalidPackage("case-colliding DOS paths") }
            total += values.fileSize ?? 0
            count += 1
            guard total <= 512 * 1024 * 1024, count <= 20_000 else { throw DosMacError.invalidPackage("package exceeds 512 MiB or 20,000 entries") }
        }
        if let enumerationError { throw enumerationError }
    }
}
