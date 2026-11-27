import Foundation
import LalabobModel
import Testing

@testable import LalabobEngine

/// Édition des états lumineux d'un pad (J14, étape 4c) : annulable, validée, refusée verrouillé.
@MainActor
@Suite("Édition des états lumineux")
struct DMXLookEditingTests {
    let session = DMXSessionTests()
    let red0 = GridPosition(column: 6, row: 0)
    let bare = GridPosition(column: 7, row: 0)
    let blue = LightColor(hue: 240, saturation: 1)

    func makeRig(locked: Bool = false) -> (rig: DMXSessionTests.Rig, undo: UndoManager) {
        let rig = session.makeRig(locked: locked)
        let undo = UndoManager()
        undo.groupsByEvent = false
        rig.controller.undoManager = undo
        return (rig, undo)
    }

    @Test("setLook remplace l'état du pad, d'une seule annulation")
    func setLookUndo() {
        let (rig, undo) = makeRig()
        let look = LightLook.uniform(color: blue, intensity: 0.5, headCount: 4)
        #expect(rig.controller.setLook(at: red0, to: look))
        #expect(rig.controller.pad(at: red0)?.light?.look == look)
        undo.undo()
        #expect(rig.controller.pad(at: red0)?.light?.look != look)
    }

    @Test("setLook refuse un état injouable (3 projecteurs) et ne change rien")
    func setLookRejectsInvalid() {
        let (rig, _) = makeRig()
        let before = rig.controller.pad(at: red0)
        #expect(!rig.controller.setLook(at: red0, to: LightLook.uniform(color: blue, intensity: 1, headCount: 3)))
        #expect(rig.controller.pad(at: red0) == before)
    }

    @Test("Verrouillé : refusé")
    func setLookLocked() {
        let (rig, _) = makeRig(locked: true)
        #expect(!rig.controller.setLook(at: red0, to: LightLook.uniform(color: blue, intensity: 1, headCount: 4)))
    }

    @Test("Une case qui n'est pas une lumière : refusé")
    func setLookOnSound() {
        let (rig, _) = makeRig()
        #expect(!rig.controller.setLook(at: GridPosition(column: 0, row: 0), to: LightLook.uniform(color: blue, intensity: 1, headCount: 4)))
        #expect(rig.controller.effectiveLook(at: GridPosition(column: 0, row: 0)) == nil)
    }

    @Test("Une cue venue de LightKey (sans état) : le réglage la fait passer à son état propre")
    func bareCueGetsLook() throws {
        let (rig, _) = makeRig()
        #expect(rig.controller.pad(at: bare)?.light?.look == nil)
        let fallback = try #require(rig.controller.effectiveLook(at: bare))
        #expect(fallback.isValid(for: rig.controller.show.lighting.rig.profile))
        #expect(rig.controller.setLookStyle(at: bare, to: .alternate))
        guard case .alternate = rig.controller.pad(at: bare)?.light?.look?.content else {
            Issue.record("l'état n'est pas une alternance")
            return
        }
        // La note MIDI de la cue n'a pas bougé : revenir en mode LightKey ne perd rien.
        #expect(rig.controller.pad(at: bare)?.light?.output.number == 0)
    }

    @Test("setLookStyle : un type que l'appareil ne sait pas jouer est refusé")
    func styleUnsupported() {
        let (rig, _) = makeRig()
        var edited = rig.controller.show.lighting.rig
        edited.profile.programs = nil
        edited.profile.soundActiveValue = nil
        rig.controller.setDMXRig(edited)
        #expect(!rig.controller.setLookStyle(at: red0, to: .fixtureProgram))
        #expect(rig.controller.setLookStyle(at: red0, to: .alternate))
    }

    @Test("Nouvel appui : un pad lumière seul accepte « allume ou éteint »")
    func lightPadRetrigger() {
        let (rig, _) = makeRig()
        #expect(rig.controller.setLightRetrigger(at: red0, to: .toggle))
        #expect(rig.controller.pad(at: red0)?.lightRetrigger == .toggle)
    }

    @Test("Favoris : on garde une couleur, on la retire, plafond de 16")
    func favorites() {
        let (rig, _) = makeRig()
        #expect(rig.controller.toggleFavoriteColor(blue))
        #expect(rig.controller.show.lighting.rig.favoriteColors == [blue])
        #expect(rig.controller.toggleFavoriteColor(blue))
        #expect(rig.controller.show.lighting.rig.favoriteColors.isEmpty)
        for hue in 0..<DMXRig.maximumFavoriteColors {
            #expect(rig.controller.toggleFavoriteColor(LightColor(hue: Double(hue) * 20, saturation: 1)))
        }
        #expect(!rig.controller.toggleFavoriteColor(LightColor(hue: 355, saturation: 0.5)))
    }
}
