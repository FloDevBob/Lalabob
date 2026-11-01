import ControllerDrivers
import Foundation
import LalabobAudio
import LalabobMIDI
import LalabobModel
import Testing

@testable import LalabobEngine

/// Le retour de LightKey met à jour l'état des cues, l'écran et les LED (jamais les sons).
@MainActor
@Suite("Retour de LightKey sur les pads", .serialized)
struct LightFeedbackTests {
    /// Note 23 de l'APC = colonne 7, 3e rangée en partant du bas = rangée 5 en partant du haut.
    static let light = GridPosition(column: 7, row: 5)

    struct Rig {
        let controller: ShowController
        let transport: FakeMIDITransport
        let session: ControllerSession
        let runner: Task<Void, Never>
    }

    private func makeController() -> ShowController {
        var grid = PadGrid.empty(name: "G1")
        grid[Self.light] = Pad(
            title: "Plein feu", tint: .ambre,
            content: .light(cue: LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 0))))
        return ShowController(
            show: Show(name: "S", grids: [grid]), audio: RecordingAudioEngine(),
            audioDirectory: URL(filePath: "/tmp/lalabob-audio"),
            defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
    }

    private func makeRig() -> Rig {
        let controller = makeController()
        let transport = FakeMIDITransport()
        let session = ControllerSession(controller: controller, transport: transport)
        let runner = Task { await session.run() }
        return Rig(controller: controller, transport: transport, session: session, runner: runner)
    }

    @Test("Inconnue au départ ; Note On allume, Note Off éteint")
    func onAndOff() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        #expect(rig.controller.lightState(at: Self.light) == .unknown)

        await rig.transport.receiveLightingFeedback([.noteOn(channel: 0, note: 23, velocity: 127)])
        #expect(await waitUntil { await rig.controller.lightState(at: Self.light) == .on })
        await rig.transport.receiveLightingFeedback([.noteOff(channel: 0, note: 23, velocity: 0)])
        #expect(await waitUntil { await rig.controller.lightState(at: Self.light) == .off })
    }

    @Test("Une rafale : le dernier message gagne, les autres cases restent inconnues")
    func lastMessageWins() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        // Changement de couleur dans LightKey (relevé) : Note On puis Note Off, plusieurs fois.
        let burst: [MIDIEvent] = [
            .noteOn(channel: 0, note: 23, velocity: 127), .noteOff(channel: 0, note: 23, velocity: 0),
            .noteOn(channel: 0, note: 23, velocity: 127), .noteOff(channel: 0, note: 23, velocity: 0),
            .noteOff(channel: 0, note: 23, velocity: 0),
        ]
        await rig.transport.receiveLightingFeedback(burst)
        await rig.transport.receiveLightingFeedback([.noteOn(channel: 0, note: 14, velocity: 127)])
        #expect(await waitUntil { await rig.controller.lightState(at: GridPosition(column: 6, row: 6)) == .on })
        #expect(rig.controller.lightState(at: Self.light) == .off)
        #expect(rig.controller.lightState(at: GridPosition(column: 0, row: 0)) == .unknown)
    }

    @Test("Les LED suivent : allumée = pulsation, éteinte = atténuée")
    func ledsFollow() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        #expect(rig.controller.ledStates[Self.light] == .lit(.ambre, .full))
        await rig.transport.receiveLightingFeedback([.noteOn(channel: 0, note: 23, velocity: 127)])
        #expect(await waitUntil { await rig.controller.ledStates[Self.light] == .pulsing(.ambre) })
        await rig.transport.receiveLightingFeedback([.noteOff(channel: 0, note: 23, velocity: 0)])
        #expect(await waitUntil { await rig.controller.ledStates[Self.light] == .lit(.ambre, .quarter) })
    }

    @Test("Un second spectacle rattaché reçoit l'état déjà connu")
    func attachedShowGetsKnownState() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await rig.transport.receiveLightingFeedback([.noteOn(channel: 0, note: 23, velocity: 127)])
        #expect(await waitUntil { await rig.controller.lightState(at: Self.light) == .on })

        let other = makeController()
        rig.session.attach(other)
        #expect(other.lightState(at: Self.light) == .on)
    }

    @Test("Un retour ne déclenche aucune commande audio et ne touche pas aux colonnes sons")
    func neverTouchesSound() async {
        let controller = makeController()
        let transport = FakeMIDITransport()
        let session = ControllerSession(controller: controller, transport: transport)
        let runner = Task { await session.run() }
        defer { runner.cancel() }
        // Note 0 = colonne 0, rangée du bas : une colonne son. L'état est retenu mais n'allume aucune LED de son.
        await transport.receiveLightingFeedback([.noteOn(channel: 0, note: 0, velocity: 127)])
        #expect(await waitUntil { await controller.lightState(at: GridPosition(column: 0, row: 7)) == .on })
        #expect(controller.ledStates[GridPosition(column: 0, row: 7)] == .off)  // case vide : éteinte
        #expect(controller.playback.isEmpty)
    }
}
