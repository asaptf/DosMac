import Foundation
import Testing
@testable import DosMacCore

struct EngineIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DOSMAC_TEST_ENGINE"] != nil))
    @MainActor func realDOSWritesToHostExchange() async throws {
        #if os(macOS)
        let engine = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DOSMAC_TEST_ENGINE"]!)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DosMac-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("Smoke.dosmac")
        let payload = package.appendingPathComponent("payload")
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        let manifest = PackageManifest(id: "smoke", title: "Smoke", summary: "", author: "DosMac", license: "CC0-1.0", executable: "TEST.BAT")
        try JSONEncoder().encode(manifest).write(to: package.appendingPathComponent("manifest.json"))
        try Data("@echo off\r\necho DOSMAC_OK>D:\\RESULT.TXT\r\nexit\r\n".utf8).write(to: payload.appendingPathComponent("TEST.BAT"))
        let library = try LibraryStore(root: root.appendingPathComponent("Library"))
        let installed = try await library.install(from: package)
        let session = EmulatorSession()
        try await session.start(program: installed, library: library, engine: engine)
        let deadline = Date().addingTimeInterval(30)
        while case .running = session.state, Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        defer { session.stop() }
        let log = (try? String(contentsOf: library.programURL(installed.id).appendingPathComponent("session.log"), encoding: .utf8)) ?? "No log"
        #expect(session.state == .exited(0), Comment(rawValue: log))
        let result = try String(contentsOf: library.exchangeURL.appendingPathComponent("RESULT.TXT"), encoding: .ascii)
        #expect(result.trimmingCharacters(in: .whitespacesAndNewlines) == "DOSMAC_OK")
        #endif
    }
}
