import Foundation
import Testing

@testable import LalabobAudio

/// Tampon du pont audio (ADR 0011).
@Suite("Tampon circulaire du pont audio")
struct AudioRingBufferTests {
    private func write(_ ring: AudioRingBuffer, _ values: [Float]) {
        values.withUnsafeBufferPointer { left in ring.write(left: left.baseAddress!, right: left.baseAddress!, frames: values.count) }
    }

    private func read(_ ring: AudioRingBuffer, _ frames: Int) -> [Float] {
        var left = [Float](repeating: -1, count: frames)
        var right = [Float](repeating: -1, count: frames)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in ring.read(left: l.baseAddress!, right: r.baseAddress!, frames: frames) }
        }
        return left
    }

    @Test("Amorçage : silence tant que l'avance n'est pas atteinte, puis le son dans l'ordre")
    func priming() {
        let ring = AudioRingBuffer(capacity: 64, latencyFrames: 8)
        write(ring, [1, 2, 3, 4])
        #expect(read(ring, 4) == [0, 0, 0, 0])
        write(ring, [5, 6, 7, 8])
        #expect(read(ring, 4) == [1, 2, 3, 4])
        #expect(read(ring, 4) == [5, 6, 7, 8])
    }

    @Test("Manque de son : silence, jamais de vieux échantillons")
    func underflow() {
        let ring = AudioRingBuffer(capacity: 64, latencyFrames: 4)
        write(ring, [1, 2, 3, 4])
        #expect(read(ring, 6) == [1, 2, 3, 4, 0, 0])
        #expect(read(ring, 2) == [0, 0])
    }

    @Test("Trop d'avance (horloges qui dérivent) : le lecteur rattrape, l'avance reste bornée")
    func drift() {
        let ring = AudioRingBuffer(capacity: 64, latencyFrames: 4)
        write(ring, (1...20).map(Float.init))
        #expect(read(ring, 4) == [17, 18, 19, 20])
    }

    @Test("Tampon plein : ce qui ne tient pas est abandonné")
    func overflow() {
        let ring = AudioRingBuffer(capacity: 16, latencyFrames: 4)
        write(ring, (1...20).map(Float.init))
        // 16 tiennent ; le lecteur, très en retard, rattrape vers la fin de ce qui est écrit.
        #expect(read(ring, 4) == [13, 14, 15, 16])
    }

    @Test("Entrelacé : un canal sur deux")
    func interleaved() {
        let ring = AudioRingBuffer(capacity: 64, latencyFrames: 2)
        let data: [Float] = [1, -1, 2, -2, 3, -3]
        data.withUnsafeBufferPointer { p in ring.write(left: p.baseAddress!, right: p.baseAddress! + 1, frames: 3, stride: 2) }
        var left = [Float](repeating: 0, count: 3)
        var right = [Float](repeating: 0, count: 3)
        left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in ring.read(left: l.baseAddress!, right: r.baseAddress!, frames: 3) } }
        #expect(left == [1, 2, 3] && right == [-1, -2, -3])
    }

    @Test("Fondu : le gain glisse sans saut jusqu'à la cible")
    func gainRamp() {
        let ring = AudioRingBuffer(capacity: 1024, latencyFrames: 128)
        write(ring, [Float](repeating: 1, count: 200))
        ring.setGain(0, overFrames: 100)
        let out = read(ring, 120)
        #expect(out[0] < 1 && out[0] > 0.95)
        #expect(zip(out, out.dropFirst()).allSatisfy { $0 >= $1 && $0 - $1 < 0.02 })
        #expect(out[110] == 0)
    }

    @Test("Silence capté : se repère ; écriture : datée")
    func silence() {
        let ring = AudioRingBuffer(capacity: 64, latencyFrames: 4)
        #expect(ring.secondsSinceLastWrite == .infinity && ring.secondsSinceLastSound == .infinity)
        write(ring, [0, 0, 0, 0])
        #expect(ring.secondsSinceLastWrite < 1)
        #expect(ring.secondsSinceLastSound == .infinity)
        write(ring, [0.2])
        #expect(ring.secondsSinceLastSound < 1)
    }
}

/// Le moteur joue le son du pont dans une colonne (rendu hors ligne).
@Suite("Pont audio dans le moteur", .serialized)
struct ExternalSourceOfflineTests {
    @Test(.timeLimit(.minutes(1))) func theBridgeSoundPlaysInItsColumnThroughTheFader() async throws {
        let engine = AVAudioEngineController(output: .offline(sampleRate: 48_000, maxFrames: 4096))
        let ring = AudioRingBuffer(capacity: 96_000, latencyFrames: 24_000)
        let tone = [Float](repeating: 0.5, count: 48_000)
        tone.withUnsafeBufferPointer { p in ring.write(left: p.baseAddress!, right: p.baseAddress!, frames: tone.count) }
        await engine.attachExternal(ring, sampleRate: 48_000, column: 2)
        await engine.setColumnLevel(2, level: 1)
        let out = try await engine.renderOffline(frames: 4096)
        #expect(ring.framesRead > 0, "le moteur doit tirer le son du tampon")
        #expect((out.map(abs).max() ?? 0) > 0.3)
        _ = try await engine.renderOffline(frames: 22_050)
        let meters = engine.meters
        #expect(await waitUntil { meters.peak(column: 2, channel: 0) > 0.3 })

        await engine.setColumnLevel(2, level: 0)
        _ = try await engine.renderOffline(frames: 4096)
        let silent = try await engine.renderOffline(frames: 4096)
        #expect((silent.map(abs).max() ?? 1) < 0.001)

        await engine.setColumnLevel(2, level: 1)
        await engine.detachExternal()
        let after = try await engine.renderOffline(frames: 4096)
        #expect((after.map(abs).max() ?? 1) < 0.001)
    }
}
