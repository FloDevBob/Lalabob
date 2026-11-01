import AVFoundation
import Foundation
import LalabobModel
import Testing

@testable import LalabobAudio

/// Arrêt d'un son : un fondu de sortie très bref (40 ms) évite le « clac » d'une coupure nette.
@Suite("Fondu à l'arrêt")
struct StopFadeCurveTests {
    @Test func startsAtFullLevelAndEndsSilent() {
        #expect(StopFade.gain(elapsed: 0) == 1)
        #expect(StopFade.gain(elapsed: StopFade.duration) == 0)
        #expect(StopFade.gain(elapsed: StopFade.duration * 3) == 0)
    }

    @Test func neverIncreasesAndStaysInsideZeroToOne() {
        var previous: Float = 1
        for step in 0...100 {
            let gain = StopFade.gain(elapsed: StopFade.duration * Double(step) / 100)
            #expect(gain <= previous && gain >= 0 && gain <= 1)
            previous = gain
        }
    }

    @Test func invalidTimesAreHarmless() {
        #expect(StopFade.gain(elapsed: -1) == 1)
        #expect(StopFade.gain(elapsed: .nan) == 1)
    }

    @Test func isShortEnoughNotToDelayAnythingAudibly() {
        #expect(StopFade.duration > 0.01 && StopFade.duration <= 0.06)
    }
}

@Suite("Fondu à l'arrêt (moteur hors ligne)", .serialized)
struct StopFadeEngineTests {
    private let rate = 44100.0
    static var fadeFramesAt44k: Int { Int((StopFade.duration * 44100).rounded(.up)) }
    private var fadeFrames: Int { Self.fadeFramesAt44k }

    private func makeShow(_ clips: [AudioClip]) -> (Show, [Pad.ID]) {
        var grid = PadGrid.empty(name: "Test")
        var ids: [Pad.ID] = []
        for (column, clip) in clips.enumerated() {
            let pad = Pad(title: "P\(column)", tint: .rouge, content: .audio(clip: clip))
            grid.columns[column].slots[0] = pad
            grid.columns[column].level = 1
            ids.append(pad.id)
        }
        return (Show(name: "Test", grids: [grid]), ids)
    }

    private func makeEngine(_ clips: [AudioClip], value: Float = 0.5) async throws -> (AVAudioEngineController, [Pad.ID]) {
        let dir = try makeTemporaryDirectory()
        try writeTestFile(named: "a.wav", in: dir, duration: 3, channels: 2) { _ in value }
        let (show, ids) = makeShow(clips)
        let engine = AVAudioEngineController(output: .offline(sampleRate: rate, maxFrames: 4096))
        try await engine.configure(show: show, audioDirectory: dir)
        return (engine, ids)
    }

    /// Valeurs du canal gauche.
    private func left(_ samples: [Float]) -> [Float] { stride(from: 0, to: samples.count, by: 2).map { samples[$0] } }

    @Test func aStoppedSoundFadesOutInsteadOfBeingCut() async throws {
        let (engine, ids) = try await makeEngine([AudioClip(fileName: "a.wav")])
        await engine.trigger(ids[0])
        _ = try await engine.renderOffline(frames: 4410)

        await engine.stop(ids[0])
        #expect(await engine.state(of: ids[0]) == .idle)  // l'interface et les LED voient l'arrêt tout de suite
        let out = left(try await engine.renderOffline(frames: fadeFrames + 2000))

        #expect(abs(out[0] - 0.5) < 0.05)  // le son ne tombe pas à zéro d'un coup
        #expect(out[fadeFrames / 2] > 0.05 && out[fadeFrames / 2] < 0.45)  // à mi-chemin : ni plein ni muet
        #expect(out[(fadeFrames + 200)...].allSatisfy { $0 == 0 })  // puis le silence
        let biggestStep = zip(out, out.dropFirst()).map { abs($0 - $1) }.max() ?? 1
        #expect(biggestStep < 0.02)  // aucune marche brutale (un clic) : la coupure nette en ferait une de 0,5
    }

    @Test func theFadeIsMonotonic() async throws {
        let (engine, ids) = try await makeEngine([AudioClip(fileName: "a.wav")])
        await engine.trigger(ids[0])
        _ = try await engine.renderOffline(frames: 4410)
        await engine.stop(ids[0])
        let out = left(try await engine.renderOffline(frames: fadeFrames + 500))
        let fading = out.prefix(fadeFrames)
        #expect(zip(fading, fading.dropFirst()).allSatisfy { $1 <= $0 + 0.001 })
    }

    @Test func stopAllFadesEveryVoice() async throws {
        let clips = (0..<3).map { _ in AudioClip(fileName: "a.wav", loops: true) }
        let (engine, ids) = try await makeEngine(clips, value: 0.2)
        for id in ids { await engine.trigger(id) }
        _ = try await engine.renderOffline(frames: 4410)

        await engine.stopAll()
        let out = left(try await engine.renderOffline(frames: fadeFrames + 2000))
        #expect(out[0] > 0.5)  // trois sons à 0,2 : on entend toujours le mélange au premier échantillon
        #expect(out[(fadeFrames + 200)...].allSatisfy { $0 == 0 })
        for id in ids { #expect(await engine.state(of: id) == .idle) }
        let biggestStep = zip(out, out.dropFirst()).map { abs($0 - $1) }.max() ?? 1
        #expect(biggestStep < 0.02)
    }

    @Test func aStopBehaviourRetriggerAlsoFades() async throws {
        let (engine, ids) = try await makeEngine([AudioClip(fileName: "a.wav", retrigger: .stop)])
        await engine.trigger(ids[0])
        _ = try await engine.renderOffline(frames: 4410)
        await engine.trigger(ids[0])  // 2e appui : arrêt
        let out = left(try await engine.renderOffline(frames: fadeFrames + 2000))
        #expect(abs(out[0] - 0.5) < 0.05)
        #expect(out[(fadeFrames + 200)...].allSatisfy { $0 == 0 })
    }

    @Test func playingAgainDuringTheFadeRestartsAtFullLevel() async throws {
        let (engine, ids) = try await makeEngine([AudioClip(fileName: "a.wav")])
        await engine.trigger(ids[0])
        _ = try await engine.renderOffline(frames: 4410)
        await engine.stop(ids[0])
        _ = try await engine.renderOffline(frames: 400)  // en plein fondu
        await engine.trigger(ids[0])
        let out = left(try await engine.renderOffline(frames: fadeFrames + 2000))
        #expect(abs(out[200] - 0.5) < 0.01)
        #expect(abs((out.last ?? 0) - 0.5) < 0.01)  // le fondu d'avant ne vient pas éteindre le nouveau son
        #expect(await engine.state(of: ids[0]) != .idle)
    }

    @Test func aPausedSoundStopsAtOnceBecauseNothingIsSounding() async throws {
        let (engine, ids) = try await makeEngine([AudioClip(fileName: "a.wav")])
        await engine.trigger(ids[0])
        _ = try await engine.renderOffline(frames: 4410)
        await engine.togglePause(ids[0])
        _ = try await engine.renderOffline(frames: 2000)
        await engine.stop(ids[0])
        let out = try await engine.renderOffline(frames: 3000)
        #expect(out.allSatisfy { $0 == 0 })
        #expect(await engine.state(of: ids[0]) == .idle)
    }

    @Test func pressingAgainAfterTheFadeStartsFromTheBeginning() async throws {
        let (engine, ids) = try await makeEngine([AudioClip(fileName: "a.wav")])
        await engine.trigger(ids[0])
        _ = try await engine.renderOffline(frames: 4410)
        await engine.stop(ids[0])
        _ = try await engine.renderOffline(frames: fadeFrames + 3000)
        await engine.trigger(ids[0])
        let out = left(try await engine.renderOffline(frames: 2000))
        #expect(abs(out[500] - 0.5) < 0.01)
    }
}
