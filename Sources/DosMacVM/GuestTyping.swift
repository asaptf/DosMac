import Foundation

public struct GuestKeystroke: Equatable, Sendable {
    public let qcode: String
    public let shift: Bool
}

public enum GuestTyping {
    public static func strokes(for text: String) throws -> [GuestKeystroke] {
        guard text.count <= 4096 else { throw VMError.invalid("Guest command is too long.") }
        let plain: [Character:String] = [" ":"spc","\n":"ret","\r":"ret","\t":"tab",":":"semicolon",";":"semicolon","\\":"backslash","/":"slash",".":"dot",",":"comma","-":"minus","_":"minus","=":"equal","+":"equal","\"":"apostrophe","'":"apostrophe","[":"bracket_left","]":"bracket_right","(":"9",")":"0","?":"slash","*":"8",">":"dot","<":"comma","!":"1","%":"5","&":"7","|":"backslash","@":"2","$":"4","#":"3","^":"6","`":"grave_accent","~":"grave_accent","{":"bracket_left","}":"bracket_right"]
        let shifted = Set(":_+\"()?*><!%&|@$#^~{}")
        return try text.map { char in
            if let code = plain[char] { return GuestKeystroke(qcode: code, shift: shifted.contains(char)) }
            let string = String(char)
            guard string.range(of: "^[A-Za-z0-9]$", options: .regularExpression) != nil else { throw VMError.invalid("Guest automation currently supports the US ASCII keyboard layout.") }
            return GuestKeystroke(qcode: string.lowercased(), shift: string != string.lowercased())
        }
    }
}
