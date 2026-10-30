/// Conversion entre `MIDIEvent` (MIDI 1.0) et les mots de 32 bits des paquets MIDI universels (UMP),
/// le format que CoreMIDI échange avec les applications.
///
/// Fonctions pures : tout est testable sans contrôleur ni CoreMIDI.
public enum UMP {
    /// Mots UMP d'un message. `group` : groupe UMP (0 à 15), presque toujours 0.
    ///
    /// - Messages de voix (type 2) : un mot `2 g status data1 data2`.
    /// - SysEx 7 bits (type 3) : des paquets de deux mots portant 6 octets au plus, sans `F0` ni `F7`.
    public static func encode(_ event: MIDIEvent, group: UInt8 = 0) -> [UInt32] {
        let group = UInt32(group & 0x0F)
        switch event {
        case .noteOn, .noteOff, .controlChange:
            let b = event.bytes
            return [0x2000_0000 | group << 24 | UInt32(b[0]) << 16 | UInt32(b[1]) << 8 | UInt32(b[2])]
        case .systemExclusive(let bytes):
            var data = bytes[...]
            if data.first == 0xF0 { data = data.dropFirst() }
            if data.last == 0xF7 { data = data.dropLast() }
            let chunks = stride(from: data.startIndex, to: data.endIndex, by: 6).map {
                data[$0..<min($0 + 6, data.endIndex)]
            }
            if chunks.isEmpty { return sysExPacket(status: .complete, group: group, chunk: [][...]) }
            return chunks.enumerated().flatMap { index, chunk -> [UInt32] in
                let status: SysExStatus =
                    chunks.count == 1 ? .complete : index == 0 ? .start : index == chunks.count - 1 ? .end : .continuation
                return sysExPacket(status: status, group: group, chunk: chunk)
            }
        }
    }

    enum SysExStatus: UInt32 {
        case complete = 0, start = 1, continuation = 2, end = 3
    }

    private static func sysExPacket(status: SysExStatus, group: UInt32, chunk: ArraySlice<UInt8>) -> [UInt32] {
        var padded = Array(chunk)
        padded += [UInt8](repeating: 0, count: 6 - padded.count)
        let first =
            0x3000_0000 | group << 24 | status.rawValue << 20 | UInt32(chunk.count) << 16
            | UInt32(padded[0] & 0x7F) << 8 | UInt32(padded[1] & 0x7F)
        let second =
            UInt32(padded[2] & 0x7F) << 24 | UInt32(padded[3] & 0x7F) << 16
            | UInt32(padded[4] & 0x7F) << 8 | UInt32(padded[5] & 0x7F)
        return [first, second]
    }
}

/// Décodeur de mots UMP vers `MIDIEvent`. Garde en mémoire un SysEx commencé dans un envoi
/// et fini dans le suivant : un décodeur par source.
public struct UMPDecoder: Sendable {
    private var pendingSysEx: [UInt8]?

    public init() {}

    /// Messages contenus dans `words`. Les types inconnus sont sautés selon leur taille ;
    /// un message tronqué ou incohérent est ignoré.
    public mutating func decode(_ words: [UInt32]) -> [MIDIEvent] {
        var events: [MIDIEvent] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            let type = word >> 28
            let size = Self.wordCount(forMessageType: type)
            guard index + size <= words.count else { break }
            switch type {
            case 2: if let event = voiceMessage(word) { events.append(event) }
            case 3: if let event = sysExPacket(word, words[index + 1]) { events.append(event) }
            default: break
            }
            index += size
        }
        return events
    }

    /// Taille d'un message UMP selon son type (spécification UMP).
    static func wordCount(forMessageType type: UInt32) -> Int {
        switch type {
        case 0x0, 0x1, 0x2, 0x6, 0x7: 1
        case 0x3, 0x4, 0x8, 0x9, 0xA: 2
        case 0xB, 0xC: 3
        default: 4
        }
    }

    private func voiceMessage(_ word: UInt32) -> MIDIEvent? {
        let status = UInt8((word >> 16) & 0xFF)
        let channel = status & 0x0F
        let a = UInt8((word >> 8) & 0x7F)
        let b = UInt8(word & 0x7F)
        switch status & 0xF0 {
        case 0x90 where b > 0: return .noteOn(channel: channel, note: a, velocity: b)
        case 0x90, 0x80: return .noteOff(channel: channel, note: a, velocity: b)
        case 0xB0: return .controlChange(channel: channel, controller: a, value: b)
        default: return nil
        }
    }

    private mutating func sysExPacket(_ first: UInt32, _ second: UInt32) -> MIDIEvent? {
        let status = (first >> 20) & 0x0F
        let count = Int((first >> 16) & 0x0F)
        guard count <= 6 else { pendingSysEx = nil; return nil }
        let bytes = [first >> 8, first, second >> 24, second >> 16, second >> 8, second]
            .prefix(count).map { UInt8($0 & 0x7F) }
        switch status {
        case 0:  // complet
            pendingSysEx = nil
            return .systemExclusive([0xF0] + bytes + [0xF7])
        case 1:  // début
            pendingSysEx = bytes
            return nil
        case 2:  // milieu
            guard pendingSysEx != nil else { return nil }
            pendingSysEx?.append(contentsOf: bytes)
            return nil
        case 3:  // fin
            guard let start = pendingSysEx else { return nil }
            pendingSysEx = nil
            return .systemExclusive([0xF0] + start + bytes + [0xF7])
        default:
            pendingSysEx = nil
            return nil
        }
    }
}
