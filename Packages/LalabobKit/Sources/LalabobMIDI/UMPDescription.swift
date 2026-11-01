/// Texte lisible des messages UMP bruts, pour le journal du relevé de LightKey.
///
/// On décrit les mots reçus tels quels, avant tout décodage : `UMPDecoder` ignore volontairement
/// ce que Lalabob n'utilise pas (changement de programme, pitch bend…) et lit un Note On de vélocité 0
/// comme un Note Off ; pour savoir ce que LightKey envoie vraiment, il faut voir l'original.
public enum UMPDescription {
    /// Une ligne par message UMP contenu dans `words`.
    public static func lines(for words: [UInt32]) -> [String] {
        var lines: [String] = []
        var index = 0
        while index < words.count {
            let type = words[index] >> 28
            let size = UMPDecoder.wordCount(forMessageType: type)
            guard index + size <= words.count else {
                lines.append("message tronqué : \(hex(words[index...]))")
                break
            }
            let message = Array(words[index..<index + size])
            lines.append(describe(message, type: type))
            index += size
        }
        return lines
    }

    private static func describe(_ message: [UInt32], type: UInt32) -> String {
        let raw = hex(message[...])
        guard type == 2 else { return "UMP type \(type) [\(raw)]" }
        let status = UInt8((message[0] >> 16) & 0xFF)
        let channel = Int(status & 0x0F) + 1
        let a = Int((message[0] >> 8) & 0x7F)
        let b = Int(message[0] & 0x7F)
        switch status & 0xF0 {
        case 0x80: return "Note Off · canal \(channel) · note \(a) · vélocité \(b) [\(raw)]"
        case 0x90: return "Note On · canal \(channel) · note \(a) · vélocité \(b) [\(raw)]"
        case 0xA0: return "Pression de note · canal \(channel) · note \(a) · valeur \(b) [\(raw)]"
        case 0xB0: return "Control Change · canal \(channel) · contrôleur \(a) · valeur \(b) [\(raw)]"
        case 0xC0: return "Changement de programme · canal \(channel) · programme \(a) [\(raw)]"
        case 0xD0: return "Pression de canal · canal \(channel) · valeur \(a) [\(raw)]"
        case 0xE0: return "Pitch Bend · canal \(channel) · valeur \(b << 7 | a) [\(raw)]"
        default: return "Message de voix inconnu [\(raw)]"
        }
    }

    private static func hex(_ words: ArraySlice<UInt32>) -> String {
        words.map { String($0, radix: 16, uppercase: true).leftPadded(to: 8) }.joined(separator: " ")
    }
}

extension String {
    fileprivate func leftPadded(to length: Int) -> String {
        String(repeating: "0", count: max(0, length - count)) + self
    }
}

extension MIDIEvent {
    /// Texte court d'un message déjà décodé, pour le banc d'essai lumière.
    public var summary: String {
        switch self {
        case let .noteOn(channel, note, velocity):
            "Note On · canal \(channel + 1) · note \(note) · vélocité \(velocity)"
        case let .noteOff(channel, note, velocity):
            "Note Off · canal \(channel + 1) · note \(note) · vélocité \(velocity)"
        case let .controlChange(channel, controller, value):
            "Control Change · canal \(channel + 1) · contrôleur \(controller) · valeur \(value)"
        case .systemExclusive(let bytes):
            "SysEx · \(bytes.count) octets"
        }
    }
}
