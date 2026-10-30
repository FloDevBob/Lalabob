import AVFoundation
import LalabobModel

/// Prépare les échantillons d'un extrait : élagage, fondus et gain sont « cuits » une fois
/// pour toutes avant la lecture, hors du thread audio.
enum ClipRenderer {
    /// Copie de `source` élaguée selon `timing`, avec fondus et gain. `nil` si rien à jouer
    /// ou si le format n'est pas du flottant 32 bits non entrelacé.
    static func bake(_ source: AVAudioPCMBuffer, timing: ClipTiming, gainDB: Double) -> AVAudioPCMBuffer? {
        guard !timing.isEmpty, let channels = source.floatChannelData else { return nil }
        let rate = source.format.sampleRate
        let firstFrame = min(Int(timing.start * rate), Int(source.frameLength))
        let endFrame = min(Int((timing.end * rate).rounded()), Int(source.frameLength))
        let count = endFrame - firstFrame
        guard count > 0,
            let output = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: AVAudioFrameCount(count)),
            let target = output.floatChannelData
        else { return nil }
        output.frameLength = AVAudioFrameCount(count)

        let gain = Gain.linear(fromDB: gainDB)
        let fadeInFrames = Int(timing.fadeIn * rate)
        let fadeOutFrames = Int(timing.fadeOut * rate)
        for channel in 0..<Int(source.format.channelCount) {
            let input = channels[channel] + firstFrame
            let out = target[channel]
            for i in 0..<count {
                var value = input[i] * gain
                if i < fadeInFrames { value *= Float(i) / Float(fadeInFrames) }
                let remaining = count - i
                if remaining < fadeOutFrames { value *= Float(remaining) / Float(fadeOutFrames) }
                out[i] = value
            }
        }
        return output
    }

    /// Copie de `buffer` à partir de la trame `frame` (reprise à mi-extrait). `nil` si au-delà de la fin.
    static func slice(_ buffer: AVAudioPCMBuffer, fromFrame frame: Int) -> AVAudioPCMBuffer? {
        let start = max(frame, 0)
        let count = Int(buffer.frameLength) - start
        guard count > 0, let source = buffer.floatChannelData,
            let output = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(count)),
            let target = output.floatChannelData
        else { return nil }
        output.frameLength = AVAudioFrameCount(count)
        for channel in 0..<Int(buffer.format.channelCount) {
            target[channel].update(from: source[channel] + start, count: count)
        }
        return output
    }
}
