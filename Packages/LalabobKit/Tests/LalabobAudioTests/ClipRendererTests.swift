import AVFoundation
import LalabobModel
import Testing

@testable import LalabobAudio

@Suite("ClipRenderer")
struct ClipRendererTests {
    private let rate = 44100.0

    private func constantBuffer(_ value: Float, seconds: Double) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let frames = AVAudioFrameCount(seconds * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for c in 0..<2 { for i in 0..<Int(frames) { buffer.floatChannelData![c][i] = value } }
        return buffer
    }

    @Test func trimCutsTheBuffer() throws {
        let source = constantBuffer(1, seconds: 2)
        let clip = AudioClip(fileName: "a.wav", trimStart: 0.5, trimEnd: 1.5)
        let timing = ClipTiming(clip: clip, fileDuration: 2)
        let baked = try #require(ClipRenderer.bake(source, timing: timing, gainDB: 0))
        #expect(baked.frameLength == AVAudioFrameCount(1.0 * rate))
    }

    @Test func fadesAreAppliedToSamples() throws {
        let source = constantBuffer(1, seconds: 2)
        let clip = AudioClip(fileName: "a.wav", fadeIn: 1, fadeOut: 1)
        let timing = ClipTiming(clip: clip, fileDuration: 2)
        let baked = try #require(ClipRenderer.bake(source, timing: timing, gainDB: 0))
        let samples = baked.floatChannelData![0]
        #expect(samples[0] == 0)
        #expect(abs(samples[Int(0.5 * rate)] - 0.5) < 0.001)
        #expect(abs(samples[Int(1.0 * rate)] - 1) < 0.001)
        #expect(abs(samples[Int(1.5 * rate)] - 0.5) < 0.001)
        #expect(samples[Int(baked.frameLength) - 1] < 0.001)
    }

    @Test func gainIsApplied() throws {
        let source = constantBuffer(1, seconds: 0.1)
        let timing = ClipTiming(clip: AudioClip(fileName: "a.wav"), fileDuration: 0.1)
        let baked = try #require(ClipRenderer.bake(source, timing: timing, gainDB: -6.0206))
        #expect(abs(baked.floatChannelData![1][100] - 0.5) < 0.001)
    }

    @Test func sourceBufferIsNotModified() throws {
        let source = constantBuffer(1, seconds: 1)
        let timing = ClipTiming(clip: AudioClip(fileName: "a.wav", fadeIn: 0.5), fileDuration: 1)
        _ = ClipRenderer.bake(source, timing: timing, gainDB: -20)
        #expect(source.floatChannelData![0][0] == 1)
    }

    @Test func emptyClipBakesToNothing() {
        let source = constantBuffer(1, seconds: 1)
        let timing = ClipTiming(clip: AudioClip(fileName: "a.wav", trimStart: 5), fileDuration: 1)
        #expect(ClipRenderer.bake(source, timing: timing, gainDB: 0) == nil)
    }
}
