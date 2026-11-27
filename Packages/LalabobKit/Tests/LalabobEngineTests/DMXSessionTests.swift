import ControllerDrivers
import Foundation
import LalabobAudio
import LalabobDMX
import LalabobModel
import Testing

@testable import LalabobEngine

/// Branchement de la console DMX sur le spectacle (J14, étape 3) : appuis, Noir, faders à rôle, état des pads, fermeture.
@MainActor
@Suite("Session DMX")
struct DMXSessionTests {
    final class Clock {
        var time = 100.0
    }

    final class Factory {
        var made: [SilentDMX] = []
        func make() -> any DMXTransport {
            let silent = SilentDMX()
            made.append(silent)
            return silent
        }
    }

    static let red = LightColor(hue: 0, saturation: 1)
    static let blue = LightColor(hue: 240, saturation: 1)

    let redPad = Pad(
        title: "Rouge", tint: .rouge, light: LightCue(look: LightLook.uniform(color: red, intensity: 1, headCount: 4)))
    let bluePad = Pad(
        title: "Bleu", tint: .azur, light: LightCue(look: LightLook.uniform(color: blue, intensity: 1, headCount: 4)))
    /// Cue créée pour LightKey, sans état lumineux : jouée à la couleur du pad.
    let bareCue = Pad(title: "Nu", tint: .vert, light: LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 0)))
    let sound = Pad(title: "Son", tint: .ciel, audio: AudioClip(fileName: "a.wav"))

    struct Rig {
        let controller: ShowController
        let session: DMXSession
        let factory: Factory
        let clock: Clock
        var transport: SilentDMX { factory.made.last! }
        func frame(after seconds: Double = 0) -> DMXFrame { transport.frame(at: clock.time + seconds) }
    }

    func makeRig(mode: LightingMode = .dmx, onQuit: DMXRig.QuitBehavior = .fadeToBlack, locked: Bool = false) -> Rig {
        var grid = PadGrid.empty(name: "G")
        grid.columns[0].slots[0] = sound
        grid.columns[6].slots[0] = redPad
        grid.columns[6].slots[1] = bluePad
        grid.columns[7].slots[0] = bareCue
        var show = Show(name: "S", grids: [grid])
        show.lighting = LightingSettings(mode: mode, rig: DMXRig(address: 1, blackoutFade: 0, onQuit: onQuit))
        let defaults = UserDefaults(suiteName: "DMXSessionTests-\(UUID().uuidString)")!
        let controller = ShowController(show: show, defaults: defaults, isLocked: locked)
        let clock = Clock()
        let factory = Factory()
        let session = DMXSession(defaults: defaults, now: { clock.time }, makeTransport: { factory.make() })
        session.attach(controller)
        return Rig(controller: controller, session: session, factory: factory, clock: clock)
    }

    func headRGB(_ frame: DMXFrame, head: Int) -> [UInt8] {
        let first = 1 + 3 + (head - 1) * 3
        return [frame[first], frame[first + 1], frame[first + 2]]
    }

    let red0 = GridPosition(column: 6, row: 0)
    let blue1 = GridPosition(column: 6, row: 1)
    let bare = GridPosition(column: 7, row: 0)

    // MARK: - Mode

    @Test("Mode LightKey : aucune sortie DMX, rien n'est piloté")
    func lightKeyMode() {
        let rig = makeRig(mode: .lightKey)
        #expect(rig.factory.made.isEmpty)
        #expect(rig.session.console == nil)
        rig.controller.audition(at: red0)
        #expect(rig.session.console == nil)
        #expect(rig.controller.lightState(at: red0) == .unknown)
    }

    @Test("Mode Projecteurs : la sortie démarre, noire, avec le boîtier choisi sur ce Mac")
    func dmxModeStarts() {
        let rig = makeRig()
        #expect(rig.factory.made.count == 1)
        #expect(rig.session.status == .noDevice)
        #expect(rig.session.console?.isBlack == true)
        #expect(headRGB(rig.frame(), head: 1) == [0, 0, 0])
    }

    @Test("Repasser en LightKey arrête la sortie DMX (sans noir) ; revenir en Projecteurs la relance")
    func switchMode() async {
        let rig = makeRig()
        rig.controller.setLightingMode(.lightKey)
        #expect(rig.session.console == nil)
        let first = rig.factory.made[0]
        #expect(await waitUntil { first.status == .stopped })
        rig.controller.setLightingMode(.dmx)
        #expect(rig.factory.made.count == 2)
        #expect(rig.session.console != nil)
    }

    // MARK: - Jeu

    @Test("Double-clic sur un pad lumière : son état part, en fondu ; le pad est allumé, les autres éteints")
    func playLook() {
        let rig = makeRig()
        rig.controller.audition(at: red0)
        #expect(rig.session.console?.activePad == redPad.id)
        #expect(headRGB(rig.frame(after: LightLook.defaultFadeIn), head: 1) == [255, 0, 0])
        #expect(rig.controller.lightState(at: red0) == .on)
        #expect(rig.controller.lightState(at: blue1) == .off)
        #expect(rig.controller.ledStates[red0] == .pulsing(.rouge))
    }

    @Test("Une cue sans état lumineux joue les 4 projecteurs à la couleur du pad")
    func bareCueUsesTint() {
        let rig = makeRig()
        rig.controller.audition(at: bare)
        let rgb = headRGB(rig.frame(after: 5), head: 1)
        #expect(rgb[1] > rgb[0] && rgb[1] > rgb[2])  // vert
    }

    @Test("Nouvel appui : « laisse allumé » ne change rien ; « allume ou éteint » éteint en fondu")
    func retrigger() {
        let rig = makeRig()
        rig.controller.audition(at: red0)
        rig.clock.time += 5
        rig.controller.audition(at: red0)
        #expect(rig.session.console?.activePad == redPad.id)

        var grid = rig.controller.currentGrid
        grid.columns[6].slots[0]?.lightRetrigger = .toggle
        var show = rig.controller.show
        show.grids[0] = grid
        rig.controller.replaceShow(show)
        rig.controller.audition(at: red0)
        #expect(rig.session.console?.activePad == nil)
        #expect(rig.controller.lightState(at: red0) == .off)
    }

    @Test("Essayer (bouton du panneau) rejoue l'état même s'il est déjà allumé")
    func testCueForces() {
        let rig = makeRig()
        rig.controller.audition(at: red0)
        rig.clock.time += 10
        rig.controller.testCue(at: red0)
        // Rejoué : un nouveau fondu part du rouge vers le rouge (aucun saut), le pad reste actif.
        #expect(rig.session.console?.activePad == redPad.id)
    }

    @Test("Contrôleur : un appui sur une colonne lumière joue l'état, rien n'est relayé à LightKey")
    func controllerRouting() {
        let rig = makeRig()
        let press = rig.controller.controllerPress(at: red0)
        #expect(press.relaysLight == false)
        #expect(press.playsLight)
        #expect(!press.playsSound)
        rig.controller.pressLightFromController(at: red0)
        #expect(rig.session.console?.activePad == redPad.id)
        // Case vide d'une colonne lumière : rien.
        let empty = rig.controller.controllerPress(at: GridPosition(column: 6, row: 5))
        #expect(!empty.playsLight && !empty.relaysLight)
    }

    @Test("Verrouillé, on joue toujours la lumière")
    func lockedPlays() {
        let rig = makeRig(locked: true)
        rig.controller.audition(at: blue1)
        #expect(rig.session.console?.activePad == bluePad.id)
    }

    @Test("Tout arrêter (Échap) ne touche pas la lumière")
    func stopAllKeepsLight() {
        let rig = makeRig()
        rig.controller.audition(at: red0)
        rig.controller.stopAll()
        #expect(rig.session.console?.activePad == redPad.id)
    }

    // MARK: - Noir et boutons ronds

    @Test("Bouton rond d'une colonne lumière (APC) : Noir en fondu ; sa LED est rouge comme celle des colonnes son")
    func columnStopIsBlackout() {
        let rig = makeRig()
        #expect(rig.controller.stopButtonColumns.isSuperset(of: [0, 6, 7]))
        rig.controller.audition(at: red0)
        rig.controller.stopColumn(6)
        #expect(rig.session.console?.isBlack == true)
        #expect(rig.controller.lightState(at: red0) == .off)
    }

    @Test("En mode LightKey, les colonnes lumière n'ont pas de bouton stop")
    func lightKeyStopButtons() {
        let rig = makeRig(mode: .lightKey)
        #expect(!rig.controller.stopButtonColumns.contains(6))
    }

    @Test("Noir à l'écran, même verrouillé")
    func blackoutLocked() {
        let rig = makeRig(locked: true)
        rig.controller.audition(at: red0)
        rig.controller.blackout()
        #expect(rig.session.console?.isBlack == true)
    }

    @Test("Mini-barre : un projecteur s'éteint à la main sans changer le pad actif")
    func headToggle() {
        let rig = makeRig()
        rig.controller.audition(at: red0)
        rig.clock.time += 5
        rig.session.setHead(0, on: false)
        #expect(headRGB(rig.frame(after: 1), head: 1) == [0, 0, 0])
        #expect(headRGB(rig.frame(after: 1), head: 2) == [255, 0, 0])
        #expect(rig.session.console?.activePad == redPad.id)
    }

    // MARK: - Faders à rôle

    @Test("Faders : 1re colonne lumière = Général, 2e = Couleurs ; à l'écran comme à la main")
    func faderRoles() {
        let rig = makeRig()
        #expect(DMXFaderRole.roles(for: rig.controller.currentGrid) == [6: .general, 7: .colors])
        rig.controller.setLightFader(column: 6, level: 0.5)
        #expect(rig.session.console?.master == 0.5)
        rig.controller.setLightFader(column: 7, level: 0.25)
        #expect(rig.session.console?.colorFader == 0.25)
        rig.controller.moveHardwareFader(column: 6, value: 0.5)  // rejoint la valeur de l'écran : il prend la main
        rig.controller.moveHardwareFader(column: 6, value: 0.2)
        #expect(abs((rig.session.console?.master ?? 0) - Gain.faderLevel(0.2)) < 0.001)
        #expect(rig.frame()[2] == UInt8((255 * Gain.faderLevel(0.2)).rounded()))
    }

    @Test("Un seul Général pour le spectacle : changer de grille ne change pas la lumière")
    func generalSharedAcrossGrids() {
        let rig = makeRig()
        rig.controller.addGrid()
        rig.controller.selectGrid(at: 0)
        rig.controller.setLightFader(column: 6, level: 0.3)
        rig.controller.setLightFader(column: 7, level: 0.6)
        rig.controller.selectGrid(at: 1)
        #expect(rig.controller.currentGrid.columns[6].level == 0.3)
        #expect(rig.controller.currentGrid.columns[7].level == 0.6)
        #expect(rig.session.console?.master == 0.3)
    }

    @Test("Passer en Projecteurs aligne les faders à rôle de toutes les grilles sur la grille affichée")
    func switchingAlignsFaders() {
        let rig = makeRig(mode: .lightKey)
        rig.controller.addGrid()
        rig.controller.selectGrid(at: 1)
        rig.controller.setLightFader(column: 6, level: 0.4)  // LightKey : propre à la grille
        rig.controller.selectGrid(at: 0)
        #expect(rig.controller.currentGrid.columns[6].level == 1)
        rig.controller.selectGrid(at: 1)
        rig.controller.setLightingMode(.dmx)
        #expect(rig.controller.show.grids[0].columns[6].level == 0.4)
    }

    // MARK: - Banc d'essai

    @Test("Le banc d'essai prend le boîtier : la sortie du spectacle s'arrête, la console continue, puis tout revient")
    func benchTakesOver() async {
        let rig = makeRig()
        rig.controller.audition(at: red0)
        rig.session.suspendForBench()
        #expect(rig.session.isSuspendedForBench)
        let first = rig.factory.made[0]
        #expect(await waitUntil { first.status == .stopped })
        rig.controller.audition(at: blue1)  // on joue toujours : la console suit
        #expect(rig.session.console?.activePad == bluePad.id)
        #expect(rig.factory.made.count == 1)  // rien ne reprend le boîtier tant que le banc est ouvert
        rig.session.resumeAfterBench()
        #expect(rig.factory.made.count == 2)
        #expect(headRGB(rig.frame(after: 5), head: 1) == [0, 0, 255])
    }

    @Test("Le banc prévient avant de prendre le boîtier et après l'avoir rendu")
    func benchHooks() async {
        let bench = DMXTestBench(
            defaults: UserDefaults(suiteName: "DMXSessionTests-\(UUID().uuidString)")!, makeTransport: { SilentDMX() })
        var events: [String] = []
        bench.willOpen = { events.append("open") }
        bench.didClose = { events.append("close") }
        bench.open()
        await bench.close()
        #expect(events == ["open", "close"])
    }

    @Test("Sans colonne lumière, le général reste à fond")
    func noGeneralColumn() {
        var grid = PadGrid.empty(name: "G")
        grid.columns[6] = Column.empty(name: "6", kind: .audio)
        grid.columns[7] = Column.empty(name: "7", kind: .audio)
        #expect(DMXFaderRole.roles(for: grid).isEmpty)
    }

    // MARK: - Appairage

    @Test("Relier aux projecteurs (LightKey) est refusé en mode DMX")
    func pairingRefused() {
        let rig = makeRig()
        rig.controller.setPairingLights(true)
        #expect(!rig.controller.isPairingLights)
    }

    // MARK: - Fermeture

    @Test("En quittant, « fondu au noir » : la dernière trame est noire")
    func shutdownBlack() async {
        let rig = makeRig(onQuit: .fadeToBlack)
        rig.controller.audition(at: red0)
        await rig.session.shutdown()
        #expect(rig.transport.status == .stopped)
        #expect(headRGB(rig.transport.lastFrame, head: 1) == [0, 0, 0])
    }

    @Test("En quittant, « laisser la lumière » : rien n'est éteint")
    func shutdownLeave() async {
        let rig = makeRig(onQuit: .leaveLight)
        rig.controller.audition(at: red0)
        rig.clock.time += 5
        let lit = rig.frame()
        await rig.session.shutdown()
        #expect(rig.transport.status == .stopped)
        #expect(headRGB(lit, head: 1) == [255, 0, 0])
        #expect(headRGB(rig.transport.frame(at: rig.clock.time), head: 1) == [255, 0, 0])
    }
}
