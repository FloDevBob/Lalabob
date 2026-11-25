import ControllerDrivers
import Foundation
import LalabobAudio
import LalabobMIDI
import LalabobModel
import Testing

@testable import LalabobEngine

/// Colonnes lumière communes (fiche 01b) dans le moteur : édition visible partout, une annulation, canal commun.
@MainActor
@Suite("Colonnes lumière communes (moteur)", .serialized)
struct SharedLightEngineTests {
    /// Colonne 6, 2e rangée depuis le haut : note 54 et CC 54 sur l'APC mini mk2.
    static let light = GridPosition(column: 6, row: 1)
    static let note: UInt8 = 54

    struct Rig {
        let audio: RecordingAudioEngine
        let controller: ShowController
        let transport: FakeMIDITransport
        let runner: Task<Void, Never>
        let undo: UndoManager
    }

    private func makeRig(locked: Bool = false) -> Rig {
        var first = PadGrid.empty(name: "G1")
        first[Self.light] = Pad(
            title: "Face", tint: .blanc, content: .light(cue: LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 0))))
        first[GridPosition(column: 0, row: 0)] = Pad(title: "Rire", tint: .vert, content: .audio(clip: AudioClip(fileName: "a.wav")))
        let audio = RecordingAudioEngine()
        let controller = ShowController(
            show: Show(name: "S", grids: [first, .empty(name: "G2")]), audio: audio,
            audioDirectory: URL(filePath: "/tmp/lalabob-audio"),
            defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!, isLocked: locked)
        let undo = UndoManager()
        undo.groupsByEvent = false
        controller.undoManager = undo
        let transport = FakeMIDITransport()
        let session = ControllerSession(controller: controller, transport: transport)
        let runner = Task { await session.run() }
        return Rig(audio: audio, controller: controller, transport: transport, runner: runner, undo: undo)
    }

    private func plugAPC(_ rig: Rig) async {
        await rig.transport.setPorts(
            sources: [ControllerSessionTests.apcSource], destinations: [ControllerSessionTests.apcDestination])
        _ = await waitUntil { await rig.controller.connectedController == .apcMiniMK2 }
    }

    @Test("Activer depuis la grille 1 : la cue apparaît dans la grille 2 ; une seule annulation")
    func enableAndUndo() {
        let rig = makeRig()
        rig.runner.cancel()
        let controller = rig.controller
        controller.setSharedLight(true)
        #expect(controller.show.sharedLight != nil)
        controller.selectGrid(at: 1)
        #expect(controller.pad(at: Self.light)?.title == "Face")

        rig.undo.undo()
        #expect(controller.show.sharedLight == nil)
        #expect(controller.show.grids[1][Self.light] == nil)
        #expect(controller.show.grids.allSatisfy { $0.parkedColumns.isEmpty })
    }

    @Test("Modifier une cue commune depuis la grille 2 la modifie dans toutes les grilles")
    func editFromAnotherGrid() {
        let rig = makeRig()
        rig.runner.cancel()
        let controller = rig.controller
        controller.setSharedLight(true)
        controller.selectGrid(at: 1)
        controller.updatePad(at: Self.light, title: "Plein feu")
        controller.renameColumn(at: 6, to: "Projecteurs")
        #expect(controller.show.grids[0][Self.light]?.title == "Plein feu")
        #expect(controller.show.grids[0].columns[6].name == "Projecteurs")
        #expect((try? controller.show.validate()) != nil)
    }

    @Test("Le fader d'une colonne commune est le même dans toutes les grilles")
    func sharedFader() {
        let rig = makeRig()
        rig.runner.cancel()
        let controller = rig.controller
        controller.setSharedLight(true)
        controller.selectGrid(at: 1)
        controller.setLightFader(column: 6, level: 0.4)
        #expect(controller.show.grids[0].columns[6].level == 0.4)
    }

    @Test("Une grille ajoutée reçoit les colonnes communes")
    func addedGrid() {
        let rig = makeRig()
        rig.runner.cancel()
        let controller = rig.controller
        controller.setSharedLight(true)
        controller.addGrid()
        #expect(controller.show.grids[2][Self.light]?.title == "Face")
        #expect(controller.show.grids[2].lightChannel != controller.show.sharedLight?.channel)
    }

    @Test("Verrouillé : activer est refusé")
    func lockedRefused() {
        let rig = makeRig(locked: true)
        rig.runner.cancel()
        rig.controller.setSharedLight(true)
        #expect(rig.controller.show.sharedLight == nil)
        #expect(rig.controller.lockNotice != nil)
    }

    @Test("Canal commun : un appui sur une colonne commune part sur le canal commun, depuis n'importe quelle grille")
    func pressUsesSharedChannel() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugAPC(rig)
        rig.controller.setSharedLight(true)
        let shared = UInt8((rig.controller.show.sharedLight?.channel ?? 1) - 1)
        rig.controller.selectGrid(at: 1)

        await rig.transport.receive([.noteOn(channel: 0, note: Self.note, velocity: 100)], from: ControllerSessionTests.apcSource.id)
        #expect(await waitUntil { await rig.transport.lighting == [.noteOn(channel: shared, note: Self.note, velocity: 127)] })
    }

    @Test("Canal commun : le retour de LightKey allume la cue commune quelle que soit la grille affichée")
    func feedbackOnSharedChannel() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugAPC(rig)
        rig.controller.setSharedLight(true)
        let shared = UInt8((rig.controller.show.sharedLight?.channel ?? 1) - 1)
        rig.controller.selectGrid(at: 1)

        await rig.transport.receiveLightingFeedback([.noteOn(channel: shared, note: Self.note, velocity: 127)])
        #expect(await waitUntil { await rig.controller.lightState(at: Self.light) == .on })
        rig.controller.selectGrid(at: 0)
        #expect(rig.controller.lightState(at: Self.light) == .on)
    }

    @Test("Le canal d'une grille ne peut pas prendre le canal commun")
    func gridChannelAvoidsShared() {
        let rig = makeRig()
        rig.runner.cancel()
        let controller = rig.controller
        controller.setSharedLight(true)
        let shared = controller.show.sharedLight?.channel ?? 0
        controller.setLightChannel(grid: 1, channel: shared)
        #expect(controller.show.grids[1].lightChannel != shared)
    }

    @Test("Activer ou désactiver n'arrête aucun son")
    func noSoundStops() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        rig.controller.audition(at: GridPosition(column: 0, row: 0))
        rig.controller.setSharedLight(true)
        rig.controller.setSharedLight(false)
        try? await Task.sleep(for: .milliseconds(100))
        let commands = await rig.audio.commands
        #expect(!commands.contains { if case .stop = $0 { true } else if case .stopAll = $0 { true } else { false } })
    }
}
