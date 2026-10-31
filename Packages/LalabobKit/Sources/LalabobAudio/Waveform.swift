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
    /// Finesse de la première passe : un pic par bloc de 1 024 trames, regroupés ensuite en `buckets` tranches.
    static let blockFrames = 1_024

    /// Calcule `buckets` pics en lisant le fichier par blocs (Accelerate). Hors du thread audio.
    ///
    /// La longueur annoncée par le fichier (`AVAudioFile.length`) n'est **pas** fiable pour les formats compressés
    /// (MP3 à débit variable surtout : elle est estimée, souvent trop grande, et lire au-delà de la fin fait échouer la
    /// lecture avec `eofErr`). On lit donc jusqu'à la vraie fin, on garde un pic par petit bloc, et on regroupe ensuite
    /// selon le nombre réel de trames lues. Une erreur de lecture après avoir lu du son termine l'analyse sur ce qu'on
    /// a (forme d'onde tronquée plutôt qu'absente) ; une erreur avant tout son est renvoyée.
    public static func analyze(_ url: URL, buckets: Int) throws -> Waveform {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let count = max(buckets, 1)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            return Waveform(duration: 0, peaks: [Float](repeating: 0, count: count))
        }

        var blockPeaks: [Float] = []
        var totalFrames = 0
        while true {
            buffer.frameLength = 0
            do {
                try file.read(into: buffer, frameCount: chunkFrames)
            } catch {
                if totalFrames == 0 { throw error }
                break  // fin de fichier mal annoncée, ou fin abîmée : on garde ce qui a été lu
            }
            let read = Int(buffer.frameLength)
            guard read > 0, let channels = buffer.floatChannelData else { break }
            var offset = 0
            while offset < read {
                let length = min(blockFrames, read - offset)
                var blockPeak: Float = 0
                for channel in 0..<Int(format.channelCount) {
                    var peak: Float = 0
                    vDSP_maxmgv(channels[channel] + offset, 1, &peak, vDSP_Length(length))
                    blockPeak = max(blockPeak, peak)
                }
                blockPeaks.append(blockPeak)
                offset += length
            }
            totalFrames += read
        }
        guard totalFrames > 0, !blockPeaks.isEmpty else {
            return Waveform(duration: 0, peaks: [Float](repeating: 0, count: count))
        }

        // Regroupe les blocs en `count` tranches. Fichier plus court que le nombre de tranches : chaque tranche
        // prend le bloc qui lui correspond (donc les blocs se répètent, la forme reste fidèle).
        let blocks = blockPeaks.count
        var peaks = [Float](repeating: 0, count: count)
        for bucket in 0..<count {
            let first = min(bucket * blocks / count, blocks - 1)
            let last = min(max((bucket + 1) * blocks / count, first + 1), blocks)
            peaks[bucket] = blockPeaks[first..<last].max() ?? 0
        }
        return Waveform(duration: Double(totalFrames) / format.sampleRate, peaks: peaks)
    }
}
