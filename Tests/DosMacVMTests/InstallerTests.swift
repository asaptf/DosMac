import Foundation
import Testing
import DosMacCore
@testable import DosMacVM
#if os(macOS)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#endif

struct InstallerTests {
    @Test func supportDiskRoundTripsFilesAcrossClusterBoundaries() throws {
        let files = ["SETUP.SHH": Data("[windir]\r\nC:\\WINDOWS\r\n".utf8), "LARGE.DAT": Data((0..<4000).map { UInt8($0 % 251) }), "EMPTY.TXT": Data()]
        let disk = try FAT12Disk(data: FAT12Disk.make(files: files))
        #expect(Set(disk.fileNames) == Set(files.keys))
        for (name, data) in files { #expect(try disk.file(name) == data) }
        #expect(throws: (any Error).self) { try FAT12Disk.make(files: ["../BAD.TXT": Data()]) }
    }

    @Test func recipeWaitsAtUnknownPromptsAndLicenseReview() {
        #expect(DOS622Rules.action(screen: "Unknown error, press any key", rebooted: false) == .wait)
        #expect(DOS622Rules.action(screen: "Welcome to Setup. Press ENTER", rebooted: false) == .enter)
        if case .review = DOS622Rules.action(screen: "License Agreement", rebooted: false) { } else { Issue.record("License prompt was not gated") }
        #expect(DOS622Rules.action(screen: "Insert Setup Disk #2 and press ENTER", rebooted: false) == .disk(2))
        #expect(DOS622Rules.action(screen: "Increase your hard disk space with DriveSpace. MS-DOS 6.22. Please insert Setup Disk #2", rebooted: false) == .disk(2))
        #expect(DOS622Rules.action(screen: "Remove disks from all floppy disk drives, and then press ENTER.", rebooted: false) == .finish)
    }

    @Test func guestTypingValidatesWholeCommandBeforeSending() throws {
        let strokes = try GuestTyping.strokes(for: "C:\\SETUP /H:C:\\SETUP.SHH\n")
        #expect(strokes.last?.qcode == "ret")
        #expect(strokes.contains { $0.qcode == "semicolon" && $0.shift })
        #expect(throws: (any Error).self) { try GuestTyping.strokes(for: "unsupported 🐈") }
    }

    @Test func exchangeDiskExportsWithoutReplacingHostFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MachineStore(root: root.appendingPathComponent("Machines"))
        let machine = Machine(name: "Exchange verification", guest: .msdos622)
        try FileManager.default.createDirectory(at: store.directory(for: machine.id).appendingPathComponent("Media"), withIntermediateDirectories: true)
        try await store.save(machine)
        let source = root.appendingPathComponent("LETTER.DOC"), content = Data("Original host document".utf8)
        try content.write(to: source)
        let updated = try await store.createExchangeDisk(files: [source], into: machine)
        let media = try #require(updated.floppies.first)
        let exported = try await store.exportExchangeDisk(media, from: updated, to: root)
        #expect(try Data(contentsOf: exported.appendingPathComponent("LETTER.DOC")) == content)
        #expect(try Data(contentsOf: source) == content)
        let link = root.appendingPathComponent("LINK.DOC")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        await #expect(throws: (any Error).self) { try await store.createExchangeDisk(files: [link], into: updated) }
    }

    #if os(macOS)
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DOSMAC_TEST_WORD_WORKFLOW_MACHINE"] != nil))
    @MainActor func launchesWordSavesDocumentAndExportsIt() async throws {
        let file = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DOSMAC_TEST_WORD_WORKFLOW_MACHINE"]!)
        var machine = try JSONDecoder().decode(Machine.self, from: Data(contentsOf: file))
        let store = try MachineStore(root: file.deletingLastPathComponent().deletingLastPathComponent())
        machine.boot = .hardDisk
        machine = try await store.createExchangeDisk(files: [], into: machine)
        let exchange = try #require(machine.floppies.last)
        let session = MachineSession()
        session.onDisplayError = { Issue.record("Guest display: \($0)") }
        try await session.start(machine, directory: store.directory(for: machine.id), muted: true)
        defer { session.terminate() }
        try await session.waitForDOSPrompt()
        try await session.insert(exchange, cdrom: false)
        try await session.launchWindows(word: true)
        try await waitForGuestText("table", session: session)
        try await session.typeText("DosMac end-to-end document.\n")
        try await session.tap("f12")
        try await waitForGuestText("save as", session: session)
        try await session.tap("home"); try await session.sendChord(["shift", "end"])
        try await session.typeText("A:\\DOSMAC.DOC\n")
        try await waitForGuestText("table", excluding: "save as", session: session)
        try await waitForGuestText("dosmac.doc", excluding: "saving", session: session)
        let frame = try #require(session.frameSnapshot())
        let provider = try #require(CGDataProvider(data: frame.pixels as CFData))
        let image = try #require(CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: frame.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue).union(.byteOrder32Big), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let snapshot = file.deletingLastPathComponent().appendingPathComponent("word-workflow.png")
        let writer = try #require(CGImageDestinationCreateWithURL(snapshot as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, image, nil)
        #expect(CGImageDestinationFinalize(writer))
        try await session.sendChord(["alt", "f4"])
        do { try await session.waitForDOSPrompt(timeout: 2) }
        catch {
            try await waitForGuestText("program manager", session: session)
            try await session.sendChord(["alt", "f4"])
            try await waitForGuestText("exit windows", session: session)
            try await session.tap("ret")
            try await session.waitForDOSPrompt()
        }
        try await session.typeText("C:\\DOS\\SMARTDRV /C\n")
        try await session.waitForDOSPrompt()
        try await session.eject(cdrom: false)
        await session.powerOff()
        let output = try await store.exportExchangeDisk(exchange, from: machine, to: file.deletingLastPathComponent())
        let document = try Data(contentsOf: output.appendingPathComponent("DOSMAC.DOC"))
        #expect(document.prefix(4) == Data([0xd0, 0xcf, 0x11, 0xe0]))
        #expect(document.range(of: Data("DosMac end-to-end document.".utf8)) != nil)
        print("Verified Word document: \(output.appendingPathComponent("DOSMAC.DOC").path)")
    }

    @MainActor private func waitForGuestText(_ text: String, excluding: String? = nil, session: MachineSession) async throws {
        let deadline = Date().addingTimeInterval(45)
        var observed = ""
        while Date() < deadline {
            observed = try await session.observeScreenText()
            let normalized = observed.lowercased().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            if normalized.contains(text), excluding.map({ !normalized.contains($0) }) ?? true { return }
            try await Task.sleep(for: .seconds(1))
        }
        throw VMError.invalid("Expected guest text '\(text)'; observed:\n\(observed)")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DOSMAC_TEST_STACK_SETUP"] == "1"))
    @MainActor func actualReferenceStackInstallation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DosMacStack-\(UUID().uuidString)")
        print("Stack verification directory: \(root.path)")
        let store = try MachineStore(root: root)
        var machine = try await store.create(name: "Reference stack verification", guest: .windows31)
        if let sourcePath = ProcessInfo.processInfo.environment["DOSMAC_TEST_SOURCE_MACHINE"] {
            let file = URL(fileURLWithPath: sourcePath)
            let source = try JSONDecoder().decode(Machine.self, from: Data(contentsOf: file))
            try source.validate()
            for purpose in [MediaPurpose.dosSetup, .windowsSetup, .wordSetup] {
                let media = source.floppies.filter { $0.purpose == purpose }
                machine = try await store.importMedia(media.map { file.deletingLastPathComponent().appendingPathComponent($0.relativePath) }, into: machine, cdrom: false, purpose: purpose, names: media.map(\.name))
            }
        } else {
            let service = SoftwareSources()
            for (purpose, address) in [(MediaPurpose.dosSetup, "https://winworldpc.com/download/c38fc38d-68c2-bbe2-80a6-4b11c3a4c2ac"), (.windowsSetup, "https://winworldpc.com/download/41574932-18c3-9a11-c3a4-e284a2c3a570"), (.wordSetup, "https://winworldpc.com/download/57ce7cd2-479c-11ee-b57b-0200008a0da4")] {
                let releases = try await service.inspect(URL(string: address)!)
                let prepared = try await service.prepare(try #require(releases.first))
                machine = try await store.importMedia(prepared.floppyDisks.map { prepared.package.appendingPathComponent("payload").appendingPathComponent($0.imagePath) }, into: machine, cdrom: false, purpose: purpose, names: prepared.floppyDisks.map(\.label))
                await service.discard(prepared)
            }
        }
        try await store.save(machine)
        let session = MachineSession()
        session.onDisplayError = { Issue.record("Guest display: \($0)") }
        try await session.start(machine, directory: store.directory(for: machine.id), muted: true)
        defer { session.terminate() }
        let dos = try await DOS622Installer(session: session, disks: machine.floppies.filter { $0.purpose == .dosSetup }).run { message, _ in print(message) }
        try #require(dos)
        do {
            let windows = try await Windows31Installer(session: session, disks: machine.floppies.filter { $0.purpose == .windowsSetup }).run { message, _ in print(message) }
            #expect(windows)
            let word = try await Word6Installer(session: session, disks: machine.floppies.filter { $0.purpose == .wordSetup }).run { message, _ in print(message) }
            #expect(word)
        } catch { print("Stack guest screen: \(try await session.textScreen())"); throw error }
        await session.powerOff()
        machine.boot = .hardDisk
        try await session.start(machine, directory: store.directory(for: machine.id), muted: true)
        try await session.waitForDOSPrompt()
        try await session.runDOSBatch(commands: ["IF NOT EXIST C:\\WINDOWS\\WIN.COM GOTO FAILED", "IF NOT EXIST C:\\WINWORD\\WINWORD.EXE GOTO FAILED"])
        await session.powerOff()
        if ProcessInfo.processInfo.environment["DOSMAC_TEST_KEEP_STACK"] != "1" { try FileManager.default.removeItem(at: root) }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DOSMAC_TEST_WORD_MEDIA"] == "1"))
    func verifiesWord6ReferenceMedia() async throws {
        let service = SoftwareSources()
        let releases = try await service.inspect(URL(string: "https://winworldpc.com/download/57ce7cd2-479c-11ee-b57b-0200008a0da4")!)
        let release = try #require(releases.first)
        #expect(release.sha1?.count == 40)
        let prepared = try await service.prepare(release)
        #expect(prepared.floppyDisks.count >= 3)
        let first = try #require(prepared.floppyDisks.first)
        let disk = try FAT12Disk(data: Data(contentsOf: prepared.package.appendingPathComponent("payload").appendingPathComponent(first.imagePath)))
        #expect(disk.fileNames.contains("SETUP.EXE"))
        await service.discard(prepared)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DOSMAC_TEST_WINDOWS_MEDIA"] == "1"))
    func inspectWindowsBatchSetupSchema() async throws {
        let service = SoftwareSources()
        let releases = try await service.inspect(URL(string: "https://winworldpc.com/download/41574932-18c3-9a11-c3a4-e284a2c3a570")!)
        let prepared = try await service.prepare(try #require(releases.first))
        let disk = try #require(prepared.floppyDisks.first)
        let image = try FAT12Disk(data: Data(contentsOf: prepared.package.appendingPathComponent("payload").appendingPathComponent(disk.imagePath)))
        let script = try #require(try image.file("SETUP.SHH"))
        let schema = String(decoding: script, as: UTF8.self)
        #expect(schema.contains("[sysinfo]"))
        #expect(schema.contains("[userinfo]"))
        #expect(schema.contains("[endinstall]"))
        await service.discard(prepared)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DOSMAC_TEST_DOS_SETUP"] == "1"))
    @MainActor func actualDOS622InstallationRecipe() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DosMacDOS622-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let service = SoftwareSources()
        let releases = try await service.inspect(URL(string: "https://winworldpc.com/download/c38fc38d-68c2-bbe2-80a6-4b11c3a4c2ac")!)
        let release = try #require(releases.first)
        let prepared = try await service.prepare(release)
        let disks = prepared.floppyDisks
        let store = try MachineStore(root: root)
        var machine = try await store.create(name: "DOS 6.22 recipe verification", guest: .msdos622)
        machine = try await store.importMedia(disks.map { prepared.package.appendingPathComponent("payload").appendingPathComponent($0.imagePath) }, into: machine, cdrom: false, purpose: .dosSetup, names: disks.map(\.label))
        await service.discard(prepared)
        let session = MachineSession()
        try await session.start(machine, directory: store.directory(for: machine.id), muted: true)
        defer { session.terminate() }
        let installer = DOS622Installer(session: session, disks: machine.floppies)
        let success = try await installer.run { message, attention in print("DOS recipe: \(message) attention=\(attention)") }
        let screen = try await session.textScreen()
        #expect(success, Comment(rawValue: screen))
        await session.powerOff()
    }
    #endif
}
