import AppKit
import Foundation
import UniformTypeIdentifiers
import DosMacVM

@MainActor enum FixtureImporter {
    static func chooseWindows98(initialPath: String) throws -> URL {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.finishLaunching()
        application.activate()
        let panel = NSOpenPanel()
        panel.title = "Choose a stopped, licensed Windows 98 test disk"
        panel.message = "The test uses a private copy. Choose a stopped backup, not a running computer's disk. No guest media or keys are published."
        panel.prompt = "Use private copy"
        panel.allowedContentTypes = [.data]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        let initial = URL(fileURLWithPath: initialPath)
        panel.directoryURL = initial.deletingLastPathComponent()
        panel.nameFieldStringValue = initial.lastPathComponent
        guard panel.runModal() == .OK, let source = panel.url else { throw VMError.invalid("Private fixture selection was cancelled") }
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        let info = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true else { throw VMError.invalid("Choose a regular stopped QCOW2 disk") }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DosMacFixtures")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fixture = directory.appendingPathComponent("windows98-\(UUID().uuidString).qcow2")
        try FileManager.default.copyItem(at: source, to: fixture)
        try Data(fixture.lastPathComponent.utf8).write(to: directory.appendingPathComponent("last-fixture.txt"), options: .atomic)
        return fixture
    }
    static func reuseWindows98() throws -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DosMacFixtures")
        let saved = try? String(contentsOf: directory.appendingPathComponent("last-fixture.txt"), encoding: .utf8)
        let candidates = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]).filter {
            $0.lastPathComponent.range(of: "^windows98-[A-Fa-f0-9-]+\\.qcow2$", options: .regularExpression) != nil
        }
        guard let fixture = candidates.first(where: { $0.lastPathComponent == saved }) ?? (candidates.count == 1 ? candidates.first : nil) else { throw VMError.invalid("Select a private fixture before using the reuse option") }
        let info = try fixture.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true else { throw VMError.invalid("Invalid private fixture") }
        return fixture
    }

}
