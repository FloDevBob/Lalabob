import Foundation
import LalabobDMX
import LalabobModel
import Testing

@testable import LalabobEngine

/// Réglages des projecteurs (J14, étape 4a) : appareil du spectacle, essai en blanc, textes d'état du boîtier.
@MainActor
@Suite("Réglages DMX")
struct DMXSettingsTests {
    @Test("setDMXRig garde l'avance de la lumière, les couleurs favorites et la sortie")
    func rigKeepsEveryField() {
        let rig = DMXSessionTests().makeRig(mode: .lightKey)
        let favorite = LightColor(hue: 30, saturation: 0.8)
        var edited = rig.controller.show.lighting.rig
        edited.address = 50
        edited.lightLead = 0.12
        edited.favoriteColors = [favorite]
        edited.onQuit = .leaveLight
        edited.blackoutFade = 2
        rig.controller.setDMXRig(edited)
        let stored = rig.controller.show.lighting.rig
        #expect(stored.address == 50)
        #expect(stored.lightLead == 0.12)
        #expect(stored.favoriteColors == [favorite])
        #expect(stored.onQuit == .leaveLight)
        #expect(stored.blackoutFade == 2)
    }

    @Test("setDMXRig borne l'adresse au profil et se défait d'un seul ⌘Z")
    func rigAddressClampedAndUndoable() {
        let rig = DMXSessionTests().makeRig(mode: .lightKey)
        let undo = UndoManager()
        undo.groupsByEvent = false
        rig.controller.undoManager = undo
        var edited = rig.controller.show.lighting.rig
        edited.address = 9999
        rig.controller.setDMXRig(edited)
        #expect(rig.controller.show.lighting.rig.address == 498)
        let before = rig.controller.show.lighting.rig
        edited.address = 120
        rig.controller.setDMXRig(edited)
        #expect(rig.controller.show.lighting.rig.address == 120)
        undo.undo()
        #expect(rig.controller.show.lighting.rig == before)
    }

    @Test("« 4 projecteurs en blanc » : la console joue du blanc sans pad ; le Noir l'éteint")
    func whiteTest() {
        let rig = DMXSessionTests().makeRig()
        rig.session.testWhite()
        rig.clock.time += 5
        let frame = rig.frame()
        for head in 1...4 { #expect(DMXSessionTests().headRGB(frame, head: head) == [255, 255, 255]) }
        #expect(rig.session.console?.activePad == nil)
        #expect(rig.controller.dmxActivePad == nil)
    }

    @Test("Sans mode Projecteurs, l'essai en blanc ne fait rien")
    func whiteTestIgnoredInLightKeyMode() {
        let rig = DMXSessionTests().makeRig(mode: .lightKey)
        rig.session.testWhite()
        #expect(rig.session.console == nil)
    }

    @Test("Textes d'état du boîtier")
    func statusText() {
        let port = DMXPortInfo(path: "/dev/cu.usbserial-AU0483EN")
        #expect(DMXStatus.stopped.headline == "Signal arrêté")
        #expect(DMXStatus.noDevice.headline == "Boîtier absent")
        #expect(DMXStatus.connected(port).headline == "Branché")
        #expect(DMXStatus.failed(port, "pris").headline == "En erreur")
        #expect(DMXStatus.failed(port, "pris").detail?.contains("pris") == true)
        #expect(DMXStatus.connected(port).detail == nil)
    }
}
