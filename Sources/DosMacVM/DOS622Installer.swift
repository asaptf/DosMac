import Foundation

public enum DOSSetupAction: Equatable, Sendable {
    case wait, enter, disk(Int), finish, verifyVersion, installed, review(String)
}

/// Conservative rules for English MS-DOS 6.22 Setup on a newly created blank machine.
public enum DOS622Rules {
    public static func action(screen: String, rebooted: Bool) -> DOSSetupAction {
        let text = screen.lowercased().replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: " +", with: " ", options: .regularExpression)
        if text.contains("license agreement") || text.contains("licence agreement") { return .review("Review the license inside the guest, then continue the assistant.") }
        if rebooted, text.contains("c:\\>") { return text.contains("6.22") ? .installed : .verifyVersion }
        if text.contains("setup is now complete") || text.contains("setup is complete") || (text.contains("remove disks from all floppy disk drives") && text.contains("enter")) { return .finish }
        if text.contains("insert"), let re = try? NSRegularExpression(pattern: "(?:setup disk|diskette)\\s*#?\\s*([1-9])"), let match = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range(at: 1), in: text), let number = Int(text[range]) { return .disk(number) }
        if text.contains("welcome to setup"), text.contains("enter") { return .enter }
        if text.contains("configure unallocated disk space"), text.contains("enter") { return .enter }
        if text.contains("restart your computer"), text.contains("enter") { return .enter }
        if text.contains("format"), text.contains("drive c"), text.contains("enter") { return .enter }
        if text.contains("system settings"), text.contains("settings are correct") { return .enter }
        if text.contains("c:\\dos"), text.contains("directory"), text.contains("enter") { return .enter }
        return .wait
    }
}

#if os(macOS)
@MainActor
public final class DOS622Installer {
    private let session: MachineSession
    private let disks: [MachineMedia]
    public init(session: MachineSession, disks: [MachineMedia]) { self.session = session; self.disks = disks }

    public func run(report: @escaping @MainActor (String, Bool) async -> Void) async throws -> Bool {
        guard disks.count >= 3 else { throw VMError.invalid("The DOS 6.22 recipe requires its complete setup disk set.") }
        var lastHandled = "", rebooted = false, lastProgress = Date()
        let deadline = Date().addingTimeInterval(600)
        while Date() < deadline, session.isActive {
            try Task.checkCancellation()
            let screen = try await session.textScreen()
            let action = DOS622Rules.action(screen: screen, rebooted: rebooted)
            let fingerprint = String(describing: action) + screen
            if action != .wait, fingerprint != lastHandled {
                switch action {
                case .enter:
                    await report("Continuing DOS Setup…", false)
                    try await session.tap("ret")
                case .disk(let number):
                    guard number <= disks.count else { await report("DOS Setup requested disk \(number), which is not in this recipe.", true); return false }
                    await report("Inserting DOS Setup disk \(number)…", false)
                    try await session.insert(disks[number-1], cdrom: false)
                    try await session.tap("ret")
                case .finish:
                    await report("DOS Setup finished. Ejecting the installer and restarting from HDD…", false)
                    try await session.eject(cdrom: false)
                    try await session.tap("ret"); rebooted = true
                case .installed:
                    await report("MS-DOS 6.22 is running from the virtual hard disk.", false)
                    return true
                case .verifyVersion:
                    await report("Verifying the installed DOS version…", false)
                    try await session.typeText("VER\n")
                case .review(let reason): await report(reason, true); return false
                case .wait: break
                }
                lastHandled = fingerprint; lastProgress = Date()
            }
            if Date().timeIntervalSince(lastProgress) > 30 {
                await report("Setup needs attention. Use the guest screen; the assistant will not guess at an unknown prompt.", true)
                return false
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw VMError.timeout("DOS installation")
    }
}
#endif
