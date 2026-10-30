import AVFoundation
import Accelerate
import Foundation

/// Forme d'onde d'un fichier : un pic (valeur absolue maximale, tous canaux) par tranche de temps.
public struct Waveform: Codable, Equatable, Sendable {
    public let duration: TimeInterval
    /// Valeurs de 0 à 1 (au-delà si le fichier sature), une par tranche, régulièrement réparties sur `duration`.
    public let peaks: [Float]

    public init(duration: TimeInterval, peaks: [Float]) {
        self.duration = duration
        self.peaks = peaks
    }
}

extension Waveform {
    /// Taille des blocs lus : le fichier n'est jamais chargé en entier.
    static let chunkFrames: AVAudioFrameCount = 65_536

    /// Calcule `buckets` pics en lisant le fichier par blocs (Accelerate). Hors du thread audio.
    public static func analyze(_ url: URL, buckets: Int) throws -> Waveform {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let length = Int(file.length)
        let count = max(buckets, 1)
        var peaks = [Float](repeating: 0, count: count)
        var filled = [Bool](repeating: false, count: count)
        guard length > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            return Waveform(duration: 0, peaks: peaks)
        }
        let framesPerBucket = Double(length) / Double(count)
        var position = 0
        while position < length {
            buffer.frameLength = 0
            try file.read(into: buffer, frameCount: min(chunkFrames, AVAudioFrameCount(length - position)))
            let read = Int(buffer.frameLength)
            guard read > 0, let channels = buffer.floatChannelData else { break }
            var offset = 0
            while offset < read {
                let frame = position + offset
                let bucket = min(Int(Double(frame) / framesPerBucket), count - 1)
                let bucketEnd = Int((Double(bucket + 1) * framesPerBucket).rounded(.up))
                let segment = max(min(bucketEnd - frame, read - offset), 1)
                for channel in 0..<Int(format.channelCount) {
                    var peak: Float = 0
                    vDSP_maxmgv(channels[channel] + offset, 1, &peak, vDSP_Length(segment))
                    peaks[bucket] = max(peaks[bucket], peak)
                }
                filled[bucket] = true
                offset += segment
            }
            position += read
        }
        // Fichier plus court que le nombre de tranches : les tranches vides reprennent la précédente.
        for index in peaks.indices where !filled[index] && index > 0 { peaks[index] = peaks[index - 1] }
        return Waveform(duration: Double(length) / format.sampleRate, peaks: peaks)
    }
}
