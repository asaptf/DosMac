import Foundation
import Testing
import DosMacPlatform
@testable import DosMacCore

struct DistributionPolicyTests {
    @Test @MainActor func storeDoesNotExecuteAUserSuppliedNativeEngine() throws {
        #if os(macOS)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dosmac-policy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        #expect(EmulatorSession.findEngine(customPath: file.path, policy: .init(channel: .developer)) == file)
        #expect(EmulatorSession.findEngine(customPath: file.path, policy: .init(channel: .appStore)) == nil)
        #endif
    }
    @Test func storeRejectsEngineInstallationWithoutNetworkOrProgress() async throws {
        #if os(macOS)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dosmac-no-download-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            _ = try await ManagedEngine(root: root).ensureInstalled(policy: .init(channel: .appStore)) { _ in Issue.record("Store attempted native engine preparation") }
            Issue.record("Store permitted native engine installation")
        } catch DosMacError.engineInstallation { }
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #endif
    }
    @Test func storeRejectsUnreviewedDownloadsBeforeFetching() async throws {
        let sources = SoftwareSources(policy: .init(channel: .appStore))
        do {
            _ = try await sources.inspect(URL(string: "https://example.invalid/install.zip")!)
            Issue.record("Store accepted an unreviewed source")
        } catch DosMacError.invalidPackage(let message) {
            #expect(message.contains("Archive catalog downloads are unavailable"))
        }
    }

}
