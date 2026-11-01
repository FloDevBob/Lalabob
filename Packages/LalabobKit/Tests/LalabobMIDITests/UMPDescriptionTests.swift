import Testing

@testable import LalabobMIDI

/// Le journal du relevé de LightKey décrit les mots bruts : il doit montrer ce que le décodeur écarte.
struct UMPDescriptionTests {
    @Test func noteOnShowsChannelNoteAndVelocity() {
        let lines = UMPDescription.lines(for: [0x2090_2405])
        #expect(lines == ["Note On · canal 1 · note 36 · vélocité 5 [20902405]"])
    }

    @Test func noteOnWithZeroVelocityStaysANoteOn() {
        // UMPDecoder en fait un Note Off ; le journal doit garder l'original.
        let lines = UMPDescription.lines(for: [0x209F_3C00])
        #expect(lines == ["Note On · canal 16 · note 60 · vélocité 0 [209F3C00]"])
    }

    @Test func controlChangeAndMessagesTheDecoderDrops() {
        let lines = UMPDescription.lines(for: [0x20B0_3040, 0x20C2_0500, 0x20E0_0140])
        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("Control Change · canal 1 · contrôleur 48 · valeur 64"))
        #expect(lines[1].hasPrefix("Changement de programme · canal 3 · programme 5"))
        #expect(lines[2].hasPrefix("Pitch Bend · canal 1 · valeur 8193"))
        var decoder = UMPDecoder()
        #expect(decoder.decode([0x20C2_0500, 0x20E0_0140]).isEmpty)
    }

    @Test func severalMessagesAndTruncation() {
        let lines = UMPDescription.lines(for: [0x2090_2401, 0x2080_2400, 0x3000_0000])
        #expect(lines.count == 3)
        #expect(lines[2].hasPrefix("message tronqué"))
    }

    @Test func emptyInputGivesNoLine() {
        #expect(UMPDescription.lines(for: []).isEmpty)
    }
}
