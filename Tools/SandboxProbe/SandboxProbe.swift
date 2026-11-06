import Foundation
import Darwin
import DosMacVM
import DosMacPlatform

/// Original boot-code acceptance inside the same sandbox used by the store target.
/// No commercial guest images, developer engine paths, or user documents are used.
@main struct SandboxProbe {
    @MainActor static func main() async {
        let fm = FileManager.default
        let root = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DosMacProbe-\(UUID().uuidString)")
        var report: [String: Any] = [:]
        let session = MachineSession()
        var importedFixture: URL?
        do {
            guard DistributionPolicy.current.channel == .appStore else { throw VMError.invalid("Wrong distribution policy") }
            guard root.path.contains("/Containers/org.dosmac.probe/") else { throw VMError.invalid("Not running in the expected app container") }
            guard let index = CommandLine.arguments.firstIndex(of: "--outside-marker"), index + 1 < CommandLine.arguments.count else { throw VMError.invalid("Run this probe with scripts/check-sandbox.py") }
            let marker = CommandLine.arguments[index + 1]
            guard marker.hasPrefix("/tmp/dosmac-sandbox-probe-"), !marker.contains("..") else { throw VMError.invalid("Invalid outside test marker") }
            let outside = URL(fileURLWithPath: marker)
            do {
                _ = try Data(contentsOf: outside)
                throw VMError.invalid("The sandbox allowed the outside marker")
            } catch let error as VMError { throw error }
            catch { report["outsideFileReadBlocked"] = true }
            if let index = CommandLine.arguments.firstIndex(of: "--choose-windows98-fixture"), index + 1 < CommandLine.arguments.count {
                importedFixture = try FixtureImporter.chooseWindows98(initialPath: CommandLine.arguments[index + 1])
            }
            if CommandLine.arguments.contains("--reuse-private-fixture") { importedFixture = try FixtureImporter.reuseWindows98() }
            if CommandLine.arguments.contains("--windows98") {
                guard let importedFixture else { throw VMError.invalid("Select the licensed fixture through the file picker") }
                report.merge(try await Windows98Acceptance.run(root: root, session: session, fixture: importedFixture)) { _, new in new }
            } else {
            let store = try MachineStore(root: root.appendingPathComponent("Machines"))
            var machine = try await store.create(name: "DosMac sandbox acceptance", guest: .msdos622)
            let image = DiagnosticBootDisk.make()
            let floppy = root.appendingPathComponent("BOOT.IMG")
            try image.write(to: floppy)
            machine = try await store.importMedia([floppy], into: machine, cdrom: false)
            machine.sharedFolder = CommandLine.arguments.contains("--sharing")
            try await session.start(machine, directory: store.directory(for: machine.id), muted: true)
            let deadline = Date().addingTimeInterval(30)
            var ready = false
            while Date() < deadline {
                if (try await session.textScreen()).contains("DosMac PC hardware check"), session.frameSnapshot() != nil { ready = true; break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard ready else { throw VMError.timeout("Sandboxed guest boot") }
            report["guestBootConfirmed"] = true
            report["nativeFramebufferConfirmed"] = true
            let width = session.frameSnapshot()?.width
            try await session.tap("ret")
            let graphicsDeadline = Date().addingTimeInterval(10)
            while session.frameSnapshot()?.width == width, Date() < graphicsDeadline { try await Task.sleep(for: .milliseconds(100)) }
            guard session.frameSnapshot()?.width != width else { throw VMError.invalid("Guest keyboard or framebuffer mode switch failed") }
            let paletteDeadline = Date().addingTimeInterval(10)
            var colors = 0
            while Date() < paletteDeadline {
                if let frame = session.frameSnapshot() {
                    colors = Set(stride(from: 0, to: frame.pixels.count - 3, by: 4).map { frame.pixels[$0..<($0+3)] }).count
                    if colors >= 8 { break }
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard colors >= 8 else { throw VMError.invalid("The diagnostic did not render its color pattern") }
            report["guestKeyboardConfirmed"] = true
            report["colorPatternConfirmed"] = true
            try await session.tap("ret")
            let textDeadline = Date().addingTimeInterval(10)
            while session.frameSnapshot()?.width != width, Date() < textDeadline { try await Task.sleep(for: .milliseconds(100)) }
            guard session.frameSnapshot()?.width == width, (try await session.textScreen()).contains("DosMac PC hardware check") else { throw VMError.invalid("The diagnostic did not return to its text screen") }
            report["returnToTextConfirmed"] = true
            try await session.pause()
            guard try await session.queryStatus()["status"]?.string == "paused" else { throw VMError.invalid("Pause failed") }
            try await session.resume()
            report["lifecycleConfirmed"] = true
            report["sharingRequested"] = machine.sharedFolder == true
            await session.powerOff()
            }
            report["success"] = true
        } catch {
            report["success"] = false
            report["error"] = error.localizedDescription
            await session.powerOff()
        }
        let success = report["success"] as? Bool == true
        if success {
            try? fm.removeItem(at: root)
            // Keep the privately imported baseline for repeated acceptance runs.
        }
        let data = (try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(success ? 0 : 1)
    }
}
