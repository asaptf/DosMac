import Foundation

public enum SessionState: Equatable, Sendable {
    case idle, running(String), exited(Int32), failed(String)
}

/// Native process adapter for the first macOS milestone. iOS requires an embedded core.
@MainActor
public final class EmulatorSession {
    public private(set) var state: SessionState = .idle
    public var onStateChange: (@MainActor (SessionState) -> Void)?
    #if os(macOS)
    private var process: Process?
    private var logHandle: FileHandle?
    #endif

    public init() {}

    public static func findEngine(customPath: String? = nil) -> URL? {
        #if os(macOS)
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Emulator/dosbox-x.app/Contents/MacOS/dosbox-x").path
        let candidates = [customPath, ProcessInfo.processInfo.environment["DOSMAC_ENGINE_PATH"], bundled, ManagedEngine.cachedExecutable()?.path, "/Applications/dosbox-x.app/Contents/MacOS/dosbox-x", "/Applications/DOSBox-X.app/Contents/MacOS/dosbox-x", "/opt/homebrew/bin/dosbox-x", "/usr/local/bin/dosbox-x"].compactMap { $0 }
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
        #else
        return nil
        #endif
    }

    public func start(program: InstalledProgram, library: LibraryStore, engine: URL?) async throws {
        if case .running = state { throw DosMacError.sessionActive }
        #if os(macOS)
        guard let engine else { throw DosMacError.engineMissing }
        let folder = library.programURL(program.id)
        let config = try DOSBoxConfiguration.render(program: program, driveC: folder.appendingPathComponent("DriveC"), exchange: library.exchangeURL)
        let configURL = folder.appendingPathComponent("session.conf")
        try config.write(to: configURL, atomically: true, encoding: .utf8)
        let log = folder.appendingPathComponent("session.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        let task = Process()
        task.executableURL = engine
        task.arguments = ["-defaultconf", "-conf", configURL.path]
        task.currentDirectoryURL = folder
        task.standardOutput = handle
        task.standardError = handle
        task.terminationHandler = { [weak self] task in
            let status = task.terminationStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? self.logHandle?.close()
                self.logHandle = nil
                self.process = nil
                self.update(.exited(status))
            }
        }
        do { try task.run() } catch {
            try? handle.close()
            update(.failed(error.localizedDescription))
            throw error
        }
        process = task
        logHandle = handle
        update(.running(program.id))
        do { try await library.recordLaunch(program) }
        catch {
            task.terminate()
            throw error
        }
        #else
        throw DosMacError.unsupportedPlatform
        #endif
    }

    public func stop() {
        #if os(macOS)
        process?.terminate()
        #endif
    }

    private func update(_ next: SessionState) {
        state = next
        onStateChange?(next)
    }
}
