import ControllerDrivers
import Foundation
import LalabobAudio
import LalabobMIDI
import LalabobModel
import Testing

@testable import LalabobEngine

/// Transport MIDI factice : on branche et débranche des ports, on injecte des messages, on lit ce qui est envoyé.
actor FakeMIDITransport: MIDITransport {
    nonisolated let incoming: AsyncStream<IncomingMIDI>
    nonisolated let changes: AsyncStream<Void>
    private let incomingContinuation: AsyncStream<IncomingMIDI>.Continuation
    private let changesContinuation: AsyncStream<Void>.Continuation

    private var sourcePorts: [MIDIPort] = []
    private var destinationPorts: [MIDIPort] = []
    private(set) var listening: Set<MIDIPortID> = []
    private(set) var sent: [(destination: MIDIPortID, events: [MIDIEvent])] = []
    /// Ce qui est parti sur le port virtuel « Lalabob Lumière ».
    private(set) var lighting: [MIDIEvent] = []

    init() {
        (incoming, incomingContinuation) = AsyncStream.makeStream(of: IncomingMIDI.self)
        (changes, changesContinuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    }

    func setPorts(sources: [MIDIPort], destinations: [MIDIPort]) {
        sourcePorts = sources
        destinationPorts = destinations
        listening = listening.filter { id in sources.contains { $0.id == id } }
        changesContinuation.yield()
    }

    func receive(_ events: [MIDIEvent], from source: MIDIPortID) {
        incomingContinuation.yield(IncomingMIDI(source: source, events: events))
    }

    func clearSent() { sent = [] }
    func sentEvents(to destination: MIDIPortID) -> [MIDIEvent] {
        sent.filter { $0.destination == destination }.flatMap(\.events)
    }

    func sources() -> [MIDIPort] { sourcePorts }
    func destinations() -> [MIDIPort] { destinationPorts }
    func listen(to source: MIDIPortID) { if sourcePorts.contains(where: { $0.id == source }) { listening.insert(source) } }
    func stopListening(to source: MIDIPortID) { listening.remove(source) }
    func sendLighting(_ events: [MIDIEvent]) { lighting.append(contentsOf: events) }
    func send(_ events: [MIDIEvent], to destination: MIDIPortID) throws {
        guard destinationPorts.contains(where: { $0.id == destination }) else {
            throw MIDITransportError.destinationUnavailable
        }
        sent.append((destination, events))
    }
}

@MainActor
@Suite("Session de contrôleur", .serialized)
struct ControllerSessionTests {
    // Un Launchpad X : deux ports (MIDI et DAW), chacun avec sa source et sa destination.
    static let lpxSource = MIDIPort(id: MIDIPortID(uniqueID: 101), name: "Launchpad X LPX MIDI In", groupID: 11)
    static let lpxDestination = MIDIPort(id: MIDIPortID(uniqueID: 102), name: "Launchpad X LPX MIDI Out", groupID: 11)
    static let lpxDAWSource = MIDIPort(id: MIDIPortID(uniqueID: 103), name: "Launchpad X LPX DAW In", groupID: 12)
    static let lpxDAWDestination = MIDIPort(id: MIDIPortID(uniqueID: 104), name: "Launchpad X LPX DAW Out", groupID: 12)
    static let apcSource = MIDIPort(id: MIDIPortID(uniqueID: 201), name: "APC mini mk2 Control In", groupID: 21)
    static let apcDestination = MIDIPort(id: MIDIPortID(uniqueID: 202), name: "APC mini mk2 Control Out", groupID: 21)

    struct Rig {
        let audio: RecordingAudioEngine
        let controller: ShowController
        let transport: FakeMIDITransport
        let session: ControllerSession
        let runner: Task<Void, Never>
        let pad: Pad
    }

    private func makeRig() -> Rig {
        var grid = PadGrid.empty(name: "G1")
        let pad = Pad(title: "Rire", tint: .vert, content: .audio(clip: AudioClip(fileName: "a.wav")))
        grid.columns[0].slots[0] = pad  // en haut à gauche
        let audio = RecordingAudioEngine()
        let controller = ShowController(
            show: Show(name: "S", grids: [grid]), audio: audio, audioDirectory: URL(filePath: "/tmp/lalabob-audio"),
            defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
        controller.isLocked = false  // déverrouillé : un appui sur le contrôleur joue quand même
        let transport = FakeMIDITransport()
        let session = ControllerSession(controller: controller, transport: transport)
        let runner = Task { await session.run() }
        return Rig(audio: audio, controller: controller, transport: transport, session: session, runner: runner, pad: pad)
    }

    private func plugLaunchpad(_ rig: Rig, withDAW: Bool = true) async {
        var sources = [Self.lpxSource]
        var destinations = [Self.lpxDestination]
        if withDAW {
            sources.append(Self.lpxDAWSource)
            destinations.append(Self.lpxDAWDestination)
        }
        await rig.transport.setPorts(sources: sources, destinations: destinations)
    }

    @Test("Un Launchpad branché est reconnu, écouté, et passe en mode Programmeur")
    func connects() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugLaunchpad(rig)

        #expect(await waitUntil { await rig.controller.connectedController == .launchpadX })
        #expect(await waitUntil { await rig.transport.listening == [Self.lpxSource.id] })
        let driver = ControllerModel.launchpadX.driver
        let sent = await rig.transport.sentEvents(to: Self.lpxDestination.id)
        #expect(sent.starts(with: driver.connectionMessages))
        #expect(await rig.transport.sentEvents(to: Self.lpxDAWDestination.id).isEmpty)
    }

    @Test("Le port DAW seul n'est pas un contrôleur utilisable")
    func dawOnly() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await rig.transport.setPorts(sources: [Self.lpxDAWSource], destinations: [Self.lpxDAWDestination])
        try? await Task.sleep(for: .milliseconds(200))
        #expect(rig.controller.connectedController == nil)
        #expect(await rig.transport.sent.isEmpty)
    }

    @Test("Un port inconnu est ignoré")
    func unknownDevice() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        let iacIn = MIDIPort(id: MIDIPortID(uniqueID: 9), name: "IAC Driver Bus 1", groupID: 0)
        await rig.transport.setPorts(sources: [iacIn], destinations: [iacIn])
        try? await Task.sleep(for: .milliseconds(200))
        #expect(rig.controller.connectedController == nil)
    }

    @Test("Un appui sur un pad joue le son, même en mode Édition")
    func padPress() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugLaunchpad(rig)
        #expect(await waitUntil { await rig.controller.connectedController != nil })

        // Haut à gauche du Launchpad = note 81.
        await rig.transport.receive([.noteOn(channel: 0, note: 81, velocity: 100)], from: Self.lpxSource.id)
        #expect(await waitUntil { await rig.audio.commands.contains(.trigger(rig.pad.id)) })
    }

    @Test("Le relâchement d'un pad ne fait rien")
    func padRelease() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugLaunchpad(rig)
        #expect(await waitUntil { await rig.controller.connectedController != nil })

        await rig.transport.receive([.noteOff(channel: 0, note: 81, velocity: 0)], from: Self.lpxSource.id)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(!(await rig.audio.commands.contains(.trigger(rig.pad.id))))
    }

    @Test("Les messages d'une autre source sont ignorés")
    func otherSource() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugLaunchpad(rig)
        #expect(await waitUntil { await rig.controller.connectedController != nil })

        await rig.transport.receive([.noteOn(channel: 0, note: 81, velocity: 100)], from: Self.lpxDAWSource.id)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(!(await rig.audio.commands.contains(.trigger(rig.pad.id))))
    }

    @Test("Un fader de l'APC règle la colonne correspondante, le 9e est ignoré")
    func faders() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await rig.transport.setPorts(sources: [Self.apcSource], destinations: [Self.apcDestination])
        #expect(await waitUntil { await rig.controller.connectedController == .apcMiniMK2 })

        await rig.transport.receive(
            [.controlChange(channel: 0, controller: 49, value: 127), .controlChange(channel: 0, controller: 56, value: 0)],
            from: Self.apcSource.id)
        #expect(await waitUntil { await rig.controller.currentGrid.columns[1].level == 1 })
        #expect(await waitUntil { await rig.audio.commands.contains(.level(1, 1)) })
        #expect(rig.controller.currentGrid.columns[0].level == 0.8)  // le fader maître n'a rien touché
    }

    @Test("À la connexion, les LED reflètent l'écran")
    func initialLEDs() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugLaunchpad(rig)
        #expect(await waitUntil { await rig.transport.sentEvents(to: Self.lpxDestination.id).count > 2 })

        let driver = ControllerModel.launchpadX.driver
        let expected = driver.ledMessages([GridPosition(column: 0, row: 0): .lit(.vert, .full)])
        let sent = await rig.transport.sentEvents(to: Self.lpxDestination.id)
        // Le message complet de la grille contient la spec du pad allumé ; on vérifie la note 81.
        let sysEx = sent.compactMap { event -> [UInt8]? in
            if case .systemExclusive(let bytes) = event { bytes } else { nil }
        }
        let wanted = expected.compactMap { event -> [UInt8]? in
            if case .systemExclusive(let bytes) = event { Array(bytes.dropFirst(7).dropLast()) } else { nil }
        }.first ?? []
        #expect(sysEx.contains { message in message.windows(of: wanted.count).contains(wanted) })
    }

    @Test("Quand un son joue, seule sa LED change (elle pulse)")
    func ledFollowsPlayback() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        let observer = Task { await rig.controller.observePlayback() }
        defer { observer.cancel() }
        await plugLaunchpad(rig)
        #expect(await waitUntil { await rig.transport.sentEvents(to: Self.lpxDestination.id).count > 2 })
        try? await Task.sleep(for: .milliseconds(150))
        await rig.transport.clearSent()

        await rig.audio.send(PlaybackEvent(pad: rig.pad.id, state: .playing(startedAt: 0), duration: 2))
        let driver = ControllerModel.launchpadX.driver
        let expected = driver.ledMessages([GridPosition(column: 0, row: 0): .pulsing(.vert)])
        #expect(await waitUntil { await rig.transport.sentEvents(to: Self.lpxDestination.id) == expected })
    }

    @Test("Débrancher le contrôleur n'arrête aucun son")
    func unplugKeepsSoundPlaying() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugLaunchpad(rig)
        #expect(await waitUntil { await rig.controller.connectedController != nil })
        await rig.transport.receive([.noteOn(channel: 0, note: 81, velocity: 100)], from: Self.lpxSource.id)
        #expect(await waitUntil { await rig.audio.commands.contains(.trigger(rig.pad.id)) })

        await rig.transport.setPorts(sources: [], destinations: [])
        #expect(await waitUntil { await rig.controller.connectedController == nil })
        try? await Task.sleep(for: .milliseconds(200))
        let commands = await rig.audio.commands
        #expect(!commands.contains(.stopAll))
        #expect(!commands.contains(.stop(rig.pad.id)))
    }

    @Test("Rebrancher le contrôleur réinitialise le mode Programmeur et toutes les LED")
    func replug() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugLaunchpad(rig)
        #expect(await waitUntil { await rig.controller.connectedController != nil })
        await rig.transport.setPorts(sources: [], destinations: [])
        #expect(await waitUntil { await rig.controller.connectedController == nil })
        await rig.transport.clearSent()

        await plugLaunchpad(rig)
        #expect(await waitUntil { await rig.controller.connectedController == .launchpadX })
        let driver = ControllerModel.launchpadX.driver
        #expect(await waitUntil { await rig.transport.sentEvents(to: Self.lpxDestination.id).starts(with: driver.connectionMessages) })
        // Les appuis sont de nouveau pris en compte.
        await rig.transport.receive([.noteOn(channel: 0, note: 81, velocity: 100)], from: Self.lpxSource.id)
        #expect(await waitUntil { await rig.audio.commands.contains(.trigger(rig.pad.id)) })
    }
}

extension Array where Element: Equatable {
    /// Toutes les sous-suites contiguës de `count` éléments.
    fileprivate func windows(of count: Int) -> [[Element]] {
        guard count > 0, self.count >= count else { return [] }
        return (0...(self.count - count)).map { Array(self[$0..<($0 + count)]) }
    }
}
