import Foundation
import LalabobAudio
import LalabobModel
import Testing

@testable import LalabobEngine

/// Moteur factice : enregistre les commandes reçues, dans l'ordre.
actor RecordingAudioEngine: AudioEngineControlling {
    enum Command: Equatable, Sendable {
        case configure(padCount: Int)
        case trigger(Pad.ID)
        case togglePause(Pad.ID)
        case stop(Pad.ID)
        case stopAll
        case level(Int, Double)
        case output(String?)
    }

    nonisolated let events: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    private(set) var commands: [Command] = []

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
}

@MainActor
@Suite("ShowController et audio")
struct ShowControllerAudioTests {
    private func makeShow() -> (Show, Pad) {
        var grid = PadGrid.empty(name: "G1")
        let pad = Pad(title: "Applaudissements", tint: .vert, content: .audio(clip: AudioClip(fileName: "a.wav")))
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

    @Test func liveClickTriggersThePad() async {
        let audio = RecordingAudioEngine()
        let (show, pad) = makeShow()
        let controller = makeController(audio, show: show)
        controller.mode = .live

        controller.press(at: GridPosition(column: 0, row: 2))
        let sent = await commands(of: audio)
        #expect(sent.last == .trigger(pad.id))
    }

    @Test func editClickSelectsWithoutPlaying() async {
        let audio = RecordingAudioEngine()
        let (show, _) = makeShow()
        let controller = makeController(audio, show: show)
        controller.mode = .edit

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
        controller.mode = .live
        controller.press(at: GridPosition(column: 3, row: 3))
        controller.press(at: GridPosition(column: 9, row: -1))
        try? await Task.sleep(for: .milliseconds(100))
        let sent = await audio.commands
        #expect(!sent.contains { if case .trigger = $0 { true } else { false } })
    }

    @Test func lightPadsAreNotSentToTheAudioEngine() async {
        var grid = PadGrid.empty(name: "G")
        let cue = LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 60))
        grid.columns[6].slots[0] = Pad(title: "Flash", tint: .ambre, content: .light(cue: cue))
        let audio = RecordingAudioEngine()
        let controller = makeController(audio, show: Show(name: "S", grids: [grid]))
        controller.mode = .live
        controller.press(at: GridPosition(column: 6, row: 0))
        try? await Task.sleep(for: .milliseconds(100))
        let sent = await audio.commands
        #expect(!sent.contains { if case .trigger = $0 { true } else { false } })
    }

    @Test func commandsArriveInOrder() async {
        let audio = RecordingAudioEngine()
        let (show, pad) = makeShow()
        let controller = makeController(audio, show: show)
        controller.mode = .live
        let position = GridPosition(column: 0, row: 2)

        controller.press(at: position)
        controller.press(at: position)
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

    @Test func switchingGridSendsItsFaderLevels() async {
        var second = PadGrid.empty(name: "G2")
        second.columns[0].level = 0.25
        let show = Show(name: "S", grids: [.empty(name: "G1"), second])
        let audio = RecordingAudioEngine()
        let controller = makeController(audio, show: show)

        controller.selectGrid(at: 1)
        let sent = await commands(of: audio)
        #expect(sent.contains(.level(0, 0.25)))
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
