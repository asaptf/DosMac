#if os(macOS)
  import Foundation
  import Testing
  import CoreGraphics
  import ImageIO
  import UniformTypeIdentifiers
  @testable import DosMacVM

  struct Windows9xTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DOSMAC_TEST_WIN9X_ISO"] != nil))
    @MainActor func actualWindowsMediaReachesLicenseOrProductKeyReview() async throws {
      let env = ProcessInfo.processInfo.environment
      let resume = env["DOSMAC_TEST_WIN9X_RESUME"].map { URL(fileURLWithPath: $0) }
      let root =
        resume?.deletingLastPathComponent().deletingLastPathComponent()
        ?? URL(fileURLWithPath: "/tmp/dosmac-9x-media-\(UUID().uuidString)")
      let store = try MachineStore(root: root)
      let guest: GuestSystem = env["DOSMAC_TEST_WIN9X_GUEST"] == "95" ? .windows95 : .windows98
      var machine: Machine
      if let resume {
        machine = try JSONDecoder().decode(Machine.self, from: Data(contentsOf: resume))
        machine.boot = .hardDisk
      } else {
        machine = try await store.createWindows9x(
          guest: guest, iso: URL(fileURLWithPath: env["DOSMAC_TEST_WIN9X_ISO"]!),
          bootDisk: URL(fileURLWithPath: try #require(env["DOSMAC_TEST_WIN9X_BOOT"])),
          productKey: "", acceptedLicense: false)
      }
      print("Windows media verification: \(store.directory(for: machine.id).path)")
      let session = MachineSession()
      try await session.start(machine, directory: store.directory(for: machine.id), muted: true)
      defer { session.terminate() }
      var attention = false
      let finished = try await Windows9xInstaller(session: session).run { message, review in
        print(message)
        fflush(nil)
        attention = review
        if let frame = session.frameSnapshot(),
          let provider = CGDataProvider(data: frame.pixels as CFData),
          let image = CGImage(
            width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: frame.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue).union(
              .byteOrder32Big), provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent),
          let writer = CGImageDestinationCreateWithURL(
            root.appendingPathComponent("setup.png") as CFURL, UTType.png.identifier as CFString, 1,
            nil)
        {
          CGImageDestinationAddImage(writer, image, nil)
          _ = CGImageDestinationFinalize(writer)
        }
      } staged: {
        machine.boot = .hardDisk
        try await store.save(machine)
      }
      let observed = try await session.observeScreenText()
      print("Windows review screen: \(observed)")
      #expect(!finished && attention)
      let text = observed.lowercased().filter { $0.isLetter || $0.isNumber }
      #expect(
        text.contains("licenseagreement") || text.contains("productkey")
          || text.contains("certificateofauthenticity"), Comment(rawValue: observed))
      await session.powerOff()
      if env["DOSMAC_TEST_KEEP_WIN9X"] != "1" { try FileManager.default.removeItem(at: root) }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DOSMAC_TEST_WIN9X_BOOT"] != nil))
    @MainActor func preparesFreshDiskBootsFromHDDAndSharesFilesWithDOS() async throws {
      let root = URL(fileURLWithPath: "/tmp/dosmac-9x-test-\(UUID().uuidString)")
      try FileManager.default.createDirectory(
        at: root.appendingPathComponent("CD/WIN98"), withIntermediateDirectories: true)
      print("Windows 9x boot fixture: \(root.path)")
      defer {
        if ProcessInfo.processInfo.environment["DOSMAC_TEST_KEEP_WIN9X"] != "1" {
          try? FileManager.default.removeItem(at: root)
        }
      }
      // Original inert fixture; the test stops before executing this placeholder.
      try Data("not an executable".utf8).write(
        to: root.appendingPathComponent("CD/WIN98/SETUP.EXE"))
      let iso = root.appendingPathComponent("fixture.iso")
      try await ChildProcess.run(
        URL(fileURLWithPath: "/usr/bin/hdiutil"),
        arguments: [
          "makehybrid", "-iso", "-joliet", "-o", iso.path, root.appendingPathComponent("CD").path,
        ])
      let store = try MachineStore(root: root.appendingPathComponent("Machines"))
      var machine = try await store.createWindows9x(
        guest: .windows98, iso: iso,
        bootDisk: URL(
          fileURLWithPath: ProcessInfo.processInfo.environment["DOSMAC_TEST_WIN9X_BOOT"]!),
        productKey: "", acceptedLicense: false)
      machine.sharedFolder = false
      let directory = store.directory(for: machine.id)
      let volume = try await SharedStorage.mountForHost(in: directory)
      try Data("DOSMAC-HOST-INPUT".utf8).write(to: volume.appendingPathComponent("HOST.TXT"))
    let largeFile = Data((0..<(3 * 1024 * 1024)).map { UInt8($0 % 251) })
    try largeFile.write(to: volume.appendingPathComponent("HOST.BIN"))
      let session = MachineSession()
      try await session.start(machine, directory: directory, muted: true)
      defer { session.terminate() }
      let deadline = Date().addingTimeInterval(120)
      var screen = ""
      while Date() < deadline {
        screen = try await session.textScreen()
        if screen.contains("DM9X-STAGED") || screen.contains("DM9X-FAILED") { break }
        try await Task.sleep(for: .milliseconds(500))
      }
      try #require(screen.contains("DM9X-STAGED"), Comment(rawValue: screen))
      await session.powerOff()
      machine.boot = .hardDisk
      try await session.start(machine, directory: directory, muted: true)
      do { try await session.waitForDOSPrompt(timeout: 45) } catch {
        throw VMError.invalid("HDD boot screen: \(try await session.textScreen())")
      }
      try await session.typeText("TYPE D:\\HOST.TXT\n")
      try await session.waitForDOSPrompt()
      try await session.typeText("ECHO DOSMAC-GUEST-OUTPUT > D:\\GUEST.TXT\n")
      try await session.waitForDOSPrompt()
    try await session.typeText("COPY /B D:\\HOST.BIN C:\\CHECK.BIN\n")
    try await session.waitForDOSPrompt()
    try await session.typeText("COPY /B C:\\CHECK.BIN D:\\GUEST.BIN\n")
    try await session.waitForDOSPrompt()
      try await session.typeText("C:\\DMFLUSH.COM\n")
      try await session.waitForDOSPrompt()
      try await Task.sleep(for: .seconds(2))
      screen = try await session.textScreen()
      print("DOS transfer screen: \(screen)")
      #expect(screen.contains("DOSMAC-HOST-INPUT"), Comment(rawValue: screen))
      await session.powerOff()
      let output = try await SharedStorage.mountForHost(in: directory)
      let data = try String(contentsOf: output.appendingPathComponent("GUEST.TXT"), encoding: .utf8)
      #expect(data.contains("DOSMAC-GUEST-OUTPUT"))
    #expect(try Data(contentsOf: output.appendingPathComponent("GUEST.BIN")) == largeFile)
      try await SharedStorage.prepareForGuest(in: directory)
    }
  }
#endif
