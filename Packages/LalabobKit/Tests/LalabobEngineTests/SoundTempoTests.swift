import Foundation
import LalabobAudio
import LalabobDMX
import LalabobModel
import Testing

@testable import LalabobEngine

/// Tempo des sons (J14, étape 3b) : analyse en arrière-plan, son qui donne le tempo, corrections à la main, alternance
/// calée sur le son en cours.
@MainActor
@Suite("Tempo des sons")
struct SoundTempoTests {
    struct FakeAnalyzer: TempoAnalyzing {
        let results: [String: TempoEstimate]
        func tempo(for url: URL) async -> TempoEstimate? { results[url.lastPathComponent] }
    }

    static let beat = TempoEstimate(bpm: 120, firstBeat: 0.25, confidence: 0.8)
    static let slow = TempoEstimate(bpm: 90, firstBeat: 0.1, confidence: 0.6)
    static let vague = TempoEstimate(bpm: 101, firstBeat: 0.3, confidence: 0.05)

    let drums = Pad(title: "Batterie", tint: .rouge, audio: AudioClip(fileName: "drums.wav", trimStart: 1))
    let groove = Pad(title: "Groove", tint: .vert, audio: AudioClip(fileName: "groove.wav"))
    let rain = Pad(title: "Pluie", tint: .ciel, audio: AudioClip(fileName: "rain.wav"))
    let flash = Pad(
        title: "Alternance", tint: .ambre,
        light: LightCue(
            look: LightLook(
                fadeIn: 0,
                content: .alternate(
                    AlternateLook(
                        a: LightColor(hue: 0, saturation: 1), b: LightColor(hue: 240, saturation: 1), every: .beat,
                        switchFade: 0, fallbackBPM: 100)))))

    let drumsAt = GridPosition(column: 0, row: 0)
    let grooveAt = GridPosition(column: 0, row: 1)
    let rainAt = GridPosition(column: 1, row: 0)

    struct Rig {
        let audio: RecordingAudioEngine
        let controller: ShowController
        let observer: Task<Void, Never>
    }

    func makeRig(locked: Bool = false, mode: LightingMode = .lightKey) async -> Rig {
        var grid = PadGrid.empty(name: "G")
        grid.columns[0].slots[0] = drums
        grid.columns[0].slots[1] = groove
        grid.columns[1].slots[0] = rain
        grid.columns[6].slots[0] = flash
        var show = Show(name: "S", grids: [grid])
        show.lighting.mode = mode
        let audio = RecordingAudioEngine()
        let controller = ShowController(
            show: show, audio: audio, audioDirectory: URL(filePath: "/tmp/lalabob-tempo"),
            defaults: UserDefaults(suiteName: "SoundTempoTests-\(UUID().uuidString)")!, isLocked: locked)
        controller.tempoAnalyzer = FakeAnalyzer(results: ["drums.wav": Self.beat, "groove.wav": Self.slow, "rain.wav": Self.vague])
        let rig = Rig(audio: audio, controller: controller, observer: Task { await controller.observePlayback() })
        _ = await waitUntil { await controller.detectedTempos.count == 3 }
        return rig
    }

    func send(_ rig: Rig, _ pad: Pad, _ state: PlaybackState, duration: TimeInterval = 30) async {
        await rig.audio.send(PlaybackEvent(pad: pad.id, state: state, duration: duration))
        _ = await waitUntil { await rig.controller.playback[pad.id]?.state == (state == .idle ? nil : state) }
    }

    // MARK: - Détection

    @Test("Chaque son du spectacle est analysé une fois, en arrière-plan")
    func analysis() async {
        let rig = await makeRig()
        #expect(rig.controller.detectedTempo(for: drums.audio!) == Self.beat)
        #expect(rig.controller.beatGrid(for: drums.audio!) == BeatGrid(bpm: 120, firstBeat: 0.25))
        // Pas assez sûr : pas de tempo.
        #expect(rig.controller.beatGrid(for: rain.audio!) == nil)
    }

    // MARK: - Le son qui donne le tempo

    @Test("Le dernier son lancé qui a un tempo ; s'il s'arrête, le précédent ; une pause ou un son sans tempo ne compte pas")
    func tempoSource() async {
        let rig = await makeRig()
        #expect(rig.controller.tempoSource(atUptime: 0) == nil)
        await send(rig, drums, .playing(startedAt: 100))
        // Parti à 100 s depuis 1 s dans le fichier : le temps du fichier à 0,25 s tombe à 100 − 0,75 s.
        #expect(rig.controller.tempoSource(atUptime: 101) == TempoSource(bpm: 120, beatUptime: 99.25))
        await send(rig, groove, .playing(startedAt: 102))
        #expect(rig.controller.tempoSource(atUptime: 103)?.bpm == 90)
        await send(rig, rain, .playing(startedAt: 104))  // sans tempo : ne prend pas la main
        #expect(rig.controller.tempoSource(atUptime: 105)?.bpm == 90)
        await send(rig, groove, .paused(elapsed: 3))
        #expect(rig.controller.tempoSource(atUptime: 105)?.bpm == 120)
        await send(rig, groove, .playing(startedAt: 102))  // reprise : garde son rang, reste le dernier lancé
        #expect(rig.controller.tempoSource(atUptime: 105)?.bpm == 90)
        await send(rig, groove, .idle)
        #expect(rig.controller.tempoSource(atUptime: 106)?.bpm == 120)
        await send(rig, drums, .idle)
        #expect(rig.controller.tempoSource(atUptime: 107) == nil)
    }

    @Test("Boucle : la grille repart à chaque tour")
    func loopingSource() async {
        var grid = PadGrid.empty(name: "G")
        let loop = Pad(title: "Boucle", tint: .rouge, audio: AudioClip(fileName: "drums.wav", loops: true))
        grid.columns[0].slots[0] = loop
        let audio = RecordingAudioEngine()
        let controller = ShowController(
            show: Show(name: "S", grids: [grid]), audio: audio, audioDirectory: URL(filePath: "/tmp/lalabob-tempo"),
            defaults: UserDefaults(suiteName: "SoundTempoTests-\(UUID().uuidString)")!)
        controller.tempoAnalyzer = FakeAnalyzer(results: ["drums.wav": Self.beat])
        let observer = Task { await controller.observePlayback() }
        defer { observer.cancel() }
        _ = await waitUntil { await !controller.detectedTempos.isEmpty }
        await audio.send(PlaybackEvent(pad: loop.id, state: .playing(startedAt: 100), duration: 4.1))
        _ = await waitUntil { await controller.playback[loop.id] != nil }
        #expect(controller.tempoSource(atUptime: 101)?.beatUptime == 100.25)
        #expect(controller.tempoSource(atUptime: 109)?.beatUptime == 100 + 2 * 4.1 + 0.25)
    }

    // MARK: - Corrections

    @Test("×2, ÷2, pas de tempo, revenir à la détection : une annulation chacune")
    func corrections() async {
        let rig = await makeRig()
        let undo = UndoManager()
        undo.groupsByEvent = false
        rig.controller.undoManager = undo
        rig.controller.doubleTempo(at: drumsAt)
        #expect(rig.controller.pad(at: drumsAt)?.audio?.tempo == .manual(BeatGrid(bpm: 240, firstBeat: 0.25)))
        rig.controller.halveTempo(at: drumsAt)
        rig.controller.halveTempo(at: drumsAt)
        #expect(rig.controller.beatGrid(for: rig.controller.pad(at: drumsAt)!.audio!)?.bpm == 60)
        rig.controller.setTempo(at: drumsAt, SoundTempo.none)
        #expect(rig.controller.beatGrid(for: rig.controller.pad(at: drumsAt)!.audio!) == nil)
        undo.undo()
        #expect(rig.controller.beatGrid(for: rig.controller.pad(at: drumsAt)!.audio!)?.bpm == 60)
        rig.controller.setTempo(at: drumsAt, nil)
        #expect(rig.controller.beatGrid(for: rig.controller.pad(at: drumsAt)!.audio!)?.bpm == 120)
        // Un son sans tempo fiable peut en recevoir un à la main.
        rig.controller.setTempo(at: rainAt, .manual(BeatGrid(bpm: 80, firstBeat: 0)))
        #expect(rig.controller.beatGrid(for: rig.controller.pad(at: rainAt)!.audio!)?.bpm == 80)
    }

    @Test("Corrections refusées verrouillé")
    func lockedRefused() async {
        let rig = await makeRig(locked: true)
        rig.controller.doubleTempo(at: drumsAt)
        #expect(rig.controller.pad(at: drumsAt)?.audio?.tempo == nil)
    }

    @Test("Taper le tempo : 4 appuis donnent le tempo ; sur un son qui joue, le dernier appui marque un temps")
    func tapTempo() async {
        let rig = await makeRig()
        #expect(rig.controller.tapTempo(at: rainAt, uptime: 10) == nil)
        #expect(rig.controller.tapTempo(at: rainAt, uptime: 10.5) == nil)
        #expect(rig.controller.tapTempo(at: rainAt, uptime: 11) == nil)
        #expect(rig.controller.tapTempo(at: rainAt, uptime: 11.5) == 120)
        // Trop long entre deux appuis : on recompte.
        #expect(rig.controller.tapTempo(at: rainAt, uptime: 20) == nil)

        await send(rig, groove, .playing(startedAt: 50))
        for time in [51.0, 51.6, 52.2, 52.8] { rig.controller.tapTempo(at: grooveAt, uptime: time) }
        guard case .manual(let grid)? = rig.controller.pad(at: grooveAt)?.audio?.tempo else {
            Issue.record("tempo manuel attendu")
            return
        }
        #expect(abs(grid.bpm - 100) < 0.01)
        #expect(abs(grid.firstBeat - 2.8.truncatingRemainder(dividingBy: 0.6)) < 1e-9)
    }

    // MARK: - Alternance

    @Test("Mode Projecteurs : l'alternance suit le son en cours, puis le tempo de repli quand il s'arrête")
    func alternateFollowsSound() async {
        let rig = await makeRig(mode: .dmx)
        let session = DMXSession(
            defaults: UserDefaults(suiteName: "SoundTempoTests-\(UUID().uuidString)")!, now: { 1000 }, uptime: { 200 },
            makeTransport: { SilentDMX() })
        session.attach(rig.controller)
        rig.controller.audition(at: GridPosition(column: 6, row: 0))
        #expect(session.console?.beatClock == nil)
        await send(rig, drums, .playing(startedAt: 190))
        _ = await waitUntil { await session.console?.beatClock != nil }
        // Temps du son à 189,25 s (horloge des sons) = 989,25 s (horloge de la lumière).
        #expect(session.console?.beatClock == LightConsole.BeatClock(bpm: 120, origin: 989.25))
        await send(rig, drums, .idle)
        _ = await waitUntil { await session.console?.beatClock == nil }
        #expect(session.console?.beatClock == nil)
    }
}
