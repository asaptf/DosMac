#if os(macOS)
import AppKit
import DosMacVM

@MainActor
final class DosMacAppDelegate: NSObject, NSApplicationDelegate {
    static weak var machineSession: MachineSession?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let session = Self.machineSession, session.isActive else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "A machine is still running"
        alert.informativeText = "Shut down the guest OS before quitting to protect its disk. Quitting now will power off the machine and discard unsaved guest work."
        alert.addButton(withTitle: "Keep running")
        alert.addButton(withTitle: "Power off and quit")
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        session.terminate()
        return .terminateNow
    }
}
#endif
