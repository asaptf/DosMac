#if os(macOS)
import AppKit
@preconcurrency import ApplicationServices

/// Sends only documented emulator shortcuts to the owned process, never global keys.
@MainActor
enum MacEmulatorControls {
    static var isEnabled: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func activate(pid: Int32) {
        NSRunningApplication(processIdentifier: pid)?.activate(options: [])
    }

    static func nextDisk(pid: Int32) async throws {
        guard isEnabled else { throw DosMacError.diskControl("Enable Accessibility for DosMac to use disk buttons, or press F12 + O in DOSBox-X.") }
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { throw DosMacError.diskControl("The emulator is no longer running.") }
        app.activate(options: [])
        try await Task.sleep(for: .milliseconds(150))
        // macOS virtual key codes: F12 = 111; ANSI O = 31.
        guard let hostDown = CGEvent(keyboardEventSource: nil, virtualKey: 111, keyDown: true),
              let hostUp = CGEvent(keyboardEventSource: nil, virtualKey: 111, keyDown: false),
              let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 31, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 31, keyDown: false) else {
            throw DosMacError.diskControl("Could not create the disk-switch shortcut.")
        }
        hostDown.postToPid(pid)
        defer { keyUp.postToPid(pid); hostUp.postToPid(pid) }
        try await Task.sleep(for: .milliseconds(40))
        keyDown.postToPid(pid)
        try await Task.sleep(for: .milliseconds(40))
    }
}
#endif
