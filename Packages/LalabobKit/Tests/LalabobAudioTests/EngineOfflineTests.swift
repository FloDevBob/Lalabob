import AVFoundation
import Foundation
import LalabobModel
import Testing

@testable import LalabobAudio

/// Tests du moteur complet en rendu hors ligne : pas de carte son, résultat déterministe.
@Suite("Moteur audio (hors ligne)", .serialized)
struct EngineOfflineTests {
    private let rate = 44100.0

    /// Spectacle d'une grille ; `clips[i]` va dans la colonne `i`, rangée 0.
    private func makeShow(_ clips: [AudioClip], levels: [Double] = []) -> (Show, [Pad.ID]) {
        var grid = PadGrid.empty(name: "Test")
        var ids: [Pad.ID] = []
        for (i, clip) in clips.enumerated() {
            let pad = Pad(title: "P\(i)", tint: .rouge, content: .audio(clip: clip))
            grid.columns[i].slots[0] = pad
            if i < levels.count { grid.columns[i].level = levels[i] }
            ids.append(pad.id)
        }
        return (Show(name: "Test", grids: [grid]), ids)
    }

    private func makeEngine(show: Show, directory: URL) async throws -> AVAudioEngineController {
        let engine = AVAudioEngineController(output: .offline(sampleRate: rate, maxFrames: 4096))
        try await engine.configure(show: show, audioDirectory: directory)
        return engine
    }

    private func peak(_ samples: ArraySlice<Float>) -> Float { samples.map(abs).max() ?? 0 }

    @Test func triggerPlaysTheClipAtUnityGain() async throws {
        let dir = try makeTemporaryDirectory()
        try writeTestFile(named: "a.wav", in: dir, duration: 1) { _ in 0.5 }
        let (show, ids) = makeShow([AudioClip(fileName: "a.wav")], levels: [1])
        let engine = try await makeEngine(show: show, directory: dir)

        await engine.trigger(ids[0])
        let out = try await engine.renderOffline(frames: 4410)
        #expect(abs(out[1000] - 0.5) < 0.001)
    }

    @Test func columnFaderScalesTheOutput() async throws {
        let dir = try makeTemporaryDirectory()
        try writeTestFile(named: "a.wav", in: dir, duration: 1) { _ in 0.5 }
        let (show, ids) = makeShow([AudioClip(fileName: "a.wav")], levels: [1])
        let engine = try await makeEngine(show: show, directory: dir)

        await engine.setColumnLevel(0, level: 0.5)
        await engine.trigger(ids[0])
        let out = try await engine.renderOffline(frames: 4410)
        #expect(abs(out[1000] - 0.25) < 0.001)
    }

    @Test func trimStartsPlaybackAtTheRightPlace() async throws {
        let dir = try makeTemporaryDirectory()
        // 0,2 pendant la première seconde, 0,8 ensuite.
        try writeTestFile(named: "a.wav", in: dir, duration: 2) { $0 < 1 ? 0.2 : 0.8 }
        let (show, ids) = makeShow([AudioClip(fileName: "a.wav", trimStart: 1)], levels: [1])
        let engine = try await makeEngine(show: show, directory: dir)

        await engine.trigger(ids[0])
        let out = try await engine.renderOffline(frames: 4410)
        #expect(abs(out[100] - 0.8) < 0.001)
    }

    @Test func fadeInRampsUp() async throws {
        let dir = try makeTemporaryDirectory()
        try writeTestFile(named: "a.wav", in: dir, duration: 2) { _ in 1 }
        let (show, ids) = makeShow([AudioClip(fileName: "a.wav", fadeIn: 1)], levels: [1])
        let engine = try await makeEngine(show: show, directory: dir)

        await engine.trigger(ids[0])
        let out = try await engine.renderOffline(frames: Int(rate))
        #expect(out[0] < 0.001)
        let middle: Int = Int(rate / 2) * 2
        #expect(abs(out[middle] - 0.5) < 0.01)
    }

    @Test func clipEndsAndPadReturnsToIdle() async throws {
        let dir = try makeTemporaryDirectory()
        try writeTestFile(named: "a.wav", in: dir, duration: 0.2) { _ in 0.5 }
        let (show, ids) = makeShow([AudioClip(fileName: "a.wav")], levels: [1])
        let engine = try await makeEngine(show: show, directory: dir)

        await engine.trigger(ids[0])
        let out = try await engine.renderOffline(frames: Int(rate))
        let tailStart: Int = Int(0.3 * rate) * 2
        let tail = out[tailStart...]
        #expect(peak(tail) == 0)
        let id = ids[0]
        let becameIdle = await waitUntil { await engine.state(of: id) == .idle }
        #expect(becameIdle)
    }

    @Test func loopNeverEnds() async throws {
        let dir = try makeTemporaryDirectory()
        try writeTestFile(named: "a.wav", in: dir, duration: 0.2) { _ in 0.5 }
        let (show, ids) = makeShow([AudioClip(fileName: "a.wav", loops: true)], levels: [1])
        let engine = try await makeEngine(show: show, directory: dir)

        await engine.trigger(ids[0])
        let out = try await engine.renderOffline(frames: Int(rate) * 2)
        let late: Int = Int(1.9 * rate) * 2
        #expect(abs(out[late] - 0.5) < 0.001)
        #expect(await engine.state(of: ids[0]).isActive)
    }

    @Test func pauseSilencesAndResumeContinues() async throws {
        let dir = try makeTemporaryDirectory()
        // Marches de 0,1 s : 0.1, 0.2, 0.3, …
        try writeTestFile(named: "a.wav", in: dir, duration: 2) { Float(Int($0 * 10) + 1) / 10 }
        let (show, ids) = makeShow([AudioClip(fileName: "a.wav")], levels: [1])
        let engine = try await makeEngine(show: show, directory: dir)

        await engine.trigger(ids[0])
        _ = try await engine.renderOffline(frames: Int(0.25 * rate))
        await engine.togglePause(ids[0])
        guard case .paused = await engine.state(of: ids[0]) else {
            Issue.record("le pad devrait être en pause")
            return
        }
        let silent = try await engine.renderOffline(frames: 4410)
        #expect(peak(silent[...]) == 0)

        await engine.togglePause(ids[0])
        let resumed = try await engine.renderOffline(frames: 4410)
        // On reprend vers 0,25 s : troisième marche (0.3), pas le début (0.1).
        #expect(abs(resumed[200] - 0.3) < 0.001)
    }

    @Test func retriggerRestartsFromTheBeginning() async throws {
        let dir = try makeTemporaryDirectory()
        try writeTestFile(named: "a.wav", in: dir, duration: 2) { $0 < 0.5 ? 0.2 : 0.8 }
        let (show, ids) = makeShow([AudioClip(fileName: "a.wav")], levels: [1])
        let engine = try await makeEngine(show: show, directory: dir)

        await engine.trigger(ids[0])
        _ = try await engine.renderOffline(frames: Int(0.8 * rate))
        await engine.trigger(ids[0])
        let out = try await engine.renderOffline(frames: 2205)
        #expect(abs(out[200] - 0.2) < 0.001)
    }

    @Test func retriggerWithStopBehaviorStops() async throws {
        let dir = try makeTemporaryDirectory()
        try writeTestFile(named: "a.wav", in: dir, duration: 2) { _ in 0.5 }
        let clip = AudioClip(fileName: "a.wav", retrigger: .stop)
        let (show, ids) = makeShow([clip], levels: [1])
        let engine = try await makeEngine(show: show, directory: dir)

        await engine.trigger(ids[0])
        _ = try await engine.renderOffline(frames: 4410)
        await engine.trigger(ids[0])
        #expect(await engine.state(of: ids[0]) == .idle)
        let out = try await engine.renderOffline(frames: 4410)
        #expect(peak(out[...]) == 0)
    }

    @Test func stopAllSilencesEverything() async throws {
        let dir = try makeTemporaryDirectory()
        try writeTestFile(named: "a.wav", in: dir, duration: 2) { _ in 0.3 }
        let clips = (0..<4).map { _ in AudioClip(fileName: "a.wav", loops: true) }
        let (show, ids) = makeShow(clips, levels: [1, 1, 1, 1])
        let engine = try await makeEngine(show: show, directory: dir)

        for id in ids { await engine.trigger(id) }
        _ = try await engine.renderOffline(frames: 4410)
        await engine.stopAll()
        let out = try await engine.renderOffline(frames: 4410)
        #expect(peak(out[...]) == 0)
        for id in ids { #expect(await engine.state(of: id) == .idle) }
    }

    @Test func sixteenSimultaneousVoicesAreMixed() async throws {
        let dir = try makeTemporaryDirectory()
        try writeTestFile(named: "a.wav", in: dir, duration: 1) { _ in 0.05 }
        var grid = PadGrid.empty(name: "Test")
        var ids: [Pad.ID] = []
        for column in 0..<2 {
            grid.columns[column].level = 1
            for row in 0..<8 {
                let pad = Pad(title: "p", tint: .vert, content: .audio(clip: AudioClip(fileName: "a.wav")))
                grid.columns[column].slots[row] = pad
                ids.append(pad.id)
            }
        }
        let engine = try await makeEngine(show: Show(name: "T", grids: [grid]), directory: dir)

        for id in ids { await engine.trigger(id) }
        let out = try await engine.renderOffline(frames: 4410)
        #expect(abs(out[1000] - 0.8) < 0.001)  // 16 × 0,05
    }

    @Test func missingFileDoesNotCrashNorPlay() async throws {
        let dir = try makeTemporaryDirectory()
        let (show, ids) = makeShow([AudioClip(fileName: "absent.wav")], levels: [1])
        let engine = try await makeEngine(show: show, directory: dir)

        await engine.trigger(ids[0])
        #expect(await engine.state(of: ids[0]) == .idle)
    }

    @Test func unknownPadIsIgnored() async throws {
        let dir = try makeTemporaryDirectory()
        let engine = try await makeEngine(show: .new(), directory: dir)
        await engine.trigger(UUID())
        await engine.togglePause(UUID())
        await engine.stop(UUID())
    }
}
