import DosMacVM
import SwiftUI

struct Windows9xInstallView: View {
  @ObservedObject var model: MachineLibraryModel
  let initialGuest: GuestSystem
  var otherSessionRunning = false
  @Environment(\.dismiss) private var dismiss
  @State private var guest = GuestSystem.windows98
  @State private var key = ""
  @State private var acceptedLicense = false
  @State private var error: String?
  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Windows version", selection: $guest) {
            Text("Windows 98 SE · English OEM").tag(GuestSystem.windows98)
            Text("Windows 95 · English CD").tag(GuestSystem.windows95)
          }
          Text(
            "DosMac downloads the installation CD and startup disk, verifies their checksums, creates a new computer, and starts batch Setup. Your existing computers are kept separately."
          )
          .foregroundStyle(.secondary)
          Text(
            "Windows 9x installation is experimental. Setup may ask for your license or product key, and unfamiliar prompts remain available for manual control."
          )
          .font(.caption).foregroundStyle(.secondary)
        }
        Section("Your Windows license") {
          SecureField("Product key (optional)", text: $key).autocorrectionDisabled()
          Text(
            "Leave this empty to enter your key inside Windows Setup. Keys are not stored in Library metadata or sent to the download website; Setup's private answer file contains the value you enter."
          )
          .font(.caption).foregroundStyle(.secondary)
          Toggle(
            "I have reviewed and accept this release’s license; skip its license page",
            isOn: $acceptedLicense)
          Link(
            "Review source media and accompanying documentation",
            destination: URL(
              string: "https://archive.org/details/" + Windows9xProvisioner.source(for: guest).item)!
          )
        }
        Section("Included") {
          Label("1 GB private hard disk", systemImage: "internaldrive")
          Label("64 MB shared disk · DOS and Windows", systemImage: "externaldrive")
          Label("Live shared folder · Windows networking", systemImage: "network")
          Text(
            "About 625 MB to download. Setup files are copied to C: so the computer can restart without swapping disks. No Windows images or product keys are included in the app or repository."
          )
          .font(.caption).foregroundStyle(.secondary)
        }
        if let error { Text(error).foregroundStyle(.orange) }
        if model.active || otherSessionRunning {
          Text("Close the running session before installing another computer.").foregroundStyle(
            .orange)
        }
      }.formStyle(.grouped)
        .navigationTitle("Install Windows")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button("Install \(guest.title)") {
              do {
                _ = try Windows9xRecipe.answerFile(
                  guest: guest, productKey: key, acceptedLicense: acceptedLicense)
                model.installWindows9x(
                  guest: guest, productKey: key, acceptedLicense: acceptedLicense)
                key = ""
                dismiss()
              } catch { self.error = error.localizedDescription }
            }.disabled(model.active || model.busy || otherSessionRunning)
          }
        }
    }.tint(workspaceMint)
      #if os(macOS)
        .frame(width: 680, height: 690)
      #endif
      .onAppear { guest = initialGuest }
  }
}
