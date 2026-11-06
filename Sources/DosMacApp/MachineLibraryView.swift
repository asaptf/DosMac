import SwiftUI
import DosMacVM
import UniformTypeIdentifiers
import CryptoKit

@MainActor
final class MachineLibraryModel: ObservableObject {
    @Published var machines: [Machine] = []
    @Published var selected: UUID?
    @Published var error: String?
    @Published var notice: String?
    @Published var busy = false
    @Published var state = MachineState.stopped
    @Published var captured = false
    @Published var absolutePointer = false
    @Published var displayModes: [GuestDisplaySize] = []
    @Published var displayAutomatic = false
    @Published var displayMessage = ""
    @Published var operationMessage: String?
    private var installationTask: Task<Void, Never>?
    #if os(macOS)
    @Published var image: CGImage?
    let session = MachineSession()
    #endif
    private(set) var store: MachineStore?
    var current: Machine? { machines.first { $0.id == selected } }
    var active: Bool { switch state { case .starting, .running, .paused: true; default: false } }
    var engineReady: Bool {
        #if os(macOS)
        QEMUInstallation.find() != nil
        #else
        false
        #endif
    }

    init() {
        do { store = try MachineStore(root: MachineStore.defaultRoot) } catch { self.error = error.localizedDescription }
        #if os(macOS)
        DosMacAppDelegate.machineSession = session
        session.onState = { [weak self] state in
            self?.state = state
            if case .failed(let message) = state { self?.error = message }
        }
        session.onDisplayError = { [weak self] in self?.error = $0 }
        session.onAbsolutePointer = { [weak self] in self?.absolutePointer = $0 }
        session.onGuestDisplayChange = { [weak self] in
            guard let self else { return }
            self.displayModes = self.session.guestDisplay?.modes ?? []
            self.displayAutomatic = self.session.guestDisplay?.automatic ?? false
            self.displayMessage = self.session.guestDisplay?.message ?? ""
        }
        session.onFrame = { [weak self] frame in
            guard let provider = CGDataProvider(data: frame.pixels as CFData) else { return }
            self?.image = CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: frame.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue).union(.byteOrder32Big), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
        #endif
        Task { await refresh() }
    }
    func refresh() async {
        do { machines = try await store?.machines() ?? []; if selected == nil { selected = machines.first?.id } }
        catch { self.error = error.localizedDescription }
    }
    func create(name: String, guest: GuestSystem) async {
        guard let store else { return }; busy = true; defer { busy = false }
        #if os(macOS)
        do { let machine = try await store.create(name: name, guest: guest); await refresh(); selected = machine.id }
        catch { self.error = error.localizedDescription }
        #else
        error = "The embedded iPhone machine engine is not available yet."
        #endif
    }
    func importMedia(_ urls: [URL], cdrom: Bool) async {
        guard let store, let machine = current, !active else { return }; busy = true; defer { busy = false }
        let accessed = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { for url in accessed { url.stopAccessingSecurityScopedResource() } }
        do { _ = try await store.importMedia(urls, into: machine, cdrom: cdrom); await refresh() }
        catch { self.error = error.localizedDescription }
    }
    func setBoot(_ device: BootDevice) async {
        guard var machine = current, let store, !active else { return }
        machine.boot = device
        do { try await store.save(machine); await refresh() } catch { self.error = error.localizedDescription }
    }
    func makeExchange(_ urls: [URL]) async {
        guard let store, let current, !active, !busy else { return }
        busy = true; defer { busy = false }
        let accessed = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { accessed.forEach { $0.stopAccessingSecurityScopedResource() } }
        do { _ = try await store.createExchangeDisk(files: urls, into: current); await refresh() }
        catch { self.error = error.localizedDescription }
    }
    func openSharedDisk() async {
        guard let store, var machine = current, !active, !busy else { return }
        busy = true; defer { busy = false }
        #if os(macOS)
        do {
            let directory = store.directory(for: machine.id)
            try SharedStorage.ensureDisk(in: directory)
            machine.sharedDisk = true
            try await store.save(machine); await refresh()
            let volume = try await SharedStorage.mountForHost(in: directory)
            NSWorkspace.shared.open(volume)
        } catch { self.error = error.localizedDescription }
        #else
        error = "Host disk access is currently available on Mac."
        #endif
    }
    func openSharedFolder() async {
        guard let store, var machine = current, !busy else { return }
        #if os(macOS)
        do {
            guard !active || machine.sharedFolder == true else { throw VMError.invalid("Stop this computer once to enable its shared folder.") }
            guard SharedFolderServer.executable() != nil else { throw VMError.invalid("This build needs its embedded sharing engine. Rebuild with Samba bundled.") }
            let folder = try SharedFolderServer.folder(in: store.directory(for: machine.id))
            machine.sharedFolder = true
            try await store.save(machine); await refresh()
            NSWorkspace.shared.open(folder)
        } catch { self.error = error.localizedDescription }
        #else
        error = "Live host sharing is currently available on Mac."
        #endif
    }
    func exportExchange(_ media: MachineMedia, destination: URL) async {
        guard let store, let current, !active, !busy else { return }
        busy = true; defer { busy = false }
        let accessed = destination.startAccessingSecurityScopedResource()
        defer { if accessed { destination.stopAccessingSecurityScopedResource() } }
        do { notice = "Files exported to \(try await store.exportExchangeDisk(media, from: current, to: destination).path)" }
        catch { self.error = error.localizedDescription }
    }
    func launch() async {
        #if os(macOS)
        guard let current, let store, !active else { return }
        image = nil
        do { try await session.start(current, directory: store.directory(for: current.id)) }
        catch { self.error = error.localizedDescription }
        #endif
    }
    func launchWindows(word: Bool) async {
        #if os(macOS)
        guard let current, let store, !busy else { return }
        busy = true; defer { busy = false }
        do {
            if !active {
                image = nil
                try await session.start(current, directory: store.directory(for: current.id))
                try await session.waitForDOSPrompt()
            }
            try await session.launchWindows(word: word)
        } catch { self.error = error.localizedDescription }
        #endif
    }
    func insert(_ media: MachineMedia, cdrom: Bool) async {
        #if os(macOS)
        do { try await session.insert(media, cdrom: cdrom); objectWillChange.send() }
        catch { self.error = error.localizedDescription }
        #endif
    }
    func launchApplication(_ app: GuestApplication) async {
        #if os(macOS)
        guard !busy, let store, let machine = machines.first(where: { $0.id == app.machineID }) else { return }
        guard !active || selected == app.machineID else { error = "Close the current computer before opening another one."; return }
        busy = true; defer { busy = false }
        do {
            try app.validate()
            selected = machine.id
            if !active {
                image = nil
                var boot = machine; boot.boot = .hardDisk
                if app.bootFromMedia == true {
                    guard !app.mediaIDs.isEmpty else { throw VMError.invalid("This installer has no boot disk.") }
                    boot.boot = .floppy
                    boot.floppies = app.mediaIDs.compactMap { id in machine.floppies.first { $0.id == id } } + machine.floppies.filter { !app.mediaIDs.contains($0.id) }
                }
                try await session.start(boot, directory: store.directory(for: machine.id))
                if app.bootFromMedia == true { return }
                try await session.waitForDOSPrompt()
            }
            guard try await session.isAtDOSPrompt() else { throw VMError.invalid("Open the computer and return to the DOS prompt before starting this installer or app.") }
            if let id = app.mediaIDs.first, let disk = machine.floppies.first(where: { $0.id == id }) { try await session.insert(disk, cdrom: false) }
            try await session.typeText(GuestApplication.command(executable: app.executable, windows: app.windows))
        } catch { self.error = error.localizedDescription }
        #endif
    }
    func eject(cdrom: Bool) async {
        #if os(macOS)
        do { try await session.eject(cdrom: cdrom); objectWillChange.send() }
        catch { self.error = error.localizedDescription }
        #endif
    }
    func terminate() {
        installationTask?.cancel()
        #if os(macOS)
        session.terminate()
        #endif
    }

    func setAutomaticDisplay(_ enabled: Bool) {
        #if os(macOS)
        session.guestDisplay?.setAutomatic(enabled)
        guard let store, var machine = current else { return }
        machine.automaticDisplay = enabled
        Task {
            do { try await store.save(machine); await refresh() }
            catch { self.error = error.localizedDescription }
        }
        #endif
    }

    func installGuestTools() {
        #if os(macOS)
        guard let store, let machine = current, !active, !busy, machine.guest.needsCD,
              machine.installation?.stage == .complete else { return }
        busy = true
        installationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false; self.operationMessage = nil; self.installationTask = nil }
            do {
                func asset(_ name: String, hash: String) throws -> Data {
                    var roots = [Bundle.main.resourceURL?.appendingPathComponent("GuestTools"), Bundle.main.resourceURL?.appendingPathComponent("Resources/GuestTools"), Bundle.main.resourceURL]
                    #if SWIFT_PACKAGE
                    roots.insert(Bundle.module.resourceURL?.appendingPathComponent("Resources/GuestTools"), at: 0)
                    #endif
                    guard let url = roots.compactMap({ $0?.appendingPathComponent(name) }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { throw VMError.invalid("The embedded Guest Tools files are missing from this build.") }
                    let data = try Data(contentsOf: url)
                    guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == hash else { throw VMError.invalid("Guest Tools integrity verification failed.") }
                    return data
                }
                let files = try GuestToolsMedia.mouseFiles(
                    driver: asset("qemouse.drv", hash: "049b0cc00ba812c00fcf5c7b68e1676c827a3c7d3551bb248e280d18ce4d46b9"),
                    inf: asset("qemouse.inf", hash: "00cbdf229e586708081ae35a6840c8ffe99fbd8b8dd21137934bb28f829490f1"),
                    agent: machine.sharedFolder == true ? asset("dmagent.exe", hash: "bf4df668842e6554160be6b55cd0f312910e38bee04dfa33d35eb6b80ca157e0") : nil)
                self.operationMessage = "Saving a recovery copy before installing Guest Tools…"
                let directory = store.directory(for: machine.id)
                let backup = directory.appendingPathComponent("Backups/GuestTools-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try FileManager.default.copyItem(at: directory.appendingPathComponent("disk.qcow2"), to: backup.appendingPathComponent("disk.qcow2"))
                var boot = machine; boot.boot = .hardDisk
                self.image = nil
                try await self.session.start(boot, directory: directory)
                try await GuestToolsInstaller(session: self.session).installMouse(files: files) { self.operationMessage = $0 }
                self.notice = "Guest Tools are active. Recovery disk: \(backup.path)."
            } catch is CancellationError { self.notice = "Guest Tools paused. Review Windows before restarting or retrying; the recovery disk is kept." }
            catch { self.error = error.localizedDescription }
        }
        #endif
    }

    func prepareReferenceStack() {
        #if os(macOS)
        guard let store, !active, !busy else { return }
        busy = true
        installationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false; self.operationMessage = nil; self.installationTask = nil }
            do {
                let machine = try await ReferenceStackProvisioner.prepare(store: store, onCreate: { [weak self] created in
                    await self?.refresh(); self?.selected = created.id
                }) { [weak self] in self?.operationMessage = $0 }
                await self.refresh(); self.selected = machine.id
                try await self.session.start(machine, directory: store.directory(for: machine.id))
                await self.runDOSAssistant(machine)
            } catch is CancellationError { await self.refresh() }
            catch { self.error = error.localizedDescription; await self.refresh() }
        }
        #else
        error = "The embedded iPhone machine engine is not available yet."
        #endif
    }
    func installWindows9x(guest: GuestSystem, productKey: String, acceptedLicense: Bool) {
        #if os(macOS)
        guard let store, !active, !busy else { return }
        busy = true; operationMessage = "Preparing \(guest.title)…"
        installationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false; self.operationMessage = nil; self.installationTask = nil }
            do {
                let machine = try await Windows9xProvisioner().prepare(guest: guest, productKey: productKey, acceptedLicense: acceptedLicense, store: store) { [weak self] message in
                    await MainActor.run { self?.operationMessage = message }
                }
                await self.refresh(); self.selected = machine.id
                try await self.session.start(machine, directory: store.directory(for: machine.id))
                await self.runWindows9xAssistant(machine)
            } catch is CancellationError { await self.refresh() }
            catch { self.error = error.localizedDescription; await self.refresh() }
        }
        #else
        error = "The embedded iPhone machine engine is not available yet."
        #endif
    }

    func continueInstallationAssistant() {
        #if os(macOS)
        guard let machine = current, active, !busy else { return }
        busy = true
        installationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false; self.operationMessage = nil; self.installationTask = nil }
            switch machine.installation?.stage {
            case .windowsSetup:
                if machine.guest.needsCD { await self.runWindows9xAssistant(machine) }
                else { await self.runWindowsAssistant(machine) }
            case .wordSetup: await self.runWordAssistant(machine)
            case .dosSetup: await self.runDOSAssistant(machine)
            default: break
            }
        }
        #else
        error = "The embedded iPhone machine engine is not available yet."
        #endif
    }

    func cancelAssistant() { installationTask?.cancel() }

    #if os(macOS)
    private func runWindows9xAssistant(_ original: Machine) async {
        guard let store else { return }
        var machine = original
        do {
            if machine.boot == .hardDisk, machine.installation?.recipeID == Windows9xRecipe.id(for: machine.guest), try await session.isAtDOSPrompt() {
                try await session.typeText("C:\\DMINST.BAT\n")
            }
            let finished = try await Windows9xInstaller(session: session).run { [weak self] message, attention in
                self?.operationMessage = message
                machine.installation?.message = message; machine.installation?.needsAttention = attention
                try? await store.save(machine); await self?.refresh()
            } staged: {
                machine.boot = .hardDisk
                try await store.save(machine)
            }
            if finished {
                machine.boot = .hardDisk; machine.installation?.stage = .complete
                machine.installation?.needsAttention = false
                try await store.save(machine); await refresh()
            }
        } catch {
            machine.installation?.message = error is CancellationError ? "Assistant paused. Continue from the guest screen without reinstalling." : error.localizedDescription
            machine.installation?.needsAttention = true
            try? await store.save(machine); await refresh()
        }
    }
    private func runDOSAssistant(_ original: Machine) async {
        guard let store else { return }
        var machine = original
        do {
            let installer = DOS622Installer(session: session, disks: machine.floppies.filter { $0.purpose == .dosSetup })
            let finished = try await installer.run { [weak self] message, needsAttention in
                self?.operationMessage = message
                machine.installation?.message = message
                machine.installation?.needsAttention = needsAttention
                try? await store.save(machine)
                await self?.refresh()
            }
            if finished {
                machine.boot = .hardDisk
                machine.installation?.stage = .windowsSetup
                machine.installation?.message = "DOS is installed. Starting Windows 3.1 Setup…"
                machine.installation?.needsAttention = false
                try await store.save(machine); await refresh()
                await runWindowsAssistant(machine)
            }
        } catch is CancellationError {
            machine.installation?.message = "Assistant paused. The guest remains available for manual control."
            machine.installation?.needsAttention = true
            try? await store.save(machine); await refresh()
        } catch {
            machine.installation?.message = error.localizedDescription; machine.installation?.needsAttention = true
            try? await store.save(machine); await refresh()
        }
    }

    private func runWindowsAssistant(_ original: Machine) async {
        guard let store else { return }
        var machine = original
        do {
            let finished = try await Windows31Installer(session: session, disks: machine.floppies.filter { $0.purpose == .windowsSetup }).run { [weak self] message, attention in
                self?.operationMessage = message
                machine.installation?.message = message; machine.installation?.needsAttention = attention
                try? await store.save(machine); await self?.refresh()
            }
            if finished {
                machine.installation?.stage = .wordSetup
                machine.installation?.message = "Windows 3.1 is installed. Starting Word 6 Setup…"
                machine.installation?.needsAttention = false
                try await store.save(machine); await refresh()
                await runWordAssistant(machine)
            }
        } catch {
            machine.installation?.message = error is CancellationError ? "Assistant paused. Return to the DOS prompt before continuing." : error.localizedDescription
            machine.installation?.needsAttention = true
            try? await store.save(machine); await refresh()
        }
    }
    private func runWordAssistant(_ original: Machine) async {
        guard let store else { return }
        var machine = original
        do {
            let finished = try await Word6Installer(session: session, disks: machine.floppies.filter { $0.purpose == .wordSetup }).run { [weak self] message, attention in
                self?.operationMessage = message
                machine.installation?.message = message; machine.installation?.needsAttention = attention
                try? await store.save(machine); await self?.refresh()
            }
            if finished {
                machine.installation?.stage = .complete
                machine.installation?.message = "MS-DOS 6.22, Windows 3.1, and Word 6 are installed on the virtual hard disk. Use Start Windows or Start Word 6."
                machine.installation?.needsAttention = false
                try await store.save(machine); await refresh()
            }
        } catch {
            machine.installation?.message = error is CancellationError ? "Assistant paused. Return to the DOS prompt before continuing." : error.localizedDescription
            machine.installation?.needsAttention = true
            try? await store.save(machine); await refresh()
        }
    }
    #endif
}

struct MachineLibraryView: View {
    private enum ImportAction { case floppy, cdrom, exchangeFiles, export(MachineMedia) }
    @ObservedObject var model: MachineLibraryModel
    var embedded = false
    var createOnAppear = false
    @State private var creating = false
    @State private var importing = false
    @State private var importAction: ImportAction = .floppy
    private var importingFolder: Bool { if case .export = importAction { true } else { false } }
    @State private var newName = "My retro PC"
    @State private var guest = GuestSystem.windows31
    @State private var confirmPowerOff = false
    @State private var confirmReset = false

    var body: some View {
        Group {
            if embedded { detailContent }
            else { NavigationSplitView { computerSidebar } detail: { detailContent } }
        }
        .onAppear { if createOnAppear { creating = true } }
        .sheet(isPresented: $creating) {
            NavigationStack {
                Form {
                    TextField("Name", text: $newName)
                    Picker("System profile", selection: $guest) { ForEach(GuestSystem.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Text("Creates a blank virtual hard disk. Supply your installation images next. Profiles are hardware presets; OS compatibility is still being validated.").font(.caption).foregroundStyle(.secondary)
                }.padding(20).navigationTitle("New machine")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { creating = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("Create") { creating = false; Task { await model.create(name: newName, guest: guest) } }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty) }
                    }
            }
            #if os(macOS)
            .frame(width: 500, height: 270)
            #endif
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: importingFolder ? [.folder] : [.data], allowsMultipleSelection: !importingFolder) { result in
            do {
                let urls = try result.get()
                switch importAction {
                case .floppy: Task { await model.importMedia(urls, cdrom: false) }
                case .cdrom: Task { await model.importMedia(urls, cdrom: true) }
                case .exchangeFiles: Task { await model.makeExchange(urls) }
                case .export(let media): if let destination = urls.first { Task { await model.exportExchange(media, destination: destination) } }
                }
            }
            catch { model.error = error.localizedDescription }
        }
        .alert("Machine", isPresented: Binding(get: { !embedded && (model.error != nil || model.notice != nil) }, set: { if !$0 && !embedded { model.error = nil; model.notice = nil } })) { Button("OK") { model.error = nil; model.notice = nil } } message: { Text(model.error ?? model.notice ?? "") }
        .confirmationDialog("Power off this machine? Shut down the guest OS first to protect its disk.", isPresented: $confirmPowerOff) {
            Button("Power off", role: .destructive) {
                #if os(macOS)
                model.cancelAssistant()
                Task { await model.session.powerOff() }
                #endif
            }
        }
        .confirmationDialog("Reset this machine? Unsaved guest work will be lost.", isPresented: $confirmReset) {
            Button("Reset machine", role: .destructive) {
                #if os(macOS)
                Task { do { try await model.session.reset() } catch { model.error = error.localizedDescription } }
                #endif
            }
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.terminate() }
        #endif
    }

    private var computerSidebar: some View {
            List(selection: $model.selected) {
                Section("Your machines") {
                    ForEach(model.machines) { machine in
                        VStack(alignment: .leading, spacing: 4) { Text(machine.name).font(.headline); Text(machine.guest.title).font(.caption).foregroundStyle(.secondary) }.tag(machine.id)
                    }
                }
            }.disabled(model.active || model.busy)
                .navigationTitle("Machines")
                .toolbar {
                    Menu {
                        Button("Install DOS 6.22 + Windows 3.1 + Word 6") { model.prepareReferenceStack() }
                        Button("Create a blank machine") { creating = true }
                    } label: { Label("New machine", systemImage: "plus") }.disabled(model.active || model.busy)
                }
    }

    @ViewBuilder private var detailContent: some View {
            if let machine = model.current {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let message = model.operationMessage {
                            HStack { ProgressView().controlSize(.small); Text(message); Spacer(); Button("Pause assistant") { model.cancelAssistant() } }
                        }
                        HStack {
                            VStack(alignment: .leading, spacing: 4) { Text(machine.name).font(.largeTitle.bold()); Text(machine.guest.title + " · \(machine.guest.memoryMB) MiB · \(machine.guest.diskMB) MiB HDD").foregroundStyle(.secondary) }
                            Spacer()
                            if model.active {
                                #if os(macOS)
                                Button(model.state == .paused(machine.id) ? "Resume" : "Pause") { Task { do { if model.state == .paused(machine.id) { try await model.session.resume() } else { try await model.session.pause() } } catch { model.error = error.localizedDescription } } }.disabled(model.busy)
                                Button("Reset") { confirmReset = true }.disabled(model.busy)
                                Menu("Keyboard") {
                                    Button("Ctrl + Alt + Del") { Task { try? await model.session.sendChord(["ctrl", "alt", "delete"]) } }
                                    Button("Escape") { Task { try? await model.session.tap("esc") } }
                                    Button("Enter") { Task { try? await model.session.tap("ret") } }
                                }.disabled(model.busy)
                                Button("Power off", role: .destructive) { confirmPowerOff = true }
                                #endif
                            } else { Button("Start machine") { Task { await model.launch() } }.buttonStyle(.borderedProminent).disabled(model.busy) }
                        }
                        if !machine.guest.needsCD, let stage = machine.installation?.stage, stage == .wordSetup || stage == .complete {
                            HStack {
                                Button("Start Windows") { Task { await model.launchWindows(word: false) } }
                                if stage == .complete { Button("Start Word 6") { Task { await model.launchWindows(word: true) } } }
                            }.disabled(model.busy)
                        }
                        #if os(macOS)
                        if model.active {
                            MachineDisplayView(image: model.image, session: model.session, inputEnabled: !model.busy && model.state != .paused(machine.id), absolutePointer: model.absolutePointer) { model.captured = $0 }
                                .frame(minHeight: 400, idealHeight: 540).background(.black).clipShape(RoundedRectangle(cornerRadius: 10))
                            Text(model.busy ? "Installation assistant controls the guest. Pause the assistant to take over." : (model.absolutePointer ? "Seamless mouse · Move freely between Windows and Mac" : model.captured ? "Mouse captured · Control + Option releases mouse and keyboard" : "Click the screen to capture the mouse. Keyboard, mouse, and disk changes stay inside DosMac.")).font(.caption).foregroundStyle(.secondary)
                        }
                        #endif
                        #if os(macOS)
                        if machine.guest.needsCD, machine.installation?.stage == .complete {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Guest Tools").font(.headline)
                                Text("Seamless mouse for English Windows 95/98 (Windows 95 is experimental). With the live shared folder enabled and mapped to H:, Guest Tools also adds display controls and fitting Windows to the window. Shut down Windows first; a recovery disk is saved before installation.").font(.callout).foregroundStyle(.secondary)
                                Button("Install Guest Tools") { model.installGuestTools() }.disabled(model.active || model.busy)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        #endif
                        Picker("Start from", selection: Binding(get: { model.current?.boot ?? .hardDisk }, set: { device in Task { await model.setBoot(device) } })) {
                            ForEach(BootDevice.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.disabled(model.active)
                        mediaSection(machine.floppies, cdrom: false)
                        mediaSection(machine.cdroms, cdrom: true)
                        HStack {
                            Button("Empty exchange floppy") { Task { await model.makeExchange([]) } }
                            Button("Mac files → exchange floppy…") { importAction = .exchangeFiles; importing = true }
                            Text("Use A: in the guest. Export root files after shutting down the machine. 1.44 MB, DOS 8.3 filenames.").font(.caption).foregroundStyle(.secondary)
                        }.disabled(model.active || model.busy)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Installation workspace").font(.headline)
                            if let installation = machine.installation {
                                Text(installation.message).font(.callout).foregroundStyle(installation.needsAttention ? .orange : .secondary)
                                if installation.stage != .complete, model.active, !model.busy {
                                    Button("Continue installation assistant") { model.continueInstallationAssistant() }
                                }
                            } else {
                                Text("Priority workflow: MS-DOS 6.22 → Windows 3.1 → Word 6. Import the matching disk sets, boot DOS Setup from disk 1, then switch images here. After DOS installation, select Hard disk (C:) before starting again.").font(.callout).foregroundStyle(.secondary)
                            }
                            Text("The automatic installer supports the pinned English DOS 6.22, Windows 3.1, and Word 6 releases. Other systems require their own installation media and manual setup.").font(.caption).foregroundStyle(.secondary)
                        }.padding(18).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                        Text(model.engineReady ? "QEMU engine ready · Display and input inside DosMac" : "Machine engine unavailable in this build").font(.caption).foregroundStyle(.secondary)
                    }.padding(28)
                }.navigationTitle(machine.name)
            } else {
                ContentUnavailableView {
                    Label("A complete retro PC, inside DosMac", systemImage: "desktopcomputer")
                } description: {
                    Text("Create a machine with its own hard disk, real DOS or Windows, floppy drive, and CD-ROM. The first reference stack is MS-DOS 6.22, Windows 3.1, and Word 6.")
                } actions: {
                    Button("Install DOS 6.22 + Windows 3.1 + Word 6") { model.prepareReferenceStack() }.buttonStyle(.borderedProminent).disabled(model.busy)
                    Button("Create a blank machine") { creating = true }.disabled(model.busy)
                    if let message = model.operationMessage { ProgressView(message) }
                }
            }
    }

    @ViewBuilder private func mediaSection(_ media: [MachineMedia], cdrom: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Label(cdrom ? "CD-ROM" : "Floppy drive · A:", systemImage: cdrom ? "opticaldiscdrive" : "externaldrive").font(.headline); Spacer(); Button("Import images") { importAction = cdrom ? .cdrom : .floppy; importing = true }.disabled(model.active || model.busy) }
            if media.isEmpty { Text(cdrom ? "No ISO images imported." : "No floppy images imported.").font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(media.enumerated()), id: \.element.id) { index, item in
                HStack {
                    Text("\(index + 1). \(item.purpose.map { $0.title + " · " } ?? "")\(item.name)").font(.callout)
                    Spacer()
                    if item.purpose == .exchange { Button("Export files…") { importAction = .export(item); importing = true }.disabled(model.active || model.busy) }
                    #if os(macOS)
                    if (cdrom ? model.session.currentCD : model.session.currentFloppy) == item.id, model.active { Text("Inserted").font(.caption).foregroundStyle(.green) }
                    else { Button("Insert") { Task { await model.insert(item, cdrom: cdrom) } }.disabled(!model.active || model.busy) }
                    #endif
                }
            }
            if model.active { Button("Eject") { Task { await model.eject(cdrom: cdrom) } }.disabled(model.busy) }
        }.padding(18).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
}
