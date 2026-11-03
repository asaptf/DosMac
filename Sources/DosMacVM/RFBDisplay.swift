import Foundation

public struct VMFrame: Sendable {
    public let width: Int
    public let height: Int
    /// Four bytes per pixel, red/green/blue/unused.
    public let pixels: Data
}

#if os(macOS)
/// Private RFB 3.8 viewer: raw rectangles + desktop resize, no external viewer/window.
public actor RFBDisplay {
    private let socket: LocalSocket
    private var width = 0
    private var height = 0
    private var pixels = Data()
    private var reader: Task<Void, Never>?
    private let onFrame: @Sendable (VMFrame) async -> Void
    private let onError: @Sendable (String) async -> Void

    public init(path: String, onFrame: @escaping @Sendable (VMFrame) async -> Void, onError: @escaping @Sendable (String) async -> Void) throws {
        socket = try LocalSocket(path: path); self.onFrame = onFrame; self.onError = onError
    }

    public func start() async throws {
        let transport = socket
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(10)); await transport.close() }
            catch { }
        }
        defer { watchdog.cancel() }
        await socket.start()
        let version = try await socket.read(12)
        guard String(decoding: version, as: UTF8.self).hasPrefix("RFB 003.008") else { throw VMError.protocolError("Unsupported local display protocol.") }
        try await socket.send(Data("RFB 003.008\n".utf8))
        let count = Int(try await socket.read(1)[0])
        guard count > 0, count <= 32 else { throw VMError.protocolError("QEMU rejected the local display connection.") }
        let security = try await socket.read(count)
        guard security.contains(1) else { throw VMError.protocolError("The private display requires unsupported authentication.") }
        try await socket.send(Data([1]))
        guard try await socket.read(4).u32(0) == 0 else { throw VMError.protocolError("Local display authentication failed.") }
        try await socket.send(Data([1]))
        let info = try await socket.read(24)
        try resize(width: Int(info.u16(0)), height: Int(info.u16(2)))
        let nameLength = Int(info.u32(20))
        guard nameLength <= 4096 else { throw VMError.protocolError("Invalid display name.") }
        _ = try await socket.read(nameLength)
        // Ask for 32-bit RGBx little-endian pixels and Raw + DesktopSize encodings.
        try await socket.send(Data([0,0,0,0, 32,24,0,1, 0,255,0,255,0,255, 0,8,16,0,0,0]))
        try await socket.send(Data([2,0,0,2, 0,0,0,0, 255,255,255,33])) // -223 DesktopSize
        try await requestUpdate(incremental: false)
        reader = Task { [weak self] in
            do { try await self?.readUpdates() }
            catch { if !Task.isCancelled { await self?.onError(error.localizedDescription) } }
        }
    }

    public func stop() async { reader?.cancel(); reader = nil; await socket.close() }

    private func readUpdates() async throws {
        while !Task.isCancelled {
            let type = try await socket.read(1)[0]
            switch type {
            case 0:
                let header = try await socket.read(3)
                let count = Int(header.u16(1))
                guard count <= 4096 else { throw VMError.protocolError("Too many display rectangles.") }
                var resized = false
                for _ in 0..<count {
                    let rectangle = try await socket.read(12)
                    let x = Int(rectangle.u16(0)), y = Int(rectangle.u16(2)), w = Int(rectangle.u16(4)), h = Int(rectangle.u16(6))
                    let encoding = Int32(bitPattern: rectangle.u32(8))
                    if encoding == -223 { try resize(width: w, height: h); resized = true }
                    else if encoding == 0 {
                        guard x + w <= width, y + h <= height else { throw VMError.protocolError("Display rectangle exceeds the framebuffer.") }
                        let data = try await socket.read(w * h * 4)
                        for row in 0..<h {
                            let target = ((y + row) * width + x) * 4
                            pixels.replaceSubrange(target..<(target + w * 4), with: data[(row * w * 4)..<((row + 1) * w * 4)])
                        }
                    } else { throw VMError.protocolError("Unsupported display encoding \(encoding).") }
                }
                await onFrame(VMFrame(width: width, height: height, pixels: pixels))
                // A resize invalidates every stored pixel. Incremental requests alone can leave
                // static dialogs missing from the framebuffer until they happen to repaint.
                try await requestUpdate(incremental: !resized)
            case 2: break // Bell
            case 3:
                let header = try await socket.read(7); let length = Int(header.u32(3))
                guard length <= 1024 * 1024 else { throw VMError.protocolError("Oversized guest clipboard message.") }
                _ = try await socket.read(length) // Clipboard stays opt-in, never forwarded automatically.
            default: throw VMError.protocolError("Unknown display message \(type).")
            }
        }
    }

    private func resize(width: Int, height: Int) throws {
        guard width > 0, height > 0, width <= 2048, height <= 1536 else { throw VMError.protocolError("Unsupported guest display dimensions.") }
        self.width = width; self.height = height; pixels = Data(repeating: 0, count: width * height * 4)
    }

    private func requestUpdate(incremental: Bool) async throws {
        var request = Data([3, incremental ? 1 : 0, 0,0,0,0]); request.appendBE(UInt16(width)); request.appendBE(UInt16(height))
        try await socket.send(request)
    }
}

extension Data {
    func u16(_ offset: Int) -> UInt16 { UInt16(self[startIndex + offset]) << 8 | UInt16(self[startIndex + offset + 1]) }
    func u32(_ offset: Int) -> UInt32 { UInt32(u16(offset)) << 16 | UInt32(u16(offset + 2)) }
    mutating func appendBE(_ value: UInt16) { append(UInt8(value >> 8)); append(UInt8(value & 255)) }
}
#endif
