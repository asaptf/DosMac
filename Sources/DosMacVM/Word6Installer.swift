import Foundation

#if os(macOS)
@MainActor
public final class Word6Installer {
    private let session: MachineSession
    private let disks: [MachineMedia]
    public init(session: MachineSession, disks: [MachineMedia]) { self.session = session; self.disks = disks }

    public func run(report: @escaping @MainActor (String, Bool) async -> Void) async throws -> Bool {
        guard disks.count == 9 else { throw VMError.invalid("The Word 6.0 retail recipe requires its nine-disk set.") }
        try await session.runDOSBatch(commands: ["IF NOT EXIST C:\\DMWORD\\NUL MD C:\\DMWORD"])
        for (index, disk) in disks.enumerated() {
            await report("Copying Word 6 disk \(index + 1) of \(disks.count) to the guest hard disk…", false)
            let folder = "C:\\DMWORD\\DISK\(index + 1)"
            try await session.runDOSBatch(commands: ["IF NOT EXIST \(folder)\\NUL MD \(folder)", "COPY /Y A:\\*.* \(folder)", "IF ERRORLEVEL 1 GOTO FAILED"], media: disk)
        }
        await report("Running Word 6's batch installer inside Windows…", false)
        // WINWORD6.INF explicitly resolves disks 2–9 through ../diskN paths.
        try await session.runDOSBatch(commands: ["IF NOT EXIST C:\\DMWORD\\DISK1\\SETUP.EXE GOTO FAILED", "IF NOT EXIST C:\\DOS\\SHARE.EXE GOTO FAILED", "C:\\DOS\\FIND /I \"SHARE\" C:\\AUTOEXEC.BAT >NUL", "IF ERRORLEVEL 1 ECHO C:\\DOS\\SHARE /L:500 /F:5100>>C:\\AUTOEXEC.BAT", "C:\\DOS\\SHARE /L:500 /F:5100", "C:", "CD \\DMWORD\\DISK1", "C:\\WINDOWS\\WIN.COM C:\\DMWORD\\DISK1\\SETUP.EXE /Q /N \"DosMac User\" /O \"DosMac\"", "IF ERRORLEVEL 1 GOTO FAILED", "IF NOT EXIST C:\\WINWORD\\WINWORD.EXE GOTO FAILED"], timeout: 600, completedDialog: "setup was completed successfully")
        try await session.eject(cdrom: false)
        await report("Word 6 Setup completed on the virtual hard disk.", false)
        return true
    }
}
#endif
