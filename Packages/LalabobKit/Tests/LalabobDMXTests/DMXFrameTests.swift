import Testing

@testable import LalabobDMX

@Suite("Trame DMX")
struct DMXFrameTests {
    @Test("Une trame neuve : 24 canaux à zéro, code de départ 0 en tête du paquet")
    func emptyFrame() {
        let frame = DMXFrame()
        #expect(frame.length == DMXFrame.minimumLength)
        #expect(frame.values == [UInt8](repeating: 0, count: 24))
        #expect(frame.packet.count == 25)
        #expect(frame.packet.first == 0)
    }

    @Test("Les canaux sont numérotés à partir de 1")
    func oneBasedChannels() {
        var frame = DMXFrame()
        frame[1] = 10
        frame[24] = 240
        #expect(frame.values.first == 10)
        #expect(frame.values.last == 240)
        #expect(frame[1] == 10)
        #expect(frame[2] == 0)
        #expect(frame.packet[1] == 10)
    }

    @Test("Écrire au-delà de la longueur allonge la trame, jusqu'à 512")
    func growsToHighestChannel() {
        var frame = DMXFrame()
        frame[64] = 255
        #expect(frame.length == 64)
        frame[512] = 1
        #expect(frame.length == 512)
        #expect(frame[512] == 1)
    }

    @Test("Canaux hors de 1…512 : ignorés, lus à 0")
    func outOfRangeChannels() {
        var frame = DMXFrame()
        frame[0] = 99
        frame[513] = 99
        frame[-4] = 99
        #expect(frame == DMXFrame())
        #expect(frame[0] == 0)
        #expect(frame[600] == 0)
    }

    @Test("Longueur demandée bornée à 24…512")
    func clampedLength() {
        #expect(DMXFrame(length: 3).length == 24)
        #expect(DMXFrame(length: 15 + 49).length == 64)
        #expect(DMXFrame(length: 10_000).length == 512)
    }

    @Test("Placer les 15 canaux de la barre à l'adresse 50 (relevé du 27/11/2026)")
    func placeBarAtAddress() {
        var frame = DMXFrame()
        let bar: [UInt8] = [0, 255, 0] + [UInt8](repeating: 255, count: 12)
        frame.set(bar, from: 50)
        #expect(frame.length == 64)
        #expect(frame[49] == 0)
        #expect(frame[50] == 0)  // programme 0 = pilotage DMX direct
        #expect(frame[51] == 255)  // gradateur général
        #expect(frame[64] == 255)  // bleu du projecteur 4
    }

    @Test("Ce qui dépasse le canal 512 est coupé")
    func placeClipsAtEnd() {
        var frame = DMXFrame()
        frame.set([1, 2, 3, 4], from: 510)
        #expect(frame.length == 512)
        #expect(frame[510] == 1)
        #expect(frame[512] == 3)
    }
}
