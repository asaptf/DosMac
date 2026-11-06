import Foundation

public enum MachineState: Equatable, Sendable {
    case stopped, starting, running(UUID), paused(UUID), failed(String)
}

#if os(macOS)
@MainActor
public final class MachineSession {
    public private(set) var state: MachineState = .stopped { didSet { onState?(state) } }
    public var onState: (@MainActor (MachineState) -> Void)?
    public var onFrame: (@MainActor (VMFrame) -> Void)?
    public var onDisplayError: (@MainActor (String) -> Void)?
    public var onAbsolutePointer: (@MainActor (Bool) -> Void)?
    public private(set) var absolutePointer = false
    public private(set) var guestDisplay: GuestDisplayBridge?
    public var onGuestDisplayChange: (() -> Void)?
    private var pointerMonitor: Task<Void, Never>?
    public private(set) var currentFloppy: UUID?
    public private(set) var currentCD: UUID?
    private var textDisplay = false
    private var latestFrame: VMFrame?
    private var process: Process?
    private var qmp: QMPConnection?
    private var display: RFBDisplay?
    private var runtime: URL?
    private var machine: Machine?
    private var directory: URL?
    private var log: FileHandle?
    private var sharing: SharedFolderServer?

    public init() { }
    public var isActive: Bool { process?.isRunning == true }

    public func start(_ machine: Machine, directory: URL, muted: Bool = false) async throws {
        guard !isActive, state != .starting else { throw VMError.invalid("Stop the active machine first.") }
        guard let engine = QEMUInstallation.find() else { throw VMError.engineMissing }
        try machine.validate()
        latestFrame = nil; textDisplay = false
        state = .starting
        do {
            if machine.sharedDisk == true { try await SharedStorage.prepareForGuest(in: directory) }
        } catch { state = .failed(error.localizedDescription); throw error }
        let runtime = FileManager.default.temporaryDirectory.appendingPathComponent("dm-\(UUID().uuidString.prefix(8))", isDirectory: true)
        do { try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        catch { state = .failed(error.localizedDescription); throw error }
        self.runtime = runtime; self.machine = machine; self.directory = directory
        if machine.sharedFolder == true {
            let server = SharedFolderServer()
            do {
                try await server.start(directory: directory, runtime: runtime); sharing = server
                let bridge = GuestDisplayBridge(sharedDirectory: directory.appendingPathComponent("Shared"))
                bridge.onChange = { [weak self] in self?.onGuestDisplayChange?() }
                try bridge.start(); bridge.setAutomatic(machine.automaticDisplay == true); guestDisplay = bridge
            }
            catch { await cleanup(); state = .failed(error.localizedDescription); throw error }
        }
        let input = Pipe(), output = Pipe()
        let task = Process(); task.executableURL = engine.executable
        do { task.arguments = try QEMUArguments.make(machine: machine, directory: directory, runtime: runtime, installation: engine, muted: muted, sharingPort: sharing?.port) }
        catch { await cleanup(); state = .failed(error.localizedDescription); throw error }
        task.currentDirectoryURL = directory
        let logURL = directory.appendingPathComponent("qemu.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        do { log = try FileHandle(forWritingTo: logURL) }
        catch { await cleanup(); state = .failed(error.localizedDescription); throw error }
        task.standardInput = input; task.standardOutput = output; task.standardError = log
        task.terminationHandler = { [weak self] task in
            let code = task.terminationStatus
            Task { @MainActor [weak self] in
                guard let self, self.process === task else { return }
                await self.cleanup()
                self.state = code == 0 ? .stopped : .failed("QEMU exited (\(code)). See this machine's qemu.log.")
            }
        }
        let connection = QMPConnection(input: input.fileHandleForWriting, output: output.fileHandleForReading)
        qmp = connection; process = task
        do {
            state = .starting
            try task.run()
            await connection.start(); try await connection.negotiate()
            if machine.boot == .floppy, let first = machine.floppies.first { try await insert(first, cdrom: false) }
            if machine.boot != .hardDisk, let first = machine.cdroms.first { try await insert(first, cdrom: true) }
            let socket = runtime.appendingPathComponent("display.sock")
            let viewer = try RFBDisplay(path: socket.path, onFrame: { [weak self] frame in await self?.receive(frame) }, onError: { [weak self] message in await self?.displayFailed(message) })
            display = viewer; try await viewer.start()
            _ = try await connection.execute("cont")
            state = .running(machine.id)
            pointerMonitor = Task { [weak self, connection] in
                while !Task.isCancelled {
                    do {
                        let absolute = GuestPointer.isAbsolute(try await connection.execute("query-mice"))
                        guard !Task.isCancelled, let self else { return }
                        if self.absolutePointer != absolute {
                            self.absolutePointer = absolute; self.onAbsolutePointer?(absolute)
                        }
                        try await Task.sleep(for: .milliseconds(500))
                    } catch { return }
                }
            }
        } catch {
            if task.isRunning { task.terminate() }
            let text = (try? String(contentsOf: logURL, encoding: .utf8)) ?? error.localizedDescription
            await cleanup(); state = .failed(error.localizedDescription)
            throw VMError.invalid("\(error.localizedDescription)\n\(text.suffix(2000))")
        }
    }

    public func insert(_ media: MachineMedia, cdrom: Bool) async throws {
        guard qmp != nil, let machine, let directory else { throw VMError.notRunning }
        let approved = cdrom ? machine.cdroms : machine.floppies
        guard approved.contains(media) else { throw VMError.invalid("This image does not belong to the active machine.") }
        try await changeMedium(device: cdrom ? "cdrom0" : "floppy0", file: directory.appendingPathComponent(media.relativePath), readOnly: cdrom)
        if cdrom { currentCD = media.id } else { currentFloppy = media.id }
    }

    public func eject(cdrom: Bool) async throws {
        guard let qmp else { throw VMError.notRunning }
        _ = try await qmp.execute("eject", arguments: ["device": .string(cdrom ? "cdrom0" : "floppy0"), "force": .bool(true)])
        if cdrom { currentCD = nil } else { currentFloppy = nil }
    }

    public func pause() async throws { guard let qmp, let machine else { throw VMError.notRunning }; _ = try await qmp.execute("stop"); state = .paused(machine.id) }
    public func resume() async throws { guard let qmp, let machine else { throw VMError.notRunning }; _ = try await qmp.execute("cont"); state = .running(machine.id) }
    public func reset() async throws { guard let qmp else { throw VMError.notRunning }; _ = try await qmp.execute("system_reset") }
    public func powerOff() async {
        if let display { await display.stop() }; display = nil
        if let qmp { _ = try? await qmp.execute("quit") }
        // QMP quit must be allowed to flush and close its block devices before fallback termination.
        for _ in 0..<40 {
            guard process != nil else { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
        if let process, process.isRunning { process.terminate() }
    }
    public func terminate() { if let process, process.isRunning { process.terminate() }; sharing?.stop(); sharing = nil }

    public func key(qcode: String, down: Bool) async throws {
        guard let qmp else { throw VMError.notRunning }
        _ = try await qmp.execute("input-send-event", arguments: ["events": .array([.object(["type": .string("key"), "data": .object(["down": .bool(down), "key": .object(["type": .string("qcode"), "data": .string(qcode)])])])])])
    }
    public func pointer(dx: Int, dy: Int, button: String? = nil, down: Bool = false) async throws {
        guard let qmp else { throw VMError.notRunning }
        var events: [JSONValue] = []
        if dx != 0 { events.append(.object(["type": .string("rel"), "data": .object(["axis": .string("x"), "value": .number(Double(dx))])])) }
        if dy != 0 { events.append(.object(["type": .string("rel"), "data": .object(["axis": .string("y"), "value": .number(Double(dy))])])) }
        if let button { events.append(.object(["type": .string("btn"), "data": .object(["button": .string(button), "down": .bool(down)])])) }
        if !events.isEmpty { _ = try await qmp.execute("input-send-event", arguments: ["events": .array(events)]) }
    }

    public func absolutePointer(x: Int, y: Int, button: String? = nil, down: Bool = false) async throws {
        guard let qmp, absolutePointer else { return }
        var events: [JSONValue] = [
            .object(["type": .string("abs"), "data": .object(["axis": .string("x"), "value": .number(Double(min(32767, max(0, x))))])]),
            .object(["type": .string("abs"), "data": .object(["axis": .string("y"), "value": .number(Double(min(32767, max(0, y))))])]),
        ]
        if let button { events.append(.object(["type": .string("btn"), "data": .object(["button": .string(button), "down": .bool(down)])])) }
        _ = try await qmp.execute("input-send-event", arguments: ["events": .array(events)])
    }

    public func queryStatus() async throws -> JSONValue { guard let qmp else { throw VMError.notRunning }; return try await qmp.execute("query-status") }
    public func tap(_ qcode: String) async throws {
        try await sendChord([qcode])
    }
    public func sendChord(_ qcodes: [String]) async throws {
        guard let qmp else { throw VMError.notRunning }
        guard !qcodes.isEmpty, qcodes.count <= 4 else { throw VMError.invalid("A guest key chord must contain one to four keys.") }
        _ = try await qmp.execute("send-key", arguments: ["keys": .array(qcodes.map { .object(["type": .string("qcode"), "data": .string($0)]) }), "hold-time": .number(50)])
        try await Task.sleep(for: .milliseconds(80))
    }
    public func typeText(_ text: String, paced: Bool = false) async throws {
        let strokes = try GuestTyping.strokes(for: text)
        for stroke in strokes {
            try Task.checkCancellation()
            let keys = stroke.shift ? ["shift", stroke.qcode] : [stroke.qcode]
            // Keep modifier and character in one QEMU send-key operation.
            // Mixing its delayed releases with separate input-send-event keys
            // can release Shift midway through punctuation such as a drive colon.
            try await sendChord(keys)
            if paced { try await Task.sleep(for: .milliseconds(90)) }
        }
    }
    public func mountSupportDisk(files: [String: Data]) async throws {
        guard qmp != nil, let runtime else { throw VMError.notRunning }
        // Keep the previous image intact until QEMU has switched media.
        let file = runtime.appendingPathComponent("support-\(UUID().uuidString).img")
        try FAT12Disk.make(files: files).write(to: file, options: .atomic)
        try await changeMedium(device: "floppy0", file: file, readOnly: false)
        currentFloppy = nil
    }
    private func changeMedium(device: String, file: URL, readOnly: Bool) async throws {
        guard let qmp else { throw VMError.notRunning }
        let blocks = try await qmp.execute("query-block")
        if blocks.array?.contains(where: { $0["device"]?.string == device && $0["inserted"] != nil }) == true {
            // Give legacy removable-media drivers an observable empty-drive
            // interval instead of replacing two images in a single operation.
            _ = try await qmp.execute("eject", arguments: ["device": .string(device), "force": .bool(true)])
            try await Task.sleep(for: .seconds(1))
        }
        _ = try await qmp.execute("blockdev-change-medium", arguments: ["device": .string(device), "filename": .string(file.path), "format": .string("raw"), "read-only-mode": .string(readOnly ? "read-only" : "retain"), "force": .bool(true)])
    }
    public func queryBlock() async throws -> JSONValue { guard let qmp else { throw VMError.notRunning }; return try await qmp.execute("query-block") }
    public func isAtDOSPrompt() async throws -> Bool {
        let screen = try await textScreen()
        let lastLine = screen.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty } ?? ""
        return textDisplay && lastLine.range(of: "^[A-Za-z]:\\\\[^<>]*>$", options: .regularExpression) != nil
    }
    public func waitForDOSPrompt(timeout: TimeInterval = 30) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, isActive {
            if try await isAtDOSPrompt() { return }
            try await Task.sleep(for: .milliseconds(300))
        }
        throw VMError.timeout("The guest DOS command prompt")
    }
    public func launchWindows(word: Bool = false) async throws {
        guard try await isAtDOSPrompt() else { throw VMError.invalid("Return to the DOS prompt before launching Windows or Word.") }
        try await typeText(word ? "C:\\WINDOWS\\WIN.COM C:\\WINWORD\\WINWORD.EXE /w\n" : "C:\\WINDOWS\\WIN.COM\n")
    }
    public func observeScreenText() async throws -> String {
        if textDisplay { return try await textScreen() }
        guard let latestFrame else { throw VMError.invalid("The guest display is not ready yet.") }
        return try await GuestScreenText.recognize(latestFrame)
    }
    public func frameSnapshot() -> VMFrame? { latestFrame }
    /// Runs a checked batch through the real guest DOS, with a fresh acknowledgement per operation.
    /// A source floppy can replace the support disk after the batch has reached C:.
    public func runDOSBatch(commands: [String], files: [String: Data] = [:], media: MachineMedia? = nil, timeout: TimeInterval = 60, completedDialog: String? = nil) async throws {
        guard try await isAtDOSPrompt() else {
            throw VMError.invalid("Return to the guest DOS command prompt before starting this installation stage.")
        }
        // The reference DOS loads SMARTDrive. Disable its removable/read-ahead caches before hot swaps.
        try await typeText("C:\\DOS\\SMARTDRV A- C-\n")
        try await Task.sleep(for: .milliseconds(300))
        let token = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))
        let ready = "DMREADY-" + token, done = "DMDONE-" + token, failed = "DMFAIL-" + token
        let runFile = "D" + token.prefix(7) + ".BAT", prepFile = "P" + token.prefix(7) + ".BAT"
        var payload = files
        // DOS internal COPY may preserve a previous ERRORLEVEL. FC provides a known zero baseline.
        payload[runFile] = Data((["@ECHO OFF", "C:\\DOS\\FC /B C:\\COMMAND.COM C:\\COMMAND.COM >NUL"] + commands + ["C:\\DOS\\SMARTDRV /C >NUL", "ECHO \(done)", "GOTO END", ":FAILED", "ECHO \(failed)", ":END"]).joined(separator: "\r\n").appending("\r\n").utf8)
        payload[prepFile] = Data("@ECHO OFF\r\nCOPY /Y A:\\\(runFile) C:\\\(runFile) >NUL\r\nIF NOT EXIST C:\\\(runFile) GOTO FAILED\r\nECHO \(ready)\r\nGOTO END\r\n:FAILED\r\nECHO \(failed)\r\n:END\r\n".utf8)
        try await mountSupportDisk(files: payload)
        try await typeText("A:\\\(prepFile)\n")
        try await waitForDOSMarker(ready, failure: failed, timeout: 30)
        if let media { try await insert(media, cdrom: false) }
        try await typeText("C:\\\(runFile)\n")
        try await waitForDOSMarker(done, failure: failed, timeout: timeout, completedDialog: completedDialog)
    }
    private func waitForDOSMarker(_ marker: String, failure: String, timeout: TimeInterval, completedDialog: String? = nil) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        var lastGraphicalObservation = Date.distantPast
        var acknowledgedCompletion = false
        var requestedWindowsExit = false, confirmedWindowsExit = false
        while Date() < deadline, isActive {
            try Task.checkCancellation()
            let screen = try await textScreen()
            if screen.contains(failure) { throw VMError.invalid("The guest DOS command failed. Review the guest screen before continuing.") }
            if screen.contains(marker) { return }
            if !textDisplay, Date().timeIntervalSince(lastGraphicalObservation) >= 3, let latestFrame {
                let observed = try await GuestScreenText.recognize(latestFrame)
                let normalized = observed.lowercased().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                if ["not completed successfully", "setup cannot", "setup error", "out of memory", "please insert"].contains(where: normalized.contains) {
                    throw VMError.invalid("The guest installer needs attention:\n\(observed.prefix(1200))")
                }
                if let completedDialog, !acknowledgedCompletion, normalized.contains(completedDialog), !normalized.contains("not completed") {
                    try await tap("ret")
                    acknowledgedCompletion = true
                }
                // WIN can retain Program Manager after Setup closes. Exit only this recognized,
                // successful installation session so DOS can execute the post-install checks.
                if acknowledgedCompletion, !requestedWindowsExit, normalized.contains("program manager") {
                    try await sendChord(["alt", "f4"])
                    requestedWindowsExit = true
                } else if requestedWindowsExit, !confirmedWindowsExit, normalized.contains("exit windows"), normalized.contains("windows session") {
                    try await tap("ret")
                    confirmedWindowsExit = true
                }
                lastGraphicalObservation = Date()
            }
            try await Task.sleep(for: .milliseconds(300))
        }
        throw VMError.timeout("Guest DOS command; review the guest screen before continuing")
    }
    public func textScreen() async throws -> String {
        guard let qmp, let runtime else { throw VMError.notRunning }
        let path = runtime.appendingPathComponent("text.bin")
        _ = try await qmp.execute("pmemsave", arguments: ["val": .number(0xb8000), "size": .number(4000), "filename": .string(path.path)])
        let bytes = try Data(contentsOf: path)
        return stride(from: 0, to: min(4000, bytes.count), by: 2).enumerated().map { index, offset in
            let byte = bytes[offset]
            let char = byte >= 32 && byte < 127 ? String(UnicodeScalar(byte)) : " "
            return char + (index % 80 == 79 ? "\n" : "")
        }.joined()
    }

    private func receive(_ frame: VMFrame) { latestFrame = frame; textDisplay = frame.width == 720 && frame.height == 400; onFrame?(frame) }
    private func displayFailed(_ message: String) async {
        // ACPI shutdown closes RFB before QEMU finishes flushing its disk.
        // Report a disconnect only if the same VM remains alive after that grace period.
        guard let source = process else { return }
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
        guard process === source, isActive else { return }
        onDisplayError?(message)
    }
    private func cleanup() async {
        guestDisplay?.stop(); guestDisplay = nil; onGuestDisplayChange?()
        pointerMonitor?.cancel(); pointerMonitor = nil
        absolutePointer = false; onAbsolutePointer?(false)
        sharing?.stop(); sharing = nil
        if let display { await display.stop() }; self.display = nil
        if let qmp { await qmp.close() }; self.qmp = nil
        try? log?.close(); log = nil
        if let runtime { try? FileManager.default.removeItem(at: runtime) }; runtime = nil
        process = nil; currentFloppy = nil; currentCD = nil
    }
}
#endif
