import DosMacVM
import DosMacPlatform
import UniformTypeIdentifiers
import SwiftUI

struct Windows9xInstallView: View {
  @ObservedObject var model: MachineLibraryModel
  let initialGuest: GuestSystem
  var otherSessionRunning = false
  @Environment(\.dismiss) private var dismiss
  @State private var iso: URL?
  @State private var bootDisk: URL?
  @State private var choosingISO = false
  @State private var importing = false
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
            DistributionPolicy.current.allowsUnreviewedCatalogs ? "DosMac downloads the installation CD and startup disk, verifies their checksums, creates a new computer, and starts batch Setup. Your existing computers are kept separately." : "Choose your own installation ISO and startup floppy. DosMac copies them into a private computer and starts guided Setup. Your original files stay unchanged."
          )
          .foregroundStyle(.secondary)
          Text(
            "Windows 9x installation is experimental. Setup may ask for your license or product key, and unfamiliar prompts remain available for manual control."
          )
          .font(.caption).foregroundStyle(.secondary)
        }
        if !DistributionPolicy.current.allowsUnreviewedCatalogs {
          Section("Your installation images") {
            Button(iso?.lastPathComponent ?? "Choose Windows ISO…") { choosingISO = true; importing = true }
            Button(bootDisk?.lastPathComponent ?? "Choose startup floppy…") { choosingISO = false; importing = true }
            Text("Use an English Windows 98 SE OEM startup disk with CD-ROM support, including MSCDEX and OAKCDROM. The startup disk is also used to prepare Windows 95.").font(.caption).foregroundStyle(.secondary)
          }
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
          if DistributionPolicy.current.allowsUnreviewedCatalogs { Link(
            "Review source media and accompanying documentation",
            destination: URL(
              string: "https://archive.org/details/" + Windows9xProvisioner.source(for: guest).item)!
          ) }
        }
        Section("Included") {
          Label("1 GB private hard disk", systemImage: "internaldrive")
          Label(DistributionPolicy.current.allowsHostDiskMounts ? "64 MB shared disk · DOS and Windows" : "64 MB guest data disk", systemImage: "externaldrive")
          Label("Live shared folder · Windows networking", systemImage: "network")
          Text(
            DistributionPolicy.current.allowsUnreviewedCatalogs ? "About 625 MB to download. Setup files are copied to C: so the computer can restart without swapping disks. No Windows images or product keys are included in the app or repository." : "Setup files are copied to C: so installation can restart without swapping disks. No Windows downloads are offered in this edition."
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
                if DistributionPolicy.current.allowsUnreviewedCatalogs {
                  model.installWindows9x(guest: guest, productKey: key, acceptedLicense: acceptedLicense)
                } else if let iso, let bootDisk {
                  model.installWindows9xFromMedia(guest: guest, iso: iso, bootDisk: bootDisk, productKey: key, acceptedLicense: acceptedLicense)
                }
                key = ""
                dismiss()
              } catch { self.error = error.localizedDescription }
            }.disabled(model.active || model.busy || otherSessionRunning || (!DistributionPolicy.current.allowsUnreviewedCatalogs && (iso == nil || bootDisk == nil)))
          }
        }
    }.tint(workspaceMint)
      #if os(macOS)
        .frame(width: 680, height: 690)
      #endif
      .onAppear { guest = initialGuest }
      .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
        do { if let url = try result.get().first { if choosingISO { iso = url } else { bootDisk = url } } }
        catch { self.error = error.localizedDescription }
      }
  }
}
