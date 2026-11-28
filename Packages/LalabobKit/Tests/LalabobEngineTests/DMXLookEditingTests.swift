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

    @Test("La couleur du pad suit la roue, d'une seule annulation ; le fondu ne la change pas")
    func padTintFollowsColor() {
        let (rig, undo) = makeRig()
        #expect(rig.controller.pad(at: red0)?.tint == .rouge)
        #expect(rig.controller.setLook(at: red0, to: LightLook.uniform(color: LightColor(hue: 120, saturation: 1), intensity: 1, headCount: 4)))
        #expect(rig.controller.pad(at: red0)?.tint == .vert)
        rig.controller.updatePad(at: red0, tint: .rose)
        var longer = rig.controller.effectiveLook(at: red0)!
        longer.fadeIn = 3
        rig.controller.setLook(at: red0, to: longer)
        #expect(rig.controller.pad(at: red0)?.tint == .rose)
        undo.undo()
        undo.undo()
        #expect(rig.controller.pad(at: red0)?.tint == .vert)
        undo.undo()
        #expect(rig.controller.pad(at: red0)?.tint == .rouge)
    }

    @Test("Libellé automatique : titre d'ambiance et couleur en sous-titre, sans écraser un texte tapé")
    func autoLabel() {
        let (rig, undo) = makeRig()
        rig.controller.updatePad(at: red0, title: LightLook.blankTitle, subtitle: "")
        let green = LightLook.uniform(color: LightColor(hue: 120, saturation: 1), intensity: 1, headCount: 4)
        #expect(rig.controller.setLook(at: red0, to: green))
        #expect(rig.controller.pad(at: red0)?.title == "Forêt")
        #expect(rig.controller.pad(at: red0)?.subtitle == "Vert")
        // Le libellé suit la couleur tant qu'on n'y touche pas.
        #expect(rig.controller.setLook(at: red0, to: LightLook.uniform(color: LightColor(hue: 225, saturation: 1), intensity: 1, headCount: 4)))
        #expect(rig.controller.pad(at: red0)?.title == "Nuit")
        // Un titre tapé à la main reste ; le sous-titre automatique, lui, continue de suivre.
        rig.controller.updatePad(at: red0, title: "Entrée du roi")
        #expect(rig.controller.setLook(at: red0, to: LightLook.uniform(color: LightColor(hue: 0, saturation: 1), intensity: 1, headCount: 4)))
        #expect(rig.controller.pad(at: red0)?.title == "Entrée du roi")
        #expect(rig.controller.pad(at: red0)?.subtitle == "Rouge")
        // Un seul ⌘Z défait couleur, teinte et libellé ensemble.
        undo.undo()
        #expect(rig.controller.pad(at: red0)?.title == "Entrée du roi")
        #expect(rig.controller.pad(at: red0)?.subtitle == "Bleu")
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

/// Rôle des faders des colonnes lumière (étape 4d).
@MainActor
@Suite("Rôle des faders lumière")
struct DMXFaderRoleTests {
    let session = DMXSessionTests()

    @Test("Par défaut : 1re colonne lumière = Général, 2e = Couleurs")
    func defaults() {
        let rig = session.makeRig()
        let grid = rig.controller.currentGrid
        #expect(DMXFaderRole.roles(for: grid) == [6: .general, 7: .colors])
    }

    @Test("Changer le rôle de la 2e colonne en Strobo, d'une seule annulation")
    func changeRole() {
        let rig = session.makeRig()
        let undo = UndoManager()
        undo.groupsByEvent = false
        rig.controller.undoManager = undo
        #expect(rig.controller.setFaderRole(column: 7, to: .strobeSpeed))
        #expect(DMXFaderRole.roles(for: rig.controller.currentGrid)[7] == .strobeSpeed)
        undo.undo()
        #expect(DMXFaderRole.roles(for: rig.controller.currentGrid)[7] == .colors)
    }

    @Test("Aucun : le fader ne règle plus rien")
    func noRole() {
        let rig = session.makeRig()
        #expect(rig.controller.setFaderRole(column: 7, to: .none))
        #expect(DMXFaderRole.roles(for: rig.controller.currentGrid)[7] == nil)
    }

    @Test("Une colonne qui prend un rôle déjà tenu reprend son niveau : la lumière ne bouge pas")
    func adoptsLevel() {
        let rig = session.makeRig()
        rig.controller.setLightFader(column: 6, level: 0.4)  // Général à 40 %
        #expect(rig.controller.setFaderRole(column: 7, to: .general))
        #expect(rig.controller.currentGrid.columns[7].level == 0.4)
        // Même rôle = même réglage : bouger l'un bouge l'autre.
        rig.controller.setLightFader(column: 7, level: 0.9)
        #expect(rig.controller.currentGrid.columns[6].level == 0.9)
    }

    @Test("Une colonne son n'a pas de rôle ; verrouillé, refusé")
    func refused() {
        let rig = session.makeRig()
        #expect(!rig.controller.setFaderRole(column: 0, to: .general))
        let locked = session.makeRig(locked: true)
        #expect(!locked.controller.setFaderRole(column: 7, to: .none))
    }

    @Test("La console suit le rôle choisi : fader 7 réglé en Strobo")
    func consoleFollowsRole() {
        let rig = session.makeRig()
        rig.controller.setFaderRole(column: 7, to: .strobeSpeed)
        rig.controller.setLightFader(column: 7, level: 0.5)
        #expect(rig.session.console?.strobeOverride == 0.5)
    }
}

@Suite("Tempo de l'alternance affiché")
struct AlternationInfoTests {
    func console(playing content: LightLook.Content?) -> LightConsole {
        var console = LightConsole(rig: DMXRig(address: 1))
        if let content { console.play(LightLook(fadeIn: 0, content: content), pad: UUID(), at: 0) }
        return console
    }

    @Test("Alternance au tempo de repli : 120 BPM, le point bat sur le temps")
    func fallbackTempo() {
        let red = LightColor(hue: 0, saturation: 1)
        let content = LightLook.Content.alternate(
            AlternateLook(a: red, b: .white, every: .beat, switchFade: 0, fallbackBPM: 120))
        let console = console(playing: content)
        #expect(console.alternationInfo(at: 0.1)?.bpm == 120)
        #expect(console.alternationInfo(at: 0.1)?.onBeat == true)  // le temps dure 0,5 s
        #expect(console.alternationInfo(at: 0.4)?.onBeat == false)
    }

    @Test("Le tempo du son en cours prime sur le repli")
    func soundTempoWins() {
        let content = LightLook.Content.alternate(
            AlternateLook(a: .white, b: .white, every: .beat, switchFade: 0, fallbackBPM: 120))
        var console = console(playing: content)
        console.beatClock = LightConsole.BeatClock(bpm: 90, origin: 0)
        #expect(console.alternationInfo(at: 10)?.bpm == 90)
    }

    @Test("Hors alternance : rien à afficher")
    func notAlternating() {
        #expect(console(playing: nil).alternationInfo(at: 1) == nil)
        #expect(console(playing: .soundActive(sensitivity: 0.5)).alternationInfo(at: 1) == nil)
    }
}
