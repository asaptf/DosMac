import Foundation

public struct FloppyDisk: Codable, Equatable, Identifiable, Sendable {
    public var id: Int { number }
    public let number: Int
    public let imagePath: String
    public let label: String

    public init(number: Int, imagePath: String, label: String) {
        self.number = number
        self.imagePath = imagePath
        self.label = label
    }
}

public struct FloppyDriveStatus: Equatable, Sendable {
    public var disks: [FloppyDisk] = []
    public var mountedNumber: Int?
    public var isChanging = false
    public var message: String?
    public init() { }
    public var mountedDisk: FloppyDisk? { disks.first { $0.number == mountedNumber } }
    public var nextDisk: FloppyDisk? {
        guard let mountedNumber, !disks.isEmpty else { return nil }
        return disks[(mountedNumber % disks.count)]
    }
}

struct DiskMountReport: Equatable, Sendable {
    let number: Int
    let count: Int
}

/// Consumes bounded log chunks; state changes only on an emulator mount acknowledgement.
struct DiskLogDecoder: Sendable {
    private var pending = Data()

    mutating func append(_ data: Data) -> [DiskMountReport] {
        pending.append(data)
        var reports: [DiskMountReport] = []
        while let newline = pending.firstIndex(of: 10) {
            let line = String(decoding: pending[..<newline], as: UTF8.self)
            pending.removeSubrange(...newline)
            if let report = Self.parse(line) { reports.append(report) }
        }
        if pending.count > 8192 { pending.removeAll(keepingCapacity: true) }
        return reports
    }

    static func parse(_ line: String) -> DiskMountReport? {
        guard let expression = try? NSRegularExpression(pattern: "Drive A: disk ([0-9]+) of ([0-9]+) now active"),
              let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let nr = Range(match.range(at: 1), in: line), let cr = Range(match.range(at: 2), in: line),
              let number = Int(line[nr]), let count = Int(line[cr]), count > 0, count <= 32, (1...count).contains(number) else { return nil }
        return DiskMountReport(number: number, count: count)
    }
}
