import Foundation
import Testing
@testable import DosMacVM

struct GuestPointerTests {
    @Test func normalizesIndependentlyOfDisplayScaleAndClampsEdges() {
        #expect(GuestPointer.coordinate(0, extent: 640) == 0)
        #expect(GuestPointer.coordinate(640, extent: 640) == 32767)
        #expect(GuestPointer.coordinate(320, extent: 640) == GuestPointer.coordinate(960, extent: 1920))
        #expect(GuestPointer.coordinate(-1, extent: 640) == 0)
        #expect(GuestPointer.coordinate(999, extent: 640) == 32767)
        #expect(GuestPointer.coordinate(.nan, extent: 640) == 0)
        #expect(GuestPointer.coordinate(10, extent: 0) == 0)
    }
    @Test func followsCurrentGuestDeviceRatherThanMerelyAvailableTablet() {
        let relative = JSONValue.object(["current": .bool(true), "absolute": .bool(false)])
        let tablet = JSONValue.object(["current": .bool(false), "absolute": .bool(true)])
        #expect(!GuestPointer.isAbsolute(.array([relative, tablet])))
        #expect(GuestPointer.isAbsolute(.array([.object(["current": .bool(true), "absolute": .bool(true)])])))
        #expect(!GuestPointer.isAbsolute(.null))
    }
    #if os(macOS)
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DOSMAC_TEST_GUEST_TOOLS_DISK"] != nil))
    @MainActor func installsMouseToolsInPrivateWindowsCopyAndSurvivesColdBoot() async throws {
        let env = ProcessInfo.processInfo.environment
        let source = URL(fileURLWithPath: try #require(env["DOSMAC_TEST_GUEST_TOOLS_DISK"]))
        let assets = URL(fileURLWithPath: try #require(env["DOSMAC_TEST_GUEST_TOOLS_FILES"]))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DosMacToolsTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { if env["DOSMAC_TEST_KEEP_TOOLS"] != "1" { try? FileManager.default.removeItem(at: root) } }
        let store = try MachineStore(root: root.appendingPathComponent("Machines"))
        var machine = try await store.create(name: "Guest Tools acceptance", guest: .windows98)
        let directory = store.directory(for: machine.id)
        let disk = directory.appendingPathComponent("disk.qcow2")
        try FileManager.default.removeItem(at: disk)
        try FileManager.default.copyItem(at: source, to: disk)
        machine.boot = .hardDisk; machine.sharedFolder = true
        machine.installation = InstallationRecord(recipeID: Windows9xRecipe.id(for: .windows98), stage: .complete)
        let withDisplay = env["DOSMAC_TEST_DISPLAY_AGENT"] == "1"
        let files = GuestToolsMedia.mouseFiles(driver: try Data(contentsOf: assets.appendingPathComponent("qemouse.drv")), inf: try Data(contentsOf: assets.appendingPathComponent("qemouse.inf")), agent: withDisplay ? try Data(contentsOf: assets.appendingPathComponent("dmagent.exe")) : nil)
        let session = MachineSession()
        try await session.start(machine, directory: directory, muted: true)
        defer { session.terminate() }
        do {
            try await GuestToolsInstaller(session: session).installMouse(files: files) { print($0); fflush(nil) }
            try #require(session.absolutePointer)
            if withDisplay {
                let bridge = try #require(session.guestDisplay)
                try #require(bridge.ready)
                print("Guest display modes: \(bridge.modes.map(\.title))")
                let target = GuestDisplaySize(800, 600)
                try #require(bridge.modes.contains(target))
                bridge.request(target)
                let resizeDeadline = Date().addingTimeInterval(15)
                while Date() < resizeDeadline, session.frameSnapshot()?.width != 800 || session.frameSnapshot()?.height != 600 || bridge.current != target {
                    try await Task.sleep(for: .milliseconds(250))
                }
                print("Resize acknowledgement: \(bridge.message)")
                if let reply = try? String(contentsOf: directory.appendingPathComponent("Shared/DMTOOLS/STATUS.TXT"), encoding: .ascii) { print("Display reply: \(reply)") }
                try #require(session.frameSnapshot()?.width == 800)
                try #require(session.frameSnapshot()?.height == 600)
                try #require(bridge.current == target)
                print("Confirmed real Windows framebuffer at 800 x 600")
                let startX = GuestPointer.coordinate(20, extent: 800)
                let startY = GuestPointer.coordinate(585, extent: 600)
                try await session.absolutePointer(x: startX, y: startY)
                try await Task.sleep(for: .seconds(1))
                try await session.absolutePointer(x: startX, y: startY, button: "left", down: true)
                try await Task.sleep(for: .milliseconds(150))
                try await session.absolutePointer(x: startX, y: startY, button: "left", down: false)
                let menuDeadline = Date().addingTimeInterval(8)
                var startOpened = false
                while Date() < menuDeadline {
                    let text = try await session.observeScreenText().lowercased().filter { $0.isLetter }
                    if text.contains("windowsupdate") && text.contains("favorites") && text.contains("documents") { startOpened = true; break }
                    try await Task.sleep(for: .milliseconds(250))
                }
                try #require(startOpened)
                try await session.tap("esc")
                print("Confirmed actual mouse click opens the Windows Start menu after resizing")
                bridge.setAutomatic(true)
                bridge.fit(width: 1100, height: 800)
                let fitDeadline = Date().addingTimeInterval(15)
                while Date() < fitDeadline, session.frameSnapshot()?.width != 1024 || session.frameSnapshot()?.height != 768 || bridge.current != GuestDisplaySize(1024,768) {
                    try await Task.sleep(for: .milliseconds(250))
                }
                try #require(session.frameSnapshot()?.width == 1024)
                try #require(session.frameSnapshot()?.height == 768)
                print("Confirmed automatic fit at 1024 x 768")
                bridge.setAutomatic(false)
                bridge.request(GuestDisplaySize(640,480))
                let restoreDeadline = Date().addingTimeInterval(15)
                while Date() < restoreDeadline, bridge.current != GuestDisplaySize(640,480) { try await Task.sleep(for: .milliseconds(250)) }
                try #require(bridge.current == GuestDisplaySize(640,480))
            }
            // Windows must finish booting and shut down normally. Cutting power
            // during driver startup makes the next boot choose Safe Mode.
            var shutdownShown = false
            for _ in 0..<3 {
                try await session.sendChord(["ctrl", "esc"])
                try await Task.sleep(for: .milliseconds(750))
                try await session.tap("u")
                let shutdownDeadline = Date().addingTimeInterval(5)
                while Date() < shutdownDeadline {
                    let text = try await session.observeScreenText().lowercased().filter { $0.isLetter }
                    if text.contains("shutdownwindows") { shutdownShown = true; break }
                    try await Task.sleep(for: .milliseconds(500))
                }
                if shutdownShown { break }
            }
            try #require(shutdownShown)
            try await session.tap("s"); try await session.tap("ret")
            let powerDeadline = Date().addingTimeInterval(60)
            var safeToStop = false
            while Date() < powerDeadline {
                if !session.isActive { safeToStop = true; break }
                let text = try await session.observeScreenText().lowercased().filter { $0.isLetter }
                if text.contains("safetoturnoff") { safeToStop = true; break }
                try await Task.sleep(for: .milliseconds(500))
            }
            try #require(safeToStop)
            await session.powerOff()
            while session.isActive { try await Task.sleep(for: .milliseconds(100)) }
            try await session.start(machine, directory: directory, muted: true)
            let deadline = Date().addingTimeInterval(120)
            while !session.absolutePointer, Date() < deadline { try await Task.sleep(for: .milliseconds(250)) }
            if withDisplay {
                let agentDeadline = Date().addingTimeInterval(90)
                while session.guestDisplay?.ready != true, Date() < agentDeadline { try await Task.sleep(for: .milliseconds(500)) }
                #expect(session.guestDisplay?.ready == true)
            }
            if !session.absolutePointer {
                let text = try await session.observeScreenText()
                if !text.lowercased().contains("password") { print("Cold boot diagnostic: \(text)") }
            }
            #expect(session.absolutePointer)
            await session.powerOff()
        } catch {
            print("Guest Tools acceptance stopped in its private copy: \(root.path)")
            let text = (try? await session.observeScreenText()) ?? "No display"
            if !text.lowercased().contains("password"), !text.lowercased().contains("product key") { print("Private fixture diagnostic: \(text)") }
            throw error
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DOSMAC_TEST_QEMU"] == "1"))
    @MainActor func realVMPortSwitchesBetweenAbsoluteAndRelativeInput() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DosMacPointer-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MachineStore(root: root.appendingPathComponent("Machines"))
        var machine = try await store.create(name: "Pointer protocol fixture", guest: .msdos622)
        // Original boot code: use the documented VMware I/O ABI, wait for Enter,
        // then return to relative input. No DOS/Windows or third-party driver executes.
        var code: [UInt8] = [0xfa, 0x31, 0xc0, 0x8e, 0xd8, 0x8e, 0xd0, 0xbc, 0, 0x7c, 0xfb]
        func command(_ value: UInt32) {
            code += [0x66, 0xb8, 0x68, 0x58, 0x4d, 0x56, 0x66, 0xbb]
            code += (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
            code += [0x66, 0xb9, 41, 0, 0, 0, 0x66, 0xba, 0x58, 0x56, 0, 0, 0x66, 0xed]
        }
        command(0x45414552); command(0x53424152)
        code += [0x31, 0xc0, 0xcd, 0x16]
        command(0x4c455252)
        code += [0xfb, 0xf4, 0xeb, 0xfd]
        var image = Data(repeating: 0, count: 1440 * 1024)
        image.replaceSubrange(0..<code.count, with: code); image[510] = 0x55; image[511] = 0xaa
        let disk = root.appendingPathComponent("POINTER.IMG"); try image.write(to: disk)
        machine = try await store.importMedia([disk], into: machine, cdrom: false)
        let session = MachineSession()
        try await session.start(machine, directory: store.directory(for: machine.id), muted: true)
        defer { session.terminate() }
        let absoluteDeadline = Date().addingTimeInterval(8)
        while !session.absolutePointer, Date() < absoluteDeadline { try await Task.sleep(for: .milliseconds(100)) }
        try #require(session.absolutePointer)
        try await session.absolutePointer(x: 0, y: 32767, button: "left", down: true)
        try await session.absolutePointer(x: 32767, y: 0, button: "left", down: false)
        try await session.tap("ret")
        let relativeDeadline = Date().addingTimeInterval(5)
        while session.absolutePointer, Date() < relativeDeadline { try await Task.sleep(for: .milliseconds(100)) }
        #expect(!session.absolutePointer)
        try await session.pointer(dx: 12, dy: -8)
        await session.powerOff()
    }
    #endif
}
