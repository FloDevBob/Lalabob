import ControllerDrivers
import Foundation
import LalabobAudio
import LalabobMIDI
import LalabobModel
import Testing

@testable import LalabobEngine

/// Colonnes lumière : LightKey écoute directement le contrôleur. Un clic à l'écran envoie la même note
/// sur le port virtuel « Lalabob Lumière » ; un appui physique n'y envoie rien (sinon la cue partirait deux fois).
@MainActor
@Suite("Lumière", .serialized)
struct LightingTests {
    static let light = GridPosition(column: 6, row: 1)

    struct Rig {
        let audio: RecordingAudioEngine
        let controller: ShowController
        let transport: FakeMIDITransport
        let runner: Task<Void, Never>
    }

    private func makeRig(defaults: UserDefaults = UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!) -> Rig {
        var grid = PadGrid.empty(name: "G1")
        grid[Self.light] = Pad(
            title: "Plein feu", tint: .ambre,
            content: .light(cue: LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 0))))
        let audio = RecordingAudioEngine()
        let controller = ShowController(
            show: Show(name: "S", grids: [grid]), audio: audio, audioDirectory: URL(filePath: "/tmp/lalabob-audio"),
            defaults: defaults)
        controller.isLocked = true
        let transport = FakeMIDITransport()
        let session = ControllerSession(controller: controller, transport: transport)
        let runner = Task { await session.run() }
        return Rig(audio: audio, controller: controller, transport: transport, runner: runner)
    }

    private func plugLaunchpad(_ rig: Rig) async {
        await rig.transport.setPorts(
            sources: [ControllerSessionTests.lpxSource], destinations: [ControllerSessionTests.lpxDestination])
        _ = await waitUntil { await rig.controller.connectedController == .launchpadX }
    }

    @Test("Un clic sur un pad lumière envoie la note du Launchpad (Note On puis Note Off)")
    func clickSendsControllerNote() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugLaunchpad(rig)

        rig.controller.press(at: Self.light)
        // Colonne 7, 2e rangée depuis le haut → rangée 7 depuis le bas → note 77.
        let expected: [MIDIEvent] = [.noteOn(channel: 0, note: 77, velocity: 127), .noteOff(channel: 0, note: 77, velocity: 0)]
        #expect(await waitUntil { await rig.transport.lighting == expected })
    }

    @Test("Sans contrôleur branché, on utilise le dernier modèle connu")
    func usesLastKnownController() async {
        let defaults = UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!
        do {
            let first = makeRig(defaults: defaults)
            await first.transport.setPorts(
                sources: [ControllerSessionTests.apcSource], destinations: [ControllerSessionTests.apcDestination])
            _ = await waitUntil { await first.controller.connectedController == .apcMiniMK2 }
            first.runner.cancel()
        }
        let rig = makeRig(defaults: defaults)
        defer { rig.runner.cancel() }
        #expect(rig.controller.lastControllerModel == .apcMiniMK2)

        rig.controller.press(at: Self.light)
        // APC : note = rangée depuis le bas × 8 + colonne = 6 × 8 + 6 = 54.
        #expect(await waitUntil { await rig.transport.lighting.first == .noteOn(channel: 0, note: 54, velocity: 127) })
    }

    @Test("Aucun contrôleur connu : rien n'est envoyé")
    func noKnownController() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        rig.controller.press(at: Self.light)
        try? await Task.sleep(for: .milliseconds(250))
        #expect(await rig.transport.lighting.isEmpty)
    }

    @Test("Un appui physique sur un pad lumière n'envoie rien sur le port virtuel ni au moteur audio")
    func physicalPressIsLeftToLightKey() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugLaunchpad(rig)

        await rig.transport.receive([.noteOn(channel: 0, note: 77, velocity: 100)], from: ControllerSessionTests.lpxSource.id)
        try? await Task.sleep(for: .milliseconds(250))
        #expect(await rig.transport.lighting.isEmpty)
        #expect(!(await rig.audio.commands.contains { if case .trigger = $0 { true } else { false } }))
    }

    @Test("En mode Édition, un clic sélectionne sans rien envoyer")
    func editModeSelects() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugLaunchpad(rig)
        rig.controller.isLocked = false

        rig.controller.press(at: Self.light)
        try? await Task.sleep(for: .milliseconds(250))
        #expect(rig.controller.selection == Self.light)
        #expect(await rig.transport.lighting.isEmpty)
    }

    @Test("La LED d'un pad lumière reste allumée à sa couleur")
    func ledIsFixed() {
        let rig = makeRig()
        rig.runner.cancel()
        #expect(rig.controller.ledStates[Self.light] == .lit(.ambre, .full))
    }
}
