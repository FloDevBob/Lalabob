import AVFoundation
import Foundation
import LalabobModel
import Testing

@testable import LalabobAudio

@Suite("Conversion du volume d'un pad pour le moteur")
struct PadGainConversionTests {
    @Test func zeroDecibelsIsUnchanged() { #expect(Gain.engineDecibels(forPadGainDB: 0) == 0) }

    @Test func boostAndCutPassThrough() {
        #expect(Gain.engineDecibels(forPadGainDB: 12) == 12)
        #expect(Gain.engineDecibels(forPadGainDB: -20) == -20)
    }

    @Test func belowTheSilenceFloorMutes() {
        #expect(Gain.engineDecibels(forPadGainDB: -60) == Gain.engineSilenceDB)
        #expect(Gain.engineDecibels(forPadGainDB: -200) == Gain.engineSilenceDB)
    }

    @Test func invalidAndExtremeValuesStayInsideTheEngineRange() {
        #expect(Gain.engineDecibels(forPadGainDB: .nan) == Gain.engineSilenceDB)
        #expect(Gain.engineDecibels(forPadGainDB: 500) <= 24)
    }
}

/// Le volume d'un pad se règle en direct, y compris pendant la lecture et au-dessus de 0 dB.
@Suite("Volume d'un pad (moteur, hors ligne)", .serialized)
struct PadGainEngineTests {
    private let rate = 44100.0

    private func makeEngine(
        gainDB: Double, level: Float = 0.25, seconds: Double = 2, preloadLimit: TimeInterval = 30
    ) async throws -> (AVAudioEngineController, Pad, PadGrid, URL) {
        let dir = try makeTemporaryDirectory()
        try writeTestFile(named: "a.wav", in: dir, duration: seconds) { _ in level }
        let pad = Pad(
            title: "P", tint: .rouge, content: .audio(clip: AudioClip(fileName: "a.wav", gainDB: gainDB)))
        var grid = PadGrid.empty(name: "T")
        grid.columns[0].slots[0] = pad
        let engine = AVAudioEngineController(output: .offline(sampleRate: rate, maxFrames: 4096), preloadLimit: preloadLimit)
        try await engine.configure(show: Show(name: "T", grids: [grid]), audioDirectory: dir)
        return (engine, pad, grid, dir)
    }

    private func sample(_ engine: AVAudioEngineController, frames: Int = 4410) async throws -> Float {
        let out = try await engine.renderOffline(frames: frames)
        return out[out.count / 2]
    }

    @Test func attenuationAppliesAtTrigger() async throws {
        let (engine, pad, _, _) = try await makeEngine(gainDB: -6.0206)
        await engine.trigger(pad.id)
        #expect(abs(try await sample(engine) - 0.125) < 0.002)
    }

    @Test func boostAboveZeroDecibelsWorks() async throws {
        let (engine, pad, _, _) = try await makeEngine(gainDB: 6.0206)
        await engine.trigger(pad.id)
        #expect(abs(try await sample(engine) - 0.5) < 0.005)
    }

    @Test func belowTheFloorIsSilent() async throws {
        let (engine, pad, _, _) = try await makeEngine(gainDB: -60)
        await engine.trigger(pad.id)
        #expect(abs(try await sample(engine)) < 0.0005)
    }

    @Test func livePadGainChangesAPlayingSoundImmediately() async throws {
        let (engine, pad, _, _) = try await makeEngine(gainDB: 0)
        await engine.trigger(pad.id)
        #expect(abs(try await sample(engine) - 0.25) < 0.002)

        await engine.setPadGain(pad.id, gainDB: -6.0206)
        #expect(abs(try await sample(engine) - 0.125) < 0.002)
        #expect(await engine.state(of: pad.id).isActive)  // aucune relance

        await engine.setPadGain(pad.id, gainDB: 6.0206)
        #expect(abs(try await sample(engine) - 0.5) < 0.005)
    }

    @Test func changingTheGainInTheShowAlsoAppliesLiveWithoutRestarting() async throws {
        let (engine, pad, grid, dir) = try await makeEngine(gainDB: 0)
        await engine.trigger(pad.id)
        _ = try await engine.renderOffline(frames: 4410)

        var louder = pad
        louder.content = .audio(clip: AudioClip(fileName: "a.wav", gainDB: 6.0206))
        var newGrid = grid
        newGrid.columns[0].slots[0] = louder
        try await engine.configure(show: Show(name: "T", grids: [newGrid]), audioDirectory: dir)

        #expect(await engine.state(of: pad.id).isActive)
        #expect(abs(try await sample(engine) - 0.5) < 0.005)
    }

    @Test func gainIsKeptForTheNextTriggerAfterALiveChange() async throws {
        let (engine, pad, _, _) = try await makeEngine(gainDB: 0)
        await engine.setPadGain(pad.id, gainDB: -6.0206)  // avant tout déclenchement
        await engine.trigger(pad.id)
        #expect(abs(try await sample(engine) - 0.125) < 0.002)
    }

    @Test func longStreamedSoundsFollowLiveGainToo() async throws {
        let (engine, pad, _, _) = try await makeEngine(gainDB: 0, seconds: 3, preloadLimit: 0.5)  // lu en flux
        await engine.trigger(pad.id)
        #expect(abs(try await sample(engine) - 0.25) < 0.002)
        await engine.setPadGain(pad.id, gainDB: -6.0206)
        #expect(abs(try await sample(engine) - 0.125) < 0.002)
    }

    @Test func gainOfAnUnknownPadIsIgnored() async throws {
        let (engine, _, _, _) = try await makeEngine(gainDB: 0)
        await engine.setPadGain(UUID(), gainDB: -10)
    }

    @Test func columnFaderStillMultipliesThePadGain() async throws {
        let (engine, pad, _, _) = try await makeEngine(gainDB: -6.0206)
        await engine.setColumnLevel(0, level: 0.5)
        await engine.trigger(pad.id)
        #expect(abs(try await sample(engine) - 0.0625) < 0.002)  // 0,25 × 0,5 × 0,5
    }
}
