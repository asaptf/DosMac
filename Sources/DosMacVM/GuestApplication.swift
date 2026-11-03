import Foundation

public enum GuestApplicationKind: String, Codable, Sendable { case application, installer }

public struct GuestApplication: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public let machineID: UUID
  public var title: String
  public var executable: String
  public var windows: Bool
  public var kind: GuestApplicationKind
  public var mediaIDs: [UUID]
  public var source: URL?
  public var bootFromMedia: Bool?
  public var lastOpenedAt: Date?
  public init(
    machineID: UUID, title: String, executable: String, windows: Bool,
    kind: GuestApplicationKind = .application, mediaIDs: [UUID] = [], source: URL? = nil,
    bootFromMedia: Bool = false
  ) {
    id = UUID()
    self.machineID = machineID
    self.title = title
    self.executable = executable
    self.windows = windows
    self.kind = kind
    self.mediaIDs = mediaIDs
    self.source = source
    self.bootFromMedia = bootFromMedia
  }
  public func validate() throws {
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 160,
      mediaIDs.count <= 64
    else { throw VMError.invalid("Enter an app name and a valid disk set.") }
    _ = try Self.command(executable: executable, windows: windows)
  }
  public static func command(executable: String, windows: Bool) throws -> String {
    guard executable.count <= 127,
      executable.range(
        of: "^[A-Za-z]:\\\\(?:[A-Za-z0-9_~-]{1,8}\\\\)*[A-Za-z0-9_~-]{1,8}\\.(?:EXE|COM|BAT)$",
        options: .caseInsensitive.union(.regularExpression)) != nil
    else {
      throw VMError.invalid("Use a full DOS 8.3 path, for example C:\\WINWORD\\WINWORD.EXE.")
    }
    if windows { return "C:\\WINDOWS\\WIN.COM \(executable)\n" }
    let pieces = executable.split(separator: "\\").map(String.init)
    let directory = pieces.dropFirst().dropLast().joined(separator: "\\")
    return "\(pieces[0])\nCD \\\(directory)\n\(executable)\n"
  }
}

public actor GuestApplicationStore {
  private let file: URL
  public init(file: URL) { self.file = file }
  public static var defaultURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DosMac/Library/apps.json")
  }
  public func applications() throws -> [GuestApplication] {
    guard FileManager.default.fileExists(atPath: file.path) else { return [] }
    let apps = try JSONDecoder().decode([GuestApplication].self, from: Data(contentsOf: file))
    for app in apps { try app.validate() }
    return apps
  }
  public func save(_ app: GuestApplication) throws {
    try app.validate()
    var apps = try applications()
    apps.removeAll { $0.id == app.id }
    apps.append(app)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(apps).write(to: file, options: .atomic)
  }
}
