import Foundation
import LalabobModel
import Testing

@testable import LalabobAudio

@Suite("Gain")
struct GainTests {
    @Test func zeroDecibelsIsUnity() {
        #expect(Gain.linear(fromDB: 0) == 1)
    }

    @Test func minusSixDecibelsIsAboutHalf() {
        #expect(abs(Gain.linear(fromDB: -6.0206) - 0.5) < 0.001)
    }

    @Test func belowFloorIsSilence() {
        #expect(Gain.linear(fromDB: -60) == 0)
        #expect(Gain.linear(fromDB: -90) == 0)
    }

    @Test func faderLevelIsClampedToUnitRange() {
        #expect(Gain.faderLevel(1.7) == 1)
        #expect(Gain.faderLevel(-0.2) == 0)
        #expect(Gain.faderLevel(.nan) == 0)
        #expect(Gain.faderLevel(0.4) == 0.4)
    }
}

@Suite("ClipTiming")
struct ClipTimingTests {
    @Test func defaultsCoverTheWholeFile() {
        let timing = ClipTiming(clip: AudioClip(fileName: "a.wav"), fileDuration: 10)
        #expect(timing.start == 0)
        #expect(timing.end == 10)
        #expect(timing.duration == 10)
        #expect(!timing.isEmpty)
    }

    @Test func trimIsApplied() {
        let clip = AudioClip(fileName: "a.wav", trimStart: 2, trimEnd: 7)
        let timing = ClipTiming(clip: clip, fileDuration: 10)
        #expect(timing.start == 2)
        #expect(timing.end == 7)
        #expect(timing.duration == 5)
    }

    @Test func trimEndBeyondFileIsClamped() {
        let clip = AudioClip(fileName: "a.wav", trimStart: 1, trimEnd: 99)
        let timing = ClipTiming(clip: clip, fileDuration: 4)
        #expect(timing.end == 4)
    }

    @Test func trimStartBeyondFileGivesEmptyClip() {
        let clip = AudioClip(fileName: "a.wav", trimStart: 12)
        let timing = ClipTiming(clip: clip, fileDuration: 4)
        #expect(timing.isEmpty)
        #expect(timing.duration == 0)
    }

    @Test func fadesLongerThanTheClipAreScaledDown() {
        let clip = AudioClip(fileName: "a.wav", fadeIn: 3, fadeOut: 3)
        let timing = ClipTiming(clip: clip, fileDuration: 4)
        #expect(timing.fadeIn + timing.fadeOut <= 4 + 1e-9)
        #expect(abs(timing.fadeIn - 2) < 1e-9)
    }

    @Test func envelopeFollowsFades() {
        let clip = AudioClip(fileName: "a.wav", fadeIn: 1, fadeOut: 2)
        let timing = ClipTiming(clip: clip, fileDuration: 10)
        #expect(timing.envelope(at: 0) == 0)
        #expect(abs(timing.envelope(at: 0.5) - 0.5) < 1e-9)
        #expect(timing.envelope(at: 1) == 1)
        #expect(timing.envelope(at: 5) == 1)
        #expect(abs(timing.envelope(at: 9) - 0.5) < 1e-9)
        #expect(timing.envelope(at: 10) == 0)
    }

    @Test func envelopeIsClampedOutsideTheClip() {
        let timing = ClipTiming(clip: AudioClip(fileName: "a.wav", fadeIn: 1), fileDuration: 4)
        #expect(timing.envelope(at: -3) == 0)
        #expect(timing.envelope(at: 100) == 1)
    }
}

@Suite("Relance")
struct RetriggerTests {
    @Test func idlePadStarts() {
        #expect(RetriggerAction.resolve(state: .idle, behavior: .restart) == .start)
        #expect(RetriggerAction.resolve(state: .idle, behavior: .stop) == .start)
    }

    @Test func playingPadFollowsItsBehavior() {
        let playing = PlaybackState.playing(startedAt: 0)
        #expect(RetriggerAction.resolve(state: playing, behavior: .restart) == .restart)
        #expect(RetriggerAction.resolve(state: playing, behavior: .stop) == .stop)
    }

    @Test func pausedPadAlwaysResumes() {
        let paused = PlaybackState.paused(elapsed: 3)
        #expect(RetriggerAction.resolve(state: paused, behavior: .restart) == .resume)
        #expect(RetriggerAction.resolve(state: paused, behavior: .stop) == .resume)
    }
}
