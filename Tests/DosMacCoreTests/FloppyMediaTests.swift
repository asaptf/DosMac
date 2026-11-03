import Foundation
import Testing
@testable import DosMacCore

struct FloppyMediaTests {
    @MainActor private final class ShortcutState { var active = true }
    @Test func decodesFragmentedMountAcknowledgementsAndIgnoresOtherDrives() {
        var decoder = DiskLogDecoder()
        #expect(decoder.append(Data("LOG: Drive A: disk 2 of ".utf8)).isEmpty)
        let reports = decoder.append(Data("7 now active\r\nLOG: Drive B: disk 3 of 7 now active\nLOG: Drive A: disk 4 of 7 now active\n".utf8))
        #expect(reports == [DiskMountReport(number: 2, count: 7), DiskMountReport(number: 4, count: 7)])
        #expect(DiskLogDecoder.parse("Drive A: disk 0 of 7 now active") == nil)
        #expect(DiskLogDecoder.parse("Drive A: disk 8 of 7 now active") == nil)
        #expect(DiskLogDecoder.parse("Drive A: disk 1 of 9999999999999999999999999999999999 now active") == nil)
    }

    @Test func discoversExistingMediaWithoutReinstalling() async throws {
        let (root, package, library) = try LibraryTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let media = package.appendingPathComponent("payload/MEDIA")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        for number in 1...3 { try Data([0]).write(to: media.appendingPathComponent(String(format: "DISK%02d.IMG", number))) }
        let installed = try await library.install(from: package)
        let disks = try await library.floppyDisks(for: installed)
        #expect(disks.map(\.number) == [1, 2, 3])
        #expect(disks[1].imagePath == "MEDIA/DISK02.IMG")
    }

    @Test func retainsSourceLabelsAndRejectsUnsafeDiskMetadata() throws {
        var manifest = PackageManifest(id: "media", title: "Media", summary: "", author: "", license: "CC0", executable: "SETUP.EXE")
        manifest.floppyDisks = [FloppyDisk(number: 1, imagePath: "MEDIA/DISK01.IMG", label: "Windows Setup Disk 1.img")]
        let reopened = try JSONDecoder().decode(PackageManifest.self, from: JSONEncoder().encode(manifest))
        #expect(reopened.floppyDisks?.first?.label == "Windows Setup Disk 1.img")
        try reopened.validate()
        manifest.floppyDisks = [FloppyDisk(number: 1, imagePath: "../../secret.img", label: "Bad")]
        #expect(throws: (any Error).self) { try manifest.validate() }
    }

    @Test func nextDiskWrapsWithoutPretendingItWasInserted() {
        var drive = FloppyDriveStatus()
        drive.disks = (1...3).map { FloppyDisk(number: $0, imagePath: "MEDIA/DISK0\($0).IMG", label: "Disk \($0)") }
        #expect(drive.nextDisk == nil)
        drive.mountedNumber = 3
        #expect(drive.nextDisk?.number == 1)
        #expect(drive.mountedNumber == 3)
    }

    #if os(macOS)
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DOSMAC_TEST_ENGINE"] != nil))
    @MainActor func confirmsDiskSelectionWithRealEngineLog() async throws {
        let engine = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DOSMAC_TEST_ENGINE"]!)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DosMacDisks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("Media.dosmac")
        let media = package.appendingPathComponent("payload/MEDIA")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        let manifest = PackageManifest(id: "media", title: "Test Media", summary: "", author: "DosMac", license: "CC0", executable: "TEST.BAT")
        try JSONEncoder().encode(manifest).write(to: package.appendingPathComponent("manifest.json"))
        for number in 1...3 { try Self.floppyImage().write(to: media.appendingPathComponent(String(format: "DISK%02d.IMG", number))) }
        let batch = """
        @echo off
        imgmount a C:\\MEDIA\\DISK01.IMG C:\\MEDIA\\DISK02.IMG C:\\MEDIA\\DISK03.IMG -t floppy
        echo Ready>D:\\READY.TXT
        :wait
        rescan /a /q
        if exist D:\\SWAP.TXT goto swap
        goto wait
        :swap
        del D:\\SWAP.TXT
        imgswap a
        goto wait

        """.replacingOccurrences(of: "\n", with: "\r\n")
        try batch.write(to: package.appendingPathComponent("payload/TEST.BAT"), atomically: true, encoding: .ascii)
        let library = try LibraryStore(root: root.appendingPathComponent("Library"))
        let program = try await library.install(from: package)
        // Replace only the OS shortcut transport: the real guest performs IMGSWAP,
        // and the production monitor must observe each actual mount acknowledgement.
        let transport = ShortcutState()
        let session = EmulatorSession { _ in
            if transport.active { try Data().write(to: library.exchangeURL.appendingPathComponent("SWAP.TXT")) }
        }
        try await session.start(program: program, library: library, engine: engine)
        defer { session.stop() }
        let deadline = Date().addingTimeInterval(10)
        while session.floppyDrive.mountedNumber == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        #expect(session.floppyDrive.mountedNumber == 1)
        do { try await session.selectFloppy(number: 3) }
        catch {
            let log = (try? String(contentsOf: library.programURL(program.id).appendingPathComponent("session.log"), encoding: .utf8)) ?? "No session log"
            Issue.record(Comment(rawValue: log))
            Issue.record(Comment(rawValue: "Exchange: \((try? FileManager.default.contentsOfDirectory(atPath: library.exchangeURL.path)) ?? [])"))
            throw error
        }
        #expect(session.floppyDrive.mountedNumber == 3)
        try await session.selectFloppy(number: 1)
        #expect(session.floppyDrive.mountedNumber == 1)
        #expect(!session.floppyDrive.isChanging)
        transport.active = false
        await #expect(throws: (any Error).self) { try await session.selectFloppy(number: 2) }
        #expect(session.floppyDrive.mountedNumber == 1)
        #expect(session.floppyDrive.message != nil)
    }

    static func floppyImage() -> Data {
        // Original blank FAT12 160 KiB test disk, with a standard BPB and two FATs.
        var image = Data(repeating: 0, count: 160 * 1024)
        image.replaceSubrange(0..<3, with: [0xeb, 0x3c, 0x90])
        image.replaceSubrange(3..<11, with: Data("DOSMAC  ".utf8))
        image[11] = 0; image[12] = 2 // 512-byte sectors
        image[13] = 1; image[14] = 1; image[16] = 2
        image[17] = 64; image[19] = 64; image[20] = 1 // 320 sectors
        image[21] = 0xfe; image[22] = 1; image[24] = 8; image[26] = 1
        image[510] = 0x55; image[511] = 0xaa
        image.replaceSubrange(512..<515, with: [0xfe, 0xff, 0xff])
        image.replaceSubrange(1024..<1027, with: [0xfe, 0xff, 0xff])
        return image
    }
    #endif
}
