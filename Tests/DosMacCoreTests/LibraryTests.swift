import Foundation
import Testing
@testable import DosMacCore

struct LibraryTests {
    func fixture(executable: String = "HELLO.BAT") throws -> (URL, URL, LibraryStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let package = root.appendingPathComponent("Hello.dosmac")
        try FileManager.default.createDirectory(at: package.appendingPathComponent("payload"), withIntermediateDirectories: true)
        let manifest = PackageManifest(id: "org.dosmac.test", title: "Test", summary: "Test program", author: "DosMac", license: "CC0-1.0", executable: executable)
        try JSONEncoder().encode(manifest).write(to: package.appendingPathComponent("manifest.json"))
        try Data("@echo hello".utf8).write(to: package.appendingPathComponent("payload/HELLO.BAT"))
        return (root, package, try LibraryStore(root: root.appendingPathComponent("Library")))
    }

    @Test func installPersistsAndRejectsDuplicate() async throws {
        let (root, package, library) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let installed = try await library.install(from: package)
        #expect(installed.id == "org.dosmac.test")
        #expect(try await library.programs().count == 1)
        let copy = library.programURL(installed.id).appendingPathComponent("DriveC/HELLO.BAT")
        #expect(FileManager.default.fileExists(atPath: copy.path))
        do { _ = try await library.install(from: package); Issue.record("Duplicate install succeeded") }
        catch DosMacError.alreadyInstalled { }
        try await library.recordLaunch(installed)
        #expect(try await library.programs().first?.lastLaunchedAt != nil)
        // Reopening the store uses persisted metadata, not in-memory state.
        let reopened = try LibraryStore(root: library.root)
        #expect(try await reopened.programs().count == 1)
    }

    @Test(arguments: ["../BAD.EXE", "C:/BAD.EXE", "HELLO.BAT\nmount c /", "HELLO.BAT & DEL C:*.*", "LONGFILENAME.EXE", "a/../../BAD.COM", "BAD.TXT", "A\".EXE"])
    func rejectsCommandAndPathInjection(_ entry: String) throws {
        let manifest = PackageManifest(id: "test", title: "Test", summary: "", author: "", license: "CC0", executable: entry)
        #expect(throws: (any Error).self) { try manifest.validate() }
    }

    @Test func missingEntryDoesNotPublishPartialInstall() async throws {
        let (root, package, library) = try fixture(executable: "MISSING.EXE")
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: (any Error).self) { try await library.install(from: package) }
        #expect(try await library.programs().isEmpty)
    }

    @Test func rejectsSymlinkPayload() async throws {
        let (root, package, library) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: package.appendingPathComponent("payload/SECRET"), withDestinationURL: root)
        await #expect(throws: (any Error).self) { try await library.install(from: package) }
        #expect(try await library.programs().isEmpty)
    }

    @Test func rejectsSymlinkManifest() async throws {
        let (root, package, library) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = package.appendingPathComponent("manifest.json")
        let moved = root.appendingPathComponent("external.json")
        try FileManager.default.moveItem(at: manifest, to: moved)
        try FileManager.default.createSymbolicLink(at: manifest, withDestinationURL: moved)
        await #expect(throws: (any Error).self) { try await library.install(from: package) }
    }

    @Test func configurationUsesInterpreterAndOnlyOwnedDrives() async throws {
        let (root, package, library) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let item = try await library.install(from: package)
        let config = try DOSBoxConfiguration.render(program: item, driveC: library.programURL(item.id).appendingPathComponent("DriveC"), exchange: library.exchangeURL)
        #expect(config.contains("core=normal"))
        #expect(config.contains("cputype=386"))
        #expect(config.contains("mount d \"\(library.exchangeURL.path)\""))
        #expect(!config.contains("mount c \"/\""))
        #expect(throws: (any Error).self) {
            try DOSBoxConfiguration.render(program: item, driveC: URL(fileURLWithPath: "/tmp/bad\nmount c /"), exchange: library.exchangeURL)
        }
    }

    @Test func nestedWindowsEntryChangesWorkingDirectory() throws {
        let manifest = PackageManifest(id: "windows", title: "Windows", summary: "", author: "User", license: "User supplied", executable: "WINDOWS/WIN.COM", profile: .windows31)
        let program = InstalledProgram(manifest: manifest, installedAt: Date())
        let config = try DOSBoxConfiguration.render(program: program, driveC: URL(fileURLWithPath: "/tmp/drive c"), exchange: URL(fileURLWithPath: "/tmp/exchange"))
        #expect(config.contains("cd \\WINDOWS"))
        #expect(config.contains("cputype=486"))
        #expect(config.contains("memsize=64"))
    }
}
