import Foundation
import Testing
@testable import DosMacCore

struct StartupTests {
    @Test func dosPromptDoesNotExecuteInstallerOrMountFloppies() throws {
        var manifest = PackageManifest(id: "dos", title: "DOS", summary: "", author: "", license: "CC0", executable: "INSTALL.BAT")
        manifest.startupMode = .dosPrompt
        let config = try DOSBoxConfiguration.render(program: InstalledProgram(manifest: manifest, installedAt: Date()), driveC: URL(fileURLWithPath: "/tmp/drive-c"), exchange: URL(fileURLWithPath: "/tmp/exchange"))
        #expect(config.contains("\nc:\ncd \\\n"))
        #expect(!config.contains("INSTALL.BAT"))
        #expect(!config.contains("imgmount"))
    }

    @Test func savesDOSPreferenceAndCanSwitchToInstalledWindows() async throws {
        let (root, package, library) = try LibraryTests().fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let installed = try await library.install(from: package)
        let drive = library.programURL(installed.id).appendingPathComponent("DriveC")
        // DOS does not require the previous installer executable to remain present.
        try FileManager.default.removeItem(at: drive.appendingPathComponent("HELLO.BAT"))
        try await library.updateStartup(installed, executable: "HELLO.BAT", profile: .dos, mode: .dosPrompt)
        let prompt = try #require(await library.programs().first)
        #expect(prompt.manifest.effectiveStartupMode == .dosPrompt)
        let windows = drive.appendingPathComponent("WINDOWS")
        try FileManager.default.createDirectory(at: windows, withIntermediateDirectories: true)
        try Data([0x4d, 0x5a]).write(to: windows.appendingPathComponent("WIN.COM"))
        try await library.updateStartup(prompt, executable: "WINDOWS/WIN.COM", profile: .windows31)
        let updated = try #require(await library.programs().first)
        #expect(updated.manifest.effectiveStartupMode == .program)
        #expect(updated.manifest.hasWindowsEntryPoint)
        let config = try DOSBoxConfiguration.render(program: updated, driveC: drive, exchange: library.exchangeURL)
        #expect(config.contains("set PATH=%PATH%;C:\\WINDOWS"))
        #expect(config.contains("cd \\WINDOWS\nWIN.COM"))
        #expect(!config.contains("HELLO.BAT"))
    }

    @Test func oldManifestDefaultsToProgramLaunch() throws {
        let manifest = PackageManifest(id: "legacy", title: "Legacy", summary: "", author: "", license: "CC0", executable: "START.EXE")
        let data = try JSONEncoder().encode(manifest)
        #expect(!String(decoding: data, as: UTF8.self).contains("startupMode"))
        let decoded = try JSONDecoder().decode(PackageManifest.self, from: data)
        #expect(decoded.effectiveStartupMode == .program)
    }
}
