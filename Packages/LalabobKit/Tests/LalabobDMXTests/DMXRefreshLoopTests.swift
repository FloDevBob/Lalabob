import Testing

@testable import LalabobDMX

@Suite("Boucle de rafraîchissement : branchement, débranchement, rebranchement")
struct DMXRefreshLoopTests {
    let start = ContinuousClock.now

    func frame(_ value: UInt8) -> DMXFrame {
        var f = DMXFrame()
        f[1] = value
        return f
    }

    @Test("Aucun boîtier : « aucun boîtier », nouvel essai une fois par seconde seulement")
    func noDevice() {
        let opener = FakeOpener()
        var loop = DMXRefreshLoop(opener: opener, writer: instantWriter)
        let changed1 = loop.step(frame: frame(1), preferredSerial: nil, reselect: false, now: start)
        #expect(changed1)
        #expect(loop.status == .noDevice)
        let changed2 = loop.step(frame: frame(1), preferredSerial: nil, reselect: false, now: start + .milliseconds(500))
        #expect(!changed2)
        #expect(opener.listings == 1)
        _ = loop.step(frame: frame(1), preferredSerial: nil, reselect: false, now: start + .seconds(1))
        #expect(opener.listings == 2)
    }

    @Test("Boîtier branché en cours de route : la trame part dès l'ouverture")
    func plugLater() {
        let opener = FakeOpener()
        var loop = DMXRefreshLoop(opener: opener, writer: instantWriter)
        _ = loop.step(frame: frame(1), preferredSerial: nil, reselect: false, now: start)
        opener.plug([.troupe])
        let changed3 = loop.step(frame: frame(7), preferredSerial: nil, reselect: false, now: start + .seconds(1))
        #expect(changed3)
        #expect(loop.status == .connected(.troupe))
        #expect(opener.lines.first?.writes == [frame(7).packet])
    }

    @Test("Chaque pas renvoie la trame en cours (le Mac fabrique le signal en continu)")
    func continuousRefresh() {
        let opener = FakeOpener(ports: [.troupe])
        var loop = DMXRefreshLoop(opener: opener, writer: instantWriter)
        for i in 0..<3 {
            _ = loop.step(frame: frame(UInt8(i)), preferredSerial: nil, reselect: false, now: start + .milliseconds(33 * i))
        }
        #expect(opener.lines.count == 1)
        #expect(opener.lines[0].writes == [frame(0).packet, frame(1).packet, frame(2).packet])
    }

    @Test("Débranché en jouant : ligne fermée, état « en erreur », puis la trame en cours repart au rebranchement")
    func unplugAndReplug() {
        let opener = FakeOpener(ports: [.troupe])
        var loop = DMXRefreshLoop(opener: opener, writer: instantWriter)
        _ = loop.step(frame: frame(1), preferredSerial: nil, reselect: false, now: start)
        let first = opener.lines[0]
        first.failWrites()
        opener.plug([])
        let changed4 = loop.step(frame: frame(2), preferredSerial: nil, reselect: false, now: start + .milliseconds(33))
        #expect(changed4)
        #expect(first.isClosed)
        guard case .failed(let port, _) = loop.status else {
            Issue.record("état attendu : en erreur, obtenu \(loop.status)")
            return
        }
        #expect(port == .troupe)

        // Rebranché : rien avant une seconde, puis réouverture et renvoi de la trame en cours.
        opener.plug([.troupe])
        _ = loop.step(frame: frame(3), preferredSerial: nil, reselect: false, now: start + .milliseconds(500))
        #expect(opener.lines.count == 1)
        _ = loop.step(frame: frame(4), preferredSerial: nil, reselect: false, now: start + .milliseconds(1100))
        #expect(loop.status == .connected(.troupe))
        #expect(opener.lines.count == 2)
        #expect(opener.lines[1].writes == [frame(4).packet])
    }

    @Test("Ouverture refusée (port pris par une autre app) : « en erreur », nouvel essai après une seconde")
    func openRefused() {
        let opener = FakeOpener(ports: [.troupe])
        opener.refuseOpening(true)
        var loop = DMXRefreshLoop(opener: opener, writer: instantWriter)
        _ = loop.step(frame: frame(1), preferredSerial: nil, reselect: false, now: start)
        #expect(loop.status == .failed(.troupe, "Resource busy"))
        opener.refuseOpening(false)
        _ = loop.step(frame: frame(1), preferredSerial: nil, reselect: false, now: start + .seconds(1))
        #expect(loop.status == .connected(.troupe))
    }

    @Test("Le boîtier choisi est préféré ; changer de choix ferme l'ancien et ouvre le nouveau tout de suite")
    func reselect() {
        let opener = FakeOpener(ports: [.troupe, .spare])
        var loop = DMXRefreshLoop(opener: opener, writer: instantWriter)
        _ = loop.step(frame: frame(1), preferredSerial: "B0001", reselect: false, now: start)
        #expect(loop.status == .connected(.spare))
        _ = loop.step(frame: frame(1), preferredSerial: "AU0483EN", reselect: true, now: start + .milliseconds(33))
        #expect(opener.lines[0].isClosed)
        #expect(loop.status == .connected(.troupe))
        #expect(opener.lines[1].port == .troupe)
        #expect(opener.lines[1].writes.count == 1)
    }

    @Test("Fermer la boucle ferme la ligne")
    func closeLine() {
        let opener = FakeOpener(ports: [.troupe])
        var loop = DMXRefreshLoop(opener: opener, writer: instantWriter)
        _ = loop.step(frame: frame(1), preferredSerial: nil, reselect: false, now: start)
        loop.close()
        #expect(opener.lines[0].isClosed)
        #expect(loop.status == .stopped)
    }
}
