import ControllerDrivers
import Foundation
import LalabobAudio
import LalabobMIDI
import LalabobModel
import Testing

@testable import LalabobEngine

/// Mode « Appairage lumière » : la case cible est appairée quand LightKey répond (ou sur confirmation), puis nommée.
@MainActor
@Suite("Appairage lumière", .serialized)
struct LightPairingTests {
    static let first = GridPosition(column: 6, row: 0)
    static let second = GridPosition(column: 6, row: 1)
    static let sound = GridPosition(column: 0, row: 0)

    private func makeController(locked: Bool = false) -> (ShowController, UndoManager) {
        var grid = PadGrid.empty(name: "G")
        grid[Self.sound] = Pad(title: "Rire", tint: .vert, content: .audio(clip: AudioClip(fileName: "a.wav")))
        let controller = ShowController(
            show: Show(name: "S", grids: [grid]), defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
        let undo = UndoManager()
        undo.groupsByEvent = false
        controller.undoManager = undo
        controller.isLocked = locked
        return (controller, undo)
    }

    @Test("Entrer dans le mode sélectionne la première case lumière libre ; en sortir ne change rien d'autre")
    func enteringSelectsTheFirstFreeCell() {
        let (controller, _) = makeController()
        controller.setPairingLights(true)
        #expect(controller.isPairingLights)
        #expect(controller.selection == Self.first)
        controller.setPairingLights(false)
        #expect(!controller.isPairingLights)
        #expect(controller.pairingNaming == nil)
    }

    @Test("Refusé verrouillé ; verrouiller quitte le mode")
    func lockedRefusesAndExits() {
        let (locked, _) = makeController(locked: true)
        locked.setPairingLights(true)
        #expect(!locked.isPairingLights)
        #expect(locked.lockNotice != nil)

        let (controller, _) = makeController()
        controller.setPairingLights(true)
        controller.isLocked = true
        #expect(!controller.isPairingLights)
    }

    @Test("Un retour de LightKey pour la case cible crée la cue appairée et ouvre la saisie du nom")
    func feedbackPairsTheTarget() {
        let (controller, _) = makeController()
        controller.setPairingLights(true)
        controller.lightFeedbackArrived(at: Self.first)

        guard case .light(let cue)? = controller.pad(at: Self.first)?.content else {
            Issue.record("la cue n'a pas été créée")
            return
        }
        #expect(cue.isPaired)
        #expect(controller.pairingNaming == Self.first)
        #expect(controller.isPaired(at: Self.first))
    }

    @Test("Un retour pour une autre case, ou hors du mode, n'appaire rien")
    func feedbackElsewhereDoesNothing() {
        let (controller, _) = makeController()
        controller.lightFeedbackArrived(at: Self.first)  // mode inactif
        #expect(controller.pad(at: Self.first) == nil)

        controller.setPairingLights(true)
        controller.lightFeedbackArrived(at: Self.second)  // la cible est la première case
        #expect(controller.pad(at: Self.second) == nil)
        #expect(controller.pad(at: Self.first) == nil)
    }

    @Test("Confirmation à la main : mêmes effets, sur une cue existante non appairée")
    func manualConfirmation() {
        let (controller, _) = makeController()
        controller.newLightCue(at: Self.first)
        controller.setPairingLights(true)
        #expect(controller.selection == Self.first)  // une cue non appairée reste une case à appairer
        #expect(controller.confirmPairing())
        #expect(controller.isPaired(at: Self.first))
        #expect(controller.pad(at: Self.first)?.title == "Nouvelle cue")
        #expect(!controller.confirmPairing())  // déjà appairée : rien de plus
    }

    @Test("Un appairage = une seule annulation, qui défait aussi la création de la cue")
    func oneUndoStep() {
        let (controller, undo) = makeController()
        controller.setPairingLights(true)
        controller.lightFeedbackArrived(at: Self.first)
        #expect(controller.pad(at: Self.first) != nil)
        undo.undo()
        #expect(controller.pad(at: Self.first) == nil)
        undo.redo()
        #expect(controller.isPaired(at: Self.first))
    }

    @Test("Nommer termine l'étape : la case libre suivante devient la cible")
    func namingMovesToTheNextFreeCell() {
        let (controller, _) = makeController()
        controller.setPairingLights(true)
        controller.lightFeedbackArrived(at: Self.first)
        controller.updatePad(at: Self.first, title: "Plein feu")
        controller.finishPairingNaming()
        #expect(controller.pairingNaming == nil)
        #expect(controller.selection == Self.second)
        #expect(controller.pad(at: Self.first)?.title == "Plein feu")
    }

    @Test("Retirer l'appairage garde la cue et son nom")
    func unpair() {
        let (controller, _) = makeController()
        controller.setPairingLights(true)
        controller.lightFeedbackArrived(at: Self.first)
        controller.updatePad(at: Self.first, title: "Plein feu")
        #expect(controller.unpairCue(at: Self.first))
        #expect(!controller.isPaired(at: Self.first))
        #expect(controller.pad(at: Self.first)?.title == "Plein feu")
        #expect(!controller.unpairCue(at: Self.first))  // rien à retirer
    }

    @Test("Les colonnes sons ne s'appairent jamais")
    func soundColumnsAreNeverPaired() {
        let (controller, _) = makeController()
        controller.setPairingLights(true)
        controller.selection = Self.sound
        controller.lightFeedbackArrived(at: Self.sound)
        controller.pairingSend(at: Self.sound)
        #expect(controller.pad(at: Self.sound)?.title == "Rire")
        #expect(!controller.isPaired(at: Self.sound))
        #expect(controller.pairingNaming == nil)
    }

    @Test("Un clic sur l'ampoule sélectionne la case et envoie la note à LightKey")
    func bulbSendsAndTargets() {
        let (controller, _) = makeController()
        var sent: [GridPosition] = []
        controller.lightPressHandler = { sent.append($0) }
        // Hors du mode : rien.
        controller.pairingSend(at: Self.second)
        #expect(sent.isEmpty)

        controller.newLightCue(at: Self.second)
        controller.setPairingLights(true)
        controller.pairingSend(at: Self.second)
        #expect(sent == [Self.second])
        #expect(controller.selection == Self.second)
    }

    @Test("Un appui sur le contrôleur désigne la case cible, sans toucher aux sons")
    func controllerPressTargetsTheCell() {
        let (controller, _) = makeController()
        controller.setPairingLights(true)
        controller.pairingPress(at: Self.second)
        #expect(controller.selection == Self.second)
        controller.pairingPress(at: Self.sound)  // colonne son : ignoré
        #expect(controller.selection == Self.second)
    }

    @Test("Un ancien spectacle sans isPaired s'ouvre non appairé ; le nouveau champ est enregistré")
    func oldShowsDecode() throws {
        // Un fichier d'avant l'appairage : un cue encodé, sans la clé `isPaired`.
        let current = LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 0))
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as? [String: Any])
        #expect(object.removeValue(forKey: "isPaired") != nil)
        let old = try JSONSerialization.data(withJSONObject: object)
        let cue = try JSONDecoder().decode(LightCue.self, from: old)
        #expect(!cue.isPaired)

        var paired = cue
        paired.isPaired = true
        let again = try JSONDecoder().decode(LightCue.self, from: JSONEncoder().encode(paired))
        #expect(again.isPaired)
    }
}

/// Appairage des deux faders lumière : bouger un fader (à la main ou à l'écran) l'envoie à LightKey et le désigne comme cible.
@MainActor
@Suite("Appairage des faders lumière", .serialized)
struct FaderPairingTests {
    struct Rig {
        let controller: ShowController
        let transport: FakeMIDITransport
        let undo: UndoManager
        let runner: Task<Void, Never>
    }

    private func makeRig() async -> Rig {
        let controller = ShowController(
            show: Show(name: "S", grids: [PadGrid.empty(name: "G")]),
            defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
        let undo = UndoManager()
        undo.groupsByEvent = false
        controller.undoManager = undo
        controller.isLocked = false
        let transport = FakeMIDITransport()
        let session = ControllerSession(controller: controller, transport: transport)
        let runner = Task { await session.run() }
        await transport.setPorts(sources: [ControllerSessionTests.apcSource], destinations: [ControllerSessionTests.apcDestination])
        _ = await waitUntil { await controller.connectedController == .apcMiniMK2 }
        return Rig(controller: controller, transport: transport, undo: undo, runner: runner)
    }

    @Test("Un fader bougé à l'écran devient la cible et part vers LightKey")
    func screenFaderBecomesTheTarget() async {
        let rig = await makeRig()
        defer { rig.runner.cancel() }
        rig.controller.setPairingLights(true)
        rig.controller.setLightFader(column: 6, level: 0.5)
        #expect(rig.controller.pairingFader == 6)
        #expect(rig.controller.selection == nil)
        #expect(await waitUntil { await rig.transport.lighting.count == 1 })
    }

    @Test("Un fader physique devient la cible ; hors du mode, rien ne change")
    func physicalFaderBecomesTheTarget() async {
        let rig = await makeRig()
        defer { rig.runner.cancel() }
        await rig.transport.receive([.controlChange(channel: 0, controller: 55, value: 100)], from: ControllerSessionTests.apcSource.id)
        #expect(await waitUntil { await rig.transport.lighting.count == 1 })  // relayé, comme toujours
        #expect(rig.controller.pairingFader == nil)

        rig.controller.setPairingLights(true)
        await rig.transport.receive([.controlChange(channel: 0, controller: 55, value: 90)], from: ControllerSessionTests.apcSource.id)
        #expect(await waitUntil { await rig.controller.pairingFader == 7 })
    }

    @Test("Le CC de retour de LightKey appaire le fader cible, en une annulation")
    func feedbackPairsTheFader() async {
        let rig = await makeRig()
        defer { rig.runner.cancel() }
        rig.controller.setPairingLights(true)
        rig.controller.setLightFader(column: 6, level: 0.5)
        await rig.transport.receiveLightingFeedback([.controlChange(channel: 0, controller: 54, value: 64)])
        #expect(await waitUntil { await rig.controller.isFaderPaired(column: 6) })
        #expect(rig.controller.pairingFader == 7)  // le fader libre suivant devient la cible
        rig.undo.undo()
        #expect(!rig.controller.isFaderPaired(column: 6))
    }

    @Test("Un retour pour un fader qui n'est pas la cible n'appaire rien")
    func feedbackForAnotherFader() async {
        let rig = await makeRig()
        defer { rig.runner.cancel() }
        rig.controller.setPairingLights(true)
        rig.controller.setLightFader(column: 6, level: 0.5)
        await rig.transport.receiveLightingFeedback([.controlChange(channel: 0, controller: 55, value: 64)])
        try? await Task.sleep(for: .milliseconds(150))
        #expect(!rig.controller.isFaderPaired(column: 7))
        #expect(!rig.controller.isFaderPaired(column: 6))
    }

    @Test("Confirmation à la main, puis retrait ; choisir un pad abandonne la cible fader")
    func manualConfirmationAndUnpair() async {
        let rig = await makeRig()
        defer { rig.runner.cancel() }
        rig.controller.setPairingLights(true)
        rig.controller.selectPairingFader(column: 7)
        #expect(rig.controller.confirmPairing())
        #expect(rig.controller.isFaderPaired(column: 7))
        #expect(!rig.controller.confirmPairing())
        #expect(rig.controller.unpairFader(column: 7))
        #expect(!rig.controller.isFaderPaired(column: 7))

        rig.controller.selectPairingFader(column: 6)
        rig.controller.pairingPress(at: GridPosition(column: 6, row: 2))
        #expect(rig.controller.pairingFader == nil)
        #expect(rig.controller.selection == GridPosition(column: 6, row: 2))
    }

    @Test("Les faders des sons ne s'appairent pas ; verrouillé, tout est refusé")
    func soundFadersAndLock() async {
        let rig = await makeRig()
        defer { rig.runner.cancel() }
        rig.controller.setPairingLights(true)
        rig.controller.selectPairingFader(column: 2)
        #expect(rig.controller.pairingFader == nil)
        rig.controller.selectPairingFader(column: 6)
        rig.controller.isLocked = true
        #expect(rig.controller.pairingFader == nil)
        #expect(!rig.controller.isPairingLights)
        #expect(!rig.controller.unpairFader(column: 6))
    }

    @Test("Un ancien spectacle sans isFaderPaired s'ouvre non appairé")
    func oldColumnsDecode() throws {
        let current = Column.empty(name: "C", kind: .light)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as? [String: Any])
        #expect(object.removeValue(forKey: "isFaderPaired") != nil)
        let column = try JSONDecoder().decode(Column.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(!column.isFaderPaired)
        #expect(column.name == "C")
    }
}
