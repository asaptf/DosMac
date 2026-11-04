import Foundation
import Testing
@testable import DosMacVM

struct MachineTests {
    @Test func validatesOwnedMediaPaths() throws {
        var machine = Machine(name: "DOS", guest: .msdos622)
        machine.floppies = [MachineMedia(name: "Setup disk", relativePath: "../../secret.img")]
        #expect(throws: (any Error).self) { try machine.validate() }
        machine.floppies = [MachineMedia(name: "Setup disk", relativePath: "Media/DISK01.img")]
        try machine.validate()
    }

    @Test func JSONRoundTripsQMPValues() throws {
        let original = JSONValue.object(["command": .string("blockdev-change-medium"), "id": .string("a"), "args": .array([.number(2), .bool(true), .null])])
        #expect(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(original)) == original)
    }

    #if os(macOS)
    @MainActor private final class Probe { var frames = 0; var width = 0; var nonzero = false; var paintedBytes = 0; var displayError: String? }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DOSMAC_TEST_QEMU"] == "1"))
    @MainActor func realPCBootDisplayAndDirectMediaControl() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DosMacQEMU-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MachineStore(root: root.appendingPathComponent("Machines"))
        // Option-like user names must never be mistaken for argument-vector switches.
        var machine = try await store.create(name: "-net", guest: .msdos622)
        machine.sharedDisk = true
        machine.sharedFolder = ProcessInfo.processInfo.environment["DOSMAC_TEST_SAMBA"] == "1"
        let first = root.appendingPathComponent("DISK1.img"), second = root.appendingPathComponent("DISK2.img"), cd = root.appendingPathComponent("SETUP.iso")
        try Self.bootDisk(message: "DOSMAC VM READY").write(to: first)
        try Self.bootDisk(message: "DOSMAC DISK TWO").write(to: second)
        try Data(repeating: 0, count: 2048).write(to: cd)
        machine = try await store.importMedia([first, second], into: machine, cdrom: false)
        machine = try await store.importMedia([cd], into: machine, cdrom: true)
        #expect(try await store.machines().first?.floppies.count == 2)
        let session = MachineSession()
        let probe = Probe()
        session.onFrame = { frame in probe.frames += 1; probe.width = frame.width; probe.paintedBytes = frame.pixels.filter { $0 != 0 }.count; probe.nonzero = probe.paintedBytes > 0 }
        session.onDisplayError = { probe.displayError = $0 }
        try await session.start(machine, directory: store.directory(for: machine.id), muted: true)
        defer { session.terminate() }
        let deadline = Date().addingTimeInterval(10)
        var screen = ""
        while Date() < deadline {
            screen = try await session.textScreen()
            if screen.contains("DOSMAC VM READY"), probe.frames > 1 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(screen.contains("DOSMAC VM READY"), Comment(rawValue: screen))
        #expect(probe.frames > 1)
        #expect(probe.width > 0 && probe.nonzero)
        #expect(probe.displayError == nil)
        try await session.pause()
        #expect(try await session.queryStatus()["status"]?.string == "paused")
        try await session.resume()
        let textWidth = probe.width
        for _ in 0..<8 {
            try await session.tap("ret")
            let graphicsDeadline = Date().addingTimeInterval(5)
            while probe.width == textWidth, Date() < graphicsDeadline { try await Task.sleep(for: .milliseconds(100)) }
            try #require(probe.width != textWidth, "The native display did not follow the guest into graphics mode.")
            try await session.tap("ret")
            let textDeadline = Date().addingTimeInterval(5)
            while (probe.width != textWidth || probe.paintedBytes < 500), Date() < textDeadline { try await Task.sleep(for: .milliseconds(100)) }
            try #require(probe.width == textWidth, "The native display did not return to text mode.")
            try #require(probe.paintedBytes >= 500, "The resized display must repaint the complete text, not only a cursor.")
        }
        try await session.pointer(dx: 10, dy: 5, button: "left", down: true)
        try await session.pointer(dx: 0, dy: 0, button: "left", down: false)
        try await session.insert(machine.floppies[1], cdrom: false)
        #expect(session.currentFloppy == machine.floppies[1].id)
        let blocks = try await session.queryBlock()
        #expect(blocks.array?.first { $0["device"]?.string == "floppy0" }?["inserted"]?["file"]?.string?.hasSuffix(machine.floppies[1].relativePath) == true)
        try await session.eject(cdrom: true)
        #expect(session.currentCD == nil)
        try await session.insert(machine.cdroms[0], cdrom: true)
        #expect(session.currentCD == machine.cdroms[0].id)
        await session.powerOff()
        let stopDeadline = Date().addingTimeInterval(3)
        while session.isActive, Date() < stopDeadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(!session.isActive)
        #expect(probe.displayError == nil)
    }

    static func bootDisk(message: String) -> Data {
        var disk = Data(repeating: 0, count: 1440 * 1024)
        // Original fixture: print, wait for a key, switch to VGA 12h, wait, return to mode 3.
        let code: [UInt8] = [0xfa,0x31,0xc0,0x8e,0xd8,0x8e,0xd0,0xbc,0,0x7c,0xfb,0xb8,3,0,0xcd,0x10,0xbe,0x40,0x7c,0xac,0x84,0xc0,0x74,0x09,0xb4,0x0e,0xbb,7,0,0xcd,0x10,0xeb,0xf2,0x31,0xc0,0xcd,0x16,0xb8,0x12,0,0xcd,0x10,0x31,0xc0,0xcd,0x16,0xeb,0xdb]
        disk.replaceSubrange(0..<code.count, with: code)
        let text = Data((message + "\0").utf8)
        disk.replaceSubrange(64..<(64 + text.count), with: text)
        disk[510] = 0x55; disk[511] = 0xaa
        return disk
    }
    #endif
}
