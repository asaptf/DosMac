import Foundation

/// QMP absolute input uses the inclusive range 0...32767, independently of resolution.
public enum GuestPointer {
    public static func coordinate(_ position: Double, extent: Double) -> Int {
        guard position.isFinite, extent.isFinite, extent > 0 else { return 0 }
        return Int((min(1, max(0, position / extent)) * 32767).rounded())
    }

    public static func isAbsolute(_ mice: JSONValue) -> Bool {
        mice.array?.contains { $0["current"] == .bool(true) && $0["absolute"] == .bool(true) } == true
    }
}
