import Foundation

/// First Guest Tools component. Uses Windows' INF installer; never edits a mounted HDD.
public enum GuestToolsMedia {
    public static func mouseFiles(driver: Data, inf: Data, agent: Data? = nil) -> [String: Data] {
        let agentCopy = agent == nil ? "" : """
        COPY /Y /B A:\\DMAGENT.EXE C:\\DMTOOLS\\DMAGENT.EXE >NUL
        IF ERRORLEVEL 1 GOTO FAILED
        COPY /Y /B A:\\DMAGENT.INF C:\\DMTOOLS\\DMAGENT.INF >NUL
        IF ERRORLEVEL 1 GOTO FAILED
        """
        let batch = """
        @ECHO OFF
        IF NOT EXIST C:\\WINDOWS\\SYSTEM.INI GOTO FAILED
        IF NOT EXIST C:\\DMTOOLS\\NUL MD C:\\DMTOOLS
        IF EXIST C:\\DMTOOLS\\SYSINI.BAK GOTO INSTALL
        COPY /B C:\\WINDOWS\\SYSTEM.INI C:\\DMTOOLS\\SYSINI.BAK >NUL
        IF ERRORLEVEL 1 GOTO FAILED
        :INSTALL
        COPY /Y /B A:\\QEMOUSE.DRV C:\\DMTOOLS\\QEMOUSE.DRV >NUL
        IF ERRORLEVEL 1 GOTO FAILED
        COPY /Y /B A:\\QEMOUSE.INF C:\\DMTOOLS\\QEMOUSE.INF >NUL
        IF ERRORLEVEL 1 GOTO FAILED
        \(agentCopy)
        ECHO DosMac files are ready
        PAUSE >NUL
        EXIT
        :FAILED
        ECHO Guest Tools could not prepare their files. Your original mouse driver is unchanged.
        PAUSE
        """
        // Verify Windows applied the INF before asking for a restart. A DOS START /W
        // wrapper around 16-bit RUNDLL can remain running and block shutdown on 98.
        var verify = ["@ECHO OFF"]
        for attempt in 0..<10 {
            verify += ["IF NOT EXIST C:\\WINDOWS\\SYSTEM\\QEMOUSE.DRV GOTO WAIT\(attempt)",
                       "C:\\WINDOWS\\COMMAND\\FIND.EXE /I \"mouse.drv=qemouse.drv\" C:\\WINDOWS\\SYSTEM.INI >NUL",
                       "IF NOT ERRORLEVEL 1 GOTO READY", ":WAIT\(attempt)",
                       "C:\\WINDOWS\\PING.EXE -n 2 127.0.0.1 >NUL"]
        }
        verify += ["ECHO DosMac mouse check failed", "PAUSE >NUL", "EXIT", ":READY", "ECHO DosMac mouse verified", "PAUSE >NUL", "EXIT"]
        var files = ["QEMOUSE.DRV": driver, "QEMOUSE.INF": inf,
                "INSTALL.BAT": Data((batch.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n").utf8),
                "VERIFY.BAT": Data((verify.joined(separator: "\r\n") + "\r\n").utf8)]
        if let agent {
            files["DMAGENT.EXE"] = agent
            files["DMAGENT.INF"] = Data("[Version]\r\nSignature=\"$CHICAGO$\"\r\n[DefaultInstall]\r\nAddReg=Agent.Run\r\n[Agent.Run]\r\nHKLM,Software\\Microsoft\\Windows\\CurrentVersion\\Run,DosMacDisplay,,C:\\DMTOOLS\\DMAGENT.EXE\r\n".utf8)
        }
        return files
    }
}

#if os(macOS)
@MainActor
public struct GuestToolsInstaller {
    public let session: MachineSession
    public init(session: MachineSession) { self.session = session }

    private func waitFor(_ predicate: (String) -> Bool, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, session.isActive {
            try Task.checkCancellation()
            guard session.frameSnapshot() != nil else {
                try await Task.sleep(for: .milliseconds(100)); continue
            }
            let text = try await session.observeScreenText().lowercased().filter { $0.isLetter || $0.isNumber }
            if text.contains("enterwindowspassword") || text.contains("confirmnewpassword") {
                throw VMError.invalid("Complete the Windows logon locally, then run Guest Tools again. The backup has been kept.")
            }
            if predicate(text) { return }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw VMError.invalid("Guest Tools paused because Windows did not reach the expected screen. Your backup is kept; review the guest before continuing.")
    }

    private func run(_ command: String) async throws {
        // Explorer can paint Start before it begins handling hotkeys. Retry the
        // idempotent open action; never type a command until Run is observed.
        var opened = false
        for attempt in 0..<3 {
            try await session.sendChord(["meta_l", "r"])
            try await Task.sleep(for: .milliseconds(750))
            do {
                try await waitFor({ $0.contains("typethenameofaprogram") }, timeout: 5)
                opened = true; break
            } catch VMError.invalid(let message) where message.hasPrefix("Guest Tools paused") && attempt < 2 {
                continue
            }
        }
        guard opened else { throw VMError.invalid("Windows did not open Run. Review the guest before retrying Guest Tools.") }
        try await Task.sleep(for: .milliseconds(500))
        try await session.tap("home")
        try await session.sendChord(["shift", "end"])
        try await Task.sleep(for: .milliseconds(250))
        try await session.typeText(command + "\n", paced: true)
        try await waitFor({ !$0.contains("typethenameofaprogram") }, timeout: 10)
    }

    public func installMouse(files: [String: Data], report: (String) -> Void) async throws {
        report("Waiting for the Windows desktop…")
        try await waitFor({ $0.contains("start") && ($0.contains("mycomputer") || $0.contains("recyclebin")) }, timeout: 120)
        let alreadyActive = session.absolutePointer
        let includesAgent = files["DMAGENT.EXE"] != nil
        if alreadyActive && (!includesAgent || session.guestDisplay?.ready == true) {
            report("Guest Tools are already active."); return
        }
        try await session.mountSupportDisk(files: files)
        report("Installing the seamless mouse driver…")
        try await run("C:\\COMMAND.COM /C A:\\INSTALL.BAT")
        report("Waiting for the guest file-copy acknowledgement…")
        try await waitFor({ $0.contains("filesareready") }, timeout: 30)
        try await session.tap("ret")
        try await waitFor({ !$0.contains("filesareready") }, timeout: 8)
        if includesAgent {
            report("Installing the Windows display agent…")
            try await run("C:\\WINDOWS\\RUNDLL.EXE SETUPX.DLL,InstallHinfSection DefaultInstall 128 C:\\DMTOOLS\\DMAGENT.INF")
        }
        if alreadyActive { try await activateAgent(report: report); return }
        report("Applying the Windows mouse driver settings…")
        try await run("C:\\WINDOWS\\RUNDLL.EXE SETUPX.DLL,InstallHinfSection DefaultInstall 128 C:\\DMTOOLS\\QEMOUSE.INF")
        try await Task.sleep(for: .seconds(2))
        try await run("C:\\COMMAND.COM /C A:\\VERIFY.BAT")
        report("Checking the installed mouse driver files…")
        try await waitFor({ $0.contains("mouseverified") }, timeout: 40)
        try await session.tap("ret")
        try await waitFor({ !$0.contains("mouseverified") }, timeout: 8)
        try await session.sendChord(["ctrl", "esc"])
        try await Task.sleep(for: .milliseconds(750))
        try await session.tap("u")
        try await waitFor({ $0.contains("shutdownwindows") && $0.contains("restart") }, timeout: 8)
        report("Restarting Windows to activate seamless mouse input…")
        try await session.tap("r"); try await session.tap("ret")
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline, session.isActive {
            try Task.checkCancellation()
            if session.absolutePointer {
                // The driver activates before Explorer finishes startup. Do not
                // hand control back while Windows is still completing its boot.
                try await waitFor({ $0.contains("start") && ($0.contains("mycomputer") || $0.contains("recyclebin")) }, timeout: 60)
                try await run("C:\\COMMAND.COM /C EXIT")
                try await session.eject(cdrom: false)
                if includesAgent { try await activateAgent(report: report) }
                report("Seamless mouse is active. Move freely between Windows and your Mac.")
                return
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw VMError.invalid("The driver has not activated absolute input. Your backup and the original SYSTEM.INI are kept; review Windows before retrying.")
    }
    private func activateAgent(report: (String) -> Void) async throws {
        report("Starting the Windows display agent…")
        try await run("C:\\DMTOOLS\\DMAGENT.EXE")
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline, session.isActive {
            try Task.checkCancellation()
            if session.guestDisplay?.ready == true { report("Guest Tools are active: seamless mouse and Windows display controls."); return }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw VMError.invalid("The Windows display agent did not connect. Check that the live shared folder is mapped to H:, then retry Guest Tools.")
    }

}
#endif
