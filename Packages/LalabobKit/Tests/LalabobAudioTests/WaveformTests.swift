import AVFoundation
import Foundation
import LalabobModel
import Testing

@testable import LalabobAudio

@Suite("Forme d'onde")
struct WaveformTests {
    @Test func peaksFollowTheSignal() throws {
        let dir = try makeTemporaryDirectory()
        // Moitié à 0,5 puis silence ; canal droit plus fort pour vérifier qu'on prend le max des canaux.
        try writeTestFile(named: "a.wav", in: dir, duration: 2) { $0 < 1 ? 0.5 : 0 }
        let waveform = try Waveform.analyze(dir.appending(path: "a.wav"), buckets: 100)
        #expect(waveform.peaks.count == 100)
        #expect(abs(waveform.duration - 2) < 0.001)
        #expect(abs(waveform.peaks[10] - 0.5) < 0.001)
        #expect(waveform.peaks[90] == 0)
    }

    @Test func negativeSamplesCountAsLoud() throws {
        let dir = try makeTemporaryDirectory()
        try writeTestFile(named: "a.wav", in: dir, duration: 0.5) { _ in -0.8 }
        let waveform = try Waveform.analyze(dir.appending(path: "a.wav"), buckets: 10)
        #expect(waveform.peaks.allSatisfy { abs($0 - 0.8) < 0.001 })
    }

    @Test func shortFileGivesAsManyBucketsAsRequested() throws {
        let dir = try makeTemporaryDirectory()
        try writeTestFile(named: "a.wav", in: dir, duration: 0.001) { _ in 0.3 }  // 44 trames
        let waveform = try Waveform.analyze(dir.appending(path: "a.wav"), buckets: 200)
        #expect(waveform.peaks.count == 200)
    }

    @Test func unreadableFileThrows() throws {
        let dir = try makeTemporaryDirectory()
        let url = dir.appending(path: "faux.wav")
        try Data("pas un son".utf8).write(to: url)
        #expect(throws: (any Error).self) { try Waveform.analyze(url, buckets: 10) }
    }

    @Test func roundTripsThroughCodable() throws {
        let waveform = Waveform(duration: 1.5, peaks: [0, 0.5, 1])
        let data = try JSONEncoder().encode(waveform)
        #expect(try JSONDecoder().decode(Waveform.self, from: data) == waveform)
    }
}

@Suite("Moteur audio : réglages modifiés pendant la lecture", .serialized)
struct EngineSettingsChangeTests {
    @Test func changingTheSettingsOfAPlayingPadDoesNotStopIt() async throws {
        let dir = try makeTemporaryDirectory()
        try writeTestFile(named: "a.wav", in: dir, duration: 2) { _ in 0.5 }
        var pad = Pad(title: "P", tint: .rouge, content: .audio(clip: AudioClip(fileName: "a.wav")))
        var grid = PadGrid.empty(name: "T")
        grid.columns[0].slots[0] = pad
        let engine = AVAudioEngineController(output: .offline(sampleRate: 44100, maxFrames: 4096))
        try await engine.configure(show: Show(name: "T", grids: [grid]), audioDirectory: dir)
        await engine.trigger(pad.id)
        _ = try await engine.renderOffline(frames: 4410)

        pad.content = .audio(clip: AudioClip(fileName: "a.wav", fadeOut: 1, loops: true))
        grid.columns[0].slots[0] = pad
        try await engine.configure(show: Show(name: "T", grids: [grid]), audioDirectory: dir)
        #expect(await engine.state(of: pad.id).isActive)
        let out = try await engine.renderOffline(frames: 4410)
        #expect(abs(out[1000] - 0.5) < 0.001)  // le son en cours continue tel quel
    }
}
