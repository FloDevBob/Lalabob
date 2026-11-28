import Foundation
import Synchronization
import Testing

@testable import LalabobDMX

/// Source de trames (J14, étape 3) : la console calcule la trame à chaque rafraîchissement, sur le fil DMX ; un fondu
/// avance donc même si l'interface rame.
@Suite("Source de trames DMX")
struct DMXFrameSourceTests {
    /// Trame dont le canal 1 vaut le nombre de dixièmes de seconde écoulés (borné à 255).
    struct Ramp: DMXFrameSource {
        let origin: Double
        func frame(at time: Double) -> DMXFrame {
            var frame = DMXFrame()
            frame[1] = UInt8(min(max((time - origin) * 10, 0), 255))
            return frame
        }
    }


    @Test("L'horloge DMX avance")
    func clockAdvances() async throws {
        let a = DMXClock.now()
        try await Task.sleep(for: .milliseconds(20))
        #expect(DMXClock.now() > a)
    }

    @Test("SilentDMX : une source donne la trame à l'instant demandé ; une trame fixe la remplace")
    func silentSource() {
        let silent = SilentDMX()
        silent.setSource(Ramp(origin: 0))
        #expect(silent.frame(at: 1.5)[1] == 15)
        var fixed = DMXFrame()
        fixed[1] = 7
        silent.setFrame(fixed)
        #expect(silent.frame(at: 1.5)[1] == 7)
        #expect(silent.lastFrame == fixed)
    }

    @Test("DMXOutput : la trame envoyée est recalculée par la source à chaque rafraîchissement")
    func outputRendersSource() async {
        let opener = FakeOpener(ports: [.troupe])
        let output = DMXOutput(opener: opener, writer: instantWriter, rate: 44)
        output.setSource(Ramp(origin: DMXClock.now()))
        output.start()
        var changed = false
        for _ in 0..<200 {
            let writes = opener.lines.first?.writes ?? []
            if Set(writes.map { $0[1] }).count >= 3 { changed = true; break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(changed)
        await output.shutdown(finalFrame: nil)
    }
}
