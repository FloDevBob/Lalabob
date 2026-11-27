import Testing

@testable import LalabobDMX

@Suite("Sortie DMX sur son propre fil")
struct DMXOutputTests {
    /// Attend (au plus 2 s) qu'une condition devienne vraie.
    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test("Démarrée : envoie la dernière trame donnée, en continu, et annonce le boîtier branché")
    func sendsLatestFrame() async {
        let opener = FakeOpener(ports: [.troupe])
        let output = DMXOutput(opener: opener, writer: instantWriter, rate: 44)
        #expect(output.status == .stopped)
        var frame = DMXFrame()
        frame[3] = 200
        output.setFrame(frame)
        output.start()
        #expect(await eventually { (opener.lines.first?.writes.count ?? 0) >= 3 })
        #expect(opener.lines.first?.writes.last == frame.packet)
        #expect(output.status == .connected(.troupe))

        var statuses = output.statusUpdates.makeAsyncIterator()
        #expect(await statuses.next() == .connected(.troupe))
        await output.shutdown(finalFrame: nil)
    }

    @Test("Arrêt : la trame finale (noir) part plusieurs fois, puis le port est fermé")
    func shutdownSendsFinalFrame() async {
        let opener = FakeOpener(ports: [.troupe])
        let output = DMXOutput(opener: opener, writer: instantWriter, rate: 44)
        var lit = DMXFrame()
        lit[2] = 255
        output.setFrame(lit)
        output.start()
        #expect(await eventually { !(opener.lines.first?.writes.isEmpty ?? true) })
        await output.shutdown(finalFrame: DMXFrame())
        let line = opener.lines[0]
        #expect(line.isClosed)
        #expect(line.writes.suffix(DMXOutput.finalFrameRepeats) == Array(repeating: DMXFrame().packet, count: DMXOutput.finalFrameRepeats))
        #expect(output.status == .stopped)
        // Plus rien ne part ensuite.
        let count = line.writes.count
        try? await Task.sleep(for: .milliseconds(80))
        #expect(line.writes.count == count)
    }

    @Test("Arrêter une sortie jamais démarrée ne bloque pas")
    func shutdownWithoutStart() async {
        let output = DMXOutput(opener: FakeOpener(), writer: instantWriter)
        await output.shutdown(finalFrame: DMXFrame())
        #expect(output.status == .stopped)
    }

    @Test("La cadence est bornée à 1…44 Hz (44 = trame complète de 512 canaux)")
    func rateClamped() {
        #expect(DMXOutput(opener: FakeOpener(), rate: 500).rate == 44)
        #expect(DMXOutput(opener: FakeOpener(), rate: 0).rate == 1)
        #expect(DMXOutput(opener: FakeOpener()).rate == 30)
    }

    @Test("SilentDMX garde la dernière trame et ne touche à aucun port")
    func silent() async {
        let silent = SilentDMX()
        var frame = DMXFrame()
        frame[1] = 9
        silent.start()
        silent.setFrame(frame)
        #expect(silent.lastFrame == frame)
        #expect(silent.availablePorts().isEmpty)
        await silent.shutdown(finalFrame: DMXFrame())
        #expect(silent.lastFrame == DMXFrame())
        #expect(silent.status == .stopped)
    }
}
