import DosMacCore
import DosMacVM
import SwiftUI

@MainActor
final class WorkspaceLibraryModel: ObservableObject {
  @Published var apps: [GuestApplication] = []
  @Published var error: String?
  let store = GuestApplicationStore(file: GuestApplicationStore.defaultURL)
  init() { Task { await refresh() } }
  func refresh() async {
    do { apps = try await store.applications() } catch { self.error = error.localizedDescription }
  }
  @discardableResult func save(_ app: GuestApplication) async -> Bool {
    do {
      try await store.save(app)
      await refresh()
      return true
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }
  func opened(_ app: GuestApplication) async {
    var app = app
    app.lastOpenedAt = Date()
    _ = await save(app)
  }
}

struct LibraryEntry: Identifiable {
  enum Target {
    case computer(UUID)
    case word(UUID)
    case windows(UUID)
    case guest(GuestApplication)
    case classic(InstalledProgram)
  }
  let id: String
  let title: String
  let summary: String
  let context: String
  let symbol: String
  let kind: String
  let target: Target
  var installer: Bool {
    switch target {
    case .guest(let app): app.kind == .installer
    case .classic(let app):
      !(app.manifest.floppyDisks ?? []).isEmpty && app.manifest.effectiveStartupMode == .program
    default: false
    }
  }
  var machineID: UUID? {
    switch target {
    case .word(let id), .windows(let id), .computer(let id): id
    case .guest(let app): app.machineID
    case .classic: nil
    }
  }
  static func entries(machines: [Machine], apps: [GuestApplication], packages: [InstalledProgram])
    -> [LibraryEntry]
  {
    var entries: [LibraryEntry] = []
    for machine in machines {
      if machine.diagnostic == true {
        entries.append(Self(id: "computer-\(machine.id)", title: machine.name,
          summary: "An original keyboard and display check. No operating system required.", context: machine.systemTitle,
          symbol: "desktopcomputer", kind: "PC DIAGNOSTIC", target: .computer(machine.id)))
        continue
      }
      if machine.guest.needsCD {
        if machine.installation?.stage == .complete {
          entries.append(Self(id: "windows-\(machine.id)", title: machine.guest.title,
            summary: "Your Windows desktop, programs, and shared files.", context: machine.name,
            symbol: "desktopcomputer", kind: "DESKTOP", target: .windows(machine.id)))
        }
        continue
      }
      if machine.installation?.stage == .complete {
        entries.append(
          Self(
            id: "word-\(machine.id)", title: "Microsoft Word 6",
            summary: "Write, edit, and revisit your classic documents.", context: machine.name,
            symbol: "doc.text", kind: "WINDOWS 3.1", target: .word(machine.id)))
      }
      if let stage = machine.installation?.stage, stage == .wordSetup || stage == .complete {
        entries.append(
          Self(
            id: "windows-\(machine.id)", title: "Windows 3.1",
            summary: "Your desktop, programs, and files, just as you left them.",
            context: machine.name, symbol: "macwindow", kind: "DESKTOP",
            target: .windows(machine.id)))
      }
    }
    for app in apps {
      guard let machine = machines.first(where: { $0.id == app.machineID }) else { continue }
      entries.append(
        Self(
          id: app.id.uuidString, title: app.title,
          summary: app.kind == .installer
            ? "Installation media is ready. Open Setup to install this release."
            : "Installed in \(machine.name).", context: machine.name,
          symbol: app.kind == .installer ? "shippingbox" : "app",
          kind: app.kind == .installer ? "INSTALLER" : (app.windows ? "WINDOWS 3.1" : "DOS"),
          target: .guest(app)))
    }
    for app in packages {
      entries.append(
        Self(
          id: "classic-\(app.id)", title: app.manifest.title, summary: app.manifest.summary,
          context: "Imported package", symbol: "terminal",
          kind: app.manifest.profile == .windows31 ? "WINDOWS PACKAGE" : "DOS PACKAGE",
          target: .classic(app)))
    }
    return entries
  }
}

@MainActor
final class CatalogSearchModel: ObservableObject {
  struct Response: Sendable {
    let items: [CatalogItem]
    let error: String?
  }
  @Published var query = ""
  @Published var provider = "all"
  @Published var items: [CatalogItem] = []
  @Published var errors: [String] = []
  @Published var busy = false
  @Published var searched = false
  private var operation: Task<Void, Never>?
  private var generation = UUID()
  func search() {
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    operation?.cancel()
    let token = UUID()
    generation = token
    let sources = CatalogSource.allCases.filter { provider == "all" || $0.rawValue == provider }
    items = []
    errors = []
    busy = true
    searched = true
    operation = Task {
      await withTaskGroup(of: Response.self) { group in
        for source in sources {
          group.addTask {
            do {
              return Response(
                items: try await SoftwareSources().search(text, source: source), error: nil)
            } catch is CancellationError { return Response(items: [], error: nil) } catch {
              return Response(
                items: [],
                error: source.title + ": "
                  + (error.localizedDescription.contains("429")
                    ? "Temporarily limiting requests. Try later or open the website."
                    : error.localizedDescription))
            }
          }
        }
        for await response in group {
          guard generation == token, !Task.isCancelled else { continue }
          items.append(contentsOf: response.items)
          if let error = response.error { errors.append(error) }
        }
      }
      if generation == token { busy = false }
    }
  }
  func reset() {
    cancel()
    items = []
    errors = []
    searched = false
  }
  func cancel() {
    generation = UUID()
    operation?.cancel()
    busy = false
    searched = !items.isEmpty || !errors.isEmpty
  }
}
