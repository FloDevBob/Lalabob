import Foundation
import LalabobDMX
import Testing

@testable import LalabobEngine

@MainActor
@Suite("Banc d'essai DMX")
struct DMXTestBenchTests {
    final class Factory {
        var made: [SilentDMX] = []
        func make() -> any DMXTransport {
            let silent = SilentDMX()
            made.append(silent)
            return silent
        }
    }

    func makeBench() -> (DMXTestBench, Factory, UserDefaults) {
        let defaults = UserDefaults(suiteName: "DMXTestBenchTests-\(UUID().uuidString)")!
        let factory = Factory()
        return (DMXTestBench(defaults: defaults, makeTransport: factory.make), factory, defaults)
    }

    @Test("Les 15 canaux de la barre, posés à l'adresse choisie")
    func framePlacedAtAddress() {
        let (bench, factory, _) = makeBench()
        bench.open()
        bench.address = 50
        bench.setValue(200, at: 3)  // projecteur 1, rouge
        let frame = factory.made[0].lastFrame
        #expect(frame.length == 64)
        #expect(frame[50] == 0)  // programme 0 : pilotage DMX direct
        #expect(frame[51] == 255)  // gradateur général à 100 % au départ
        #expect(frame[53] == 200)
        #expect(frame[1] == 0)
    }

    @Test("Nommage des canaux d'après le manuel de la barre")
    func channelNames() {
        #expect(DMXTestBench.channelNames.count == 15)
        #expect(DMXTestBench.channelNames[1] == "Gradateur général")
        #expect(DMXTestBench.channelNames[14] == "Projecteur 4 · bleu")
    }

    @Test("Blanc puis noir")
    func whiteAndBlack() {
        let (bench, factory, _) = makeBench()
        bench.open()
        bench.white()
        #expect(bench.values == [0, 255, 0] + [UInt8](repeating: 255, count: 12))
        bench.black()
        #expect(bench.values == [UInt8](repeating: 0, count: 15))
        #expect(factory.made[0].lastFrame == {
            var f = DMXFrame()
            f.set([UInt8](repeating: 0, count: 15), from: 1)
            return f
        }())
    }

    @Test("Adresse bornée à 1…498 et retenue sur ce Mac")
    func addressClampedAndRemembered() {
        let (bench, factory, defaults) = makeBench()
        bench.address = 600
        #expect(bench.address == 498)
        bench.address = 0
        #expect(bench.address == 1)
        bench.address = 50
        let again = DMXTestBench(defaults: defaults, makeTransport: factory.make)
        #expect(again.address == 50)
    }

    @Test("Ouvrir démarre une sortie neuve, fermer l'arrête sans noir (la barre garde sa couleur)")
    func openClose() async {
        let (bench, factory, _) = makeBench()
        bench.open()
        bench.open()
        #expect(factory.made.count == 1)
        #expect(factory.made[0].status == .noDevice)
        bench.white()
        await bench.close()
        #expect(factory.made[0].status == .stopped)
        #expect(factory.made[0].lastFrame[2] == 255)
        bench.open()
        #expect(factory.made.count == 2)
        #expect(factory.made[1].lastFrame[2] == 255)  // la trame en cours repart
    }
}
