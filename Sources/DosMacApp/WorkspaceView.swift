import DosMacCore
import DosMacPlatform
import DosMacVM
import SwiftUI
import UniformTypeIdentifiers

let workspaceMint = Color(red: 0.64, green: 0.92, blue: 0.69)
let workspaceBase = Color(red: 0.055, green: 0.07, blue: 0.065)

struct WorkspaceView: View {
  enum Section: String, CaseIterable {
    case library, discover, files, computers, session
    var key: KeyEquivalent {
      switch self {
      case .library: "1"
      case .discover: "2"
      case .files: "3"
      case .computers: "4"
      case .session: "5"
      }
    }
  }
  private enum SearchField: Hashable { case library, discover }
  enum Sheet: Identifiable {
    case source(String)
    case computer(Bool)
    case shortcut(GuestApplication?)
    case windows9x(GuestSystem)
    case classicSettings, startup, guestText
    var id: String {
      switch self {
      case .source(let url): "source-" + url
      case .computer(let new): "computer-\(new)"
      case .shortcut(let app): "shortcut-" + (app?.id.uuidString ?? "new")
      case .windows9x(let guest): "install-" + guest.rawValue
      case .classicSettings: "settings"
      case .startup: "startup"
      case .guestText: "guest-text"
      }
    }
  }
  @ObservedObject var library: LibraryModel
  @ObservedObject var machines: MachineLibraryModel
  @ObservedObject var apps: WorkspaceLibraryModel
  @StateObject private var catalog = CatalogSearchModel()
  @State private var section = Section.library
  @State private var query = ""
  @State private var filter = "All"
  @State private var selection: String?
  @State private var sheet: Sheet?
  @State private var importing = false
  @State private var playingTitle = ""
  @State private var playingMedia: [UUID] = []
  @State private var showPowerOff = false
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @FocusState private var searchFocus: SearchField?
  private var entries: [LibraryEntry] {
    LibraryEntry.entries(machines: machines.machines, apps: apps.apps, packages: DistributionPolicy.current.allowsExternalEngines ? library.programs : [])
  }
  private var visible: [LibraryEntry] {
    entries.filter { entry in
      (filter == "All" || (filter == "Installers" ? entry.installer : !entry.installer))
        && (query.isEmpty
          || (entry.title + " " + entry.context + " " + entry.kind)
            .localizedCaseInsensitiveContains(query))
    }
  }
  private var currentEntry: LibraryEntry? { visible.first { $0.id == selection } ?? visible.first }
  private var error: String? { apps.error ?? machines.error ?? library.error ?? machines.notice }

  var body: some View {
    NavigationSplitView {
      sidebar
    } detail: {
      Group {
        switch section {
        case .library: libraryPage
        case .discover: discoverPage
        case .computers: computersPage
        case .files: WorkspaceFilesView(model: machines, library: library) { section = .session }
        case .session: player
        }
      }.background(workspaceBase)
    }
    .tint(workspaceMint)
    .toolbar {
      ToolbarItem {
        Button {
          if section == .discover {
            searchFocus = .discover
          } else {
            section = .library
            searchFocus = .library
          }
        } label: {
          Image(systemName: "magnifyingglass")
        }.keyboardShortcut("f").help("Search (⌘F)")
      }
    }
    .sheet(item: $sheet) { item in
      switch item {
      case .source(let address):
        SourceInstallView(library: library, machines: machines, apps: apps, initialAddress: address)
        { id, launch in
          query = ""
          filter = "All"
          selection = id
          section = .library
          if launch, let entry = entries.first(where: { $0.id == id }) { open(entry) }
        }
      case .computer(let new):
        NavigationStack {
          MachineLibraryView(model: machines, embedded: true, createOnAppear: new)
            .toolbar {
              ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil } }
            }
        }
        #if os(macOS)
          .frame(width: 920, height: 720)
        #endif
      case .shortcut(let app):
        GuestApplicationForm(machines: machines.machines, apps: apps, existing: app)
      case .windows9x(let guest):
        Windows9xInstallView(model: machines, initialGuest: guest, otherSessionRunning: library.running)
      case .classicSettings: ScrollView { EngineSettings(model: library).padding(28) }
      case .startup:
        if let program = library.current { StartupSettings(model: library, program: program) }
      case .guestText:
        #if os(macOS)
          GuestTextSheet(model: machines)
        #endif
      }
    }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
      do {
        let url = try result.get()
        Task {
          if await library.install(url) {
            query = ""
            filter = "All"
            selection = "classic-" + (library.current?.id ?? "")
            section = .library
          }
        }
      } catch { library.error = error.localizedDescription }
    }
    .alert(
      "DosMac", isPresented: Binding(get: { error != nil }, set: { if !$0 { clearMessages() } })
    ) {
      Button("OK") { clearMessages() }
    } message: {
      Text(error ?? "")
    }
    .confirmationDialog(
      "Power off this computer? Exit Windows and finish saving your files first.",
      isPresented: $showPowerOff
    ) {
      Button("Power off", role: .destructive) {
        machines.cancelAssistant()
        #if os(macOS)
          Task { await machines.session.powerOff() }
        #endif
      }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        library.refreshDiskControlAccess()
        Task {
          await library.refresh()
          await machines.refresh()
          await apps.refresh()
        }
      }
    }
    .onChange(of: machines.active) { _, active in if active { section = .session } }
    .onChange(of: library.running) { _, active in if active { section = .session } }
    .onChange(of: machines.busy) { _, busy in
      if busy, machines.operationMessage != nil { section = .session }
    }
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 26) {
      HStack(spacing: 11) {
        Image(systemName: "terminal.fill").font(.title).foregroundStyle(workspaceMint)
        Text("DosMac").font(.title2.bold())
      }.padding(.top, 20)
      VStack(alignment: .leading, spacing: 8) {
        Text("YOUR WORKSPACE").font(.system(size: 9, weight: .semibold, design: .monospaced))
          .tracking(2).foregroundStyle(.secondary).padding(.bottom, 8)
        navigation(
          "Library", symbol: "square.grid.2x2.fill", target: .library, count: entries.count)
        navigation("Discover", symbol: "globe", target: .discover)
        navigation("Files", symbol: "folder", target: .files)
      }
      if machines.active || machines.busy || library.running || library.isLaunching {
        Button {
          section = .session
        } label: {
          HStack(alignment: .top, spacing: 10) {
            Circle().fill(workspaceMint).frame(width: 7, height: 7).padding(.top, 5)
            VStack(alignment: .leading, spacing: 5) {
              Text(machines.busy || library.isLaunching ? "Preparing…" : "Now playing").font(
                .caption.weight(.semibold)
              ).foregroundStyle(workspaceMint)
              Text(
                playingTitle.isEmpty
                  ? (machines.current?.name ?? library.current?.manifest.title ?? "Your computer")
                  : playingTitle
              ).font(.callout).lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right").font(.caption)
          }.padding(13).background(
            workspaceMint.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
      }
      Spacer()
      VStack(alignment: .leading, spacing: 8) {
        navigation(
          "Computers", symbol: "desktopcomputer", target: .computers, count: machines.machines.count
        )
        Menu {
          Button("Computer settings") { sheet = .computer(false) }.disabled(machines.current == nil)
          if DistributionPolicy.current.allowsExternalEngines { Button("Classic package settings") { sheet = .classicSettings } }
        } label: {
          Label("Settings", systemImage: "slider.horizontal.3").font(.callout).foregroundStyle(
            .secondary)
        }.menuStyle(.borderlessButton)
      }
      HStack(spacing: 7) {
        Circle().fill(machines.engineReady ? workspaceMint : .orange).frame(width: 5, height: 5)
        Text(machines.engineReady ? "Ready for your next session" : "Developer preview").font(
          .caption2
        ).foregroundStyle(.secondary)
      }
    }.padding(20).background(workspaceBase).navigationSplitViewColumnWidth(
      min: 210, ideal: 230, max: 260)
  }
  private func navigation(_ title: String, symbol: String, target: Section, count: Int? = nil)
    -> some View
  {
    Button {
      section = target
    } label: {
      HStack(spacing: 11) {
        Image(systemName: symbol).frame(width: 18)
        Text(title)
        Spacer()
        if let count { Text("\(count)").font(.caption.monospacedDigit()).opacity(0.6) }
      }
      .font(.callout.weight(section == target ? .semibold : .regular)).padding(.horizontal, 12)
      .padding(.vertical, 11)
      .foregroundStyle(section == target ? workspaceMint : .secondary)
      .background(
        section == target ? workspaceMint.opacity(0.09) : .clear,
        in: RoundedRectangle(cornerRadius: 10))
    }.buttonStyle(.plain).keyboardShortcut(target.key)
  }
  private var libraryPage: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        HStack {
          pageHeading("Library", subtitle: "Everything you love running, all in one place.")
          Spacer()
          Button {
            section = .discover
          } label: {
            Label("Find software", systemImage: "globe")
          }
          Menu {
            Button("Add installed app…") { sheet = .shortcut(nil) }.disabled(
              machines.machines.isEmpty)
            if DistributionPolicy.current.allowsUnreviewedCatalogs {
            Button("Add from a link…") { sheet = .source("") }
            Button("Import .dosmac package…") { importing = true }
            Button("Hello, DOS demo") {
              Task {
                if !library.programs.contains(where: { $0.id == "org.dosmac.hello" }) {
                  await library.installDemo()
                }
                selection = "classic-org.dosmac.hello"
                query = ""
                filter = "All"
                section = .library
              }
            }
            }
          } label: {
            Label("Add", systemImage: "plus")
          }
        }
        HStack(spacing: 22) {
          VStack(alignment: .leading, spacing: 10) {
            Text("OLD SOFTWARE. RIGHT AT HOME.").font(.system(size: 9, design: .monospaced))
              .tracking(1.6).foregroundStyle(workspaceMint)
            Text("Your favorites.\nJust a click away.").font(
              .system(size: 32, weight: .semibold, design: .rounded)
            ).tracking(-0.9)
            Text("Open an app. Pick up where you left off.").font(.callout).foregroundStyle(
              .secondary)
          }
          Spacer(minLength: 4)
          if horizontalSizeClass != .compact {
            Image(systemName: "square.stack.3d.up.fill").font(
              .system(size: 68, weight: .ultraLight)
            )
            .foregroundStyle(workspaceMint.opacity(0.6)).rotationEffect(.degrees(-10)).padding(
              .horizontal, 30)
          }
        }.padding(26).frame(maxWidth: .infinity, alignment: .leading).background(
          workspaceMint.opacity(0.045), in: RoundedRectangle(cornerRadius: 18)
        ).overlay(RoundedRectangle(cornerRadius: 18).stroke(workspaceMint.opacity(0.12)))
        HStack {
          Picker("Show", selection: $filter) {
            ForEach(["All", "Applications", "Installers"], id: \.self) { Text($0) }
          }.pickerStyle(.segmented).frame(maxWidth: 310)
          Spacer()
          HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search your library", text: $query).textFieldStyle(.plain)
              .autocorrectionDisabled().focused($searchFocus, equals: .library).onSubmit {
                if !query.isEmpty, let entry = currentEntry { open(entry) }
              }
            if !query.isEmpty {
              Button {
                query = ""
              } label: {
                Image(systemName: "xmark.circle.fill")
              }.buttonStyle(.plain).accessibilityLabel("Clear library search")
            }
          }.padding(9).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
            .frame(maxWidth: 260)
        }
        if visible.isEmpty {
          ContentUnavailableView {
            Label(
              entries.isEmpty ? "A home for your next favorite" : "No matching apps",
              systemImage: entries.isEmpty ? "books.vertical" : "magnifyingglass")
          } description: {
            Text(
              entries.isEmpty
                ? (DistributionPolicy.current.allowsUnreviewedCatalogs ? "Discover classic software, or add an app already installed in your computer." : "Open Discover to try the PC hardware check or import your own installation images.")
                : "Search the websites for more software, or try a different name.")
          } actions: {
            Button("Find software") {
              catalog.query = query
              section = .discover
              if !query.isEmpty { catalog.search() }
            }.buttonStyle(.borderedProminent).foregroundStyle(workspaceBase)
          }
        } else {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), alignment: .top)], spacing: 16) {
            ForEach(visible) { entry in appCard(entry) }
          }
        }
      }.padding(30).frame(maxWidth: 1200).frame(maxWidth: .infinity)
    }.safeAreaInset(edge: .bottom, spacing: 0) {
      if let entry = currentEntry {
        HStack(spacing: 14) {
          Image(systemName: entry.symbol).font(.title2).foregroundStyle(workspaceMint)
          VStack(alignment: .leading, spacing: 4) {
            Text(entry.title).font(.headline)
            Text(entry.context).font(.caption).foregroundStyle(.secondary).lineLimit(1)
          }
          Spacer()
          Button {
            open(entry)
          } label: {
            Label(openLabel(entry), systemImage: "play.fill")
          }.buttonStyle(.borderedProminent).foregroundStyle(workspaceBase).disabled(
            machines.busy || library.isLaunching)
        }.padding(.horizontal, 30).padding(.vertical, 16).background(workspaceBase.opacity(0.98))
          .overlay(alignment: .top) { Divider() }
      }
    }.navigationTitle("Library")
  }
  private func appCard(_ entry: LibraryEntry) -> some View {
    VStack(alignment: .leading, spacing: 15) {
      Button {
        selection = entry.id
      } label: {
        VStack(alignment: .leading, spacing: 15) {
          HStack {
            appIcon(entry)
            Spacer()
            Text(entry.kind).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
          }
          Text(entry.title).font(.headline).foregroundStyle(.primary).lineLimit(2).frame(
            height: 42, alignment: .top)
          Text(entry.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(
            height: 34, alignment: .top)
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
      }.buttonStyle(.plain)
      HStack {
        Label(
          entry.installer ? "Setup ready" : "In your library",
          systemImage: entry.installer ? "shippingbox" : "checkmark.circle.fill"
        ).font(.caption2).foregroundStyle(entry.installer ? .secondary : workspaceMint)
        Spacer(minLength: 2)
        Button(openLabel(entry)) { open(entry) }.font(.caption.weight(.semibold)).disabled(
          machines.busy || library.isLaunching)
      }
    }.padding(19).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 15)).overlay(
      RoundedRectangle(cornerRadius: 15).stroke(
        currentEntry?.id == entry.id ? workspaceMint.opacity(0.55) : .white.opacity(0.07))
    )
    .contextMenu {
      Button("Open") { open(entry) }
      if let id = entry.machineID {
        Button("Computer settings") {
          if !machines.active { machines.selected = id }
          sheet = .computer(false)
        }.disabled(machines.active && machines.selected != id)
      }
      if case .guest(let app) = entry.target { Button("Edit shortcut…") { sheet = .shortcut(app) } }
      if case .classic(let app) = entry.target {
        Button("Startup settings") {
          library.selected = app.id
          sheet = .startup
        }.disabled(library.running)
      }
    }
  }
  private func appIcon(_ entry: LibraryEntry) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: 12).fill(
        LinearGradient(
          colors: [
            entry.symbol == "doc.text" ? Color.blue.opacity(0.8) : workspaceMint.opacity(0.2),
            .black.opacity(0.2),
          ], startPoint: .topLeading, endPoint: .bottomTrailing))
      if entry.symbol == "doc.text" {
        Text("W").font(.system(size: 30, weight: .bold, design: .serif)).foregroundStyle(.white)
      } else {
        Image(systemName: entry.symbol).font(.system(size: 25)).foregroundStyle(workspaceMint)
      }
    }.frame(width: 55, height: 55)
  }
  @ViewBuilder private var discoverPage: some View {
    if !DistributionPolicy.current.allowsUnreviewedCatalogs { storeDiscoverPage } else {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        pageHeading("Discover", subtitle: "Find your next old favorite.")
        HStack(spacing: 12) {
          Image(systemName: "magnifyingglass").foregroundStyle(workspaceMint)
          TextField("Search software, or paste a download link", text: $catalog.query)
            .textFieldStyle(.plain).autocorrectionDisabled().focused(
              $searchFocus, equals: .discover
            ).onSubmit { searchWeb() }
          if !catalog.query.isEmpty {
            Button {
              catalog.query = ""
              catalog.reset()
            } label: {
              Image(systemName: "xmark.circle.fill")
            }.buttonStyle(.plain).accessibilityLabel("Clear search")
          }
          Button("Search") { searchWeb() }.buttonStyle(.borderedProminent).foregroundStyle(
            workspaceBase
          ).disabled(catalog.query.trimmingCharacters(in: .whitespaces).isEmpty || catalog.busy)
        }.padding(14).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        HStack {
          Picker("Search in", selection: $catalog.provider) {
            Text("All websites").tag("all")
            ForEach(CatalogSource.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
          }.frame(maxWidth: 300).onChange(of: catalog.provider) { _, _ in
            if catalog.searched && !catalog.query.isEmpty
              && !catalog.query.lowercased().hasPrefix("https://")
            {
              catalog.search()
            }
          }
          Spacer()
          Button("Add from a link…") { sheet = .source("") }
        }
        if !catalog.searched {
          if DistributionPolicy.current.allowsUnreviewedCatalogs { referenceCollection }
          VStack(alignment: .leading, spacing: 15) {
            Text("Windows 95 & 98").font(.title2.bold())
            Text("Create a private desktop with its installation CD, shared disk, and live host folder. Experimental batch setup; use your own Windows product key.")
              .font(.callout).foregroundStyle(.secondary)
            HStack {
              Button("Install Windows 98 SE…") { sheet = .windows9x(.windows98) }
              Button("Install Windows 95…") { sheet = .windows9x(.windows95) }
            }.disabled(machines.active || machines.busy || library.running)
          }.padding(24).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 15))
        }
        if catalog.busy {
          HStack {
            ProgressView().controlSize(.small)
            Text("Searching software archives…")
            Spacer()
            Button("Cancel") { catalog.cancel() }
          }.font(.callout)
        }
        ForEach(catalog.errors, id: \.self) { error in
          Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
        }
        if !catalog.items.isEmpty {
          Text("\(catalog.items.count) results").font(.headline)
          LazyVStack(spacing: 10) {
            ForEach(catalog.items) { item in
              HStack(alignment: .top, spacing: 16) {
                Image(systemName: "shippingbox").font(.title2).foregroundStyle(workspaceMint).frame(
                  width: 40, height: 44)
                VStack(alignment: .leading, spacing: 6) {
                  Text(item.title).font(.headline).lineLimit(2)
                  Text(item.summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                  Link(item.source.title, destination: item.pageURL).font(.caption)
                }
                Spacer(minLength: 4)
                Button("View releases") { sheet = .source(item.pageURL.absoluteString) }
              }.padding(18).background(
                .white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            }
          }
        } else if catalog.searched && !catalog.busy {
          ContentUnavailableView(
            catalog.errors.isEmpty ? "No software found" : "The websites could not return results",
            systemImage: "globe",
            description: Text("Try another name, paste a direct link, or open the source website."))
        }
        HStack {
          Link(
            "Browse WinWorld",
            destination: URL(string: "https://winworldpc.com/library/applications")!)
          Text("·").foregroundStyle(.secondary)
          Link(
            "Browse Internet Archive",
            destination: URL(string: "https://archive.org/details/software")!)
        }.font(.caption)
      }.padding(30).frame(maxWidth: 1100).frame(maxWidth: .infinity)
    }.navigationTitle("Discover")
    }
  }
  private var storeDiscoverPage: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        pageHeading("Discover", subtitle: "Your software. Your computer.")
        VStack(alignment: .leading, spacing: 16) {
          Label("Try your first PC", systemImage: "desktopcomputer").font(.title2.bold())
          Text("Boot an original hardware check, test the keyboard, and display a color pattern. No operating system, download, or product key is needed.").foregroundStyle(.secondary)
          Button("Open PC hardware check") {
            section = .session
            Task { await machines.installDiagnostic() }
          }.buttonStyle(.borderedProminent).foregroundStyle(workspaceBase).disabled(machines.active || machines.busy)
        }.padding(24).background(workspaceMint.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
        VStack(alignment: .leading, spacing: 16) {
          Label("Bring your own software", systemImage: "opticaldiscdrive").font(.title2.bold())
          Text("Create a computer and import your DOS or Windows installation images. Each computer has a private hard disk. Software and licenses are supplied by you.").foregroundStyle(.secondary)
          Button("Create a computer…") { sheet = .computer(true) }.disabled(machines.active || machines.busy)
          HStack {
            Button("Install Windows 98 SE from images…") { sheet = .windows9x(.windows98) }
            Button("Install Windows 95 from images…") { sheet = .windows9x(.windows95) }
          }.disabled(machines.active || machines.busy)
          Text("The guided Windows setup uses your local ISO and an English Windows 98 SE OEM startup floppy with CD-ROM support. You enter your own product key in the installer.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
        HStack {
          Link("Privacy policy", destination: URL(string: "https://asaptf.github.io/DosMac/privacy/")!)
          Link("Support", destination: URL(string: "https://asaptf.github.io/DosMac/support/")!)
        }.font(.callout)
      }.padding(30).frame(maxWidth: 1100).frame(maxWidth: .infinity)
    }.navigationTitle("Discover")
  }
  private var referenceCollection: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("A classic, ready to make yours.").font(.title2.weight(.semibold))
      collectionLayout {
        Image(systemName: "macwindow.on.rectangle").font(.system(size: 52, weight: .light))
          .foregroundStyle(workspaceMint)
        VStack(alignment: .leading, spacing: 8) {
          Text("Windows 3.1 + Word 6").font(.title3.bold())
          Text(
            "A complete desktop with real MS-DOS 6.22. DosMac prepares the computer, changes the disks, and installs the software for you."
          ).font(.callout).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        if let word = entries.first(where: { if case .word = $0.target { true } else { false } }) {
          Button(
            machines.active && word.machineID == machines.selected ? "Open session" : "Open Word 6"
          ) { open(word) }.buttonStyle(.borderedProminent).foregroundStyle(workspaceBase)
        } else {
          Button("Install collection") { installReference() }.buttonStyle(.borderedProminent)
            .foregroundStyle(workspaceBase).disabled(machines.busy || machines.active)
        }
      }
      Text("English retail releases · Automatic setup · Private computer").font(.caption)
        .foregroundStyle(.secondary)
    }.padding(25).background(workspaceMint.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
      .overlay(RoundedRectangle(cornerRadius: 16).stroke(workspaceMint.opacity(0.12)))
  }
  private var collectionLayout: AnyLayout {
    horizontalSizeClass == .compact
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
      : AnyLayout(HStackLayout(spacing: 24))
  }
  private var computersPage: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        HStack {
          pageHeading("Computers", subtitle: "The desktops behind your library.")
          Spacer()
          Menu("New computer") {
            Button("Install Windows 98 SE…") { sheet = .windows9x(.windows98) }
            Button("Install Windows 95…") { sheet = .windows9x(.windows95) }
            if DistributionPolicy.current.allowsUnreviewedCatalogs { Button("Install Windows 3.1 + Word 6") { installReference() } }
            Button("Create a blank computer…") { sheet = .computer(true) }
          }.disabled(machines.active || machines.busy)
        }
        if machines.machines.isEmpty && DistributionPolicy.current.allowsUnreviewedCatalogs { referenceCollection }
        ForEach(machines.machines) { machine in
          HStack(spacing: 18) {
            Image(systemName: "desktopcomputer").font(.system(size: 30)).foregroundStyle(
              workspaceMint)
            VStack(alignment: .leading, spacing: 6) {
              Text(machine.name).font(.headline)
              Text(machine.systemTitle).font(.caption).foregroundStyle(.secondary)
              if let installation = machine.installation, installation.stage != .complete {
                Text(installation.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
              }
            }
            Spacer()
            Button("Settings") {
              machines.selected = machine.id
              sheet = .computer(false)
            }.disabled(machines.busy || (machines.active && machines.selected != machine.id))
            Button(machines.active && machines.selected == machine.id ? "Open session" : "Start") {
              openComputer(machine)
            }.disabled(machines.busy || (machines.active && machines.selected != machine.id))
          }.padding(22).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        }
      }.padding(30).frame(maxWidth: 1100).frame(maxWidth: .infinity)
    }.navigationTitle("Computers")
  }
  @ViewBuilder private var player: some View {
    if machines.active || machines.busy {
      VStack(spacing: 16) {
        HStack {
          pageHeading(
            playingTitle.isEmpty ? (machines.current?.name ?? "Your computer") : playingTitle,
            subtitle: machines.current?.systemTitle ?? "Preparing your desktop")
          Spacer()
          #if os(macOS)
            if machines.active {
              Button(machines.state == .paused(machines.selected ?? UUID()) ? "Resume" : "Pause") {
                Task {
                  do {
                    if case .paused = machines.state {
                      try await machines.session.resume()
                    } else {
                      try await machines.session.pause()
                    }
                  } catch { machines.error = error.localizedDescription }
                }
              }.disabled(machines.busy)
              SessionMediaMenu(model: machines, preferredMedia: playingMedia)
              if !machines.displayModes.isEmpty {
                Menu("Display") {
                  Toggle("Fit Windows to window", isOn: Binding(get: { machines.displayAutomatic }, set: { machines.setAutomaticDisplay($0) }))
                  Divider()
                  ForEach(machines.displayModes, id: \.self) { size in
                    Button(size.title) {
                      machines.setAutomaticDisplay(false)
                      machines.session.guestDisplay?.request(size)
                    }
                  }
                }.disabled(machines.busy)
              }
              Menu {
                Button("Type text in guest…") { sheet = .guestText }
                Button("Ctrl + Alt + Del") {
                  Task { try? await machines.session.sendChord(["ctrl", "alt", "delete"]) }
                }
                Button("Windows + R (Run)") { Task { try? await machines.session.sendChord(["meta_l", "r"]) } }
                Button("Ctrl + Esc (Start menu)") { Task { try? await machines.session.sendChord(["ctrl", "esc"]) } }
                Button("Alt + F4") { Task { try? await machines.session.sendChord(["alt", "f4"]) } }
                Button("Enter") { Task { try? await machines.session.tap("ret") } }
                Button("Escape") { Task { try? await machines.session.tap("esc") } }
                Button("Computer settings") { sheet = .computer(false) }
              } label: {
                Image(systemName: "ellipsis.circle")
              }.disabled(machines.busy)
              Button("Power off", role: .destructive) { showPowerOff = true }
            }
          #endif
        }
        if let message = machines.operationMessage {
          HStack {
            ProgressView().controlSize(.small)
            Text(message).font(.callout)
            Spacer()
            Button("Pause assistant") { machines.cancelAssistant() }
          }.padding(13).background(
            workspaceMint.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
        if !machines.busy, let installation = machines.current?.installation,
          installation.stage != .complete {
          HStack {
            Text(installation.message).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Continue installation") { machines.continueInstallationAssistant() }
              .disabled(!machines.active)
          }.padding(13).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        }
        #if os(macOS)
          if machines.active {
            MachineDisplayView(
              image: machines.image, session: machines.session,
              inputEnabled: !machines.busy
                && { if case .paused = machines.state { false } else { true } }(),
              absolutePointer: machines.absolutePointer
            ) { machines.captured = $0 }
            .frame(maxWidth: .infinity, maxHeight: .infinity).frame(minHeight: 340).background(
              .black
            ).clipShape(RoundedRectangle(cornerRadius: 12))
            HStack {
              Text(
                machines.absolutePointer ? "Seamless mouse · Move freely between Windows and Mac" : machines.captured
                  ? "Mouse captured · Control + Option releases input"
                  : "Click the screen to use mouse and keyboard")
              Spacer()
              if !machines.displayModes.isEmpty { Text(machines.displayMessage) }
              Button("Files") { section = .files }
            }.font(.caption).foregroundStyle(.secondary)
          } else {
            Spacer()
            ProgressView("Preparing your computer…")
            Spacer()
          }
        #else
          ContentUnavailableView(
            "Mac required", systemImage: "desktopcomputer",
            description: Text("Running this computer on iPhone is not available yet."))
        #endif
      }.padding(24).navigationTitle("Now playing")
    } else if library.running || library.isLaunching {
      ScrollView {
        VStack(spacing: 24) {
          Spacer()
          Image(systemName: "terminal").font(.system(size: 56)).foregroundStyle(workspaceMint)
          Text(
            library.sessionProgram?.manifest.title ?? library.current?.manifest.title ?? "Your app"
          ).font(.title.bold())
          Text(
            library.engineProgress?.message ?? "Your imported app runs in its compatibility window."
          ).foregroundStyle(.secondary)
          HStack {
            Button("Show app window") { library.session.showEmulator() }
            Button("Stop session", role: .destructive) { library.session.stop() }
          }
          if library.running { SessionInputPanel { library.session.showEmulator() } }
          if !library.floppyDrive.disks.isEmpty { FloppyDrivePanel(model: library) }
          Spacer()
        }.frame(maxWidth: .infinity).padding(30)
      }.navigationTitle("Now playing")
    } else {
      ContentUnavailableView {
        Label("Ready when you are", systemImage: "play.rectangle")
      } description: {
        Text("Open an app from your library to start a session.")
      } actions: {
        Button("Back to Library") { section = .library }
      }
    }
  }
  private func pageHeading(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.system(size: 29, weight: .semibold, design: .rounded))
      Text(subtitle).font(.callout).foregroundStyle(.secondary)
    }
  }
  private func openLabel(_ entry: LibraryEntry) -> String {
    if case .classic = entry.target, library.running { return "Open session" }
    if machines.active && entry.machineID == machines.selected { return "Open session" }
    return entry.installer ? "Open Setup" : "Open"
  }
  private func open(_ entry: LibraryEntry) {
    guard !machines.busy, !library.isLaunching else { return }
    selection = entry.id
    if let id = entry.machineID {
      guard !library.running, !machines.active || machines.selected == id else {
        apps.error = "Close the current session before opening another computer."
        return
      }
      if machines.active {
        section = .session
        #if os(macOS)
          Task {
            guard (try? await machines.session.isAtDOSPrompt()) == true else { return }
            if case .guest(let app) = entry.target, app.bootFromMedia == true { return }
            playingTitle = entry.title
            await launchNative(entry)
          }
        #endif
        return
      }
      machines.selected = id
      playingTitle = entry.title
      playingMedia = []
      section = .session
      Task { await launchNative(entry) }
    } else if case .classic(let app) = entry.target {
      guard !machines.active else {
        apps.error = "Close the current computer before opening an imported package."
        return
      }
      if library.running {
        playingTitle = library.sessionProgram?.manifest.title ?? app.manifest.title
        section = .session
        library.session.showEmulator()
        return
      }
      library.selected = app.id
      playingTitle = app.manifest.title
      section = .session
      if !library.running {
        Task { await library.launch() }
      } else {
        library.session.showEmulator()
      }
    }
  }
  private func launchNative(_ entry: LibraryEntry) async {
    playingMedia = []
    switch entry.target {
    case .computer: await machines.launch()
    case .word: await machines.launchWindows(word: true)
    case .windows:
      if let machine = machines.current, machine.guest.needsCD { openComputer(machine) }
      else { await machines.launchWindows(word: false) }
    case .guest(let app):
      playingMedia = app.mediaIDs
      await machines.launchApplication(app)
      if machines.active && machines.error == nil { await apps.opened(app) }
    case .classic: break
    }
  }
  private func openComputer(_ machine: Machine) {
    guard !library.running else {
      apps.error = "Close the current app before starting a computer."
      return
    }
    machines.selected = machine.id
    playingTitle = machine.name
    playingMedia = []
    section = .session
    if !machines.active { Task { await machines.launch() } }
  }
  private func installReference() {
    guard !library.running else {
      apps.error = "Close the current app before installing a computer."
      return
    }
    playingTitle = "Windows 3.1 + Word 6"
    section = .session
    machines.prepareReferenceStack()
  }
  private func searchWeb() {
    if catalog.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix(
      "https://")
    {
      sheet = .source(catalog.query)
    } else {
      catalog.search()
    }
  }
  private func clearMessages() {
    apps.error = nil
    machines.error = nil
    machines.notice = nil
    library.error = nil
  }
}

private struct SessionMediaMenu: View {
  @ObservedObject var model: MachineLibraryModel
  var preferredMedia: [UUID]
  @State private var showing = false
  @State private var allMedia = false
  private var floppies: [MachineMedia] {
    let all = model.current?.floppies ?? []
    if preferredMedia.isEmpty || allMedia { return all }
    var bank = preferredMedia.compactMap { id in all.first { $0.id == id } }
    #if os(macOS)
      if let current = all.first(where: { $0.id == model.session.currentFloppy }),
        !bank.contains(current)
      {
        bank.append(current)
      }
    #endif
    return bank
  }
  var body: some View {
    Button {
      showing.toggle()
    } label: {
      Label("Disks", systemImage: "externaldrive")
    }
    .popover(isPresented: $showing) {
      VStack(alignment: .leading, spacing: 16) {
        Text("Disks & CD-ROM").font(.headline)
        if !preferredMedia.isEmpty {
          Toggle("Show all computer media", isOn: $allMedia).font(.caption)
        }
        #if os(macOS)
          Picker(
            "Floppy · A:",
            selection: Binding<UUID?>(
              get: { model.session.currentFloppy },
              set: { id in
                Task {
                  if let disk = floppies.first(where: { $0.id == id }) {
                    await model.insert(disk, cdrom: false)
                  } else {
                    await model.eject(cdrom: false)
                  }
                }
              })
          ) {
            Text("Empty drive").tag(UUID?.none)
            ForEach(floppies) { disk in
              Text((disk.purpose.map { $0.title + " · " } ?? "") + disk.name).tag(Optional(disk.id))
            }
          }
          HStack {
            Button("Next disk") {
              let current = floppies.firstIndex { $0.id == model.session.currentFloppy } ?? -1
              if current + 1 < floppies.count {
                Task { await model.insert(floppies[current + 1], cdrom: false) }
              }
            }.disabled(floppies.isEmpty || floppies.last?.id == model.session.currentFloppy)
            Button("Eject floppy") { Task { await model.eject(cdrom: false) } }.disabled(
              model.session.currentFloppy == nil)
          }
          Divider()
          Picker(
            "CD-ROM",
            selection: Binding<UUID?>(
              get: { model.session.currentCD },
              set: { id in
                Task {
                  if let disk = model.current?.cdroms.first(where: { $0.id == id }) {
                    await model.insert(disk, cdrom: true)
                  } else {
                    await model.eject(cdrom: true)
                  }
                }
              })
          ) {
            Text("Empty drive").tag(UUID?.none)
            ForEach(model.current?.cdroms ?? []) { Text($0.name).tag(Optional($0.id)) }
          }
        #endif
        Text("After inserting the requested disk, continue Setup in the guest.").font(.caption)
          .foregroundStyle(.secondary)
      }.padding(22).frame(width: 400).disabled(model.busy)
    }.disabled(model.busy)
  }
}

private struct WorkspaceFilesView: View {
  @ObservedObject var model: MachineLibraryModel
  @ObservedObject var library: LibraryModel
  @State private var compatibilityFiles = false
  var openSession: () -> Void
  @State private var importing = false
  @State private var exporting: MachineMedia?
  private var disks: [MachineMedia] {
    model.current?.floppies.filter { $0.purpose == .exchange } ?? []
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Files").font(.system(size: 29, weight: .semibold, design: .rounded))
          Text("A simple bridge between your Mac and your classic apps.").foregroundStyle(
            .secondary)
        }
        if !library.programs.isEmpty {
          Picker("Files for", selection: $compatibilityFiles) {
            Text("Computers").tag(false)
            Text("Imported packages · D:").tag(true)
          }.pickerStyle(.segmented).frame(maxWidth: 400)
        }
        if compatibilityFiles {
          ImportedPackageFilesView(model: library)
        } else if model.machines.isEmpty {
          ContentUnavailableView(
            "Your files need a computer", systemImage: "folder",
            description: Text(
              "Install a desktop from Discover, then use an exchange floppy to share files."))
        } else {
          Picker("Computer", selection: $model.selected) {
            ForEach(model.machines) { Text($0.name).tag(Optional($0.id)) }
          }.disabled(model.active || model.busy)
          VStack(alignment: .leading, spacing: 15) {
            Label("Live shared folder · Windows 9x", systemImage: "network").font(.title2.bold())
            Text("Files in this folder are available to both your Mac and the running Windows computer. Only this computer’s Shared folder is exposed.")
              .font(.callout).foregroundStyle(.secondary)
            Text(verbatim: "\\\\DOSHOST\\DOSMAC").font(.system(.body, design: .monospaced)).textSelection(.enabled)
            Button(model.current?.sharedFolder == true ? "Open shared folder in Finder" : "Enable & open shared folder") {
              Task { await model.openSharedFolder() }
            }.disabled(model.busy || (model.active && model.current?.sharedFolder != true))
            Text(DistributionPolicy.current.allowsHostDiskMounts ? "Windows configured by DosMac maps this share to H:. Other computers need the AMD PCnet adapter, TCP/IP, Client for Microsoft Networks, and the DOSHOST alias. DOS and Windows 3.1 can use the shared disk below." : "Windows configured by DosMac maps this share to H:. Other computers need compatible network settings and the DOSHOST alias. For DOS and Windows 3.1, use an exchange floppy below.")
              .font(.caption).foregroundStyle(.secondary)
          }.padding(24).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 15))
          if DistributionPolicy.current.allowsHostDiskMounts {
          VStack(alignment: .leading, spacing: 15) {
            Label("Shared disk · D:", systemImage: "externaldrive.fill").font(.title2.bold())
            Text("A 64 MB disk for your documents, folders, and programs. Open it in Finder while the computer is stopped; DosMac ejects it from your Mac before starting DOS or Windows.")
              .font(.callout).foregroundStyle(.secondary)
            Button(model.current?.sharedDisk == true ? "Open shared disk in Finder" : "Create & open shared disk") {
              Task { await model.openSharedDisk() }
            }.buttonStyle(.borderedProminent).foregroundStyle(workspaceBase)
              .disabled(model.active || model.busy)
            Text("Available as D: on a computer with a single C: partition. CD-ROM letters may move. Finish saving on both systems before switching.")
              .font(.caption).foregroundStyle(.secondary)
          }.padding(24).background(workspaceMint.opacity(0.05), in: RoundedRectangle(cornerRadius: 15))
          }
          VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 18) {
              Image(systemName: "arrow.left.arrow.right").font(.largeTitle).foregroundStyle(
                workspaceMint)
              VStack(alignment: .leading, spacing: 6) {
                Text("Send in. Bring back.").font(.title2.bold())
                Text(
                  "Prepare an exchange floppy, insert it from the session’s Disks menu, and use drive A: in DOS or Windows."
                ).font(.callout).foregroundStyle(.secondary)
              }
            }
            HStack {
              Button("Add files from Mac…") {
                exporting = nil
                importing = true
              }.buttonStyle(.borderedProminent).foregroundStyle(workspaceBase)
              Button("Create empty floppy") { Task { await model.makeExchange([]) } }
            }.disabled(model.active || model.busy)
            Text(
              "1.44 MB per floppy · Root files only · DOS 8.3 names (letters, digits, underscores)"
            ).font(.caption).foregroundStyle(.secondary)
          }.padding(24).background(
            workspaceMint.opacity(0.05), in: RoundedRectangle(cornerRadius: 15))
          if model.active {
            HStack {
              Text("Finish saving and exit Windows before powering off to prepare or export files.")
                .font(.callout).foregroundStyle(.secondary)
              Spacer()
              Button("Open session") { openSession() }
            }
          }
          ForEach(Array(disks.enumerated()), id: \.element.id) { index, disk in
            HStack(spacing: 15) {
              Image(systemName: "externaldrive").font(.title2).foregroundStyle(workspaceMint)
              VStack(alignment: .leading, spacing: 5) {
                Text("Exchange floppy \(index + 1)").font(.headline)
                Text("Use A: in the guest; export its files back to your Mac here.").font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Button("Export to Mac…") {
                exporting = disk
                importing = true
              }.disabled(model.active || model.busy)
            }.padding(19).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
          }
        }
      }.padding(30).frame(maxWidth: 1100).frame(maxWidth: .infinity)
    }.navigationTitle("Files").onAppear {
      if model.machines.isEmpty && !library.programs.isEmpty { compatibilityFiles = true }
    }
    .fileImporter(
      isPresented: $importing, allowedContentTypes: exporting == nil ? [.data] : [.folder],
      allowsMultipleSelection: exporting == nil
    ) { result in
      do {
        let urls = try result.get()
        if let disk = exporting, let destination = urls.first {
          Task { await model.exportExchange(disk, destination: destination) }
        } else {
          Task { await model.makeExchange(urls) }
        }
      } catch { model.error = error.localizedDescription }
    }
  }
}

struct GuestApplicationForm: View {
  let machines: [Machine]
  @ObservedObject var apps: WorkspaceLibraryModel
  var existing: GuestApplication? = nil
  @Environment(\.dismiss) private var dismiss
  @State private var title = ""
  @State private var machineID: UUID?
  @State private var executable = ""
  @State private var windows = true
  @State private var busy = false
  @State private var bootDisk = false
  @State private var error: String?
  var body: some View {
    NavigationStack {
      Form {
        Text("Add a program already installed inside one of your computers.").foregroundStyle(
          .secondary)
        TextField("App name", text: $title)
        Picker("Computer", selection: $machineID) {
          ForEach(machines) { Text($0.name).tag(Optional($0.id)) }
        }.disabled(existing != nil)
        Picker("Runs in", selection: $windows) {
          Text("Windows 3.1").tag(true)
          Text("DOS").tag(false)
        }
        if existing?.kind == .installer { Toggle("Boot from the setup disk", isOn: $bootDisk) }
        TextField("Program path", text: $executable).font(.system(.body, design: .monospaced))
        Text(
          "Use its full guest path, for example C:\\WINWORD\\WINWORD.EXE. The app will appear in Library."
        ).font(.caption).foregroundStyle(.secondary)
        if let error { Text(error).foregroundStyle(.orange) }
      }.padding(20).navigationTitle(existing == nil ? "Add installed app" : "Edit shortcut")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }.disabled(busy)
          }
          ToolbarItem(placement: .confirmationAction) {
            Button(existing == nil ? "Add to Library" : "Save changes") {
              guard let machineID else { return }
              busy = true
              Task {
                var app =
                  existing
                  ?? GuestApplication(
                    machineID: machineID, title: title, executable: executable, windows: windows)
                app.title = title
                app.executable = executable
                app.windows = windows
                app.bootFromMedia = bootDisk
                if await apps.save(app) {
                  dismiss()
                } else {
                  error = apps.error
                  apps.error = nil
                }
                busy = false
              }
            }.disabled(
              busy || title.trimmingCharacters(in: .whitespaces).isEmpty || executable.isEmpty
                || machineID == nil)
          }
        }
    }.onAppear {
      machineID = existing?.machineID ?? machines.first?.id
      if let existing {
        title = existing.title
        executable = existing.executable
        windows = existing.windows
        bootDisk = existing.bootFromMedia == true
      }
    }
    #if os(macOS)
      .frame(width: 560, height: 380)
    #endif
  }
}

private struct ImportedPackageFilesView: View {
  @ObservedObject var model: LibraryModel
  @State private var files: [URL] = []
  @State private var importing = false
  @Environment(\.scenePhase) private var phase
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Shared files · D:").font(.title2.bold())
      Text(
        "Imported packages share this folder as drive D:. Save a document there, then export it here."
      ).foregroundStyle(.secondary)
      Button("Add files from Mac…") { importing = true }
      if files.isEmpty {
        ContentUnavailableView(
          "No shared files yet", systemImage: "folder",
          description: Text("Add a file, or save one to D: in an imported app."))
      }
      ForEach(files, id: \.self) { file in
        HStack {
          Label(file.lastPathComponent, systemImage: "doc")
          Spacer()
          ShareLink(item: file) { Label("Export", systemImage: "square.and.arrow.up") }
        }.padding(16).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
      }
    }.task { reload() }.onChange(of: phase) { _, phase in if phase == .active { reload() } }
      .fileImporter(
        isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: true
      ) { result in
        do {
          guard let destination = model.library?.exchangeURL else { return }
          for source in try result.get() {
            let accessed = source.startAccessingSecurityScopedResource()
            defer { if accessed { source.stopAccessingSecurityScopedResource() } }
            let info = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true else {
              throw VMError.invalid("Choose regular files to share.")
            }
            try FileManager.default.copyItem(
              at: source, to: destination.appendingPathComponent(source.lastPathComponent))
          }
          reload()
        } catch {
          model.error = error.localizedDescription
          reload()
        }
      }
  }
  private func reload() {
    guard let folder = model.library?.exchangeURL else { return }
    files =
      ((try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])) ?? [])
      .filter { url in
        guard let info = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        else { return false }
        return info.isRegularFile == true && info.isSymbolicLink != true
      }.sorted {
        $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
      }
  }
}
