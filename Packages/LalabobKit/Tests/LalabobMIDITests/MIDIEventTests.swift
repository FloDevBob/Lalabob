import Testing
@testable import LalabobMIDI

@Suite("Messages MIDI")
struct MIDIEventTests {
    @Test("Analyse d'un paquet mixte")
    func parseMixed() {
        let bytes: [UInt8] = [0x90, 11, 127, 0x80, 11, 0, 0xB0, 48, 64]
        #expect(MIDIEvent.parse(bytes) == [
            .noteOn(channel: 0, note: 11, velocity: 127),
            .noteOff(channel: 0, note: 11, velocity: 0),
            .controlChange(channel: 0, controller: 48, value: 64),
        ])
    }

    @Test("Un Note On de vélocité 0 est un Note Off")
    func zeroVelocity() {
        #expect(MIDIEvent.parse([0x92, 60, 0]) == [.noteOff(channel: 2, note: 60, velocity: 0)])
    }

    @Test("Un SysEx est extrait en entier")
    func sysEx() {
        let sysEx: [UInt8] = [0xF0, 0x00, 0x20, 0x29, 0x02, 0x0C, 0x0E, 0x01, 0xF7]
        #expect(MIDIEvent.parse(sysEx + [0x90, 81, 100]) == [
            .systemExclusive(sysEx),
            .noteOn(channel: 0, note: 81, velocity: 100),
        ])
    }

    @Test("Les octets tronqués ou inconnus sont ignorés sans planter")
    func garbage() {
        #expect(MIDIEvent.parse([0x90, 11]) == [])
        #expect(MIDIEvent.parse([0x12, 0x34, 0xF8]) == [])
        #expect(MIDIEvent.parse([0xF0, 0x01, 0x02]) == [])
    }

    @Test("Aller-retour octets ⇄ messages")
    func roundTrip() {
        let events: [MIDIEvent] = [
            .noteOn(channel: 6, note: 0, velocity: 5),
            .controlChange(channel: 1, controller: 20, value: 127),
        ]
        #expect(MIDIEvent.parse(events.flatMap(\.bytes)) == events)
    }

    @Test("Réponse d'identité d'un Launchpad X")
    func deviceInquiry() {
        let reply: [UInt8] = [0xF0, 0x7E, 0x00, 0x06, 0x02, 0x00, 0x20, 0x29, 0x13, 0x01, 0x00, 0x00, 0, 1, 2, 3, 0xF7]
        #expect(DeviceInquiry.parseReply(reply) == .init(manufacturer: [0x00, 0x20, 0x29], family: [0x13, 0x01]))
    }
}
