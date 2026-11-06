import SwiftUI
import DosMacPlatform
import DosMacVM

#if os(macOS)
struct MachineEngineSettings: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Machine engine").font(.title2.bold())
            if let engine = QEMUInstallation.find() {
                Label(engine.executable.path.hasPrefix(Bundle.main.bundleURL.path) ? "Engine included in this application" : "Developer QEMU engine available", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Complete PC emulation with its own BIOS, hard disk, floppy drive and CD-ROM. The guest display and controls stay inside DosMac.").foregroundStyle(.secondary)
            } else {
                Text("This developer application has not been packaged with its machine engine yet.").foregroundStyle(.orange)
                Text("Build the self-contained developer app using the engine bundling script documented in the project README.").font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            Text(DistributionPolicy.current.allowsUnreviewedCatalogs ? "First reference stack" : "Your installation media").font(.headline)
            Text(DistributionPolicy.current.allowsUnreviewedCatalogs ? "MS-DOS 6.22 → Windows 3.1 → Word 6" : "Import DOS floppies or Windows CDs into a private computer")
            Text("OS and application media are separate from the engine and stay in your private machine library.").font(.caption).foregroundStyle(.secondary)
            Link("Privacy policy", destination: URL(string: "https://asaptf.github.io/DosMac/privacy/")!)
            Link("Support", destination: URL(string: "https://asaptf.github.io/DosMac/support/")!)
            Link("QEMU source and documentation", destination: URL(string: "https://www.qemu.org/")!)
        }.padding(24)
    }
}
#endif
