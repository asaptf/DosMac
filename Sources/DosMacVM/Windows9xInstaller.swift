import Foundation

public enum Windows9xRecipe {
  public static func id(for guest: GuestSystem) -> String {
    guest == .windows98 ? "win98se-oem-en-v1" : "win95-oem-en-v1"
  }
  public static func answerFile(guest: GuestSystem, productKey: String, acceptedLicense: Bool)
    throws -> String
  {
    guard guest.needsCD else { throw VMError.invalid("Choose Windows 95 or Windows 98 SE.") }
    let key = productKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard
      key.isEmpty
        || key.range(
          of:
            "^(?:[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}|[0-9]{5}-OEM-[0-9]{7}-[0-9]{5}|[0-9]{3}-[0-9]{7})$",
          options: .regularExpression) != nil
    else {
      throw VMError.invalid(
        "Enter the product key belonging to this Windows release, or leave it empty to enter it inside Setup."
      )
    }
    let keyLine =
      key.isEmpty ? "" : (guest == .windows95 ? "ProductID=\"\(key)\"" : "ProductKey=\"\(key)\"")
    return crlf(
      """
      [Version]
      Signature="$CHICAGO$"
      [Setup]
      Express=1
      InstallDir=C:\\WINDOWS
      InstallType=1
      EBD=0
      ChangeDir=0
      Network=1
      Uninstall=0
      NoPrompt2Boot=1
      ShowEula=\(acceptedLicense ? 0 : 1)
      \(keyLine)
      [NameAndOrg]
      Name="DosMac User"
      Org="DosMac"
      Display=0
      [System]
      Display=0
      [Network]
      ComputerName=DOSMAC
      Workgroup=WORKGROUP
      Description="DosMac computer"
      Clients=VREDIR
      Protocols=MSTCP
      PrimaryLogon=Windows
      Display=0
      [Install]
      AddReg=DosMac.RunOnce
      [DosMac.RunOnce]
      HKLM,Software\\Microsoft\\Windows\\CurrentVersion\\RunOnce,DosMacReady,,"C:\\COMMAND.COM /C C:\\DMREADY.BAT"
      """)
  }
  public static func bootFiles(
    guest: GuestSystem, productKey: String, acceptedLicense: Bool, sharing: Bool = false
  ) throws -> [String: Data] {
    let folder = guest == .windows98 ? "WIN98" : "WIN95"
    let autoexec = crlf(
      """
      @ECHO OFF
      PATH A:\\
      MSCDEX.EXE /D:oemcd001 /L:R
      IF NOT EXIST R:\\\(folder)\\SETUP.EXE GOTO FAILED
      EXTRACT.EXE /Y /L A:\\ A:\\EBD.CAB FORMAT.COM
      IF ERRORLEVEL 1 GOTO FAILED
      EXTRACT.EXE /Y /L A:\\ A:\\EBD.CAB SYS.COM
      IF ERRORLEVEL 1 GOTO FAILED
      EXTRACT.EXE /Y /L A:\\ A:\\EBD.CAB ATTRIB.EXE
      IF ERRORLEVEL 1 GOTO FAILED
      FORMAT.COM C: /Q /U /S /V:DOSMAC < A:\\YES.TXT
      IF ERRORLEVEL 1 GOTO FAILED
      ATTRIB.EXE -R -S -H C:\\MSDOS.SYS
      COPY /Y A:\\MSDOS.NEW C:\\MSDOS.SYS >NUL
      IF ERRORLEVEL 1 GOTO FAILED
      COPY /Y A:\\MSDOS.WIN C:\\DMBOOT.SYS >NUL
      IF ERRORLEVEL 1 GOTO FAILED
      COPY /Y A:\\ATTRIB.EXE C:\\DMATTRIB.EXE >NUL
      IF ERRORLEVEL 1 GOTO FAILED
      FDISK.EXE /MBR
      MD C:\\\(folder)
      COPY /Y R:\\\(folder)\\*.* C:\\\(folder) >NUL
      IF ERRORLEVEL 1 GOTO FAILED
      COPY /Y A:\\MSBATCH.INF C:\\MSBATCH.INF >NUL
      IF ERRORLEVEL 1 GOTO FAILED
      COPY /Y A:\\DMREADY.BAT C:\\DMREADY.BAT >NUL
      IF ERRORLEVEL 1 GOTO FAILED
      COPY /Y A:\\DMINST.BAT C:\\DMINST.BAT >NUL
      IF ERRORLEVEL 1 GOTO FAILED
      COPY /Y A:\\DMFLUSH.COM C:\\DMFLUSH.COM >NUL
      IF ERRORLEVEL 1 GOTO FAILED
      COPY /Y A:\\DMWAIT.COM C:\\DMWAIT.COM >NUL
      IF ERRORLEVEL 1 GOTO FAILED
      COPY /Y A:\\DMDONE.COM C:\\DMDONE.COM >NUL
      IF ERRORLEVEL 1 GOTO FAILED
      C:\\DMINST.BAT
      GOTO END
      :FAILED
      ECHO DM9X-FAILED
      :END
      """)
    let install = crlf(
      """
      @ECHO OFF
      C:\\DMFLUSH.COM
      C:\\DMWAIT.COM
      C:
      COPY /Y C:\\DMBOOT.SYS C:\\MSDOS.SYS >NUL
      C:\\DMATTRIB.EXE +R +S +H C:\\MSDOS.SYS
      CD \\\(folder)
      SETUP.EXE C:\\MSBATCH.INF /IS /IM /IE
      ECHO DM9X-SETUP-RETURNED
      """)
    let ready = crlf(
      """
      @ECHO OFF
      \(sharing ? "NET USE H: \\\\10.0.2.4\\DOSMAC /YES <NUL >NUL" : "REM Live sharing is disabled")
      C:\\DMDONE.COM
      EXIT
      """)
    func systemFile(bootGUI: Int) -> Data {
      var text = crlf(
        "[Paths]\nWinDir=C:\\WINDOWS\nWinBootDir=C:\\WINDOWS\nHostWinBootDrv=C\n[Options]\nBootGUI=\(bootGUI)\nBootDelay=0\nLogo=0"
      )
      while text.utf8.count < 1024 {
        text += ";xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\r\n"
      }
      return Data(text.utf8)
    }
    func waitProgram(_ marker: String) -> Data {
      Data([
        0xb8, 0x00, 0x0c, 0xcd, 0x21, 0xba, 0x15, 0x01, 0xb4, 0x09, 0xcd, 0x21, 0xb4, 0x08, 0xcd,
        0x21, 0xb8, 0x00, 0x4c, 0xcd, 0x21,
      ]) + Data((marker + "\r\n$").utf8)
    }
    return [
      "CONFIG.SYS": Data(
        crlf(
          "DEVICE=A:\\HIMEM.SYS /TESTMEM:OFF\nDEVICE=A:\\OAKCDROM.SYS /D:oemcd001\nDOS=HIGH,UMB\nFILES=60\nBUFFERS=20\nLASTDRIVE=Z"
        ).utf8),
      "AUTOEXEC.BAT": Data(autoexec.utf8), "DMINST.BAT": Data(install.utf8),
      "DMREADY.BAT": Data(ready.utf8), "YES.TXT": Data("Y\r\nY\r\n".utf8),
      // Original 8086 code: DOS disk reset/flush (INT 21h/AH=0Dh), then exit.
      "DMFLUSH.COM": Data([0xb4, 0x0d, 0xcd, 0x21, 0xb8, 0x00, 0x4c, 0xcd, 0x21]),
      // Flush pending input, print the acknowledgement, then wait for the host's key.
      "DMWAIT.COM": waitProgram("DM9X-STAGED"), "DMDONE.COM": waitProgram("DM9X-DESKTOP-READY"),
      "MSDOS.NEW": systemFile(bootGUI: 0), "MSDOS.WIN": systemFile(bootGUI: 1),
      "MSBATCH.INF": Data(
        try answerFile(guest: guest, productKey: productKey, acceptedLicense: acceptedLicense).utf8),
    ]
  }
  private static func crlf(_ text: String) -> String {
    text.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n"
  }
}

#if os(macOS)
  @MainActor
  public final class Windows9xInstaller {
    private let session: MachineSession
    public init(session: MachineSession) { self.session = session }
    public func run(
      report: @escaping @MainActor (String, Bool) async -> Void,
      staged: @escaping @MainActor () async throws -> Void
    ) async throws -> Bool {
      let deadline = Date().addingTimeInterval(3600)
      var releasedSetup = false
      var lastReport = Date.distantPast
      var lastObservation = ""
      var lastChange = Date()
      var confirmedUserInfo = false
      var confirmedDateTime = false
      while session.isActive, Date() < deadline {
        try Task.checkCancellation()
        if session.frameSnapshot() == nil {
          try await Task.sleep(for: .milliseconds(100))
          continue
        }
        let screen = try await session.observeScreenText()
        let text = screen.lowercased().replacingOccurrences(
          of: "\\s+", with: " ", options: .regularExpression)
        let marker = text.filter { $0.isLetter || $0.isNumber }
        if marker != lastObservation {
          lastObservation = marker
          lastChange = Date()
        }
        if marker.contains("dm9xfailed") {
          throw VMError.invalid(
            "Windows preparation failed. Review the guest screen; the assistant has stopped.")
        }
        if marker.contains("dm9xsetupreturned") {
          await report("Windows Setup returned to DOS. Review its message before continuing.", true)
          return false
        }
        if marker.contains("dm9xdesktopready") {
          try await session.tap("ret")
          await report(
            "Windows installation completed. Your desktop and shared files are ready.", false)
          return true
        }
        if !confirmedUserInfo, marker.contains("userinformation"), marker.contains("dosmacuser"),
          marker.contains("company")
        {
          await report("Confirming the prepared user information…", false)
          try await session.tap("ret")
          confirmedUserInfo = true
          continue
        }
        if !releasedSetup, marker.contains("dm9xstaged") {
          try await staged()
          try await session.eject(cdrom: false)
          await report(
            "Starting Windows Setup from the hard disk. Reboots will continue automatically…", false
          )
          try await session.tap("ret")
          releasedSetup = true
        }
        if [
          "license agreement", "licence agreement", "product key", "certificate of authenticity",
          "windows protection error", "setup cannot", "setup error", "invalid product",
        ].contains(where: text.contains) {
          await report(
            "Setup needs your attention. Review the guest screen, then choose Continue installation.",
            true)
          return false
        }
        if !confirmedDateTime, marker.contains("datetimeproperties"), marker.contains("timezone"),
          marker.contains("close")
        {
          await report("Continuing with the selected date, time, and time zone…", false)
          try await session.tap("ret")
          confirmedDateTime = true
          continue
        }
        let knownLongOperation =
          marker.contains("initializingitsdriverdatabase")
          || marker.contains("settingupplugandplaydevices")
          || marker.contains("updatingsystemsettings")
        if Date().timeIntervalSince(lastChange) > 180 && !knownLongOperation {
          await report(
            "Setup is waiting on an unchanged screen. Review it in the guest, then continue the assistant.",
            true)
          return false
        }
        if Date().timeIntervalSince(lastReport) > 15 {
          await report(
            releasedSetup
              ? "Windows Setup is running. Files are on C:; automatic restarts can continue without the floppy."
              : "Windows Setup is running…", false)
          lastReport = Date()
        }
        try await Task.sleep(for: .seconds(2))
      }
      throw VMError.timeout("Windows 9x installation; continue from the saved computer")
    }
  }
#endif
