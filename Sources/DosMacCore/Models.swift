import Foundation

public enum DosMacError: LocalizedError {
    case invalidPackage(String)
    case alreadyInstalled
    case engineMissing
    case unsupportedPlatform
    case sessionActive

    public var errorDescription: String? {
        switch self {
        case .invalidPackage(let reason): "Invalid package: \(reason)"
        case .alreadyInstalled: "This program is already installed."
        case .engineMissing: "DOSBox-X was not found. Choose its executable in Settings."
        case .unsupportedPlatform: "The embedded emulator is not available in this iPhone preview yet. Library and file import are available."
        case .sessionActive: "Stop the current session before launching another program."
        }
    }
}

public enum MachineProfile: String, Codable, CaseIterable, Sendable {
    case dos, windows31
    public var title: String { self == .dos ? "DOS · 386" : "Windows 3.1 · 486" }
    public var memoryMB: Int { self == .dos ? 16 : 64 }
    public var cpu: String { self == .dos ? "386" : "486" }
}

public struct PackageManifest: Codable, Equatable, Sendable {
    public var formatVersion: Int
    public var id: String
    public var title: String
    public var summary: String
    public var version: String
    public var author: String
    public var license: String
    public var executable: String
    public var profile: MachineProfile

    public init(id: String, title: String, summary: String, version: String = "1.0", author: String, license: String, executable: String, profile: MachineProfile = .dos) {
        self.formatVersion = 1
        self.id = id
        self.title = title
        self.summary = summary
        self.version = version
        self.author = author
        self.license = license
        self.executable = executable
        self.profile = profile
    }

    public func validate() throws {
        guard formatVersion == 1 else { throw DosMacError.invalidPackage("unsupported format version") }
        guard !id.isEmpty, id.count <= 80, id.range(of: "^[a-z0-9]+([.-][a-z0-9]+)*$", options: .regularExpression) != nil else {
            throw DosMacError.invalidPackage("invalid identifier")
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !license.isEmpty else {
            throw DosMacError.invalidPackage("title and license are required")
        }
        // DOS 8.3 paths deliberately exclude batch metacharacters and quoted commands.
        let path = executable.replacingOccurrences(of: "\\", with: "/")
        guard path.range(of: "^([A-Za-z0-9_~-]{1,8}/)*[A-Za-z0-9_~-]{1,8}\\.(EXE|COM|BAT)$", options: [.regularExpression, .caseInsensitive]) != nil else {
            throw DosMacError.invalidPackage("entry point must be a relative DOS 8.3 EXE, COM, or BAT path")
        }
    }
}

public struct InstalledProgram: Codable, Identifiable, Equatable, Sendable {
    public var id: String { manifest.id }
    public let manifest: PackageManifest
    public let installedAt: Date
    public var lastLaunchedAt: Date?
}
