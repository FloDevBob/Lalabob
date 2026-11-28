import AVFoundation
import Foundation
import Testing

@testable import LalabobAudio

/// Détection du tempo hors ligne (J14, étape 3b), sur des signaux fabriqués : clics, motif de batterie, bruit, nappe.
@Suite("Détection du tempo")
struct TempoDetectorTests {
    static let rate = 44_100.0

    /// Bruit pseudo-aléatoire reproductible (−1…1).
    struct Noise {
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        mutating func next() -> Float {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(Int64(bitPattern: state >> 1) % 2_000_001) / 1_000_000 - 1
        }
    }

    /// Ajoute une attaque à `time` : bruit (ou sinus à `frequency`) qui décroît en `length` secondes.
    static func hit(_ samples: inout [Float], at time: Double, length: Double, amplitude: Float, frequency: Double? = nil, noise: inout Noise) {
        let start = Int(time * rate)
        let count = Int(length * rate)
        for i in 0..<count where start + i < samples.count {
            let decay = Float(exp(-5 * Double(i) / Double(count)))
            let value = frequency.map { Float(sin(2 * .pi * $0 * Double(i) / rate)) } ?? noise.next()
            samples[start + i] += amplitude * decay * value
        }
    }

    static func clicks(bpm: Double, offset: Double, duration: Double = 20) -> [Float] {
        var samples = [Float](repeating: 0, count: Int(duration * rate))
        var noise = Noise()
        var time = offset
        while time < duration {
            hit(&samples, at: time, length: 0.03, amplitude: 0.8, noise: &noise)
            time += 60 / bpm
        }
        return samples
    }

    /// Grosse caisse sur chaque temps, caisse claire sur 2 et 4, charleston sur les croches.
    static func drums(bpm: Double, offset: Double, duration: Double = 24) -> [Float] {
        var samples = [Float](repeating: 0, count: Int(duration * rate))
        var noise = Noise()
        let beat = 60 / bpm
        var index = 0
        while offset + Double(index) * beat / 2 < duration {
            let time = offset + Double(index) * beat / 2
            if index % 2 == 0 {
                hit(&samples, at: time, length: 0.12, amplitude: 0.9, frequency: 60, noise: &noise)
                if (index / 2) % 2 == 1 { hit(&samples, at: time, length: 0.08, amplitude: 0.5, noise: &noise) }
            }
            hit(&samples, at: time, length: 0.02, amplitude: 0.25, noise: &noise)
            index += 1
        }
        return samples
    }

    /// Écart de `time` à la grille (firstBeat + k × période), en secondes.
    static func phaseError(_ estimate: TempoEstimate, expected: Double) -> Double {
        let period = 60 / estimate.bpm
        let d = (expected - estimate.firstBeat).truncatingRemainder(dividingBy: period)
        return min(abs(d), period - abs(d))
    }

    @Test("Clics à 120 BPM : tempo, temps et confiance", arguments: [0.0, 0.13, 0.37])
    func clicks120(offset: Double) throws {
        let estimate = try #require(TempoDetector.estimate(samples: Self.clicks(bpm: 120, offset: offset), sampleRate: Self.rate))
        #expect(abs(estimate.bpm - 120) < 1)
        #expect(Self.phaseError(estimate, expected: offset) < 0.025)
        #expect(estimate.isReliable)
    }

    @Test("Clics lents et rapides, sans erreur d'octave", arguments: [72.0, 90.0, 140.0, 174.0])
    func otherTempos(bpm: Double) throws {
        let estimate = try #require(TempoDetector.estimate(samples: Self.clicks(bpm: bpm, offset: 0.2), sampleRate: Self.rate))
        #expect(abs(estimate.bpm - bpm) < bpm * 0.01)
        #expect(estimate.isReliable)
    }

    @Test("Motif de batterie à 100 BPM (croches au charleston) : 100, pas 200")
    func drumPattern() throws {
        let estimate = try #require(TempoDetector.estimate(samples: Self.drums(bpm: 100, offset: 0.1), sampleRate: Self.rate))
        #expect(abs(estimate.bpm - 100) < 1.5)
        #expect(Self.phaseError(estimate, expected: 0.1) < 0.03)
        #expect(estimate.isReliable)
    }

    @Test("Bruit continu : pas de tempo")
    func noise() {
        var noise = Noise()
        let samples = (0..<Int(20 * Self.rate)).map { _ in 0.3 * noise.next() }
        let estimate = TempoDetector.estimate(samples: samples, sampleRate: Self.rate)
        #expect(estimate == nil || estimate?.isReliable == false)
    }

    @Test("Nappe tenue et silence : pas de tempo")
    func drone() {
        let drone = (0..<Int(20 * Self.rate)).map { Float(0.4 * sin(2 * .pi * 220 * Double($0) / Self.rate)) }
        let estimate = TempoDetector.estimate(samples: drone, sampleRate: Self.rate)
        #expect(estimate == nil || estimate?.isReliable == false)
        #expect(TempoDetector.estimate(samples: [Float](repeating: 0, count: Int(10 * Self.rate)), sampleRate: Self.rate) == nil)
    }

    @Test("Trop court : rien")
    func tooShort() {
        #expect(TempoDetector.estimate(samples: Self.clicks(bpm: 120, offset: 0, duration: 2), sampleRate: Self.rate) == nil)
    }

    @Test("Depuis un fichier (stéréo, 48 kHz)")
    func fromFile() throws {
        let rate = 48_000.0
        var noise = Noise()
        var mono = [Float](repeating: 0, count: Int(12 * rate))
        var time = 0.25
        while time < 12 {
            let start = Int(time * rate)
            for i in 0..<Int(0.03 * rate) where start + i < mono.count { mono[start + i] += 0.7 * Float(exp(-5 * Double(i) / (0.03 * rate))) * noise.next() }
            time += 60 / 96.0
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "tempo-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(mono.count)))
        buffer.frameLength = AVAudioFrameCount(mono.count)
        for channel in 0..<2 { mono.withUnsafeBufferPointer { buffer.floatChannelData![channel].update(from: $0.baseAddress!, count: mono.count) } }
        do {  // le fichier est fermé (et complet) en sortant de ce bloc
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let estimate = try #require(try TempoDetector.analyze(url))
        #expect(abs(estimate.bpm - 96) < 1)
        #expect(Self.phaseError(estimate, expected: 0.25) < 0.025)
    }

    /// Prototype sur de vrais sons : `LALABOB_TEMPO_DIR=… swift test --filter realSounds` affiche le tempo de chaque son.
    @Test("Relevé sur un dossier de vrais sons", .enabled(if: ProcessInfo.processInfo.environment["LALABOB_TEMPO_DIR"] != nil))
    func realSounds() throws {
        let root = URL(filePath: ProcessInfo.processInfo.environment["LALABOB_TEMPO_DIR"]!)
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { ["mp3", "wav", "m4a", "aif", "aiff", "caf"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.path < $1.path } ?? []
        for url in files {
            let start = Date()
            let estimate = try? TempoDetector.analyze(url)
            let elapsed = Date().timeIntervalSince(start)
            let text = estimate.map {
                String(format: "%6.1f BPM  temps %.3f s  confiance %.2f %@", $0.bpm, $0.firstBeat, $0.confidence, $0.isReliable ? "✓" : "–")
            } ?? "   (aucun)"
            print("TEMPO \(text)  \(String(format: "%.2f s", elapsed))  \(url.path.replacingOccurrences(of: root.path + "/", with: ""))")
        }
    }
}
