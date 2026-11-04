import Foundation
import Testing

@testable import DosMacVM

struct SharedStorageTests {
  @Test func patchPreservesBootSectorAndUnrelatedStartupFiles() throws {
    let kernel = Data((0..<9000).map { UInt8($0 % 251) })
    let original = try FAT12Disk.make(files: [
      "IO.SYS": kernel, "AUTOEXEC.BAT": Data("OLD".utf8), "KEEP.DAT": kernel,
    ])
    let replacement = Data(repeating: 65, count: 5000)
    let result = try FAT12Disk(data: original).replacing(files: [
      "AUTOEXEC.BAT": replacement, "NEW.INF": Data("new answer file".utf8),
    ])
    #expect(result.prefix(512) == original.prefix(512))
    let disk = try FAT12Disk(data: result)
    #expect(try disk.file("IO.SYS") == kernel)
    #expect(try disk.file("KEEP.DAT") == kernel)
    #expect(try disk.file("AUTOEXEC.BAT") == replacement)
    #expect(try disk.file("NEW.INF") == Data("new answer file".utf8))
    #expect(throws: (any Error).self) { try disk.replacing(files: ["../HOST": Data()]) }
  }
  @Test func windowsAnswerFileRejectsInjectedCommandsAndDoesNotAssumeLicenseAcceptance() throws {
    let answer = try Windows9xRecipe.answerFile(
      guest: .windows98, productKey: "", acceptedLicense: false)
    #expect(answer.contains("ShowEula=1\r\n"))
    #expect(!answer.contains("ProductKey="))
    #expect(throws: (any Error).self) {
      try Windows9xRecipe.answerFile(
        guest: .windows98, productKey: "KEY\r\n[Install]\r\nRun=evil", acceptedLicense: true)
    }
    #expect(throws: (any Error).self) {
      try Windows9xRecipe.answerFile(guest: .msdos622, productKey: "", acceptedLicense: true)
    }
    let files = try Windows9xRecipe.bootFiles(
      guest: .windows95, productKey: "", acceptedLicense: false)
    let startup = String(decoding: try #require(files["AUTOEXEC.BAT"]), as: UTF8.self)
    #expect(startup.contains("R:\\WIN95\\SETUP.EXE"))
    #expect(startup.contains("FORMAT.COM C:"))
    #expect(!startup.contains("FORMAT.COM D:"))
  }
  #if os(macOS)
    @Test func sparseSystemDiskPlacesPartitionAndVolumeAtTheirActualOffsets() throws {
      let file = FileManager.default.temporaryDirectory.appendingPathComponent(
        "DosMacSparse-\(UUID().uuidString).img")
      defer { try? FileManager.default.removeItem(at: file) }
      try SharedDiskImage.createSystemImage(at: file)
      #expect(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize == 1024 * 1024 * 1024)
      let handle = try FileHandle(forReadingFrom: file)
      defer { try? handle.close() }
      let mbr = try #require(try handle.read(upToCount: 512))
      #expect(mbr[446] == 0x80 && mbr[450] == 0x0e)
      #expect(mbr.le32(454) == 63)
      try handle.seek(toOffset: 63 * 512)
      let volume = try #require(try handle.read(upToCount: 512))
      #expect(volume[510] == 0x55 && volume[511] == 0xaa)
      #expect(volume.le16(11) == 512)
      #expect(volume.le32(28) == 63)
      #expect(volume.le16(26) == 64)
      #expect(Int(volume.le32(32)) + 63 == 520 * 64 * 63)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DOSMAC_TEST_STORAGE"] == "1"))
    func macSharedDiskMountsRemountsAndPreservesDirectories() async throws {
      let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
        "DosMacSharedTest-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: folder) }
      let volume = try await SharedStorage.mountForHost(in: folder)
      try FileManager.default.createDirectory(
        at: volume.appendingPathComponent("DOCS"), withIntermediateDirectories: false)
      let bytes = Data(repeating: 0x5a, count: 3 * 1024 * 1024)
      try bytes.write(to: volume.appendingPathComponent("DOCS/LETTER.DOC"))
      try await SharedStorage.prepareForGuest(in: folder)
      let remounted = try await SharedStorage.mountForHost(in: folder)
      #expect(try Data(contentsOf: remounted.appendingPathComponent("DOCS/LETTER.DOC")) == bytes)
      try await SharedStorage.prepareForGuest(in: folder)
      #expect(
        try FileManager.default.attributesOfItem(atPath: SharedStorage.image(in: folder).path)[
          .size] as? Int == 64 * 1024 * 1024)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DOSMAC_TEST_SAMBA"] == "1"))
    @MainActor func privateSMB1FolderSupportsBothDirectionsAndRejectsSymlinks() async throws {
      let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
        "DosMacSMBTest-\(UUID().uuidString)")
      let runtime = URL(fileURLWithPath: "/tmp/dosmac-smb-\(UUID().uuidString)")
      try FileManager.default.createDirectory(
        at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      try FileManager.default.createDirectory(
        at: runtime, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      defer {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.removeItem(at: runtime)
      }
      let shared = try SharedFolderServer.folder(in: folder)
      let hostFile = shared.appendingPathComponent("HOST.TXT")
      try Data("host document".utf8).write(to: hostFile)
      let privateFile = folder.appendingPathComponent("PRIVATE.TXT")
      try Data("private".utf8).write(to: privateFile)
      try FileManager.default.createSymbolicLink(
        at: shared.appendingPathComponent("LINK.TXT"), withDestinationURL: privateFile)
      let server = SharedFolderServer()
      try await server.start(directory: folder, runtime: runtime)
      defer { server.stop() }
      let client = URL(
        fileURLWithPath: ProcessInfo.processInfo.environment["DOSMAC_SMBCLIENT_PATH"]
          ?? "/opt/homebrew/bin/smbclient")
      let fetched = folder.appendingPathComponent("FETCHED.TXT")
      let args = [
        "//127.0.0.1/DOSMAC", "-s", runtime.appendingPathComponent("smb.conf").path, "-N",
        "--option=client min protocol=NT1", "--option=client max protocol=NT1",
        "--option=client smb transports=nbt:\(server.port)",
      ]
      _ = try await ChildProcess.output(
        client,
        arguments: args + ["-c", "get HOST.TXT \(fetched.path); put \(fetched.path) GUEST.TXT"])
      #expect(try Data(contentsOf: fetched) == Data(contentsOf: hostFile))
      #expect(
        try Data(contentsOf: shared.appendingPathComponent("GUEST.TXT"))
          == Data(contentsOf: hostFile))
      await #expect(throws: (any Error).self) {
        _ = try await ChildProcess.output(
          client,
          arguments: args + [
            "-c", "get LINK.TXT \(folder.appendingPathComponent("LEAK.TXT").path)",
          ])
      }
      #expect(
        !FileManager.default.fileExists(atPath: folder.appendingPathComponent("LEAK.TXT").path))
    }
  #endif
}
