import AVFoundation
import Foundation
import LalabobModel
import Testing

@testable import LalabobAudio

/// Déplacer la tête de lecture : un son joue, est en pause ou est arrêté, et reprend à l'endroit demandé.
@Suite("Déplacement de la tête de lecture (moteur, hors ligne)", .serialized)
struct SeekTests {
    private let rate = 44100.0

    /// Fichier en marches de 0,1 s : valeur = (marche + 1) / 20, soit 0,05 puis 0,10 … 1,00 s plus loin.
    private func makeEngine(clip: AudioClip = AudioClip(fileName: "a.wav"), seconds: Double = 2, preloadLimit: TimeInterval = 30)
        async throws -> (AVAudioEngineController, Pad)
    {
        let dir = try makeTemporaryDirectory()
        try writeTestFile(named: "a.wav", in: dir, duration: seconds) { Float(Int($0 * 10) + 1) / 20 }
        let pad = Pad(title: "P", tint: .rouge, content: .audio(clip: clip))
        var grid = PadGrid.empty(name: "T")
        grid.columns[0].slots[0] = pad
        let engine = AVAudioEngineController(output: .offline(sampleRate: rate, maxFrames: 4096), preloadLimit: preloadLimit)
        try await engine.configure(show: Show(name: "T", grids: [grid]), audioDirectory: dir)
        return (engine, pad)
    }

    private func firstSample(_ engine: AVAudioEngineController, frames: Int = 2205) async throws -> Float {
        try await engine.renderOffline(frames: frames)[200]
    }

    @Test func seekWhilePlayingJumpsToThePosition() async throws {
        let (engine, pad) = try await makeEngine()
        await engine.trigger(pad.id)
        _ = try await engine.renderOffline(frames: 2205)
        await engine.seek(pad.id, to: 1.05)  // marche n° 10 → (10 + 1) / 20
        #expect(abs(try await firstSample(engine) - 0.55) < 0.001)
        #expect(await engine.state(of: pad.id).isActive)
    }

    @Test func seekBackwardsWorks() async throws {
        let (engine, pad) = try await makeEngine()
        await engine.trigger(pad.id)
        _ = try await engine.renderOffline(frames: Int(1.5 * rate))
        await engine.seek(pad.id, to: 0.25)  // marche n° 2
        #expect(abs(try await firstSample(engine) - 0.15) < 0.001)
    }

    @Test func seekWhilePausedStaysPausedAndResumesThere() async throws {
        let (engine, pad) = try await makeEngine()
        await engine.trigger(pad.id)
        _ = try await engine.renderOffline(frames: 2205)
        await engine.togglePause(pad.id)
        await engine.seek(pad.id, to: 1.05)

        guard case .paused(let elapsed) = await engine.state(of: pad.id) else {
            Issue.record("le pad devrait rester en pause")
            return
        }
        #expect(abs(elapsed - 1.05) < 0.2)  // l'horloge de pause est celle du mur, pas du rendu
        let silent = try await engine.renderOffline(frames: 2205)
        #expect(silent.map(abs).max() == 0)

        await engine.togglePause(pad.id)
        #expect(abs(try await firstSample(engine) - 0.55) < 0.001)
    }

    @Test func seekOnAStoppedPadStartsPlayingFromThere() async throws {
        let (engine, pad) = try await makeEngine()
        await engine.seek(pad.id, to: 1.05)
        #expect(await engine.state(of: pad.id).isActive)
        #expect(abs(try await firstSample(engine) - 0.55) < 0.001)
    }

    @Test func seekIsRelativeToTheTrimmedStart() async throws {
        let (engine, pad) = try await makeEngine(clip: AudioClip(fileName: "a.wav", trimStart: 0.5))
        await engine.trigger(pad.id)
        _ = try await engine.renderOffline(frames: 2205)
        await engine.seek(pad.id, to: 0.55)  // 0,55 s après 0,5 s = 1,05 s dans le fichier
        #expect(abs(try await firstSample(engine) - 0.55) < 0.001)
    }

    @Test func seekPastTheEndNeverCrashesAndEndsThePad() async throws {
        let (engine, pad) = try await makeEngine()
        await engine.trigger(pad.id)
        await engine.seek(pad.id, to: 500)
        _ = try await engine.renderOffline(frames: Int(0.5 * rate))
        #expect(await waitUntil { await engine.state(of: pad.id) == .idle })
    }

    @Test func seekInsideALoopKeepsLooping() async throws {
        let (engine, pad) = try await makeEngine(clip: AudioClip(fileName: "a.wav", loops: true), seconds: 1)
        await engine.trigger(pad.id)
        await engine.seek(pad.id, to: 0.55)
        _ = try await engine.renderOffline(frames: Int(1.5 * rate))  // dépasse la fin : la boucle continue
        #expect(await engine.state(of: pad.id).isActive)
    }

    @Test func longStreamedSoundsCanBeSoughtToo() async throws {
        let (engine, pad) = try await makeEngine(seconds: 3, preloadLimit: 0.5)
        await engine.trigger(pad.id)
        _ = try await engine.renderOffline(frames: 2205)
        await engine.seek(pad.id, to: 2.05)  // marche n° 20
        #expect(abs(try await firstSample(engine) - 1.05) < 0.001)
    }

    @Test func seekOnAnUnknownPadIsIgnored() async throws {
        let (engine, _) = try await makeEngine()
        await engine.seek(UUID(), to: 1)
    }

    @Test func padGainSurvivesASeek() async throws {
        let (engine, pad) = try await makeEngine(clip: AudioClip(fileName: "a.wav", gainDB: -6.0206))
        await engine.trigger(pad.id)
        await engine.seek(pad.id, to: 1.05)
        #expect(abs(try await firstSample(engine) - 0.275) < 0.002)  // 0,55 × 0,5
    }
}
