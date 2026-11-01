import ControllerDrivers
import Foundation
import LalabobMIDI
import LalabobModel
import Testing

@testable import LalabobEngine

/// Banc d'essai de l'appairage lumière : journal, envoi depuis l'écran, relais d'essai des appuis physiques.
@MainActor
@Suite("Banc d'essai lumière", .serialized)
struct LightingTestBenchTests {
    struct Rig {
        let transport: FakeMIDITransport
        let session: ControllerSession
        let runner: Task<Void, Never>
    }

    private func makeRig(open: Bool = true) -> Rig {
        let transport = FakeMIDITransport()
        let session = ControllerSession(transport: transport)
        session.bench.isOpen = open
        let runner = Task { await session.run() }
        return Rig(transport: transport, session: session, runner: runner)
    }

    private func plugLaunchpad(_ rig: Rig) async {
        await rig.transport.setPorts(
            sources: [ControllerSessionTests.lpxSource], destinations: [ControllerSessionTests.lpxDestination])
        _ = await waitUntil { await rig.session.bench.isControllerConnected }
    }

    @Test("Un retour de LightKey est journalisé et retenu par note")
    func feedbackIsRecorded() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await rig.transport.receiveLightingFeedback([.noteOn(channel: 0, note: 36, velocity: 5), .noteOff(channel: 0, note: 40, velocity: 0)])
        #expect(await waitUntil { await rig.session.bench.feedbackCount == 2 })
        let bench = rig.session.bench
        #expect(bench.lightKeyLevels == [36: 5, 40: 0])
        #expect(bench.entries.map(\.direction) == [.fromLightKey, .fromLightKey])
        #expect(bench.entries.first?.text == "Note On · canal 1 · note 36 · vélocité 5")
    }

    @Test("Fenêtre fermée : rien n'est noté")
    func closedBenchRecordsNothing() async {
        let rig = makeRig(open: false)
        defer { rig.runner.cancel() }
        await rig.transport.receiveLightingFeedback([.noteOn(channel: 0, note: 36, velocity: 5)])
        rig.session.bench.press(GridPosition(column: 6, row: 0))
        #expect(await waitUntil { await !rig.transport.lighting.isEmpty })  // l'envoi a bien lieu
        #expect(rig.session.bench.entries.isEmpty)
        #expect(rig.session.bench.feedbackCount == 0)
    }

    @Test("Un appui à l'écran envoie Note On puis Note Off sur le canal choisi, et le journal le montre")
    func screenPressSendsOnTheChosenChannel() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        let bench = rig.session.bench
        bench.channel = 16
        let position = GridPosition(column: 6, row: 1)
        let note = bench.model.driver.note(for: position)  // APC mini mk2 par défaut

        bench.press(position)
        bench.press(position)  // un appui déjà tenu n'est pas répété
        bench.release(position)
        let expected: [MIDIEvent] = [.noteOn(channel: 15, note: note, velocity: 127), .noteOff(channel: 15, note: note, velocity: 0)]
        #expect(await waitUntil { await rig.transport.lighting == expected })
        #expect(bench.entries.map(\.direction) == [.toLightKey, .toLightKey])
        #expect(bench.screenPressed.isEmpty)
    }

    @Test("Sans le relais, un appui physique est seulement journalisé")
    func physicalPressIsOnlyLogged() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugLaunchpad(rig)
        await rig.transport.receive([.noteOn(channel: 0, note: 77, velocity: 100)], from: ControllerSessionTests.lpxSource.id)
        #expect(await waitUntil { await rig.session.bench.controllerPressed == [GridPosition(column: 6, row: 1)] })
        #expect(rig.session.bench.entries.last?.direction == .fromController)
        #expect(await rig.transport.lighting.isEmpty)
    }

    @Test("Avec le relais, un appui physique sur une colonne lumière part vers LightKey, relâchement compris")
    func relayForwardsLightColumnPresses() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugLaunchpad(rig)
        rig.session.bench.relaysControllerPresses = true

        await rig.transport.receive([.noteOn(channel: 0, note: 77, velocity: 100)], from: ControllerSessionTests.lpxSource.id)
        await rig.transport.receive([.noteOff(channel: 0, note: 77, velocity: 0)], from: ControllerSessionTests.lpxSource.id)
        let expected: [MIDIEvent] = [.noteOn(channel: 0, note: 77, velocity: 127), .noteOff(channel: 0, note: 77, velocity: 0)]
        #expect(await waitUntil { await rig.transport.lighting == expected })
        #expect(rig.session.bench.controllerPressed.isEmpty)
    }

    @Test("Le relais ne touche jamais les colonnes sons")
    func relayIgnoresSoundColumns() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugLaunchpad(rig)
        rig.session.bench.relaysControllerPresses = true
        // Haut à gauche du Launchpad = note 81 : une colonne son.
        await rig.transport.receive([.noteOn(channel: 0, note: 81, velocity: 100)], from: ControllerSessionTests.lpxSource.id)
        #expect(await waitUntil { await rig.session.bench.controllerPressed == [GridPosition(column: 0, row: 0)] })
        #expect(await rig.transport.lighting.isEmpty)
    }

    @Test("Le journal garde les 300 derniers messages et se copie en texte")
    func journalIsBoundedAndCopyable() {
        let bench = LightingTestBench()
        bench.isOpen = true
        for note in 0..<350 { bench.record(.toLightKey, [.noteOn(channel: 0, note: UInt8(note % 128), velocity: 1)]) }
        #expect(bench.entries.count == LightingTestBench.capacity)
        #expect(bench.transcript.split(separator: "\n").count == LightingTestBench.capacity)
        #expect(bench.transcript.contains("→ LightKey"))
        bench.clear()
        #expect(bench.entries.isEmpty)
    }
}
