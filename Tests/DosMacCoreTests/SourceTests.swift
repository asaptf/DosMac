import Foundation
import Testing
@testable import DosMacCore

struct SourceTests {
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!)
    }

    @Test(arguments: ["hello.zip", "hello.7z"])
    func importsCompressedDOSProgram(_ name: String) async throws {
        let service = SoftwareSources()
        let url = URL(string: "https://example.com/\(name)")!
        let prepared = try await service.prepareArchive(data: fixture(name), release: RemoteRelease(title: "Archive", pageURL: url, downloadURL: url))
        #expect(prepared.candidates == ["HELLO.BAT"])
        #expect(!prepared.isInstallationMedia)
        #expect(FileManager.default.fileExists(atPath: prepared.package.appendingPathComponent("payload/HELLO.BAT").path))
        await service.discard(prepared)
    }

    @Test(arguments: ["traversal.zip", "symlink.zip", "oversize.zip", "hello-bcj.7z"])
    func rejectsUnsafeArchives(_ name: String) async throws {
        let service = SoftwareSources()
        let url = URL(string: "https://example.com/\(name)")!
        let data = try fixture(name)
        await #expect(throws: (any Error).self) { try await service.prepareArchive(data: data, release: RemoteRelease(title: "Bad", pageURL: url)) }
    }

    @Test func preparesFloppyInstallerWithoutClaimingItIsInstalled() async throws {
        let service = SoftwareSources()
        let url = URL(string: "https://example.com/media.zip")!
        let prepared = try await service.prepareArchive(data: fixture("media.zip"), release: RemoteRelease(title: "Media", pageURL: url))
        #expect(prepared.isInstallationMedia)
        #expect(prepared.candidates == ["INSTALL.BAT"])
        let package = try await service.finalize(prepared, executable: "INSTALL.BAT", profile: .windows31)
        let manifest = try JSONDecoder().decode(PackageManifest.self, from: Data(contentsOf: package.appendingPathComponent("manifest.json")))
        #expect(manifest.title.hasSuffix("Setup"))
        let script = try String(contentsOf: package.appendingPathComponent("payload/INSTALL.BAT"), encoding: .ascii)
        #expect(script.contains("imgmount a \"C:\\MEDIA\\DISK01.IMG\" -t floppy"))
        await service.discard(prepared)
    }

    @Test func parsesWinWorldProductAndMirrors() throws {
        let page = URL(string: "https://winworldpc.com/product/test/1")!
        let product = """
        <h1>Example</h1><a href="/download/first">DOS &amp; tools</a>
        <a href="/download/first">Duplicate</a><a href="https://evil.example/download/x">Other site</a>
        """
        let releases = try SoftwareSources.parseWinWorld(html: product, page: page)
        #expect(releases.count == 1)
        #expect(releases[0].title == "DOS & tools")
        #expect(releases[0].downloadURL == nil)
        let hash = String(repeating: "a", count: 128)
        let download = "<h1>DOS &amp; tools</h1><a href='/download/first/from/mirror'>Download</a><dt>Checksum</dt><dd><tt>\(hash)</tt></dd>"
        let mirrors = try SoftwareSources.parseWinWorld(html: download, page: releases[0].pageURL)
        #expect(mirrors[0].downloadURL?.path == "/download/first/from/mirror")
        #expect(mirrors[0].sha512 == hash)
        let oldHash = String(repeating: "b", count: 40)
        let legacy = download.replacingOccurrences(of: hash, with: oldHash)
        let legacyMirror = try SoftwareSources.parseWinWorld(html: legacy, page: releases[0].pageURL)[0]
        #expect(legacyMirror.sha1 == oldHash)
        #expect(legacyMirror.sha512 == nil)
    }

    @Test(arguments: ["../SECRET", "/etc/passwd", "C:\\AUTOEXEC.BAT", "dir/../../escape", "dir\\..\\escape", "a//b", "a/./b", "bad\nfile"])
    func rejectsArchiveTraversal(_ name: String) {
        #expect(throws: (any Error).self) { try SoftwareSources.validateArchivePath(name) }
    }

    @Test(arguments: ["http://example.com/file.zip", "file:///tmp/file.zip", "https://user:password@example.com/file.zip"])
    func requiresCredentialFreeHTTPS(_ address: String) {
        #expect(throws: (any Error).self) { try SoftwareSources.validateURL(URL(string: address)!) }
    }

    @Test func preparesAndInstallsDirectBatchProgram() async throws {
        let service = SoftwareSources()
        let url = URL(string: "https://example.com/HELLO.BAT")!
        let prepared = try await service.prepareArchive(data: Data("@echo hello\r\n".utf8), release: RemoteRelease(title: "Hello", pageURL: url, downloadURL: url))
        #expect(prepared.candidates == ["HELLO.BAT"])
        let package = try await service.finalize(prepared, executable: "HELLO.BAT", profile: .dos)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryStore(root: root)
        let installed = try await library.install(from: package)
        #expect(installed.manifest.title == "Hello")
        #expect(FileManager.default.fileExists(atPath: library.programURL(installed.id).appendingPathComponent("source-url.txt").path))
        await service.discard(prepared)
        #expect(!FileManager.default.fileExists(atPath: prepared.workspace.path))
    }

    @Test func changingStartupPersistsInstalledEntry() async throws {
        let (root, package, library) = try LibraryTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let installed = try await library.install(from: package)
        let drive = library.programURL(installed.id).appendingPathComponent("DriveC")
        try Data([0x4d, 0x5a]).write(to: drive.appendingPathComponent("NEW.EXE"))
        try await library.updateStartup(installed, executable: "NEW.EXE", profile: .windows31)
        let updated = try #require(await library.programs().first)
        #expect(updated.manifest.executable == "NEW.EXE")
        #expect(updated.manifest.profile == .windows31)
        await #expect(throws: (any Error).self) { try await library.updateStartup(updated, executable: "../BAD.EXE", profile: .dos) }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DOSMAC_TEST_WINWORLD"] == "1"))
    func liveWinWorldMetadata() async throws {
        let service = SoftwareSources()
        let releases = try await service.inspect(URL(string: "https://winworldpc.com/product/windows-3/31")!)
        #expect(!releases.isEmpty)
        let retail = try #require(releases.first { $0.title == "Windows 3.1 (Retail) (3.5-1.44mb)" })
        let mirrors = try await service.inspect(retail.pageURL)
        #expect(mirrors.first?.downloadURL?.path.contains("/from/") == true)
        #expect(mirrors.first?.sha512?.count == 128)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DOSMAC_TEST_WINWORLD_DOWNLOAD"] == "1"))
    func liveWinWorldFloppyArchive() async throws {
        let service = SoftwareSources()
        let releases = try await service.inspect(URL(string: "https://winworldpc.com/download/41574932-18c3-9a11-c3a4-e284a2c3a570")!)
        let release = try #require(releases.first)
        let prepared = try await service.prepare(release)
        #expect(prepared.isInstallationMedia)
        #expect(prepared.candidates == ["INSTALL.BAT"])
        await service.discard(prepared)
    }
}
