import SwiftUI
import DosMacCore

struct SoftwareSourcesView: View {
    @ObservedObject var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var service = SoftwareSources()
    @State private var address = ""
    @State private var releases: [RemoteRelease] = []
    @State private var prepared: PreparedImport?
    @State private var entry = ""
    @State private var profile = MachineProfile.dos
    @State private var launchAfterInstall = false
    @State private var busy = false
    @State private var message = ""
    @State private var error: String?
    @State private var operation: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Find a new old favorite.").font(.title2.bold())
                    Text("Paste a WinWorld product or download page, or a direct HTTPS link to a ZIP, 7z, EXE, COM, or BAT file.").font(.callout).foregroundStyle(.secondary)
                    TextField("https://winworldpc.com/product/…", text: $address).textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never).keyboardType(.URL)
                        #endif
                    HStack {
                        Button("Find downloads") { inspect() }.buttonStyle(.borderedProminent).disabled(busy || address.isEmpty || prepared != nil)
                        Link("Browse WinWorld", destination: URL(string: "https://winworldpc.com/library/applications")!)
                    }
                    Picker("Machine profile", selection: $profile) {
                        ForEach(MachineProfile.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.disabled(busy)
                    Toggle("Launch after installation", isOn: $launchAfterInstall).disabled(busy)
                    Text("Disk images prepare a guest installer; its setup and disk changes may require interaction. Windows applications need a working Windows environment.").font(.caption).foregroundStyle(.secondary)
                    if busy {
                        HStack { ProgressView().controlSize(.small); Text(message).font(.callout); Spacer(); Button("Cancel") { operation?.cancel() } }
                    }
                    if let error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                    if let prepared {
                        Divider()
                        Text(prepared.title).font(.headline)
                        Text("Choose the DOS entry point. Setup programs run inside the guest.").font(.callout).foregroundStyle(.secondary)
                        Picker("Start program", selection: $entry) { ForEach(prepared.candidates, id: \.self) { Text($0).tag($0) } }
                        Button("Install selected program") { install(prepared, executable: entry) }.buttonStyle(.borderedProminent).disabled(busy)
                    } else {
                        ForEach(releases) { release in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(release.title).font(.headline)
                                    Text(release.pageURL.host ?? "Web source").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Install") { download(release) }.disabled(busy)
                            }.padding(16).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    Text("Downloads: up to 32 MiB. Expanded files: up to 128 MiB. Password-protected archives, CD images, and automatic Windows installation are not supported in this preview.").font(.caption2).foregroundStyle(.secondary)
                }.padding(24)
            }
            .navigationTitle("Software sources")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 680, height: 640)
        #endif
        .onDisappear {
            operation?.cancel()
            if let prepared { Task { await service.discard(prepared) } }
        }
        .interactiveDismissDisabled(busy)
    }

    private func inspect() {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else { error = "Enter a valid HTTPS URL."; return }
        busy = true; error = nil; releases = []; message = "Reading source…"
        operation = Task {
            defer { busy = false }
            do { releases = try await service.inspect(url) }
            catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }

    private func download(_ release: RemoteRelease) {
        busy = true; error = nil; message = "Downloading and checking archive…"
        operation = Task {
            defer { busy = false }
            do {
                let result = try await service.prepare(release)
                if Task.isCancelled { await service.discard(result); return }
                if result.candidates.count == 1 {
                    await finish(result, executable: result.candidates[0])
                } else {
                    prepared = result
                    entry = result.candidates.first ?? ""
                }
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }

    private func install(_ prepared: PreparedImport, executable: String) {
        busy = true; error = nil; message = "Installing program…"
        operation = Task { defer { busy = false }; await finish(prepared, executable: executable) }
    }

    private func finish(_ prepared: PreparedImport, executable: String) async {
        do {
            let url = try await service.finalize(prepared, executable: executable, profile: profile)
            try Task.checkCancellation()
            if await library.install(url) {
                await service.discard(prepared)
                self.prepared = nil
                if launchAfterInstall { await library.launch() }
                dismiss()
            } else {
                self.prepared = prepared
                entry = executable
                error = library.error
                library.error = nil
            }
        } catch {
            self.prepared = prepared
            self.error = error.localizedDescription
        }
    }
}
