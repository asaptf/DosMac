import DosMacCore
import DosMacVM
import SwiftUI

struct SourceInstallView: View {
  @ObservedObject var library: LibraryModel
  @ObservedObject var machines: MachineLibraryModel
  @ObservedObject var apps: WorkspaceLibraryModel
  let initialAddress: String
  var onAdded: (String, Bool) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var address = ""
  @State private var releases: [RemoteRelease] = []
  @State private var prepared: PreparedImport?
  @State private var entry = ""
  @State private var machineID: UUID?
  @State private var windows = false
  @State private var bootDisk = false
  @State private var openAfter = false
  @State private var newComputer = false
  @State private var busy = false
  @State private var message = ""
  @State private var error: String?
  @State private var service = SoftwareSources()
  @State private var operation: Task<Void, Never>?
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          VStack(alignment: .leading, spacing: 8) {
            Text("A new old favorite.").font(.title2.bold())
            Text(
              "Choose a release to add to your library. Setup disks stay together and can be changed from the running session."
            ).font(.callout).foregroundStyle(.secondary)
          }
          HStack {
            TextField("Paste a WinWorld, Internet Archive, or direct download link", text: $address)
              .textFieldStyle(.roundedBorder).autocorrectionDisabled().onSubmit { inspect() }
              .disabled(busy || prepared != nil)
            Button("Find releases") { inspect() }.disabled(
              busy || address.isEmpty || prepared != nil)
          }
          if busy {
            HStack {
              ProgressView().controlSize(.small)
              Text(message)
              Spacer()
              Button("Cancel") { operation?.cancel() }
            }.font(.callout)
          }
          if let error {
            Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
          }
          if let prepared {
            VStack(alignment: .leading, spacing: 16) {
              Text(prepared.title).font(.headline)
              if prepared.isInstallationMedia {
                Label(
                  "\(prepared.floppyDisks.count) setup disks ready", systemImage: "externaldrive"
                ).foregroundStyle(workspaceMint)
                Picker("Install in", selection: $machineID) {
                  Text("Choose a computer").tag(UUID?.none)
                  ForEach(machines.machines) { Text($0.name).tag(Optional($0.id)) }
                }
                Button("Create an empty computer…") { newComputer = true }.disabled(
                  busy || machines.active)
                TextField("Setup program", text: $entry).font(.system(.body, design: .monospaced))
                  .textFieldStyle(.roundedBorder)
                Picker("Setup runs in", selection: $windows) {
                  Text("DOS").tag(false)
                  Text("Windows 3.1").tag(true)
                }
                Toggle("Boot from the first setup disk", isOn: $bootDisk)
                Text(
                  bootDisk
                    ? "For operating-system setup. Use a new computer when installing another system; Setup can replace its existing OS."
                    : "DosMac will open Setup with the first disk inserted. Continue its installation on screen and use Disks to switch media."
                ).font(.caption).foregroundStyle(.secondary)
                if machines.active {
                  Text("Close the running computer before adding a new disk set.").font(.caption)
                    .foregroundStyle(.orange)
                }
                Button("Add Setup to Library") { addInstaller(prepared) }.buttonStyle(
                  .borderedProminent
                ).foregroundStyle(workspaceBase).disabled(
                  busy || machineID == nil || machines.active || machines.busy)
              } else {
                Text(
                  "This program package uses classic DOS compatibility and will appear beside your computer’s apps in Library."
                ).font(.callout).foregroundStyle(.secondary)
                Picker("Start program", selection: $entry) {
                  ForEach(prepared.candidates, id: \.self) { Text($0).tag($0) }
                }
                Button("Add to Library") { addPackage(prepared) }.buttonStyle(.borderedProminent)
                  .foregroundStyle(workspaceBase).disabled(busy)
              }
              Toggle("Open after adding", isOn: $openAfter).disabled(
                busy || machines.active || library.running)
              Button("Choose another release") {
                Task {
                  await service.discard(prepared)
                  self.prepared = nil
                }
              }.disabled(busy)
            }.padding(20).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
          } else {
            ForEach(releases) { release in
              HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                  Text(release.title).font(.headline).lineLimit(2)
                  Text(release.pageURL.host ?? "Software source").font(.caption).foregroundStyle(
                    .secondary)
                }
                Spacer()
                Button("Get release") { download(release) }.disabled(busy)
              }.padding(18).background(
                .white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            }
          }
          HStack {
            Text("ZIP / 7z / DOS programs up to 32 MiB").font(.caption).foregroundStyle(.secondary)
            Spacer()
            if let url = URL(string: address), url.scheme == "https" {
              Link("Open source website", destination: url).font(.caption)
            }
          }
        }.padding(26)
      }.background(workspaceBase).navigationTitle("Add software")
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }.disabled(busy)
          }
        }
    }.tint(workspaceMint)
      #if os(macOS)
        .frame(width: 720, height: 660)
      #endif
      .onAppear {
        machineID = machines.selected ?? machines.machines.first?.id
        address = initialAddress
        if !address.isEmpty { inspect() }
      }
      .sheet(isPresented: $newComputer) {
        NewComputerForm(model: machines) { machineID = machines.selected }
      }
      .onDisappear {
        operation?.cancel()
        if let prepared { Task { await service.discard(prepared) } }
      }
      .interactiveDismissDisabled(busy)
  }
  private func inspect() {
    guard !busy, let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines))
    else {
      error = "Enter an HTTPS source link."
      return
    }
    busy = true
    error = nil
    releases = []
    message = "Finding available releases…"
    operation = Task {
      defer { busy = false }
      do { releases = try await service.inspect(url) } catch is CancellationError {} catch {
        self.error = error.localizedDescription
      }
    }
  }
  private func download(_ release: RemoteRelease) {
    busy = true
    error = nil
    message = "Downloading and checking the release…"
    operation = Task {
      defer { busy = false }
      do {
        let result = try await service.prepare(release)
        if Task.isCancelled {
          await service.discard(result)
          return
        }
        prepared = result
        if result.isInstallationMedia {
          entry = "A:\\SETUP.EXE"
          windows = result.title.lowercased().contains("for windows")
          if let first = result.floppyDisks.first,
            let data = try? Data(
              contentsOf: result.package.appendingPathComponent("payload").appendingPathComponent(
                first.imagePath)), let disk = try? FAT12Disk(data: data),
            let name = ["SETUP.EXE", "INSTALL.EXE", "INSTALL.BAT", "SETUP.BAT"].first(where: {
              disk.fileNames.contains($0)
            })
          {
            entry = "A:\\" + name
          }
        } else {
          entry = result.candidates.first ?? ""
        }
      } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
  }
  private func addInstaller(_ prepared: PreparedImport) {
    guard let store = machines.store, let machineID,
      let machine = machines.machines.first(where: { $0.id == machineID }), !machines.active,
      !machines.busy
    else { return }
    busy = true
    message = "Adding the installer to your computer…"
    error = nil
    operation = Task {
      defer { busy = false }
      do {
        var app = GuestApplication(
          machineID: machineID, title: String(prepared.title.prefix(160)), executable: entry,
          windows: windows, kind: .installer, source: prepared.source, bootFromMedia: bootDisk)
        try app.validate()
        let urls = prepared.floppyDisks.map {
          prepared.package.appendingPathComponent("payload").appendingPathComponent($0.imagePath)
        }
        let updated = try await store.importMedia(
          urls, into: machine, cdrom: false, names: prepared.floppyDisks.map(\.label))
        app.mediaIDs = updated.floppies.suffix(urls.count).map(\.id)
        guard await apps.save(app) else {
          error = apps.error
          apps.error = nil
          return
        }
        await machines.refresh()
        await service.discard(prepared)
        self.prepared = nil
        onAdded(app.id.uuidString, openAfter)
        dismiss()
      } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
  }
  private func addPackage(_ prepared: PreparedImport) {
    busy = true
    message = "Adding the app to Library…"
    error = nil
    operation = Task {
      defer { busy = false }
      do {
        let package = try await service.finalize(prepared, executable: entry, profile: .dos)
        if await library.install(package) {
          await service.discard(prepared)
          self.prepared = nil
          onAdded("classic-" + (library.current?.id ?? ""), openAfter)
          dismiss()
        } else {
          error = library.error
          library.error = nil
        }
      } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
  }
}

private struct NewComputerForm: View {
  @ObservedObject var model: MachineLibraryModel
  var onCreated: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var name = "My retro PC"
  @State private var guest = GuestSystem.windows31
  var body: some View {
    NavigationStack {
      Form {
        TextField("Name", text: $name)
        Picker("System", selection: $guest) {
          ForEach(GuestSystem.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        Text(
          "Creates an empty computer for operating-system setup. Windows application installers need a computer where DOS and Windows are already installed."
        ).font(.caption).foregroundStyle(.secondary)
        if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange) }
      }.padding(22).navigationTitle("New computer")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }.disabled(model.busy)
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Create") {
              Task {
                model.error = nil
                await model.create(name: name, guest: guest)
                if model.error == nil {
                  onCreated()
                  dismiss()
                }
              }
            }.disabled(model.busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
          }
        }
    }
    #if os(macOS)
      .frame(width: 500, height: 300)
    #endif
  }
}
