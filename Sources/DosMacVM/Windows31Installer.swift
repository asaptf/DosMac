import Foundation

public enum Windows31Recipe {
    /// Retail English Windows 3.1's documented SETUP.SHH format.
    public static let answerFile = """
    [sysinfo]
    showsysinfo=no
    [configuration]
    machine=ibm_compatible
    display=vga
    mouse=ps2mouse
    keyboard=t4s0enha
    language=enu
    kblayout=nodll
    [windir]
    C:\\WINDOWS
    [userinfo]
    "DosMac User"
    [endinstall]
    configfiles=modify
    endopt=exit
    """.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n"
}

#if os(macOS)
@MainActor
public final class Windows31Installer {
    private let session: MachineSession
    private let disks: [MachineMedia]
    public init(session: MachineSession, disks: [MachineMedia]) { self.session = session; self.disks = disks }

    public func run(report: @escaping @MainActor (String, Bool) async -> Void) async throws -> Bool {
        guard disks.count >= 6 else { throw VMError.invalid("The retail Windows 3.1 recipe requires the complete disk set.") }
        await report("Preparing Windows 3.1's unattended setup file…", false)
        try await session.runDOSBatch(commands: ["IF NOT EXIST C:\\DMWIN\\NUL MD C:\\DMWIN", "COPY /Y A:\\SETUP.SHH C:\\DMSETUP.SHH >NUL", "IF ERRORLEVEL 1 GOTO FAILED"], files: ["SETUP.SHH": Data(Windows31Recipe.answerFile.utf8)])
        for (index, disk) in disks.enumerated() {
            await report("Copying Windows 3.1 disk \(index + 1) of \(disks.count) to the guest hard disk…", false)
            try await session.runDOSBatch(commands: ["COPY /Y A:\\*.* C:\\DMWIN", "IF ERRORLEVEL 1 GOTO FAILED", "IF NOT EXIST C:\\DMWIN\\DISK\(index + 1) GOTO FAILED"], media: disk)
        }
        await report("Running Windows 3.1 batch setup…", false)
        try await session.runDOSBatch(commands: ["C:", "CD \\DMWIN", "SETUP /H:C:\\DMSETUP.SHH", "IF ERRORLEVEL 1 GOTO FAILED", "IF NOT EXIST C:\\WINDOWS\\WIN.COM GOTO FAILED", "IF NOT EXIST C:\\WINDOWS\\SYSTEM\\KRNL386.EXE GOTO FAILED"], timeout: 600)
        try await session.eject(cdrom: false)
        await report("Windows 3.1 Setup completed on the virtual hard disk.", false)
        return true
    }
}
#endif
