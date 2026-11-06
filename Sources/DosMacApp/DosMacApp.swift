import SwiftUI
import DosMacPlatform
import DosMacCore
import UniformTypeIdentifiers

@main
struct DosMacApp: App {
    @StateObject private var model = LibraryModel()
    @StateObject private var machines = MachineLibraryModel()
    @StateObject private var apps = WorkspaceLibraryModel()
    #if os(macOS)
    @NSApplicationDelegateAdaptor(DosMacAppDelegate.self) private var appDelegate
    #endif
    var body: some Scene {
        WindowGroup {
            WorkspaceView(library: model, machines: machines, apps: apps)
                .preferredColorScheme(.dark)
                #if os(macOS)
                .frame(minWidth: 960, minHeight: 680)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.cancelEngineSetup()
                    model.session.stop()
                }
                #endif
        }
        #if os(macOS)
        Settings {
            TabView {
                MachineEngineSettings().tabItem { Text("Computers") }
                OpenSourceNoticesView().tabItem { Text("Licenses") }
                if DistributionPolicy.current.allowsExternalEngines { ScrollView { EngineSettings(model: model).padding(24) }.tabItem { Text("Compatibility") } }
            }.frame(width: 580, height: 430)
        }
        #endif
    }
}

@MainActor
final class LibraryModel: ObservableObject {
    @Published var programs: [InstalledProgram] = []
    @Published var selected: String?
    @Published var query = ""
    @Published var error: String?
    @Published var status: SessionState = .idle
    @Published var isInstalling = false
    @Published var engineProgress: EngineInstallProgress?
    @Published var isLaunching = false
    @Published var floppyDrive = FloppyDriveStatus()
    @Published var diskControlsEnabled = false
    @Published var enginePath: String = UserDefaults.standard.string(forKey: "enginePath") ?? "" {
        didSet { UserDefaults.standard.set(enginePath, forKey: "enginePath") }
    }
    let session = EmulatorSession()
    #if os(macOS)
    private let engineInstaller = ManagedEngine()
    private var enginePreparation: Task<URL, Error>?
    private var enginePreparationID: UUID?
    #endif
    private(set) var library: LibraryStore?
    var engine: URL? { EmulatorSession.findEngine(customPath: enginePath.isEmpty ? nil : enginePath) }
    var filtered: [InstalledProgram] {
        programs.filter { query.isEmpty || $0.manifest.title.localizedCaseInsensitiveContains(query) }
    }
    var current: InstalledProgram? { programs.first { $0.id == selected } }
    var sessionProgram: InstalledProgram? {
        if case .running(let id) = status { return programs.first { $0.id == id } }
        return nil
    }
    var running: Bool { if case .running = status { true } else { false } }

    init() {
        do { library = try LibraryStore(root: LibraryStore.defaultRoot) }
        catch { self.error = error.localizedDescription }
        session.onStateChange = { [weak self] in self?.status = $0 }
        session.onFloppyChange = { [weak self] in self?.floppyDrive = $0 }
        refreshDiskControlAccess()
        Task { await refresh() }
    }

    func refresh() async {
        do { programs = try await library?.programs() ?? [] }
        catch { self.error = error.localizedDescription }
        if selected == nil { selected = programs.first?.id }
    }

    @discardableResult func install(_ url: URL) async -> Bool {
        guard let library, !isInstalling else { return false }
        isInstalling = true
        defer { isInstalling = false }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let item = try await library.install(from: url)
            await refresh()
            selected = item.id
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func installDemo() async {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("dosmac")
        defer { try? FileManager.default.removeItem(at: temp) }
        do {
            let payload = temp.appendingPathComponent("payload")
            try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
            let manifest = PackageManifest(id: "org.dosmac.hello", title: "Hello, DOS", summary: "Your first trip back. Explore the DOS prompt and send a file to your Mac or iPhone.", author: "DosMac", license: "CC0-1.0", executable: "HELLO.BAT")
            try JSONEncoder().encode(manifest).write(to: temp.appendingPathComponent("manifest.json"))
            try Self.demo.write(to: payload.appendingPathComponent("HELLO.BAT"), atomically: true, encoding: .ascii)
            await install(temp)
        } catch { self.error = error.localizedDescription }
    }

    func launch() async {
        guard let current, let library, !isLaunching else { return }
        isLaunching = true
        defer { isLaunching = false }
        do {
            let executable = try await prepareEngine()
            try Task.checkCancellation()
            try await session.start(program: current, library: library, engine: executable)
            await refresh()
        } catch is CancellationError { }
        catch let error as URLError where error.code == .cancelled { }
        catch { self.error = error.localizedDescription }
    }

    func prepareEngine() async throws -> URL {
        if let engine { return engine }
        #if os(macOS)
        if let enginePreparation { return try await enginePreparation.value }
        engineProgress = .downloading(nil)
        let id = UUID()
        enginePreparationID = id
        let installer = engineInstaller
        let preparation = Task { [weak self] in
            try await installer.ensureInstalled { [weak self] progress in
                await self?.updateEngineProgress(progress, id: id)
            }
        }
        enginePreparation = preparation
        defer { enginePreparation = nil; enginePreparationID = nil; engineProgress = nil }
        return try await preparation.value
        #else
        throw DosMacError.unsupportedPlatform
        #endif
    }

    func installEngine() async {
        do { _ = try await prepareEngine() }
        catch is CancellationError { }
        catch let error as URLError where error.code == .cancelled { }
        catch { self.error = error.localizedDescription }
    }

    func cancelEngineSetup() {
        #if os(macOS)
        enginePreparation?.cancel()
        #endif
    }

    func refreshDiskControlAccess() { diskControlsEnabled = session.canControlDisks }

    func selectFloppy(_ number: Int) async {
        do { try await session.selectFloppy(number: number) }
        catch { /* The drive panel displays the contextual error without interrupting setup. */ }
        refreshDiskControlAccess()
    }

    #if os(macOS)
    private func updateEngineProgress(_ progress: EngineInstallProgress, id: UUID) {
        guard enginePreparationID == id else { return }
        // Download callbacks may arrive after the async download has completed.
        if case .downloading = progress, let current = engineProgress {
            if case .verifying = current { return }
            if case .installing = current { return }
        }
        engineProgress = progress
    }
    #endif

    var engineStatusLabel: String {
        #if os(macOS)
        engineProgress?.message ?? (engine == nil ? "Engine installs on first launch" : "DOSBox-X ready")
        #else
        "Embedded engine coming soon"
        #endif
    }

    static let demo = """
    @echo off
    cls
    echo.
    echo   D O S M A C
    echo   A new home for old software.
    echo   ----------------------------------------
    echo.
    echo   C: Your private program drive
    echo   D: Your shared Exchange folder
    echo.
    echo Hello from DOS! > D:\\HELLO.TXT
    echo   A greeting was saved to D:\\HELLO.TXT
    echo   Open Exchange in DosMac to find it.
    echo.
    echo   You are now at a real DOS prompt. Try DIR.
    echo.
    """.replacingOccurrences(of: "\n", with: "\r\n")
}

private let mint = Color(red: 0.64, green: 0.92, blue: 0.69)
private let base = Color(red: 0.055, green: 0.07, blue: 0.065)

struct LibraryView: View {
    @ObservedObject var model: LibraryModel
    @State private var importing = false
    @State private var showSettings = false
    @State private var showSources = false
    @State private var showStartup = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 30) {
                HStack(spacing: 10) {
                    Image(systemName: "terminal.fill").font(.title).foregroundStyle(mint)
                    Text("DosMac").font(.title2.bold())
                }.padding(.top, 22)
                VStack(alignment: .leading, spacing: 18) {
                    Text("WORKSPACE").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                    Label("Your library", systemImage: "square.grid.2x2.fill").foregroundStyle(mint)
                    Button { openExchange() } label: { Label("Exchange", systemImage: "folder") }.buttonStyle(.plain)
                    Button { showSources = true } label: { Label("Software sources", systemImage: "globe") }.buttonStyle(.plain)
                    Button { showSettings = true } label: { Label("Engine settings", systemImage: "slider.horizontal.3") }.buttonStyle(.plain)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Circle().fill(model.engine == nil ? .orange : mint).frame(width: 6, height: 6); Text(model.engineStatusLabel) }
                    if let progress = model.engineProgress {
                        ProgressView(value: progress.fraction).progressViewStyle(.linear)
                        Button("Cancel download") { model.cancelEngineSetup() }
                    }
                    Text("INTERPRETER · NO JIT").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                    Text("DEVELOPER PREVIEW  /  0.1").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary).padding(.top, 12)
                }.font(.caption)
            }.padding(24).background(base).navigationSplitViewColumnWidth(230)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack {
                        Text("YOUR PERSONAL TIME MACHINE").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2).foregroundStyle(mint)
                        Spacer()
                        Button { showSources = true } label: { Label("Add from web", systemImage: "globe") }
                        Button { importing = true } label: { Label("Import package", systemImage: "plus") }.disabled(model.isInstalling)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Old software.\nNew possibilities.").font(.system(size: 44, weight: .semibold, design: .rounded)).tracking(-1.5)
                        Text("A thoughtful home for your DOS programs.").foregroundStyle(.secondary)
                    }
                    hero
                    if model.running, !model.floppyDrive.disks.isEmpty {
                        FloppyDrivePanel(model: model)
                    }
                    if model.running {
                        SessionInputPanel { model.session.showEmulator() }
                    }
                    HStack {
                        Text("Your library").font(.title2.weight(.semibold))
                        Text(String(model.programs.count)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        TextField("Find a program", text: $model.query).textFieldStyle(.roundedBorder).frame(maxWidth: 210)
                    }
                    if model.filtered.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: model.programs.isEmpty ? "shippingbox" : "magnifyingglass").font(.largeTitle).foregroundStyle(mint)
                            Text(model.programs.isEmpty ? "Every great library starts somewhere." : "No matching programs").font(.headline)
                            Text(model.programs.isEmpty ? "Install our tiny DOS demo, or import your own .dosmac folder." : "Try another search.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            if model.programs.isEmpty {
                                Button("Install Hello, DOS") { Task { await model.installDemo() } }.buttonStyle(.borderedProminent).tint(mint).foregroundStyle(base).disabled(model.isInstalling)
                            }
                        }.frame(maxWidth: .infinity).padding(36).background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), alignment: .top)], spacing: 16) {
                            ForEach(model.filtered) { item in
                                Button { model.selected = item.id } label: {
                                    VStack(alignment: .leading, spacing: 16) {
                                        HStack { Image(systemName: "terminal").font(.title).foregroundStyle(mint); Spacer(); Text(item.manifest.profile == .dos ? "DOS" : "WIN 3.1").font(.caption2.monospaced()).foregroundStyle(.secondary) }
                                        Text(item.manifest.title).font(.headline)
                                        Text(item.manifest.summary).font(.caption).foregroundStyle(.secondary).lineLimit(3).frame(height: 48, alignment: .top)
                                        HStack { Circle().fill(mint).frame(width: 5, height: 5); Text("Installed"); Spacer(); Text("v\(item.manifest.version)") }.font(.caption2).foregroundStyle(.secondary)
                                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(model.selected == item.id ? mint.opacity(0.7) : .white.opacity(0.07)))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    if let current = model.sessionProgram ?? model.current {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(current.manifest.title).font(.headline)
                                Text(current.manifest.profile.title + (current.manifest.effectiveStartupMode == .dosPrompt ? " · DOS prompt on C:" : "") + " · D: Exchange enabled").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { showStartup = true } label: { Image(systemName: "gearshape") }.help("Change startup program").disabled(model.running)
                            if model.running {
                                Button("Stop session", role: .destructive) { model.session.stop() }
                            } else {
                                Button { Task { await model.launch() } } label: { Label(model.isLaunching ? "Preparing…" : "Launch", systemImage: "play.fill") }.buttonStyle(.borderedProminent).tint(mint).foregroundStyle(base).disabled(model.isLaunching || model.engineProgress != nil)
                            }
                        }.padding(20).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    }
                    HStack { Text("Built for the software you still love."); Spacer(); Text(sessionLabel).monospaced() }.font(.caption2).foregroundStyle(.secondary)
                }.padding(32).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
            }.background(base).navigationTitle("Library")
        }
        .tint(mint)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshDiskControlAccess() }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
            switch result { case .success(let url): Task { await model.install(url) }; case .failure(let error): model.error = error.localizedDescription }
        }
        .sheet(isPresented: $showSettings) { EngineSettings(model: model).padding(28) }
        .sheet(isPresented: $showSources) { SoftwareSourcesView(library: model) }
        .sheet(isPresented: $showStartup) {
            if let program = model.current { StartupSettings(model: model, program: program) }
        }
        .alert("DosMac", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
    }

    private var hero: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("WELCOME TO THE COMMAND LINE").font(.system(size: 9, design: .monospaced)).tracking(1.5).foregroundStyle(mint)
                Text("The past has a future.").font(.title2.weight(.medium))
                Text("Private program drives. Simple installs.\nA shared folder that connects both worlds.").font(.callout).foregroundStyle(.secondary).lineSpacing(4)
            }
            Spacer(minLength: 0)
            #if os(macOS)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) { ForEach(0..<3) { _ in Circle().fill(mint.opacity(0.35)).frame(width: 6, height: 6) }; Spacer(); Text("DOS / 386").foregroundStyle(mint.opacity(0.45)) }.padding(.bottom, 10)
                Text("C:\\> hello"); Text("A new home for old software.").foregroundStyle(mint.opacity(0.6)); Text("C:\\> _")
            }.font(.system(size: 11, design: .monospaced)).foregroundStyle(mint).padding(20).frame(width: 300).background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            #endif
        }.padding(26).frame(maxWidth: .infinity, alignment: .leading).background(mint.opacity(0.055), in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(mint.opacity(0.12)))
    }

    private var sessionLabel: String {
        switch model.status { case .idle: "READY"; case .running: "SESSION RUNNING"; case .exited(let code): "SESSION ENDED (\(code))"; case .failed: "SESSION FAILED" }
    }

    private func openExchange() {
        guard let url = model.library?.exchangeURL else { return }
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        // The app's Documents directory is also available through the Files app.
        model.error = "Use Import / Export in Engine settings to exchange files. DOS maps this folder as drive D:."
        #endif
    }
}

struct EngineSettings: View {
    @ObservedObject var model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var exchangeFiles: [URL] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Engine & exchange").font(.title2.bold()); Spacer(); Button("Done") { dismiss() } }
            #if os(macOS)
            Text("DOSBox-X engine").font(.headline)
            Text(model.engine == nil ? "Just launch a program. DosMac automatically downloads and verifies the official engine once; later launches work offline." : "Ready to run. Sessions use the normal interpreter core and open in the emulator's own window.").font(.callout).foregroundStyle(.secondary)
            if let progress = model.engineProgress {
                Text(progress.message).font(.callout)
                ProgressView(value: progress.fraction).progressViewStyle(.linear)
                Button("Cancel download") { model.cancelEngineSetup() }
            } else if model.engine == nil {
                Button("Prepare engine now") { Task { await model.installEngine() } }
            }
            DisclosureGroup("Advanced: custom engine") {
                TextField("Optional DOSBox-X executable path", text: $model.enginePath).textFieldStyle(.roundedBorder)
                Text("Leave empty for automatic setup. The engine is stored privately in DosMac's Application Support folder.").font(.caption).foregroundStyle(.secondary)
            }
            Link("DOSBox-X source & license", destination: URL(string: "https://github.com/joncampbell123/dosbox-x/releases/tag/dosbox-x-v2026.10.01")!)
            #else
            Text("iPhone preview").font(.headline)
            Text("Library installation works on this device. Running DOS requires the planned embedded interpreter; this build cannot run programs on iPhone.").foregroundStyle(.secondary)
            #endif
            Divider()
            Text("Exchange · drive D:").font(.headline)
            Text("Files here are readable and writable by every DOS program you launch. Import a copy to share it with DOS.").font(.callout).foregroundStyle(.secondary)
            Button("Import file into Exchange") { importing = true }
            ForEach(exchangeFiles, id: \.self) { url in
                HStack { Text(url.lastPathComponent).font(.callout); Spacer(); ShareLink(item: url) { Image(systemName: "square.and.arrow.up") } }
            }
            if exchangeFiles.isEmpty { Text("No shared files yet.").font(.caption).foregroundStyle(.secondary) }
        }
        .task { reload() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            do {
                let source = try result.get()
                let accessed = source.startAccessingSecurityScopedResource()
                defer { if accessed { source.stopAccessingSecurityScopedResource() } }
                guard let folder = model.library?.exchangeURL else { return }
                try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(source.lastPathComponent))
                reload()
            } catch { model.error = error.localizedDescription }
        }
    }
    private func reload() {
        guard let folder = model.library?.exchangeURL else { return }
        exchangeFiles = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey])) ?? []).filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
