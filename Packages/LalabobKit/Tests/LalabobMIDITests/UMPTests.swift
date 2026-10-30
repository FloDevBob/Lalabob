import Testing

@testable import LalabobMIDI

@Suite("UMP (MIDI 1.0 dans paquets universels)")
struct UMPTests {
    /// SysEx dont les octets de données valent 1, 2, 3… (modulo 128).
    static func sysEx(count: Int) -> MIDIEvent {
        var bytes: [UInt8] = [0xF0]
        for i in 0..<count { bytes.append(UInt8((i + 1) % 128)) }
        bytes.append(0xF7)
        return .systemExclusive(bytes)
    }

    @Test("Note On sur le canal 1")
    func noteOn() {
        #expect(UMP.encode(.noteOn(channel: 0, note: 60, velocity: 100)) == [0x2090_3C64])
    }

    @Test("Note Off et Control Change sur d'autres canaux")
    func otherChannelMessages() {
        #expect(UMP.encode(.noteOff(channel: 5, note: 61, velocity: 0)) == [0x2085_3D00])
        #expect(UMP.encode(.controlChange(channel: 15, controller: 48, value: 127)) == [0x20BF_307F])
    }

    @Test("Le groupe UMP est écrit dans le mot")
    func group() {
        #expect(UMP.encode(.noteOn(channel: 0, note: 1, velocity: 2), group: 3) == [0x2390_0102])
    }

    @Test("SysEx court : un seul paquet « complet »")
    func shortSysEx() {
        // F0 7E 7F 06 01 F7 → données 7E 7F 06 01 (4 octets)
        let words = UMP.encode(.systemExclusive(DeviceInquiry.request))
        #expect(words == [0x3004_7E7F, 0x0601_0000])
    }

    @Test("SysEx de 6 octets exactement : un paquet complet")
    func sixByteSysEx() {
        let words = UMP.encode(.systemExclusive([0xF0, 1, 2, 3, 4, 5, 6, 0xF7]))
        #expect(words == [0x3006_0102, 0x0304_0506])
    }

    @Test("SysEx long : début, milieu, fin")
    func longSysEx() {
        let words = UMP.encode(Self.sysEx(count: 14))  // 14 octets → 6 + 6 + 2
        #expect(
            words == [
                0x3016_0102, 0x0304_0506,
                0x3026_0708, 0x090A_0B0C,
                0x3032_0D0E, 0x0000_0000,
            ])
    }

    @Test("SysEx vide")
    func emptySysEx() {
        #expect(UMP.encode(.systemExclusive([0xF0, 0xF7])) == [0x3000_0000, 0x0000_0000])
    }

    @Test("Aller-retour sur des messages variés")
    func roundTrip() {
        let events: [MIDIEvent] = [
            .noteOn(channel: 0, note: 11, velocity: 127),
            .noteOff(channel: 9, note: 88, velocity: 0),
            .controlChange(channel: 3, controller: 48, value: 64),
            .systemExclusive([0xF0, 0x00, 0x20, 0x29, 0x02, 0x0C, 0x0E, 0x01, 0xF7]),
            Self.sysEx(count: 100),
        ]
        var decoder = UMPDecoder()
        let decoded = decoder.decode(events.flatMap { UMP.encode($0) })
        #expect(decoded == events)
    }

    @Test("Un Note On de vélocité 0 est un Note Off, comme dans MIDIEvent.parse")
    func noteOnZero() {
        var decoder = UMPDecoder()
        #expect(decoder.decode([0x2090_3C00]) == [.noteOff(channel: 0, note: 60, velocity: 0)])
    }

    @Test("Un SysEx coupé entre deux envois est reconstitué")
    func sysExAcrossCalls() {
        let message = Self.sysEx(count: 14)
        let words = UMP.encode(message)
        var decoder = UMPDecoder()
        #expect(decoder.decode(Array(words[0..<2])).isEmpty)
        #expect(decoder.decode(Array(words[2..<4])).isEmpty)
        #expect(decoder.decode(Array(words[4...])) == [message])
    }

    @Test("Un « milieu » ou une « fin » sans « début » est ignoré, sans planter")
    func orphanSysEx() {
        var decoder = UMPDecoder()
        #expect(decoder.decode([0x3026_0102, 0x0304_0506]).isEmpty)
        #expect(decoder.decode([0x3032_0102, 0x0000_0000]).isEmpty)
        // Et le décodeur reste utilisable.
        #expect(decoder.decode([0x2090_3C64]) == [.noteOn(channel: 0, note: 60, velocity: 100)])
    }

    @Test("Un SysEx complet abandonne un SysEx inachevé")
    func restartedSysEx() {
        var decoder = UMPDecoder()
        _ = decoder.decode([0x3016_0102, 0x0304_0506])
        let out = decoder.decode([0x3003_0A0B, 0x0C00_0000])
        #expect(out == [.systemExclusive([0xF0, 0x0A, 0x0B, 0x0C, 0xF7])])
    }

    @Test("Les messages UMP inconnus sont sautés selon leur taille")
    func unknownMessagesAreSkipped() {
        // MT 0 (utilitaire, 1 mot), MT 1 (temps réel, 1 mot), MT 4 (MIDI 2.0, 2 mots), MT 5 (128 bits, 4 mots)
        let words: [UInt32] = [
            0x0000_0000,
            0x10F8_0000,
            0x4090_3C00, 0xFFFF_0000,
            0x5000_0000, 0, 0, 0,
            0x2090_3D64,
        ]
        var decoder = UMPDecoder()
        #expect(decoder.decode(words) == [.noteOn(channel: 0, note: 61, velocity: 100)])
    }

    @Test("Un message tronqué en fin de liste est ignoré")
    func truncated() {
        var decoder = UMPDecoder()
        #expect(decoder.decode([0x3004_7E7F]).isEmpty)
        #expect(decoder.decode([0x5000_0000, 0]).isEmpty)
    }

    @Test("Valeurs hors plage : rognées sur 7 bits comme dans MIDIEvent.bytes")
    func masking() {
        #expect(UMP.encode(.noteOn(channel: 0x1F, note: 0xFF, velocity: 0x80)) == [0x209F_7F00])
    }
}
