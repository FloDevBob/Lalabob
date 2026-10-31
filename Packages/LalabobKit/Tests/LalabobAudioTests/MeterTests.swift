import AVFoundation
import Foundation
import LalabobModel
import Testing

@testable import LalabobAudio

/// Vumètre : conversion crête → position, balistique d'affichage, stockage sans verrou et mesure réelle du signal
/// de chaque colonne (rendu hors ligne).
@Suite("Vumètre")
struct MeterTests {
    // MARK: Position sur le vumètre

    @Test func peakIsMappedFromMinus60dBToZeroDB() {
        #expect(Gain.meterFraction(forPeak: 0) == 0)
        #expect(Gain.meterFraction(forPeak: 0.001) < 0.001)  // −60 dB : tout en bas
        #expect(abs(Gain.meterFraction(forPeak: 1) - 1) < 1e-9)  // 0 dB : tout en haut
        #expect(abs(Gain.meterFraction(forPeak: 0.5) - (60 + 20 * log10(0.5)) / 60) < 1e-6)
    }

    @Test func peakAboveFullScaleIsClampedAndInvalidValuesAreSilent() {
        #expect(Gain.meterFraction(forPeak: 4) == 1)
        #expect(Gain.meterFraction(forPeak: -1) == 0)
        #expect(Gain.meterFraction(forPeak: .nan) == 0)
        #expect(Gain.meterFraction(forPeak: .infinity) == 0)
    }

    // MARK: Balistique

    @Test func theMeterRisesInstantlyAndFallsAtAFixedRate() {
        #expect(MeterBallistics.next(displayed: 0.2, target: 0.9, elapsed: 0.033) == 0.9)
        let falling = MeterBallistics.next(displayed: 0.9, target: 0.1, elapsed: 0.5)
        #expect(abs(falling - (0.9 - MeterBallistics.fallPerSecond * 0.5)) < 1e-9)
    }

    @Test func theMeterNeverFallsBelowItsTargetOrBelowZero() {
        #expect(MeterBallistics.next(displayed: 0.5, target: 0.45, elapsed: 10) == 0.45)
        #expect(MeterBallistics.next(displayed: 0.1, target: 0, elapsed: 10) == 0)
    }

    @Test func invalidTimesDoNotMoveTheMeterUp() {
        #expect(MeterBallistics.next(displayed: 0.5, target: 0, elapsed: -1) == 0.5)
        #expect(MeterBallistics.next(displayed: 0.5, target: 0, elapsed: .nan) == 0.5)
    }

    // MARK: Stockage

    @Test func eachColumnAndChannelHasItsOwnPeak() {
        let meters = ColumnMeters()
        meters.record(column: 2, channel: 0, peak: 0.25)
        meters.record(column: 2, channel: 1, peak: 0.75)
        #expect(meters.peak(column: 2, channel: 0) == 0.25)
        #expect(meters.peak(column: 2, channel: 1) == 0.75)
        #expect(meters.peak(column: 3, channel: 0) == 0)
    }

    @Test func outOfRangeColumnsAndChannelsAreIgnored() {
        let meters = ColumnMeters()
        meters.record(column: 99, channel: 0, peak: 1)
        meters.record(column: -1, channel: 0, peak: 1)
        meters.record(column: 0, channel: 5, peak: 1)
        #expect(meters.peak(column: 99, channel: 0) == 0)
        #expect(meters.peak(column: 0, channel: 5) == 0)
        #expect((0..<PadGrid.size).allSatisfy { meters.peak(column: $0, channel: 0) == 0 })
    }

    @Test func resetSilencesEveryColumn() {
        let meters = ColumnMeters()
        meters.record(column: 0, channel: 0, peak: 1)
        meters.record(column: 7, channel: 1, peak: 1)
        meters.reset()
        #expect(meters.peak(column: 0, channel: 0) == 0)
        #expect(meters.peak(column: 7, channel: 1) == 0)
    }

    @Test func theLouderChannelGivesTheColumnPeak() {
        let meters = ColumnMeters()
        meters.record(column: 1, channel: 0, peak: 0.2)
        meters.record(column: 1, channel: 1, peak: 0.6)
        #expect(meters.peak(column: 1) == 0.6)
    }

    // MARK: Mesure réelle (rendu hors ligne)

    private func makeShow(_ levels: [Double]) -> (Show, [Pad.ID]) {
        var grid = PadGrid.empty(name: "Test")
        var ids: [Pad.ID] = []
        for (column, level) in levels.enumerated() {
            let pad = Pad(title: "P\(column)", tint: .rouge, content: .audio(clip: AudioClip(fileName: "a.wav")))
            grid.columns[column].slots[0] = pad
            grid.columns[column].level = level
            ids.append(pad.id)
        }
        return (Show(name: "Test", grids: [grid]), ids)
    }

    @Test(.timeLimit(.minutes(1))) func theMeterOfAPlayingColumnFollowsItsSignalAfterTheFader() async throws {
        let dir = try makeTemporaryDirectory()
        try writeTestFile(named: "a.wav", in: dir, duration: 2) { _ in 0.5 }
        let (show, ids) = makeShow([1, 0.5])
        let engine = AVAudioEngineController(output: .offline(sampleRate: 44100, maxFrames: 4096))
        try await engine.configure(show: show, audioDirectory: dir)
        await engine.setColumnLevel(1, level: 0.5)  // c'est ShowController qui envoie les niveaux de fader

        await engine.trigger(ids[0])
        await engine.trigger(ids[1])
        _ = try await engine.renderOffline(frames: 22050)

        let meters = engine.meters
        let ready = await waitUntil { meters.peak(column: 0, channel: 0) > 0.4 && meters.peak(column: 1, channel: 0) > 0.2 }
        #expect(ready)
        #expect(abs(meters.peak(column: 0, channel: 0) - 0.5) < 0.02)
        #expect(abs(meters.peak(column: 0, channel: 1) - 0.5) < 0.02)
        #expect(abs(meters.peak(column: 1, channel: 0) - 0.25) < 0.02)  // fader à 50 % : −6 dB
        #expect(meters.peak(column: 2, channel: 0) == 0)  // colonne sans son
    }

    @Test(.timeLimit(.minutes(1))) func theMeterFallsToSilenceOnceTheSoundHasStopped() async throws {
        let dir = try makeTemporaryDirectory()
        try writeTestFile(named: "a.wav", in: dir, duration: 0.2) { _ in 0.5 }
        let (show, ids) = makeShow([1])
        let engine = AVAudioEngineController(output: .offline(sampleRate: 44100, maxFrames: 4096))
        try await engine.configure(show: show, audioDirectory: dir)

        await engine.trigger(ids[0])
        _ = try await engine.renderOffline(frames: 4410)
        let meters = engine.meters
        #expect(await waitUntil { meters.peak(column: 0, channel: 0) > 0.4 })

        _ = try await engine.renderOffline(frames: 22050)  // le son (0,2 s) est fini depuis longtemps
        #expect(await waitUntil { meters.peak(column: 0, channel: 0) == 0 })
    }
}
