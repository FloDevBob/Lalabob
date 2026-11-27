import AVFoundation
import Accelerate
import Foundation

/// Tempo détecté d'un son (J14, étape 3b) : BPM, instant d'un temps dans le fichier, et confiance.
public struct TempoEstimate: Codable, Sendable, Equatable {
    /// Sous ce seuil, le son n'a « pas de tempo » (ambiances, bruitages) : l'alternance ne s'en sert pas.
    /// À régler sur les vrais sons de la troupe (relevé dans `docs/PLAN.md`, J14).
    public static let reliableConfidence = 0.2

    public var bpm: Double
    /// Instant d'un temps, en secondes depuis le début du fichier (le premier trouvé, dans la première période).
    public var firstBeat: TimeInterval
    /// 0…1 : régularité des attaques à ce tempo (autocorrélation normalisée de l'enveloppe des attaques).
    public var confidence: Double

    public init(bpm: Double, firstBeat: TimeInterval, confidence: Double) {
        self.bpm = bpm
        self.firstBeat = firstBeat
        self.confidence = confidence
    }

    public var isReliable: Bool { confidence >= Self.reliableConfidence }
}

/// Détection du tempo **hors ligne** (jamais sur le fil audio) : enveloppe des attaques (flux spectral, Accelerate),
/// autocorrélation pour le tempo (préférence douce autour de 120 BPM contre les erreurs d'octave), puis peigne pour la
/// position des temps. Seules les `maximumDuration` premières secondes sont lues.
public enum TempoDetector {
    public static let maximumDuration: TimeInterval = 120
    /// En dessous, pas assez de temps pour juger d'un rythme.
    static let minimumDuration: TimeInterval = 4
    /// Fréquence visée de l'enveloppe des attaques (une valeur toutes les 5 ms).
    static let envelopeRate = 200.0
    static let searchRange = 55.0...215.0
    static let preferredBPM = 120.0
    static let chunkFrames: AVAudioFrameCount = 65_536
    /// Attaque la plus faible prise en compte (flux spectral ; des clics à −40 dB donnent ≈ 2,6, une nappe tenue ≈ 0,02).
    static let minimumOnset: Float = 0.3

    /// Lit le fichier (mono, au plus `maximumDuration`) et estime son tempo. `nil` : trop court, silencieux ou sans attaques.
    /// Comme `Waveform.analyze`, lit jusqu'à la vraie fin (longueur des MP3 peu fiable) ; une erreur après du son garde ce
    /// qui a été lu.
    public static func analyze(_ url: URL) throws -> TempoEstimate? {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else { return nil }
        let limit = Int(maximumDuration * sampleRate)
        var mono: [Float] = []
        mono.reserveCapacity(min(limit, Int(file.length)))
        let channelCount = Int(format.channelCount)
        while mono.count < limit {
            buffer.frameLength = 0
            do {
                try file.read(into: buffer, frameCount: chunkFrames)
            } catch {
                if mono.isEmpty { throw error }
                break
            }
            let read = min(Int(buffer.frameLength), limit - mono.count)
            guard read > 0, let channels = buffer.floatChannelData else { break }
            var chunk = [Float](UnsafeBufferPointer(start: channels[0], count: read))
            for channel in 1..<max(channelCount, 1) {
                vDSP.add(chunk, UnsafeBufferPointer(start: channels[channel], count: read), result: &chunk)
            }
            if channelCount > 1 { vDSP.multiply(1 / Float(channelCount), chunk, result: &chunk) }
            mono += chunk
        }
        return estimate(samples: mono, sampleRate: sampleRate)
    }

    /// Estime le tempo d'un signal mono. `nil` : trop court, silencieux ou sans attaques.
    public static func estimate(samples: [Float], sampleRate: Double) -> TempoEstimate? {
        guard sampleRate > 0, Double(samples.count) / sampleRate >= minimumDuration,
            let onsets = onsetEnvelope(samples, sampleRate: sampleRate)
        else { return nil }
        let envelope = onsets.values
        // Aucune vraie attaque (nappe tenue, son très faible) : le reste n'est que du bruit de calcul, parfois périodique.
        guard vDSP.maximum(envelope) > minimumOnset else { return nil }
        let rate = onsets.rate
        let n = envelope.count
        let minLag = max(2, Int((rate * 60 / searchRange.upperBound).rounded(.down)))
        let maxLag = Int((rate * 60 / searchRange.lowerBound).rounded(.up))
        guard 2 * maxLag + 2 < n else { return nil }

        // Autocorrélation de l'enveloppe centrée, normalisée par l'énergie (r(0) = 1).
        let mean = vDSP.mean(envelope)
        let centered = vDSP.add(-mean, envelope)
        let energy = vDSP.sumOfSquares(centered) / Float(n)
        guard energy > 1e-12 else { return nil }
        var r = [Double](repeating: 0, count: 2 * maxLag + 2)
        centered.withUnsafeBufferPointer { e in
            for lag in minLag..<r.count {
                var dot: Float = 0
                vDSP_dotpr(e.baseAddress!, 1, e.baseAddress! + lag, 1, &dot, vDSP_Length(n - lag))
                r[lag] = Double(dot / Float(n - lag) / energy)
            }
        }

        // Tempo : le meilleur retard, avec son double (qui conforte le vrai temps) et une préférence douce pour ~120 BPM.
        var best = minLag
        var bestScore = -Double.infinity
        for lag in minLag...maxLag {
            let bpm = 60 * rate / Double(lag)
            let weight = exp(-0.5 * pow(log2(bpm / preferredBPM) / 1.0, 2))
            let score = weight * (r[lag] + 0.5 * r[2 * lag])
            if score > bestScore {
                bestScore = score
                best = lag
            }
        }
        // Affinage parabolique du retard (précision au-dessous d'une trame d'enveloppe).
        var lag = Double(best)
        if best > minLag, best < maxLag {
            let a = r[best - 1], b = r[best], c = r[best + 1]
            let denominator = a - 2 * b + c
            if denominator < 0 { lag += min(max(0.5 * (a - c) / denominator, -0.5), 0.5) }
        }
        let bpm = 60 * rate / lag

        // Position des temps : le décalage dont le peigne (un temps tous les `lag`) récolte le plus d'attaques.
        var bestPhase = 0
        var bestSum = -Float.infinity
        for phase in 0..<Int(lag.rounded(.up)) {
            var sum: Float = 0
            var count = 0
            var position = Double(phase)
            while Int(position.rounded()) < n {
                sum += envelope[Int(position.rounded())]
                count += 1
                position += lag
            }
            let average = count > 0 ? sum / Float(count) : 0
            if average > bestSum {
                bestSum = average
                bestPhase = phase
            }
        }
        let period = 60 / bpm
        var firstBeat = (onsets.time(ofFrame: bestPhase)).truncatingRemainder(dividingBy: period)
        if firstBeat < 0 { firstBeat += period }
        return TempoEstimate(bpm: bpm, firstBeat: firstBeat, confidence: min(max(r[best], 0), 1))
    }

    struct Onsets {
        var values: [Float]
        /// Trames d'enveloppe par seconde.
        var rate: Double
        var hop: Int
        var window: Int
        var sampleRate: Double

        /// Instant (s) de l'attaque qui donne le maximum de la trame `frame` : le flux culmine quand l'attaque est à un quart
        /// de la fenêtre (fenêtre de Hann).
        func time(ofFrame frame: Int) -> Double { (Double(frame * hop) + Double(window) / 4) / sampleRate }
    }

    /// Flux spectral (somme des hausses du spectre en échelle logarithmique), moins sa moyenne glissante sur 1 s,
    /// redressé. Fenêtre de Hann de 1 024 points (2 048 au-delà de 50 kHz), pas de 5 ms.
    static func onsetEnvelope(_ samples: [Float], sampleRate: Double) -> Onsets? {
        let window = sampleRate > 50_000 ? 2048 : 1024
        let hop = max(1, Int((sampleRate / envelopeRate).rounded()))
        guard samples.count > window + hop,
            let dft = try? vDSP.DiscreteFourierTransform(
                previous: nil, count: window, direction: .forward, transformType: .complexComplex, ofType: Float.self)
        else { return nil }
        let hann = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: window, isHalfWindow: false)
        let bins = window / 2
        let zeros = [Float](repeating: 0, count: window)
        var frame = [Float](repeating: 0, count: window)
        var real = [Float](repeating: 0, count: window)
        var imaginary = [Float](repeating: 0, count: window)
        var previous = [Float](repeating: 0, count: bins)
        var current = [Float](repeating: 0, count: bins)
        var rise = [Float](repeating: 0, count: bins)
        let frameCount = (samples.count - window) / hop + 1
        var flux = [Float](repeating: 0, count: frameCount)
        let scale = 2 / Float(window)
        samples.withUnsafeBufferPointer { input in
            for index in 0..<frameCount {
                let start = index * hop
                vDSP.multiply(UnsafeBufferPointer(rebasing: input[start..<(start + window)]), hann, result: &frame)
                dft.transform(inputReal: frame, inputImaginary: zeros, outputReal: &real, outputImaginary: &imaginary)
                for bin in 0..<bins {
                    let magnitude = (real[bin] * real[bin] + imaginary[bin] * imaginary[bin]).squareRoot() * scale
                    current[bin] = log1p(100 * magnitude)
                }
                if index > 0 {
                    vDSP.subtract(current, previous, result: &rise)
                    vDSP.clip(rise, to: 0...Float.greatestFiniteMagnitude, result: &rise)
                    flux[index] = vDSP.sum(rise)
                }
                swap(&previous, &current)
            }
        }
        // Moins la moyenne glissante (1 s), redressé : il reste les attaques, pas le niveau.
        let rate = sampleRate / Double(hop)
        let span = max(1, Int(rate))
        var cumulative = [Double](repeating: 0, count: frameCount + 1)
        for i in 0..<frameCount { cumulative[i + 1] = cumulative[i] + Double(flux[i]) }
        var values = [Float](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            let lo = max(0, i - span / 2), hi = min(frameCount, i + span / 2 + 1)
            let localMean = (cumulative[hi] - cumulative[lo]) / Double(hi - lo)
            values[i] = max(0, flux[i] - Float(localMean))
        }
        return Onsets(values: values, rate: rate, hop: hop, window: window, sampleRate: sampleRate)
    }
}
