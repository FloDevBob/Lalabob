import Foundation
import LalabobAudio
import LalabobModel
import Testing

@testable import LalabobEngine

/// Moteur factice : enregistre les commandes reçues, dans l'ordre.
actor RecordingAudioEngine: AudioEngineControlling {
    nonisolated let meters = ColumnMeters()
    enum Command: Equatable, Sendable {
        case configure(padCount: Int)
        case trigger(Pad.ID)
        case togglePause(Pad.ID)
        case stop(Pad.ID)
        case stopAll
        case level(Int, Double)
        case output(String?)
        case padGain(Pad.ID, Double)
        case seek(Pad.ID, Double)
        case filter(Int, Double)
        case attachExternal(column: Int)
        case detachExternal
    }

    /// Filtre réglé : la grille en plus de la colonne (`commands` ne garde que colonne et valeur).
    struct FilterTarget: Equatable, Sendable {
        var grid: PadGrid.ID
        var column: Int
        var value: Double
    }

    nonisolated let events: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    private(set) var commands: [Command] = []
    private(set) var filterTargets: [FilterTarget] = []
    /// Grille et colonne de chaque branchement du pont audio.
    private(set) var externalTargets: [FilterTarget] = []

    init() {
        (events, continuation) = AsyncStream.makeStream(of: PlaybackEvent.self)
    }

    func send(_ event: PlaybackEvent) { continuation.yield(event) }

    func configure(show: Show, audioDirectory: URL) {
        let count = show.grids.flatMap(\.columns).flatMap(\.slots).compactMap { $0 }.count
        commands.append(.configure(padCount: count))
    }
    func trigger(_ pad: Pad.ID) { commands.append(.trigger(pad)) }
    func togglePause(_ pad: Pad.ID) { commands.append(.togglePause(pad)) }
    func stop(_ pad: Pad.ID) { commands.append(.stop(pad)) }
    func stopAll() { commands.append(.stopAll) }
    func setColumnLevel(_ column: Int, level: Double) { commands.append(.level(column, level)) }
    func setOutputDevice(uid: String?) { commands.append(.output(uid)) }
    func setPadGain(_ pad: Pad.ID, gainDB: Double) { commands.append(.padGain(pad, gainDB)) }
    func seek(_ pad: Pad.ID, to elapsed: TimeInterval) { commands.append(.seek(pad, elapsed)) }
    func setColumnFilter(grid: PadGrid.ID, column: Int, value: Double) {
        commands.append(.filter(column, value))
        filterTargets.append(FilterTarget(grid: grid, column: column, value: value))
    }
    func attachExternal(_ ring: AudioRingBuffer, sampleRate: Double, grid: PadGrid.ID, column: Int) {
        commands.append(.attachExternal(column: column))
        externalTargets.append(FilterTarget(grid: grid, column: column, value: 0))
    }
    func detachExternal() { commands.append(.detachExternal) }
}

@MainActor
@Suite("ShowController et audio")
struct ShowControllerAudioTests {
    private func makeShow() -> (Show, Pad) {
        var grid = PadGrid.empty(name: "G1")
        let pad = Pad(title: "Applaudissements", tint: .vert, audio: AudioClip(fileName: "a.wav"))
        grid.columns[0].slots[2] = pad
        return (Show(name: "S", grids: [grid]), pad)
    }

    private func makeController(
        _ audio: RecordingAudioEngine, show: Show
    ) -> ShowController {
        ShowController(
            show: show, audio: audio, audioDirectory: URL(filePath: "/tmp/lalabob-audio"),
            defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
    }

    /// Les commandes partent de façon asynchrone : on attend qu'il n'en arrive plus.
    private func commands(of audio: RecordingAudioEngine, count: Int = 1) async -> [RecordingAudioEngine.Command] {
        _ = await waitUntil { await audio.commands.count >= count }
        var last = -1
        while await audio.commands.count != last {
            last = await audio.commands.count
            try? await Task.sleep(for: .milliseconds(80))
        }
        return await audio.commands
    }

    @Test func metersComeStraightFromTheEngine() {
        let audio = RecordingAudioEngine()
        let controller = ShowController(
            audio: audio, audioDirectory: URL(filePath: "/tmp/lalabob-audio"),
            defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
        audio.meters.record(column: 3, channel: 1, peak: 0.4)
        #expect(controller.meters.peak(column: 3, channel: 1) == 0.4)
        #expect(controller.meters === audio.meters)
    }

    @Test func doubleClickTriggersThePadAndASingleClickDoesNot() async {
        let audio = RecordingAudioEngine()
        let (show, pad) = makeShow()
        let controller = makeController(audio, show: show)
        controller.isLocked = true

        controller.press(at: GridPosition(column: 0, row: 2))
        try? await Task.sleep(for: .milliseconds(100))
        #expect(!(await audio.commands.contains(.trigger(pad.id))))

        controller.audition(at: GridPosition(column: 0, row: 2))
        let sent = await commands(of: audio, count: 2)
        #expect(sent.last == .trigger(pad.id))
    }

    @Test func editClickSelectsWithoutPlaying() async {
        let audio = RecordingAudioEngine()
        let (show, _) = makeShow()
        let controller = makeController(audio, show: show)
        controller.isLocked = false

        let position = GridPosition(column: 0, row: 2)
        controller.press(at: position)
        #expect(controller.selection == position)
        try? await Task.sleep(for: .milliseconds(100))
        let sent = await audio.commands
        #expect(!sent.contains { if case .trigger = $0 { true } else { false } })
    }

    @Test func clickOnEmptyCellOrInvalidPositionDoesNothing() async {
        let audio = RecordingAudioEngine()
        let controller = makeController(audio, show: .new())
        controller.isLocked = true
        controller.press(at: GridPosition(column: 3, row: 3))
        controller.press(at: GridPosition(column: 9, row: -1))
        try? await Task.sleep(for: .milliseconds(100))
        let sent = await audio.commands
        #expect(!sent.contains { if case .trigger = $0 { true } else { false } })
    }

    @Test func lightPadsAreNotSentToTheAudioEngine() async {
        var grid = PadGrid.empty(name: "G")
        let cue = LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 60))
        grid.columns[6].slots[0] = Pad(title: "Flash", tint: .ambre, light: cue)
        let audio = RecordingAudioEngine()
        let controller = makeController(audio, show: Show(name: "S", grids: [grid]))
        controller.isLocked = true
        controller.audition(at: GridPosition(column: 6, row: 0))
        try? await Task.sleep(for: .milliseconds(100))
        let sent = await audio.commands
        #expect(!sent.contains { if case .trigger = $0 { true } else { false } })
    }

    @Test func commandsArriveInOrder() async {
        let audio = RecordingAudioEngine()
        let (show, pad) = makeShow()
        let controller = makeController(audio, show: show)
        controller.isLocked = true
        let position = GridPosition(column: 0, row: 2)

        controller.audition(at: position)
        controller.audition(at: position)
        controller.stopAll()
        let sent = await commands(of: audio)
        #expect(Array(sent.suffix(3)) == [.trigger(pad.id), .trigger(pad.id), .stopAll])
    }

    @Test func showIsSentToTheEngineAtStartup() async {
        let audio = RecordingAudioEngine()
        let (show, _) = makeShow()
        _ = makeController(audio, show: show)
        let sent = await commands(of: audio, count: 1)
        #expect(sent.first == .configure(padCount: 1))
    }

    @Test func faderUpdatesModelAndEngineAndIsClamped() async {
        let audio = RecordingAudioEngine()
        let controller = makeController(audio, show: .new())

        controller.setColumnLevel(1, level: 0.3)
        #expect(controller.currentGrid.columns[1].level == 0.3)
        controller.setColumnLevel(1, level: 4)
        #expect(controller.currentGrid.columns[1].level == 1)
        controller.setColumnLevel(12, level: 0.5)  // colonne inexistante
        let sent = await commands(of: audio)
        #expect(sent.contains(.level(1, 0.3)))
        #expect(sent.contains(.level(1, 1)))
        #expect(!sent.contains(.level(12, 0.5)))
    }

    @Test("Le volume d'une colonne son est commun à toutes les grilles : changer de grille ne le change pas")
    func faderLevelsAreSharedAcrossGrids() async {
        var second = PadGrid.empty(name: "G2")
        second.columns[0].level = 0.25  // ancien spectacle : un volume par grille
        let show = Show(name: "S", grids: [.empty(name: "G1"), second])
        let audio = RecordingAudioEngine()
        let controller = makeController(audio, show: show)
        // À l'ouverture, toutes les grilles prennent le volume de la grille 1.
        #expect(controller.show.grids.map { $0.columns[0].level } == [0.8, 0.8])

        controller.selectGrid(at: 1)
        controller.setColumnLevel(0, level: 0.3)
        #expect(controller.show.grids.map { $0.columns[0].level } == [0.3, 0.3])
        controller.selectGrid(at: 0)
        #expect(controller.currentGrid.columns[0].level == 0.3)
        let sent = await commands(of: audio)
        #expect(!sent.contains(.level(0, 0.25)))
        #expect(sent.last(where: { if case .level(0, _) = $0 { true } else { false } }) == .level(0, 0.3))
    }

    @Test("L'intensité d'une colonne lumière reste propre à sa grille")
    func lightFaderStaysPerGrid() {
        let audio = RecordingAudioEngine()
        let controller = makeController(audio, show: Show(name: "S", grids: [.empty(name: "G1"), .empty(name: "G2")]))
        controller.setLightFader(column: 6, level: 0.2)
        #expect(controller.show.grids[0].columns[6].level == 0.2)
        #expect(controller.show.grids[1].columns[6].level == PadGrid.empty(name: "x").columns[6].level)
    }

    @Test("⌘Z ne ramène pas le volume en arrière ; une grille ajoutée prend le volume commun")
    func sharedLevelsSurviveUndoAndNewGrids() {
        let audio = RecordingAudioEngine()
        let controller = makeController(audio, show: .new())
        let undo = UndoManager()
        controller.undoManager = undo
        controller.isLocked = false
        controller.setColumnLevel(2, level: 0.4)
        controller.addGrid()
        #expect(controller.show.grids.map { $0.columns[2].level } == [0.4, 0.4])
        controller.setColumnLevel(2, level: 0.6)
        undo.undo()  // annule l'ajout de la grille
        #expect(controller.show.grids.count == 1)
        #expect(controller.show.grids[0].columns[2].level == 0.6)
    }

    @Test func playbackEventsUpdateTheObservableState() async {
        let audio = RecordingAudioEngine()
        let (show, pad) = makeShow()
        let controller = makeController(audio, show: show)
        let observer = Task { await controller.observePlayback() }

        await audio.send(PlaybackEvent(pad: pad.id, state: .playing(startedAt: 10), duration: 4))
        #expect(await waitUntil { await controller.playback[pad.id]?.duration == 4 })
        #expect(controller.playback[pad.id]?.state == .playing(startedAt: 10))

        await audio.send(PlaybackEvent(pad: pad.id, state: .idle, duration: 4))
        #expect(await waitUntil { await controller.playback[pad.id] == nil })
        observer.cancel()
    }

    @Test func chosenOutputIsRememberedAndSent() async {
        let audio = RecordingAudioEngine()
        let defaults = UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!
        let controller = ShowController(show: .new(), audio: audio, defaults: defaults)

        controller.selectOutput(uid: "BuiltInSpeakers")
        #expect(controller.selectedOutputUID == "BuiltInSpeakers")
        #expect(defaults.string(forKey: ShowController.outputDefaultsKey) == "BuiltInSpeakers")
        let sent = await commands(of: audio, count: 1)
        #expect(sent.contains(.output("BuiltInSpeakers")))
    }
}

/// Attend qu'une condition devienne vraie.
func waitUntil(timeout: TimeInterval = 2, _ condition: @Sendable () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}
