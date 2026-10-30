/// Un message MIDI 1.0 entrant ou sortant, sous forme de valeur testable.
///
/// Les canaux vont de 0 à 15 (affichés 1 à 16 dans l'interface).
public enum MIDIEvent: Equatable, Sendable {
    case noteOn(channel: UInt8, note: UInt8, velocity: UInt8)
    case noteOff(channel: UInt8, note: UInt8, velocity: UInt8)
    case controlChange(channel: UInt8, controller: UInt8, value: UInt8)
    case systemExclusive([UInt8])

    /// Octets à envoyer sur le câble.
    public var bytes: [UInt8] {
        switch self {
        case let .noteOn(channel, note, velocity):
            [0x90 | (channel & 0x0F), note & 0x7F, velocity & 0x7F]
        case let .noteOff(channel, note, velocity):
            [0x80 | (channel & 0x0F), note & 0x7F, velocity & 0x7F]
        case let .controlChange(channel, controller, value):
            [0xB0 | (channel & 0x0F), controller & 0x7F, value & 0x7F]
        case let .systemExclusive(data):
            data
        }
    }

    /// Analyse un paquet d'octets reçu. Les messages non gérés sont ignorés.
    ///
    /// Un Note On de vélocité 0 est un Note Off (convention MIDI).
    public static func parse(_ bytes: [UInt8]) -> [MIDIEvent] {
        var events: [MIDIEvent] = []
        var index = 0
        while index < bytes.count {
            let status = bytes[index]
            if status == 0xF0 {
                guard let end = bytes[index...].firstIndex(of: 0xF7) else { break }
                events.append(.systemExclusive(Array(bytes[index...end])))
                index = end + 1
                continue
            }
            guard status & 0x80 != 0 else { index += 1; continue }
            let kind = status & 0xF0
            let channel = status & 0x0F
            guard [0x80, 0x90, 0xB0].contains(kind), index + 2 < bytes.count else {
                index += 1
                continue
            }
            let a = bytes[index + 1] & 0x7F
            let b = bytes[index + 2] & 0x7F
            switch kind {
            case 0x90 where b > 0: events.append(.noteOn(channel: channel, note: a, velocity: b))
            case 0x90, 0x80: events.append(.noteOff(channel: channel, note: a, velocity: b))
            default: events.append(.controlChange(channel: channel, controller: a, value: b))
            }
            index += 3
        }
        return events
    }
}

/// Requête d'identité MIDI universelle : chaque contrôleur répond avec son fabricant et son modèle.
public enum DeviceInquiry {
    public static let request: [UInt8] = [0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7]

    /// Fabricant et famille extraits d'une réponse `F0 7E <id> 06 02 <fab…> <famille…> …`.
    public struct Reply: Equatable, Sendable {
        public let manufacturer: [UInt8]
        public let family: [UInt8]
    }

    public static func parseReply(_ bytes: [UInt8]) -> Reply? {
        guard bytes.count >= 10, bytes[0] == 0xF0, bytes[1] == 0x7E, bytes[3] == 0x06, bytes[4] == 0x02 else {
            return nil
        }
        // Identifiant fabricant sur 1 octet, ou 3 octets s'il commence par 00.
        let manufacturerLength = bytes[5] == 0x00 ? 3 : 1
        let familyStart = 5 + manufacturerLength
        guard bytes.count >= familyStart + 2 else { return nil }
        return Reply(
            manufacturer: Array(bytes[5..<familyStart]),
            family: Array(bytes[familyStart..<familyStart + 2])
        )
    }
}
