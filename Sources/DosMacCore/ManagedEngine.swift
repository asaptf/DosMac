import Foundation
import CryptoKit

public enum EngineInstallProgress: Equatable, Sendable {
    case downloading(Double?), verifying, installing

    public var message: String {
        switch self {
        case .downloading: "Downloading DOSBox-X…"
        case .verifying: "Verifying DOSBox-X…"
        case .installing: "Preparing DOSBox-X…"
        }
    }

    public var fraction: Double? {
        if case .downloading(let value) = self { return value }
        return nil
    }
}

#if os(macOS)
struct EngineRelease: Sendable {
    let version: String
    let architecture: String
    let url: URL
    let sha256: String

    static var current: EngineRelease {
        #if arch(arm64)
        let architecture = "arm64"
        let digest = "8514ab856e8ac2611fbdac7adf334c34085c1e00d700a88711f842adec50240f"
        #else
        let architecture = "x86_64"
        let digest = "a0605348355ff4a45c781f124c44122e97156ae3f7d048637f545c9de641bedb"
        #endif
        return EngineRelease(version: "2026.10.01", architecture: architecture,
            url: URL(string: "https://github.com/joncampbell123/dosbox-x/releases/download/dosbox-x-v2026.10.01/dosbox-x-macosx-\(architecture)-2026.10.01.zip")!, sha256: digest)
    }

    var directoryName: String { "dosbox-x-\(version)-\(architecture)" }
}

private struct EngineReceipt: Codable, Equatable {
    let version: String
    let architecture: String
    let sha256: String
    init(_ release: EngineRelease) {
        version = release.version
        architecture = release.architecture
        sha256 = release.sha256
    }
}

/// Installs a pinned official SDL2 app privately. Never alters system security settings.
public actor ManagedEngine {
    public typealias ProgressHandler = @Sendable (EngineInstallProgress) async -> Void
    private let root: URL
    private var installation: Task<URL, Error>?

    public static var defaultRoot: URL { LibraryStore.defaultRoot.appendingPathComponent("Engines", isDirectory: true) }

    public init(root: URL = ManagedEngine.defaultRoot) { self.root = root }

    public nonisolated static func cachedExecutable(root: URL = defaultRoot) -> URL? {
        cachedExecutable(root: root, release: .current)
    }

    static func cachedExecutable(root: URL, release: EngineRelease) -> URL? {
        let folder = root.appendingPathComponent(release.directoryName)
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("receipt.json")),
              let receipt = try? JSONDecoder().decode(EngineReceipt.self, from: data), receipt == EngineReceipt(release) else { return nil }
        let executable = folder.appendingPathComponent("dosbox-x-sdl2/dosbox-x.app/Contents/MacOS/dosbox-x")
        guard FileManager.default.isExecutableFile(atPath: executable.path),
              (try? executable.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
        return executable
    }

    public func ensureInstalled(progress: @escaping ProgressHandler) async throws -> URL {
        if let cached = Self.cachedExecutable(root: root) { return cached }
        if let installation { return try await installation.value }
        let root = root
        let task = Task { try await Self.downloadAndInstall(root: root, progress: progress) }
        installation = task
        defer { installation = nil }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
    }

    private static func downloadAndInstall(root: URL, progress: @escaping ProgressHandler) async throws -> URL {
        let release = EngineRelease.current
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        let observer = EngineDownloadObserver(progress: progress)
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        await progress(.downloading(nil))
        let (archive, response) = try await session.download(from: release.url, delegate: observer)
        defer { try? FileManager.default.removeItem(at: archive) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw DosMacError.engineInstallation("The DOSBox-X download failed. Check your connection and try Launch again.")
        }
        try Task.checkCancellation()
        await progress(.verifying)
        return try await installArchive(at: archive, release: release, root: root, progress: progress)
    }

    /// Testable local half of the same verified, transactional installation path.
    static func installArchive(at archive: URL, release: EngineRelease, root: URL, progress: ProgressHandler) async throws -> URL {
        let fm = FileManager.default
        guard try sha256(of: archive) == release.sha256 else {
            throw DosMacError.engineInstallation("The DOSBox-X checksum did not match. Nothing was installed. Try again.")
        }
        try Task.checkCancellation()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent(".install-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        await progress(.installing)
        try Task.checkCancellation()
        // Only archives matching a source-pinned digest reach the system extractor.
        let extractor = Process()
        extractor.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        extractor.arguments = ["-x", "-k", archive.path, staging.path]
        extractor.standardOutput = FileHandle.nullDevice
        extractor.standardError = FileHandle.nullDevice
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                extractor.terminationHandler = { process in
                    if process.terminationStatus == 0 { continuation.resume() }
                    else { continuation.resume(throwing: DosMacError.engineInstallation("Could not unpack DOSBox-X. Try Launch again.")) }
                }
                do { try extractor.run() }
                catch { continuation.resume(throwing: error) }
            }
        } onCancel: {
            if extractor.isRunning { extractor.terminate() }
        }
        try Task.checkCancellation()
        let executable = staging.appendingPathComponent("dosbox-x-sdl2/dosbox-x.app/Contents/MacOS/dosbox-x")
        guard fm.isExecutableFile(atPath: executable.path),
              (try? executable.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              fm.fileExists(atPath: staging.appendingPathComponent("dosbox-x-sdl2/COPYING.txt").path) else {
            throw DosMacError.engineInstallation("The DOSBox-X package is incomplete. Nothing was installed.")
        }
        try JSONEncoder().encode(EngineReceipt(release)).write(to: staging.appendingPathComponent("receipt.json"), options: .atomic)
        let destination = root.appendingPathComponent(release.directoryName)
        if let cached = cachedExecutable(root: root, release: release) { return cached }
        // Preserve a damaged prior installation until a replacement has been verified.
        let backup = root.appendingPathComponent(".previous-\(UUID().uuidString)")
        if fm.fileExists(atPath: destination.path) { try fm.moveItem(at: destination, to: backup) }
        do { try fm.moveItem(at: staging, to: destination) }
        catch {
            if fm.fileExists(atPath: backup.path) { try? fm.moveItem(at: backup, to: destination) }
            throw error
        }
        try? fm.removeItem(at: backup)
        guard let installed = cachedExecutable(root: root, release: release) else { throw DosMacError.engineInstallation("DOSBox-X installation could not be verified.") }
        return installed
    }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private final class EngineDownloadObserver: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: ManagedEngine.ProgressHandler
    init(progress: @escaping ManagedEngine.ProgressHandler) { self.progress = progress }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) { }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesWritten <= 128 * 1024 * 1024, totalBytesExpectedToWrite <= 128 * 1024 * 1024 else {
            downloadTask.cancel()
            return
        }
        let fraction = totalBytesExpectedToWrite > 0 ? min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) : nil
        Task { await progress(.downloading(fraction)) }
    }
}
#endif
