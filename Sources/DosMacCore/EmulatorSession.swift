import Foundation

public enum SessionState: Equatable, Sendable {
    case idle, running(String), exited(Int32), failed(String)
}

/// Native process adapter for the first macOS milestone. iOS requires an embedded core.
@MainActor
public final class EmulatorSession {
    public private(set) var state: SessionState = .idle
    public var onStateChange: (@MainActor (SessionState) -> Void)?
    public private(set) var floppyDrive = FloppyDriveStatus()
    public var onFloppyChange: (@MainActor (FloppyDriveStatus) -> Void)?
    #if os(macOS)
    private var process: Process?
    private var logHandle: FileHandle?
    private var diskMonitor: Task<Void, Never>?
    private let diskShortcut: @MainActor (Int32) async throws -> Void
    #endif

    public init() {
        #if os(macOS)
        diskShortcut = { try await MacEmulatorControls.nextDisk(pid: $0) }
        #endif
    }

    #if os(macOS)
    init(diskShortcut: @escaping @MainActor (Int32) async throws -> Void) { self.diskShortcut = diskShortcut }
    #endif

    public var canControlDisks: Bool {
        #if os(macOS)
        MacEmulatorControls.isEnabled
        #else
        false
        #endif
    }

    public func requestDiskControlAccess() {
        #if os(macOS)
        MacEmulatorControls.requestAccess()
        #endif
    }

    public func showEmulator() {
        #if os(macOS)
        if let process { MacEmulatorControls.activate(pid: process.processIdentifier) }
        #endif
    }

    public func selectFloppy(number: Int) async throws {
        #if os(macOS)
        guard let task = process, task.isRunning, !floppyDrive.isChanging,
              floppyDrive.disks.contains(where: { $0.number == number }), floppyDrive.mountedNumber != nil else {
            throw DosMacError.diskControl("Wait for the emulator to confirm the mounted floppy disk.")
        }
        floppyDrive.isChanging = true
        floppyDrive.message = nil
        publishFloppy()
        defer { floppyDrive.isChanging = false; publishFloppy() }
        do {
            // Cycle and confirm each step rather than guessing that a posted key succeeded.
            for _ in 0..<floppyDrive.disks.count {
                guard process === task, task.isRunning, let current = floppyDrive.mountedNumber else { throw DosMacError.diskControl("The emulator session ended or its disk set changed.") }
                if current == number { return }
                let expected = current % floppyDrive.disks.count + 1
                try await diskShortcut(task.processIdentifier)
                let deadline = Date().addingTimeInterval(3)
                while floppyDrive.mountedNumber == current, Date() < deadline, task.isRunning {
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard floppyDrive.mountedNumber == expected else {
                    throw DosMacError.diskControl("DOSBox-X did not confirm the disk change. Bring the emulator forward and press F12 + O. Check Accessibility access if using the disk buttons.")
                }
            }
            throw DosMacError.diskControl("The requested floppy disk could not be selected.")
        } catch {
            floppyDrive.message = error.localizedDescription
            throw error
        }
        #else
        throw DosMacError.unsupportedPlatform
        #endif
    }

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
        let disks = try await library.floppyDisks(for: program)
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
                self.diskMonitor?.cancel()
                self.diskMonitor = nil
                self.floppyDrive = FloppyDriveStatus()
                self.publishFloppy()
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
        floppyDrive = FloppyDriveStatus()
        floppyDrive.disks = disks
        publishFloppy()
        if !disks.isEmpty { monitorDiskLog(log, process: task) }
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

    private func publishFloppy() { onFloppyChange?(floppyDrive) }

    #if os(macOS)
    private func monitorDiskLog(_ url: URL, process task: Process) {
        diskMonitor?.cancel()
        diskMonitor = Task { [weak self] in
            guard let reader = try? FileHandle(forReadingFrom: url) else { return }
            defer { try? reader.close() }
            var decoder = DiskLogDecoder()
            while !Task.isCancelled, task.isRunning {
                guard let self, self.process === task else { return }
                do {
                    let data = try reader.read(upToCount: 64 * 1024) ?? Data()
                    for report in decoder.append(data) {
                        if report.count == self.floppyDrive.disks.count {
                            self.floppyDrive.mountedNumber = report.number
                            self.floppyDrive.message = nil
                        } else {
                            self.floppyDrive.mountedNumber = nil
                            self.floppyDrive.message = "DOSBox-X mounted a different disk set. Disk selection is unavailable."
                        }
                        self.publishFloppy()
                    }
                    try await Task.sleep(for: .milliseconds(200))
                } catch { return }
            }
        }
    }
    #endif
}
