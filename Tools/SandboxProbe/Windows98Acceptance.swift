import Foundation
import AppKit
import DosMacVM

@MainActor enum Windows98Acceptance {
    static func run(root: URL, session: MachineSession, fixture: URL) async throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: fixture.path) else { throw VMError.invalid("Provision a private licensed Windows 98 fixture with the host harness") }
        let store = try MachineStore(root: root.appendingPathComponent("Machines"))
        var machine = try await store.create(name: "Private sandbox Windows acceptance", guest: .windows98)
        let directory = store.directory(for: machine.id)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("disk.qcow2"))
        try FileManager.default.copyItem(at: fixture, to: directory.appendingPathComponent("disk.qcow2"))
        machine.boot = .hardDisk; machine.sharedDisk = true; machine.sharedFolder = true
        machine.installation = InstallationRecord(recipeID: Windows9xRecipe.id(for: .windows98), stage: .complete)
        let resources = Bundle.main.resourceURL!
        func asset(_ name: String) throws -> Data { try Data(contentsOf: resources.appendingPathComponent(name)) }
        let files = GuestToolsMedia.mouseFiles(driver: try asset("qemouse.drv"), inf: try asset("qemouse.inf"), agent: try asset("dmagent.exe"))
        try await session.start(machine, directory: directory, muted: true)
        try await GuestToolsInstaller(session: session).installMouse(files: files) { log($0) }
        guard session.absolutePointer, let bridge = session.guestDisplay, bridge.ready else { throw VMError.invalid("Guest Tools did not connect inside the sandbox") }
        bridge.request(GuestDisplaySize(800,600))
        let resizeDeadline = Date().addingTimeInterval(20)
        while Date() < resizeDeadline, bridge.current != GuestDisplaySize(800,600) || session.frameSnapshot()?.width != 800 {
            try await Task.sleep(for: .milliseconds(250))
        }
        guard bridge.current == GuestDisplaySize(800,600), session.frameSnapshot()?.width == 800, session.frameSnapshot()?.height == 600 else { throw VMError.invalid("Actual guest resolution change failed") }
        let shared = directory.appendingPathComponent("Shared/DMTOOLS")
        let data = Data((0..<(3*1024*1024)).map { UInt8(truncatingIfNeeded: $0*17+43) })
        try data.write(to: shared.appendingPathComponent("HOST.BIN"))
        log("Guest Tools and 800 x 600 display confirmed. Starting the guest file-copy test.")
        let batch = """
        @ECHO OFF
        ECHO DOSMAC COPY START >H:\\DMTOOLS\\STATUS.TXT
        COPY /B H:\\DMTOOLS\\HOST.BIN C:\\DMTOOLS\\QA-ROUND.BIN >>H:\\DMTOOLS\\STATUS.TXT
        IF ERRORLEVEL 1 GOTO FAILED
        ECHO DOSMAC HOST READ COMPLETE >>H:\\DMTOOLS\\STATUS.TXT
        COPY /B C:\\DMTOOLS\\QA-ROUND.BIN H:\\DMTOOLS\\GUEST.BIN >>H:\\DMTOOLS\\STATUS.TXT
        IF ERRORLEVEL 1 GOTO FAILED
        ECHO DOSMAC COPY END >>H:\\DMTOOLS\\STATUS.TXT
        ECHO DOSMAC SANDBOX COPY COMPLETE
        PAUSE >NUL
        EXIT
        :FAILED
        ECHO DOSMAC COPY FAILED >>H:\\DMTOOLS\\STATUS.TXT
        ECHO DOSMAC SANDBOX COPY FAILED
        PAUSE >NUL
        EXIT
        """.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n"
        // Exercise the live-share path independently of removable media.
        // A separate acceptance case must cover the second floppy swap.
        try Data(batch.utf8).write(to: shared.appendingPathComponent("SHARE.BAT"))
        try await run("C:\\COMMAND.COM /C H:\\DMTOOLS\\SHARE.BAT", session: session)
        let copyDeadline = Date().addingTimeInterval(60)
        let returned = shared.appendingPathComponent("GUEST.BIN")
        var matched = false
        while Date() < copyDeadline {
            if let actual = try? Data(contentsOf: returned), actual == data { matched = true; break }
            try await Task.sleep(for: .milliseconds(500))
        }
        if !matched {
            if let text = try? String(contentsOf: shared.appendingPathComponent("STATUS.TXT"), encoding: .ascii) {
                log("Generated copy-batch status: " + String(text.prefix(1500)))
            }
            if let frame = session.frameSnapshot(), let provider = CGDataProvider(data: frame.pixels as CFData),
               let image = CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: frame.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue).union(.byteOrder32Big), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
               let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                log("PRIVATE_ACCEPTANCE_FRAME:" + png.base64EncodedString())
            }
            let screen = try await session.observeScreenText().lowercased().filter { $0.isLetter }
            let known = ["badcommandorfilename","filenotfound","invaliddrivespecification","accessdenied","notreadyreadingdrive","outofdiskspace","dosmacsandboxcopyfailed","dosmacsandboxcopycomplete","typethenameofaprogram"].filter { screen.contains($0) }
            log("Known copy-screen markers: " + known.joined(separator: ", "))
            throw VMError.invalid("Guest C: file-copy round trip failed")
        }
        log("Three MiB copied through guest C: and matched byte for byte.")
        try await session.tap("ret")
        try await Task.sleep(for: .seconds(1))
        if CommandLine.arguments.contains("--check-floppy-swap") {
            log("Checking the production support-floppy replacement path…")
            let marker = Data("Original DosMac second-floppy acceptance marker.\r\n".utf8)
            try await session.mountSupportDisk(files: ["SECOND.TXT": marker])
            let script = "@ECHO OFF\r\nCOPY /B A:\\SECOND.TXT H:\\DMTOOLS\\SECOND.OUT\r\nPAUSE >NUL\r\nEXIT\r\n"
            try Data(script.utf8).write(to: shared.appendingPathComponent("FLOPPY.BAT"))
            try await run("C:\\COMMAND.COM /C H:\\DMTOOLS\\FLOPPY.BAT", session: session)
            let deadline = Date().addingTimeInterval(20)
            var copied = false
            while Date() < deadline {
                if (try? Data(contentsOf: shared.appendingPathComponent("SECOND.OUT"))) == marker { copied = true; break }
                try await Task.sleep(for: .milliseconds(500))
            }
            guard copied else { throw VMError.invalid("The replacement support floppy was not readable") }
            try await session.tap("ret")
            log("The replacement support floppy was readable.")
        }
        var shutdown = false
        for _ in 0..<3 {
            try await session.sendChord(["ctrl","esc"])
            try await Task.sleep(for: .milliseconds(750))
            try await session.tap("u")
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                let screen = try await session.observeScreenText().lowercased().filter { $0.isLetter }
                if screen.contains("shutdownwindows") { shutdown = true; break }
                try await Task.sleep(for: .milliseconds(500))
            }
            if shutdown { break }
        }
        guard shutdown else { throw VMError.invalid("Normal Windows shutdown was not offered") }
        try await session.tap("s"); try await session.tap("ret")
        let powerDeadline = Date().addingTimeInterval(60)
        var safe = false
        while Date() < powerDeadline {
            if !session.isActive { safe = true; break }
            let screen = try await session.observeScreenText().lowercased().filter { $0.isLetter }
            if screen.contains("safetoturnoff") { safe = true; break }
            try await Task.sleep(for: .milliseconds(500))
        }
        guard safe else { throw VMError.invalid("Normal Windows shutdown did not finish") }
        await session.powerOff()
        while session.isActive { try await Task.sleep(for: .milliseconds(100)) }
        try await session.start(machine, directory: directory, muted: true)
        let bootDeadline = Date().addingTimeInterval(120)
        while Date() < bootDeadline, !session.absolutePointer || session.guestDisplay?.ready != true { try await Task.sleep(for: .milliseconds(500)) }
        guard session.absolutePointer, session.guestDisplay?.ready == true else { throw VMError.invalid("Guest Tools did not reconnect after sandboxed cold boot") }
        await session.powerOff()
        return ["windows98GuestToolsConfirmed":true, "windows98ResizeConfirmed":true,
                "guestFileRoundTripBytes":data.count, "windows98ColdBootConfirmed":true,
                "supportFloppySwapConfirmed":CommandLine.arguments.contains("--check-floppy-swap")]
    }
    private static func log(_ message: String) { FileHandle.standardError.write(Data((message + "\n").utf8)) }
    private static func run(_ command: String, session: MachineSession) async throws {
        try await session.sendChord(["meta_l","r"])
        let deadline = Date().addingTimeInterval(8)
        var opened = false
        while Date() < deadline {
            let screen = try await session.observeScreenText().lowercased().filter { $0.isLetter }
            if screen.contains("typethenameofaprogram") { opened = true; break }
            try await Task.sleep(for: .milliseconds(300))
        }
        guard opened else { throw VMError.invalid("Windows did not open Run for the file-copy test") }
        try await session.sendChord(["alt","o"])
        try await session.tap("home"); try await session.sendChord(["shift","end"])
        try await session.tap("backspace")
        try await session.typeText(command.lowercased(), paced:true)
        try await Task.sleep(for: .milliseconds(500))
        try await session.tap("end")
        let tail = String(command.split(separator: "\\").last ?? "").lowercased().filter { $0.isLetter }
        let verifyDeadline = Date().addingTimeInterval(5)
        var verified = false
        while Date() < verifyDeadline {
            let screen = try await session.observeScreenText().lowercased().filter { $0.isLetter }
            if screen.contains("typethenameofaprogram"), screen.contains(tail) { verified = true; break }
            try await Task.sleep(for: .milliseconds(300))
        }
        guard verified else { throw VMError.invalid("The file-copy command was not entered completely") }
        try await session.tap("ret")
    }
}
