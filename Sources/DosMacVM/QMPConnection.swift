#if os(macOS)
import Foundation

/// Correlated JSON-RPC-like QMP transport over owned process pipes, not a public port.
public actor QMPConnection {
    private let input: FileHandle
    private let output: FileHandle
    private var pending: [String: CheckedContinuation<JSONValue, Error>] = [:]
    private var buffer = Data()
    private var closed = false
    private var greeted = false
    private var reader: Task<Void, Never>?
    private var ingress: AsyncStream<Data>.Continuation?
    public var onEvent: (@Sendable (JSONValue) -> Void)?

    public init(input: FileHandle, output: FileHandle) { self.input = input; self.output = output }

    public func start() {
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        ingress = continuation
        output.readabilityHandler = { handle in continuation.yield(handle.availableData) }
        reader = Task { [weak self] in for await data in stream { await self?.receive(data) } }
    }

    public func negotiate() async throws {
        let deadline = Date().addingTimeInterval(5)
        while !greeted, !closed, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        guard greeted, !closed else { throw VMError.protocolError("QEMU did not send its QMP greeting.") }
        _ = try await execute("qmp_capabilities")
    }

    public func execute(_ command: String, arguments: [String: JSONValue] = [:], timeout: Double = 5) async throws -> JSONValue {
        guard !closed else { throw VMError.notRunning }
        try Task.checkCancellation()
        let id = UUID().uuidString
        let message = JSONValue.object(["execute": .string(command), "arguments": .object(arguments), "id": .string(id)])
        var data = try JSONEncoder().encode(message); data.append(contentsOf: [13, 10])
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                do { try input.write(contentsOf: data) }
                catch { pending.removeValue(forKey: id)?.resume(throwing: error); return }
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(timeout))
                    await self?.expire(id: id, command: command)
                }
            }
        } onCancel: { Task { await self.expire(id: id, command: command, cancelled: true) } }
    }

    public func close() {
        guard !closed else { return }; closed = true
        output.readabilityHandler = nil
        ingress?.finish(); ingress = nil; reader?.cancel(); reader = nil
        try? input.close(); try? output.close()
        for continuation in pending.values { continuation.resume(throwing: VMError.notRunning) }
        pending.removeAll()
    }

    private func expire(id: String, command: String, cancelled: Bool = false) {
        pending.removeValue(forKey: id)?.resume(throwing: cancelled ? CancellationError() : VMError.timeout(command))
    }

    private func receive(_ data: Data) {
        guard !closed else { return }
        if data.isEmpty { close(); return }
        buffer.append(data)
        guard buffer.count <= 4 * 1024 * 1024 else { close(); return }
        while let end = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
            guard let value = try? JSONDecoder().decode(JSONValue.self, from: line) else { continue }
            if value["QMP"] != nil { greeted = true }
            else if let id = value["id"]?.string, let continuation = pending.removeValue(forKey: id) {
                if let error = value["error"] { continuation.resume(throwing: VMError.protocolError(error["desc"]?.string ?? "QMP command failed.")) }
                else { continuation.resume(returning: value["return"] ?? .null) }
            } else if value["event"] != nil { onEvent?(value) }
        }
    }
}
#endif
