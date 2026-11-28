import Testing

@testable import LalabobDMX

@Suite("Signal Open DMX (le Mac fabrique le signal)")
struct OpenDMXWriterTests {
    @Test("Une trame = break ≥ 88 µs, mark ≥ 8 µs, code de départ + canaux, puis attente de l'envoi")
    func frameSequence() throws {
        let line = FakeLine(port: .troupe)
        let writer = OpenDMXWriter(pause: { line.record(.pause($0)) })
        var frame = DMXFrame()
        frame[2] = 255
        try writer.send(frame, on: line)
        #expect(line.ops == [.breakOn, .pause(.microseconds(120)), .breakOff, .pause(.microseconds(16)), .write(frame.packet), .drain])
        #expect(OpenDMXWriter.breakDuration >= .microseconds(88))
        #expect(OpenDMXWriter.markAfterBreak >= .microseconds(8))
    }

    @Test("Octets envoyés pour « banc-dmx blanc » à l'adresse 1 (relevé du 27/11/2026)")
    func recordedWhiteBytes() throws {
        let line = FakeLine(port: .troupe)
        var frame = DMXFrame()
        frame.set([0, 255, 0] + [UInt8](repeating: 255, count: 12), from: 1)
        try instantWriter.send(frame, on: line)
        let expected: [UInt8] = [0x00, 0x00, 0xFF, 0x00] + [UInt8](repeating: 0xFF, count: 12) + [UInt8](repeating: 0, count: 9)
        #expect(line.writes == [expected])
    }

    @Test("Une écriture refusée remonte l'erreur, le break a été relâché")
    func writeFailure() {
        let line = FakeLine(port: .troupe)
        line.failWrites()
        #expect(throws: DMXError.self) { try instantWriter.send(DMXFrame(), on: line) }
        #expect(line.ops == [.breakOn, .breakOff])
    }
}
