#if os(macOS)
import Foundation

public struct QEMUInstallation: Sendable {
    public let executable: URL
    public let imageTool: URL
    public let firmware: URL

    public static func find() -> QEMUInstallation? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("QEMU")
        let candidates: [URL] = [ProcessInfo.processInfo.environment["DOSMAC_QEMU_PATH"].map { URL(fileURLWithPath: $0) }, bundled?.appendingPathComponent("bin/qemu-system-i386"), URL(fileURLWithPath: "/opt/homebrew/bin/qemu-system-i386"), URL(fileURLWithPath: "/usr/local/bin/qemu-system-i386")].compactMap { $0 }
        for executable in candidates where FileManager.default.isExecutableFile(atPath: executable.path) {
            let prefix = executable.deletingLastPathComponent().deletingLastPathComponent()
            let imageTool = prefix.appendingPathComponent("bin/qemu-img")
            let firmware = prefix.appendingPathComponent("share/qemu")
            if FileManager.default.isExecutableFile(atPath: imageTool.path), FileManager.default.fileExists(atPath: firmware.appendingPathComponent("bios-256k.bin").path) {
                return QEMUInstallation(executable: executable, imageTool: imageTool, firmware: firmware)
            }
        }
        return nil
    }
}

enum ChildProcess {
    static func output(_ executable: URL, arguments: [String]) async throws -> Data {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("DosMac-output-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: temporary) }
        let task = Process(); task.executableURL = executable; task.arguments = arguments
        task.standardOutput = handle; task.standardError = FileHandle.nullDevice
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                task.terminationHandler = { process in
                    if process.terminationStatus == 0 { continuation.resume() }
                    else { continuation.resume(throwing: VMError.invalid("\(executable.lastPathComponent) failed (\(process.terminationStatus)).")) }
                }
                do { try task.run() } catch { continuation.resume(throwing: error) }
            }
        } onCancel: { if task.isRunning { task.terminate() } }
        try Task.checkCancellation()
        guard (try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 1024 * 1024 else { throw VMError.invalid("Unexpectedly large process response.") }
        return try Data(contentsOf: temporary)
    }
    static func run(_ executable: URL, arguments: [String]) async throws {
        let task = Process(); task.executableURL = executable; task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                task.terminationHandler = { task in
                    if task.terminationStatus == 0 { continuation.resume() }
                    else { continuation.resume(throwing: VMError.invalid("\(executable.lastPathComponent) failed (\(task.terminationStatus)).")) }
                }
                do { try task.run() } catch { continuation.resume(throwing: error) }
            }
        } onCancel: { if task.isRunning { task.terminate() } }
        try Task.checkCancellation()
    }
}

public enum QEMUArguments {
    public static func make(machine: Machine, directory: URL, runtime: URL, installation: QEMUInstallation, muted: Bool = false, sharingPort: UInt16? = nil) throws -> [String] {
        try machine.validate()
        // JSON arguments preserve commas, spaces, and Unicode in host paths.
        func json(_ value: JSONValue) throws -> String { String(decoding: try JSONEncoder().encode(value), as: UTF8.self) }
        let disk = directory.appendingPathComponent("disk.qcow2").path
        var args = ["-name", machine.name, "-machine", "pc-i440fx-9.2", "-accel", "tcg,thread=single", "-cpu", machine.guest.cpu, "-m", String(machine.guest.memoryMB), "-L", installation.firmware.path,
                    "-display", "none", "-vnc", "unix:\(runtime.appendingPathComponent("display.sock").path)", "-qmp", "stdio", "-monitor", "none", "-serial", "none", "-parallel", "none", "-vga", "cirrus", "-boot", "order=\(machine.boot.qemuOrder),menu=on", "-rtc", "base=localtime"]
        args += ["-blockdev", try json(.object(["driver": .string("qcow2"), "node-name": .string("system-disk"), "file": .object(["driver": .string("file"), "filename": .string(disk)])])), "-device", "ide-hd,drive=system-disk,bus=ide.0,unit=0"]
        if machine.guest.needsCD, machine.installation?.recipeID == Windows9xRecipe.id(for: machine.guest) {
            // DOS's BPB geometry must match SeaBIOS even before Setup installs protected-mode IDE.
            args[args.count - 1] += ",lcyls=520,lheads=64,lsecs=63,bios-chs-trans=lba"
            let bios = ProcessInfo.processInfo.environment["DOSMAC_WIN9X_BIOS"].map { URL(fileURLWithPath: $0) }
                ?? installation.firmware.appendingPathComponent("bios-win9x.bin")
            guard FileManager.default.fileExists(atPath: bios.path) else {
                throw VMError.invalid("This Windows computer needs the embedded Windows 9x firmware. Rebuild DosMac with scripts/build-win9x-bios.py and scripts/bundle-qemu.py.")
            }
            args += ["-bios", bios.path]
        }
        if machine.sharedDisk == true {
            args += ["-blockdev", try json(.object(["driver": .string("raw"), "node-name": .string("shared-disk"), "file": .object(["driver": .string("file"), "filename": .string(SharedStorage.image(in: directory).path)])])), "-device", "ide-hd,drive=shared-disk,bus=ide.0,unit=1,lcyls=131,lheads=16,lsecs=63,bios-chs-trans=none"]
        }
        // Stable drive identifiers for QMP media commands, even with empty trays.
        args += ["-drive", "if=none,id=floppy0", "-device", "floppy,drive=floppy0,unit=0", "-drive", "if=none,id=cdrom0,media=cdrom,readonly=on", "-device", "ide-cd,drive=cdrom0,bus=ide.1,unit=0"]
        args += ["-audiodev", muted ? "none,id=sound0" : "coreaudio,id=sound0", "-device", "sb16,audiodev=sound0"]
        if machine.sharedFolder == true {
            guard let sharingPort, sharingPort > 1024 else { throw VMError.invalid("The private shared folder is not ready.") }
            // Spawn a fresh relay for each guest connection, including SMB reconnects.
            args += ["-netdev", "user,id=sharing,restrict=on,guestfwd=tcp:10.0.2.4:139-cmd:/usr/bin/nc 127.0.0.1 \(sharingPort)", "-device", "pcnet,netdev=sharing,romfile="]
        } else { args += ["-net", "none"] }
        args += ["-S"] // Media is attached through QMP before the first guest instruction.
        return args
    }
}
#endif
