import SwiftUI
import DosMacCore

struct FloppyDrivePanel: View {
    @ObservedObject var model: LibraryModel
    @State private var selectedDisk = 1
    private var drive: FloppyDriveStatus { model.floppyDrive }
    private var canChange: Bool { model.diskControlsEnabled && drive.mountedNumber != nil && !drive.isChanging }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "externaldrive.fill").font(.title2).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Floppy drive · A:").font(.headline)
                    if let mounted = drive.mountedDisk {
                        Text("Disk \(mounted.number) of \(drive.disks.count) is inserted").font(.callout)
                        Text(mounted.label).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    } else {
                        Text("Waiting for DOSBox-X to mount the disk set…").font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if drive.isChanging { ProgressView().controlSize(.small) }
                Button("Show installer") { model.session.showEmulator() }
            }
            if !model.diskControlsEnabled {
                Text("To use these buttons, allow DosMac in macOS Accessibility settings. You can also switch disks directly in DOSBox-X with F12 + O (Fn may be needed on a Mac keyboard).").font(.callout).foregroundStyle(.secondary)
                Button("Enable disk controls…") {
                    model.session.requestDiskControlAccess()
                    model.refreshDiskControlAccess()
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { diskPicker; insertButton; nextButton }
                VStack(alignment: .leading, spacing: 12) { diskPicker; HStack { insertButton; nextButton } }
            }
            if let message = drive.message { Text(message).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            Text("When Setup asks for another disk, insert it here, then return to the installer and press Enter. Changes are confirmed by DOSBox-X; you can also switch back to an earlier disk.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.green.opacity(0.25)))
        .onChange(of: drive.mountedNumber, initial: true) { _, number in
            if let number { selectedDisk = number }
        }
        .task { model.refreshDiskControlAccess() }
    }

    private var diskPicker: some View {
        Picker("Disk", selection: $selectedDisk) {
            ForEach(drive.disks) { disk in
                Text("Disk \(disk.number) · \(disk.label)").tag(disk.number)
            }
        }.labelsHidden().disabled(drive.isChanging).frame(maxWidth: 330)
        .accessibilityLabel("Choose installation disk")
    }

    private var insertButton: some View {
        Button("Insert selected disk") { Task { await model.selectFloppy(selectedDisk) } }
            .disabled(!canChange || selectedDisk == drive.mountedNumber)
    }

    private var nextButton: some View {
        Button {
            if let next = drive.nextDisk { Task { await model.selectFloppy(next.number) } }
        } label: {
            Label(drive.nextDisk.map { "Next disk · \($0.number)" } ?? "Next disk", systemImage: "forward.end.fill")
        }.buttonStyle(.borderedProminent).disabled(!canChange || drive.disks.count < 2)
    }
}
