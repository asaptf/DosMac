import Foundation

public struct GuestDisplaySize: Hashable, Sendable, Comparable {
    public let width: Int
    public let height: Int
    public init(_ width: Int, _ height: Int) { self.width = width; self.height = height }
    public var title: String { "\(width) × \(height)" }
    public var valid: Bool { (640...1600).contains(width) && (480...1200).contains(height) }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.width * lhs.height == rhs.width * rhs.height ? lhs.width < rhs.width : lhs.width * lhs.height < rhs.width * rhs.height
    }
    public static func fitting(width: Int, height: Int, modes: [Self]) -> Self? {
        let valid = modes.filter(\.valid)
        return valid.filter { $0.width <= width && $0.height <= height }.max() ?? valid.min()
    }
}

public enum GuestDisplayReply: Equatable, Sendable {
    case ready(GuestDisplaySize, [GuestDisplaySize])
    case result(UInt32, Bool, GuestDisplaySize)
}

public enum GuestDisplayProtocol {
    public static func validToken(_ token: String) -> Bool {
        token.utf8.count == 32 && token.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    public static func parse(_ data: Data, token: String) -> GuestDisplayReply? {
        guard validToken(token), data.count <= 8192, let text = String(data: data, encoding: .ascii), text.hasSuffix("\nEND\n") else { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 3, lines.count <= 132 else { return nil }
        let header = lines[0].split(separator: " ")
        guard header.count >= 3, header[0] == "DMAC1", header[2] == token else { return nil }
        func size(_ w: Substring, _ h: Substring) -> GuestDisplaySize? {
            guard let w = Int(w), let h = Int(h) else { return nil }
            let value = GuestDisplaySize(w, h); return value.valid ? value : nil
        }
        if header[1] == "READY", header.count == 5, let current = size(header[3], header[4]) {
            var modes = Set<GuestDisplaySize>()
            for line in lines.dropFirst().dropLast(2) {
                let fields = line.split(separator: " ")
                guard fields.count == 3, fields[0] == "MODE", let mode = size(fields[1], fields[2]) else { return nil }
                modes.insert(mode)
            }
            guard !modes.isEmpty else { return nil }
            return .ready(current, modes.sorted())
        }
        if header[1] == "RESULT", header.count == 7, lines.count == 3,
           let id = UInt32(header[3]), ["OK", "FAILED"].contains(header[4]), let current = size(header[5], header[6]) {
            return .result(id, header[4] == "OK", current)
        }
        return nil
    }
}

#if os(macOS)
/// A small, bounded protocol over the existing isolated Windows live share.
/// It never treats guest data as a host path or executable command.
@MainActor
public final class GuestDisplayBridge {
    public private(set) var modes: [GuestDisplaySize] = []
    public private(set) var current: GuestDisplaySize?
    public private(set) var automatic = false
    public private(set) var message = "Waiting for Guest Tools…"
    public var onChange: (() -> Void)?
    private let directory: URL
    private var token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    private var poller: Task<Void, Never>?
    private var resizeTask: Task<Void, Never>?
    private var sequence: UInt32 = 0
    private var pending: (UInt32, GuestDisplaySize, Date)?
    private var viewport: (Int, Int)?
    private var lastData: Data?
    public init(sharedDirectory: URL) { directory = sharedDirectory.appendingPathComponent("DMTOOLS", isDirectory: true) }
    public var ready: Bool { !modes.isEmpty }

    public func start() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write("DMAC1 HELLO \(token)\n")
        poller = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
        }
    }
    public func stop() { poller?.cancel(); poller = nil; resizeTask?.cancel(); resizeTask = nil }
    public func setAutomatic(_ enabled: Bool) {
        automatic = enabled; onChange?()
        if enabled, let viewport { self.viewport = nil; fit(width: viewport.0, height: viewport.1) }
        else { resizeTask?.cancel() }
    }
    public func fit(width: Int, height: Int) {
        guard width > 0, height > 0, viewport?.0 != width || viewport?.1 != height else { return }
        viewport = (width, height)
        guard automatic, ready else { return }
        resizeTask?.cancel()
        resizeTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard let self, let target = GuestDisplaySize.fitting(width: width, height: height, modes: self.modes) else { return }
            self.request(target)
        }
    }
    public func request(_ target: GuestDisplaySize) {
        guard modes.contains(target), (target != current || pending != nil), pending?.1 != target else { return }
        sequence &+= 1
        do {
            try write("DMAC1 RESIZE \(token) \(sequence) \(target.width) \(target.height)\n")
            pending = (sequence, target, Date()); message = "Changing Windows to \(target.title)…"; onChange?()
        } catch { message = "Could not send the display request."; onChange?() }
    }
    private func write(_ value: String) throws { try Data(value.utf8).write(to: directory.appendingPathComponent("REQUEST.TXT"), options: .atomic) }
    private func poll() {
        if let pending, Date().timeIntervalSince(pending.2) > 12 {
            self.pending = nil; message = "Windows did not confirm the display change. Reconnecting Guest Tools…"; automatic = false
            // A guest reset can kill the agent without restarting the QEMU session.
            // A fresh handshake also discards late responses to timed-out requests.
            token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            modes = []; current = nil; lastData = nil
            try? write("DMAC1 HELLO \(token)\n")
            onChange?()
        }
        let path = directory.appendingPathComponent("STATUS.TXT")
        guard let length = try? path.resourceValues(forKeys: [.fileSizeKey]).fileSize, length <= 8192,
              let data = try? Data(contentsOf: path), data != lastData,
              let reply = GuestDisplayProtocol.parse(data, token: token) else { return }
        lastData = data
        switch reply {
        case .ready(let size, let modes):
            current = size; self.modes = modes; message = "Windows display · \(size.title)"
            if automatic, let viewport { self.viewport = nil; fit(width: viewport.0, height: viewport.1) }
        case .result(let id, let success, let size):
            guard let pending, id == pending.0 else { return }
            current = size; self.pending = nil
            if success, size == pending.1 { message = "Windows display · \(size.title)" }
            else { message = "The Windows driver could not apply this resolution."; automatic = false }
        }
        onChange?()
    }
}
#endif
