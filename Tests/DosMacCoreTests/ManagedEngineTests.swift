import Foundation
import Testing
@testable import DosMacCore

#if os(macOS)
struct ManagedEngineTests {
    private func fixture(complete: Bool = true) throws -> (URL, URL, EngineRelease) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DosMacEngine-\(UUID().uuidString)")
        let source = root.appendingPathComponent("source")
        let executable = source.appendingPathComponent("dosbox-x-sdl2/dosbox-x.app/Contents/MacOS/dosbox-x")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        if complete { try Data("Test license".utf8).write(to: source.appendingPathComponent("dosbox-x-sdl2/COPYING.txt")) }
        let archive = root.appendingPathComponent("engine.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", source.path, archive.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let release = EngineRelease(version: "test", architecture: "test", url: URL(string: "https://example.com/engine.zip")!, sha256: try ManagedEngine.sha256(of: archive))
        return (root, archive, release)
    }

    @Test func installsCompleteAppAndRetainsLicense() async throws {
        let (root, archive, release) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let engines = root.appendingPathComponent("Engines")
        let executable = try await ManagedEngine.installArchive(at: archive, release: release, root: engines) { _ in }
        #expect(ManagedEngine.cachedExecutable(root: engines, release: release) == executable)
        #expect(FileManager.default.isExecutableFile(atPath: executable.path))
        let license = engines.appendingPathComponent(release.directoryName).appendingPathComponent("dosbox-x-sdl2/COPYING.txt")
        #expect(try String(contentsOf: license, encoding: .utf8) == "Test license")
        #expect(try FileManager.default.contentsOfDirectory(atPath: engines.path).allSatisfy { !$0.hasPrefix(".install-") })
    }

    @Test func rejectsChecksumMismatchBeforeExtraction() async throws {
        let (root, archive, release) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let engines = root.appendingPathComponent("Engines")
        let wrong = EngineRelease(version: release.version, architecture: release.architecture, url: release.url, sha256: String(repeating: "0", count: 64))
        await #expect(throws: (any Error).self) {
            try await ManagedEngine.installArchive(at: archive, release: wrong, root: engines) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: engines.path))
    }

    @Test func incompleteArchiveDoesNotReplacePriorInstallation() async throws {
        let (root, archive, release) = try fixture(complete: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let engines = root.appendingPathComponent("Engines")
        let previous = engines.appendingPathComponent(release.directoryName)
        try FileManager.default.createDirectory(at: previous, withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: previous.appendingPathComponent("user-marker"))
        await #expect(throws: (any Error).self) {
            try await ManagedEngine.installArchive(at: archive, release: release, root: engines) { _ in }
        }
        #expect(try String(contentsOf: previous.appendingPathComponent("user-marker"), encoding: .utf8) == "keep me")
        #expect(ManagedEngine.cachedExecutable(root: engines, release: release) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: engines.path).count == 1)
    }

    @Test func cancelledInstallPublishesNothing() async throws {
        let (root, archive, release) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let engines = root.appendingPathComponent("Engines")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ManagedEngine.installArchive(at: archive, release: release, root: engines) { _ in }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(ManagedEngine.cachedExecutable(root: engines, release: release) == nil)
    }
}
#endif
