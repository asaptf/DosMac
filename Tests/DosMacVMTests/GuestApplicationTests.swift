import Foundation
import Testing

@testable import DosMacVM

struct GuestApplicationTests {
  @Test func launchCommandsRejectMetacharactersAndTraversal() throws {
    #expect(
      try GuestApplication.command(executable: "C:\\GAMES\\GAME.EXE", windows: false)
        == "C:\nCD \\GAMES\nC:\\GAMES\\GAME.EXE\n")
    #expect(
      try GuestApplication.command(executable: "A:\\SETUP.EXE", windows: true)
        == "C:\\WINDOWS\\WIN.COM A:\\SETUP.EXE\n")
    for path in [
      "C:\\GAME.EXE & FORMAT C:", "C:\\..\\GAME.EXE", "C:\\GAME.EXE\nDEL *.*", "GAME.EXE",
      "C:\\Program Files\\GAME.EXE",
    ] {
      #expect(throws: (any Error).self) {
        try GuestApplication.command(executable: path, windows: false)
      }
    }
  }
  @Test func editingShortcutPreservesIdentityAndDiskOrder() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = GuestApplicationStore(file: directory.appendingPathComponent("apps.json"))
    let disks = [UUID(), UUID()]
    var app = GuestApplication(
      machineID: UUID(), title: "Setup", executable: "A:\\SETUP.EXE", windows: false,
      kind: .installer, mediaIDs: disks, bootFromMedia: true)
    try await store.save(app)
    app.title = "My installer"
    app.lastOpenedAt = Date()
    try await store.save(app)
    let loaded = try await store.applications()
    #expect(loaded.count == 1)
    #expect(loaded[0].id == app.id)
    #expect(loaded[0].mediaIDs == disks)
    #expect(loaded[0].bootFromMedia == true)
    #expect(loaded[0].title == "My installer")
  }
}
