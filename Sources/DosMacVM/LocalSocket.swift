#if os(macOS)
import Foundation
import Darwin

actor LocalSocket {
    private let handle: FileHandle
    private var buffer = Data()
    private var waiter: (Int, CheckedContinuation<Data, Error>)?
    private var closed = false
    private var reader: Task<Void, Never>?
    private var ingress: AsyncStream<Data>.Continuation?

    init(path: String) throws {
        var address = sockaddr_un()
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else { throw VMError.invalid("The local display socket path is too long.") }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw VMError.protocolError("Could not create a local display connection.") }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { target in
                _ = memcpy(UnsafeMutableRawPointer(target), source, path.utf8.count + 1)
            }
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else { Darwin.close(fd); throw VMError.protocolError("The local display is not ready.") }
        var noSignal: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    func start() {
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        ingress = continuation
        handle.readabilityHandler = { handle in continuation.yield(handle.availableData) }
        // One consumer preserves byte order. Separate Tasks per read can reach an actor out of order.
        reader = Task { [weak self] in for await data in stream { await self?.receive(data) } }
    }

    func read(_ count: Int) async throws -> Data {
        guard count >= 0, count <= 32 * 1024 * 1024 else { throw VMError.protocolError("Invalid display message size.") }
        guard !closed else { throw VMError.notRunning }
        if buffer.count >= count { return consume(count) }
        guard waiter == nil else { throw VMError.protocolError("Concurrent display reads are not allowed.") }
        return try await withCheckedThrowingContinuation { waiter = (count, $0) }
    }

    func send(_ data: Data) throws { guard !closed else { throw VMError.notRunning }; try handle.write(contentsOf: data) }

    func close() {
        guard !closed else { return }; closed = true
        handle.readabilityHandler = nil
        ingress?.finish(); ingress = nil; reader?.cancel(); reader = nil
        try? handle.close()
        waiter?.1.resume(throwing: VMError.notRunning); waiter = nil
    }

    private func consume(_ count: Int) -> Data { let data = Data(buffer.prefix(count)); buffer.removeFirst(count); return data }
    private func receive(_ data: Data) {
        guard !closed else { return }
        if data.isEmpty { close(); return }
        buffer.append(data)
        if buffer.count > 32 * 1024 * 1024 { close(); return }
        if let (count, continuation) = waiter, buffer.count >= count { waiter = nil; continuation.resume(returning: consume(count)) }
    }
}
#endif
