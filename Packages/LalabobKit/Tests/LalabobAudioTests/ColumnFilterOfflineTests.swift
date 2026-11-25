import AVFoundation
import Foundation
import LalabobModel
import Testing

@testable import LalabobAudio

/// Filtre de colonne rendu hors ligne : un bruit blanc doit passer intact au neutre, perdre ses aigus à gauche
/// (passe-bas) et ses graves à droite (passe-haut).
@Suite("Filtre de colonne (hors ligne)", .serialized)
struct ColumnFilterOfflineTests {
    private let rate = 44100.0

    /// Bruit blanc déterministe (générateur congruentiel), amplitude ±0,25.
    private func writeNoise(in directory: URL) throws {
        var state: UInt32 = 0x1234_5678
        var samples: [Float] = []
        let count = Int(rate)
        samples.reserveCapacity(count)
        for _ in 0..<count {
            state = state &* 1_664_525 &+ 1_013_904_223
            samples.append((Float(state >> 8) / Float(1 << 24) - 0.5) * 0.5)
        }
        let table = samples
        try writeTestFile(named: "bruit.wav", in: directory, duration: 1) { t in table[min(Int(t * 44100 + 0.5), table.count - 1)] }
    }

    /// Joue le bruit dans la colonne 0, filtre réglé à `position`, et renvoie le canal gauche (régime établi).
    private func render(position: Double, after previous: Double? = nil, rebuildFirst: Bool = false) async throws -> [Float] {
        let dir = try makeTemporaryDirectory()
        try writeNoise(in: dir)
        var grid = PadGrid.empty(name: "Test")
        let pad = Pad(title: "Bruit", tint: .blanc, content: .audio(clip: AudioClip(fileName: "bruit.wav", loops: true)))
        grid.columns[0].slots[0] = pad
        grid.columns[0].level = 1
        let engine = AVAudioEngineController(output: .offline(sampleRate: rate, maxFrames: 4096))
        try await engine.configure(show: Show(name: "Test", grids: [grid]), audioDirectory: dir)
        await engine.setColumnLevel(0, level: 1)
        if let previous { await engine.setColumnFilter(0, value: previous) }
        await engine.setColumnFilter(0, value: position)
        if rebuildFirst { await engine.rebuild() }  // changement de sortie : le filtre doit rester branché et réglé
        await engine.trigger(pad.id)
        let out = try await engine.renderOffline(frames: 16384)
        return stride(from: 4096 * 2, to: out.count, by: 2).map { out[$0] }
    }

    /// Part des aigus : énergie de la dérivée rapportée à l'énergie du signal (≈ 2 pour un bruit blanc).
    private func highShare(_ x: [Float]) -> Double {
        var diff = 0.0, total = 0.0
        for i in 1..<x.count {
            let d = Double(x[i] - x[i - 1])
            diff += d * d
            total += Double(x[i]) * Double(x[i])
        }
        return total > 0 ? diff / total : 0
    }

    /// Part des graves : énergie des moyennes sur 32 échantillons (≈ 1/32 pour un bruit blanc).
    private func lowShare(_ x: [Float]) -> Double {
        let block = 32
        var means = 0.0, total = 0.0
        for start in stride(from: 0, to: x.count - block, by: block) {
            var sum = 0.0
            for i in start..<(start + block) {
                sum += Double(x[i])
                total += Double(x[i]) * Double(x[i])
            }
            let mean = sum / Double(block)
            means += mean * mean * Double(block)
        }
        return total > 0 ? means / total : 0
    }

    private func energy(_ x: [Float]) -> Double { x.reduce(0) { $0 + Double($1) * Double($1) } }

    @Test func neutralLetsTheNoiseThroughUnchanged() async throws {
        let neutral = try await render(position: 0)
        #expect(energy(neutral) > 0)
        #expect(abs(highShare(neutral) - 2) < 0.15)  // spectre plat, comme le bruit d'origine
        #expect(abs(lowShare(neutral) - 1.0 / 32) < 0.01)
        #expect(neutral.allSatisfy { $0.isFinite })
    }

    @Test func turningLeftRemovesTheHighs() async throws {
        let neutral = try await render(position: 0)
        let low = try await render(position: -1)
        #expect(energy(low) > 0)  // le son continue : seuls les aigus partent
        #expect(highShare(low) < 0.1 * highShare(neutral))
    }

    @Test func turningRightRemovesTheLows() async throws {
        let neutral = try await render(position: 0)
        let high = try await render(position: 1)
        #expect(energy(high) > 0)
        #expect(lowShare(high) < 0.25 * lowShare(neutral))
        #expect(highShare(high) > highShare(neutral))
    }

    @Test func backToNeutralRestoresTheFullSpectrum() async throws {
        let back = try await render(position: 0, after: -1)
        #expect(abs(highShare(back) - 2) < 0.15)
    }

    @Test func filterSurvivesAnOutputChange() async throws {
        let neutral = try await render(position: 0)
        let low = try await render(position: -1, rebuildFirst: true)
        #expect(energy(low) > 0)
        #expect(highShare(low) < 0.1 * highShare(neutral))
    }

    @Test func outOfRangeValuesAreHarmless() async throws {
        let wild = try await render(position: .nan)
        #expect(wild.allSatisfy { $0.isFinite })
        #expect(abs(highShare(wild) - 2) < 0.15)  // valeur invalide : neutre
    }
}
