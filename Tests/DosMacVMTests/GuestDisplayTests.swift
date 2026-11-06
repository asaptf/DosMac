import Foundation
import Testing
@testable import DosMacVM

struct GuestDisplayTests {
    private let token = String(repeating: "a", count: 32)
    @Test func rejectsPartialStaleAndOversizedGuestReplies() {
        let valid = "DMAC1 READY \(token) 640 480\nMODE 640 480\nEND\n"
        #expect(GuestDisplayProtocol.parse(Data(valid.utf8), token: token) != nil)
        #expect(GuestDisplayProtocol.parse(Data(valid.dropLast().utf8), token: token) == nil)
        #expect(GuestDisplayProtocol.parse(Data(valid.utf8), token: String(repeating: "b", count: 32)) == nil)
        #expect(GuestDisplayProtocol.parse(Data(repeating: 65, count: 8193), token: token) == nil)
        #expect(GuestDisplayProtocol.parse(Data("DMAC1 READY \(token) 640 480\nMODE 99999 99999\nEND\n".utf8), token: token) == nil)
        #expect(GuestDisplayProtocol.parse(Data("DMAC1 RESULT \(token) 3 OK 800 600\nEND\n".utf8), token: token) == .result(3, true, GuestDisplaySize(800, 600)))
    }
    @Test func fitsSupportedModesWithoutUsingRetinaPixelDimensions() {
        let modes = [GuestDisplaySize(640,480), GuestDisplaySize(800,600), GuestDisplaySize(1024,768)]
        #expect(GuestDisplaySize.fitting(width: 900, height: 700, modes: modes) == GuestDisplaySize(800,600))
        #expect(GuestDisplaySize.fitting(width: 500, height: 300, modes: modes) == GuestDisplaySize(640,480))
        #expect(GuestDisplaySize.fitting(width: 900, height: 500, modes: modes) == GuestDisplaySize(640,480))
    }
}
