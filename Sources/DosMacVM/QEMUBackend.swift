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
    public static func make(machine: Machine, directory: URL, runtime: URL, installation: QEMUInstallation, muted: Bool = false) throws -> [String] {
        try machine.validate()
        // JSON arguments preserve commas, spaces, and Unicode in host paths.
        func json(_ value: JSONValue) throws -> String { String(decoding: try JSONEncoder().encode(value), as: UTF8.self) }
        let disk = directory.appendingPathComponent("disk.qcow2").path
        var args = ["-name", machine.name, "-machine", "pc-i440fx-9.2", "-accel", "tcg,thread=single", "-cpu", machine.guest.cpu, "-m", String(machine.guest.memoryMB), "-L", installation.firmware.path,
                    "-display", "none", "-vnc", "unix:\(runtime.appendingPathComponent("display.sock").path)", "-qmp", "stdio", "-monitor", "none", "-serial", "none", "-parallel", "none", "-net", "none", "-vga", "cirrus", "-boot", "order=\(machine.boot.qemuOrder),menu=on", "-rtc", "base=localtime"]
        args += ["-blockdev", try json(.object(["driver": .string("qcow2"), "node-name": .string("system-disk"), "file": .object(["driver": .string("file"), "filename": .string(disk)])])), "-device", "ide-hd,drive=system-disk,bus=ide.0,unit=0"]
        // Stable drive identifiers for QMP media commands, even with empty trays.
        args += ["-drive", "if=none,id=floppy0", "-device", "floppy,drive=floppy0,unit=0", "-drive", "if=none,id=cdrom0,media=cdrom,readonly=on", "-device", "ide-cd,drive=cdrom0,bus=ide.1,unit=0"]
        args += ["-audiodev", muted ? "none,id=sound0" : "coreaudio,id=sound0", "-device", "sb16,audiodev=sound0"]
        args += ["-S"] // Media is attached through QMP before the first guest instruction.
        return args
    }
}
#endif
