import ControllerDrivers
import Foundation
import LalabobAudio
import LalabobMIDI
import LalabobModel
import Testing

@testable import LalabobEngine

/// Un canal LightKey par grille (fiche 01) : tout ce qui part vers LightKey part sur le canal de la grille affichée, et le
/// retour de LightKey n'allume que la grille de son canal. Changer de grille ne coupe aucun son.
@MainActor
@Suite("Canal LightKey par grille", .serialized)
struct LightChannelEngineTests {
    /// Colonne 6, 2e rangée depuis le haut : note 54 sur l'APC mini mk2 (rangée 6 depuis le bas × 8 + 6).
    static let light = GridPosition(column: 6, row: 1)
    static let note: UInt8 = 54
    static let sound = GridPosition(column: 0, row: 0)

    struct Rig {
        let audio: RecordingAudioEngine
        let controller: ShowController
        let transport: FakeMIDITransport
        let runner: Task<Void, Never>
        /// Gardé ici : `ShowController.undoManager` est une référence faible.
        let undo: UndoManager
    }

    private static func cue() -> Pad {
        Pad(title: "Face", tint: .blanc, light: LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 0)))
    }

    /// Deux grilles (canaux 1 et 2), une cue sur la même case dans chacune, un son en grille 1.
    private func makeRig(locked: Bool = false) -> Rig {
        var first = PadGrid.empty(name: "G1")
        first[Self.light] = Self.cue()
        first[Self.sound] = Pad(title: "Rire", tint: .vert, audio: AudioClip(fileName: "a.wav"))
        var second = PadGrid.empty(name: "G2")
        second[Self.light] = Self.cue()
        let audio = RecordingAudioEngine()
        let controller = ShowController(
            show: Show(name: "S", grids: [first, second]), audio: audio, audioDirectory: URL(filePath: "/tmp/lalabob-audio"),
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

    // MARK: Envoi

    @Test("Grille 2 : un appui physique sur un pad lumière part sur le canal 2")
    func physicalPressUsesGridChannel() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugAPC(rig)
        rig.controller.selectGrid(at: 1)

        await rig.transport.receive([.noteOn(channel: 0, note: Self.note, velocity: 100)], from: ControllerSessionTests.apcSource.id)
        #expect(await waitUntil { await rig.transport.lighting == [.noteOn(channel: 1, note: Self.note, velocity: 127)] })
        await rig.transport.receive([.noteOff(channel: 0, note: Self.note, velocity: 0)], from: ControllerSessionTests.apcSource.id)
        let expected: [MIDIEvent] = [.noteOn(channel: 1, note: Self.note, velocity: 127), .noteOff(channel: 1, note: Self.note, velocity: 0)]
        #expect(await waitUntil { await rig.transport.lighting == expected })
    }

    @Test("Grille 1 : toujours le canal 1, comme avant")
    func firstGridKeepsChannelOne() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugAPC(rig)
        await rig.transport.receive([.noteOn(channel: 0, note: Self.note, velocity: 100)], from: ControllerSessionTests.apcSource.id)
        #expect(await waitUntil { await rig.transport.lighting == [.noteOn(channel: 0, note: Self.note, velocity: 127)] })
    }

    @Test("Grille 2 : un double-clic à l'écran part sur le canal 2 (Note On puis Note Off)")
    func screenClickUsesGridChannel() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugAPC(rig)
        rig.controller.selectGrid(at: 1)
        rig.controller.audition(at: Self.light)
        let expected: [MIDIEvent] = [.noteOn(channel: 1, note: Self.note, velocity: 127), .noteOff(channel: 1, note: Self.note, velocity: 0)]
        #expect(await waitUntil { await rig.transport.lighting == expected })
    }

    @Test("Grille 2 : un fader lumière déplacé à l'écran envoie son CC sur le canal 2")
    func screenFaderUsesGridChannel() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugAPC(rig)
        rig.controller.selectGrid(at: 1)
        rig.controller.setLightFader(column: 6, level: 1)
        #expect(await waitUntil { await rig.transport.lighting == [.controlChange(channel: 1, controller: 54, value: 127)] })
    }

    @Test("Grille 2 : un fader lumière physique est relayé sur le canal 2")
    func physicalFaderUsesGridChannel() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugAPC(rig)
        rig.controller.selectGrid(at: 1)
        await rig.transport.receive([.controlChange(channel: 0, controller: 54, value: 64)], from: ControllerSessionTests.apcSource.id)
        #expect(await waitUntil { await rig.transport.lighting == [.controlChange(channel: 1, controller: 54, value: 64)] })
    }

    @Test("Grille « Sans canal » : rien ne part vers LightKey")
    func noChannelSendsNothing() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugAPC(rig)
        rig.controller.setLightChannel(grid: 1, channel: nil)
        rig.controller.selectGrid(at: 1)

        await rig.transport.receive([.noteOn(channel: 0, note: Self.note, velocity: 100)], from: ControllerSessionTests.apcSource.id)
        rig.controller.audition(at: Self.light)
        rig.controller.setLightFader(column: 6, level: 1)
        try? await Task.sleep(for: .milliseconds(250))
        #expect(await rig.transport.lighting.isEmpty)
    }

    // MARK: Retour

    @Test("Un retour sur le canal 2 n'allume que la grille 2 ; l'état suit le changement de grille")
    func feedbackIsPerChannel() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugAPC(rig)

        await rig.transport.receiveLightingFeedback([.noteOn(channel: 1, note: Self.note, velocity: 127)])
        try? await Task.sleep(for: .milliseconds(150))
        #expect(rig.controller.lightState(at: Self.light) == .unknown)  // grille 1 affichée

        rig.controller.selectGrid(at: 1)
        #expect(await waitUntil { await rig.controller.lightState(at: Self.light) == .on })
        #expect(rig.controller.ledStates[Self.light] == .pulsing(.blanc))

        rig.controller.selectGrid(at: 0)
        #expect(rig.controller.lightState(at: Self.light) == .unknown)
        await rig.transport.receiveLightingFeedback([.noteOn(channel: 0, note: Self.note, velocity: 127)])
        #expect(await waitUntil { await rig.controller.lightState(at: Self.light) == .on })
    }

    @Test("Mode d'appairage : un retour sur le canal d'une autre grille n'appaire pas la cible")
    func pairingIgnoresOtherChannels() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugAPC(rig)
        rig.controller.setPairingLights(true)
        rig.controller.selection = Self.light

        await rig.transport.receiveLightingFeedback([.noteOn(channel: 1, note: Self.note, velocity: 127)])
        try? await Task.sleep(for: .milliseconds(150))
        #expect(!rig.controller.isPaired(at: Self.light))

        await rig.transport.receiveLightingFeedback([.noteOn(channel: 0, note: Self.note, velocity: 127)])
        #expect(await waitUntil { await rig.controller.isPaired(at: Self.light) })
    }

    @Test("Changer de grille ne coupe aucun son")
    func gridChangeStopsNothing() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        rig.controller.audition(at: Self.sound)
        rig.controller.selectGrid(at: 1)
        rig.controller.selectGrid(at: 0)
        try? await Task.sleep(for: .milliseconds(100))
        let commands = await rig.audio.commands
        #expect(!commands.contains { if case .stop = $0 { true } else if case .stopAll = $0 { true } else { false } })
    }

    // MARK: Onglets

    @Test("Une nouvelle grille prend le premier canal libre ; réordonner ne change aucun canal")
    func addAndMoveGrids() {
        let rig = makeRig()
        rig.runner.cancel()
        let controller = rig.controller
        controller.setLightChannel(grid: 0, channel: 5)
        controller.addGrid()
        #expect(controller.show.grids[2].lightChannel == 1)
        let ids = controller.show.grids.map(\.id)
        controller.moveGrid(from: 2, to: 0)
        #expect(controller.show.grids.map(\.id) == [ids[2], ids[0], ids[1]])
        #expect(controller.show.grids.map(\.lightChannel) == [1, 5, 2])
    }

    @Test("Supprimer une grille libère son canal")
    func removeFreesChannel() {
        let rig = makeRig()
        rig.runner.cancel()
        let controller = rig.controller
        controller.removeGrid(at: 0)
        controller.addGrid()
        #expect(controller.show.grids.map(\.lightChannel) == [2, 1])
    }

    @Test("Changer le canal : une annulation, canal déjà pris refusé, hors bornes refusé")
    func setChannel() {
        let rig = makeRig()
        rig.runner.cancel()
        let controller = rig.controller
        let undo = rig.undo

        controller.setLightChannel(grid: 1, channel: 1)  // pris par la grille 1
        #expect(controller.show.grids[1].lightChannel == 2)
        #expect(!undo.canUndo)
        controller.setLightChannel(grid: 1, channel: 17)
        #expect(controller.show.grids[1].lightChannel == 2)

        controller.setLightChannel(grid: 1, channel: 9)
        #expect(controller.show.grids[1].lightChannel == 9)
        controller.setLightChannel(grid: 1, channel: nil)
        #expect(controller.show.grids[1].lightChannel == nil)
        undo.undo()
        #expect(controller.show.grids[1].lightChannel == 9)
        undo.undo()
        #expect(controller.show.grids[1].lightChannel == 2)
    }

    @Test("Verrouillé : changer le canal est refusé")
    func setChannelLocked() {
        let rig = makeRig(locked: true)
        rig.runner.cancel()
        rig.controller.setLightChannel(grid: 1, channel: 9)
        #expect(rig.controller.show.grids[1].lightChannel == 2)
        #expect(rig.controller.lockNotice != nil)
    }

    @Test("Canaux pris : la liste indique quelle grille occupe chaque canal")
    func channelOwners() {
        let rig = makeRig()
        rig.runner.cancel()
        #expect(rig.controller.gridIndex(usingLightChannel: 2) == 1)
        #expect(rig.controller.gridIndex(usingLightChannel: 3) == nil)
        #expect(rig.controller.currentLightChannel == 1)
    }
}
