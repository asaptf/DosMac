import Foundation

public enum VMError: LocalizedError, Sendable {
    case invalid(String), engineMissing, notRunning, protocolError(String), timeout(String)
    public var errorDescription: String? {
        switch self {
        case .invalid(let message), .protocolError(let message): message
        case .engineMissing: "The managed QEMU engine is unavailable. This developer build can also use DOSMAC_QEMU_PATH or a local QEMU installation."
        case .notRunning: "This machine is not running."
        case .timeout(let command): "The machine did not respond to \(command) in time."
        }
    }
}

public enum GuestSystem: String, Codable, CaseIterable, Sendable {
    case msdos622, pcdos, windows31, windows95, windows98
    public var title: String {
        switch self { case .msdos622: "MS-DOS 6.22"; case .pcdos: "IBM PC DOS"; case .windows31: "DOS + Windows 3.1"; case .windows95: "Windows 95"; case .windows98: "Windows 98 SE" }
    }
    public var cpu: String { self == .windows95 || self == .windows98 ? "pentium" : "486" }
    public var memoryMB: Int { self == .windows98 ? 64 : (self == .windows95 ? 32 : 16) }
    public var diskMB: Int { needsCD ? 1024 : 512 }
    public var needsCD: Bool { self == .windows95 || self == .windows98 }
}

public enum BootDevice: String, Codable, CaseIterable, Sendable {
    case hardDisk, floppy, cdrom
    public var title: String { switch self { case .hardDisk: "Hard disk (C:)"; case .floppy: "Floppy (A:)"; case .cdrom: "CD-ROM" } }
    var qemuOrder: String { switch self { case .hardDisk: "c"; case .floppy: "ac"; case .cdrom: "dc" } }
}

public enum MediaPurpose: String, Codable, Sendable {
    case dosSetup, windowsSetup, wordSetup, exchange, other
    public var title: String { switch self { case .dosSetup: "DOS Setup"; case .windowsSetup: "Windows Setup"; case .wordSetup: "Word Setup"; case .exchange: "File exchange"; case .other: "Media" } }
}

public enum InstallationStage: String, Codable, Sendable {
    case dosSetup, windowsSetup, wordSetup, complete
}

public struct InstallationRecord: Codable, Equatable, Sendable {
    public var recipeID: String
    public var stage: InstallationStage
    public var message: String
    public var needsAttention: Bool
    public init(recipeID: String, stage: InstallationStage = .dosSetup, message: String = "Ready to install DOS", needsAttention: Bool = false) {
        self.recipeID = recipeID; self.stage = stage; self.message = message; self.needsAttention = needsAttention
    }
}

public struct MachineMedia: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let relativePath: String
    public let purpose: MediaPurpose?
    public init(id: UUID = UUID(), name: String, relativePath: String, purpose: MediaPurpose? = nil) { self.id = id; self.name = name; self.relativePath = relativePath; self.purpose = purpose }
}

public struct Machine: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var guest: GuestSystem
    public var boot: BootDevice
    public var floppies: [MachineMedia]
    public var cdroms: [MachineMedia]
    public let createdAt: Date
    public var installation: InstallationRecord?
    public var sharedDisk: Bool?
    public var sharedFolder: Bool?

    public init(id: UUID = UUID(), name: String, guest: GuestSystem, boot: BootDevice = .floppy, floppies: [MachineMedia] = [], cdroms: [MachineMedia] = []) {
        self.id = id; self.name = name; self.guest = guest; self.boot = boot
        self.floppies = floppies; self.cdroms = cdroms; createdAt = Date()
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 120, floppies.count <= 64, cdroms.count <= 16 else { throw VMError.invalid("Invalid machine name or media count.") }
        let all = floppies + cdroms
        guard Set(all.map(\.id)).count == all.count, Set(all.map(\.relativePath)).count == all.count else { throw VMError.invalid("Duplicate media identifiers or paths.") }
        for media in all {
            guard media.relativePath.range(of: "^Media/[A-Za-z0-9-]+\\.(img|ima|dsk|iso)$", options: .regularExpression) != nil else { throw VMError.invalid("Media paths must stay inside the machine's Media folder.") }
        }
    }
}
