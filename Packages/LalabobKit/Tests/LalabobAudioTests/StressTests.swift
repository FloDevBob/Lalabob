import AVFoundation
import Foundation
import LalabobModel
import Testing

@testable import LalabobAudio

/// Générateur pseudo-aléatoire à graine fixe : un échec se rejoue à l'identique.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Charge et robustesse du moteur (rendu hors ligne) : beaucoup de sons à la fois, séquences d'opérations
/// désordonnées, redémarrage du moteur. Le « 3 heures d'affilée » se fait sur le vrai Mac (docs/PLAN.md, J6).
@Suite("Charge et robustesse du moteur", .serialized)
struct EngineStressTests {
    private let rate = 44100.0

    /// 6 colonnes sons de 8 pads : sons courts, boucles et un long son lu en flux.
    private func makeEngine() async throws -> (AVAudioEngineController, [Pad.ID]) {
        let dir = try makeTemporaryDirectory()
        try writeTestFile(named: "court.wav", in: dir, duration: 0.3) { _ in 0.05 }
        try writeTestFile(named: "boucle.wav", in: dir, duration: 1) { _ in 0.05 }
        try writeTestFile(named: "long.wav", in: dir, duration: 40) { _ in 0.05 }
        var grid = PadGrid.empty(name: "Charge")
        var ids: [Pad.ID] = []
        for column in 0..<6 {
            grid.columns[column].level = 0.8
            for row in 0..<PadGrid.size {
                let clip: AudioClip
                switch (column + row) % 3 {
                case 0: clip = AudioClip(fileName: "court.wav")
                case 1: clip = AudioClip(fileName: "boucle.wav", fadeIn: 0.05, fadeOut: 0.05, loops: true)
                default: clip = AudioClip(fileName: "long.wav", fadeIn: 0.1, fadeOut: 0.1)
                }
                let pad = Pad(title: "P\(column)\(row)", tint: .rouge, content: .audio(clip: clip))
                grid.columns[column].slots[row] = pad
                ids.append(pad.id)
            }
        }
        let engine = AVAudioEngineController(output: .offline(sampleRate: rate, maxFrames: 4096))
        try await engine.configure(show: Show(name: "Charge", grids: [grid]), audioDirectory: dir)
        return (engine, ids)
    }

    @Test(.timeLimit(.minutes(4)))
    func aThousandRandomOperationsNeverBreakTheEngine() async throws {
        let (engine, ids) = try await makeEngine()
        var random = SeededGenerator(seed: 2026)
        var loudest: Float = 0

        for step in 1...1_000 {
            let id = ids[Int.random(in: 0..<ids.count, using: &random)]
            let choice = Int.random(in: 0..<100, using: &random)
            switch choice {
            case 0..<55: await engine.trigger(id)
            case 55..<68: await engine.stop(id)
            case 68..<76: await engine.togglePause(id)
            case 76..<84: await engine.seek(id, to: Double.random(in: 0...2, using: &random))
            case 84..<90: await engine.setPadGain(id, gainDB: Double.random(in: -30...12, using: &random))
            case 90..<97:
                await engine.setColumnLevel(Int.random(in: 0..<6, using: &random), level: Double.random(in: 0...1, using: &random))
            case 97..<99: await engine.stopAll()
            default: await engine.trigger(UUID())  // pad inconnu : ignoré
            }
            if step % 50 == 0 {
                let out = try await engine.renderOffline(frames: 2205)
                #expect(out.allSatisfy { $0.isFinite }, "échantillon invalide à l'étape \(step)")
                loudest = max(loudest, out.map { abs($0) }.max() ?? 0)
            }
        }
        #expect(loudest < 25, "le mélange de tous ces sons ne doit pas exploser (crête \(loudest))")

        await engine.stopAll()
        let fade = Int((StopFade.duration * rate).rounded(.up))
        let tail = try await engine.renderOffline(frames: fade + 2000)
        #expect(tail[(2 * (fade + 300))...].allSatisfy { $0 == 0 })
        for id in ids { #expect(await engine.state(of: id) == .idle) }
    }

    @Test(.timeLimit(.minutes(3)))
    func fortyEightSimultaneousSoundsRenderFasterThanRealTime() async throws {
        let (engine, ids) = try await makeEngine()
        for id in ids { await engine.trigger(id) }
        let seconds = 10
        let clock = ContinuousClock()
        let start = clock.now
        let out = try await engine.renderOffline(frames: Int(rate) * seconds)
        let elapsed = start.duration(to: clock.now)
        #expect(out.allSatisfy { $0.isFinite })
        #expect(elapsed < .seconds(seconds), "48 voix : \(elapsed) pour \(seconds) s de son, plus lent que le temps réel")
    }

    @Test(.timeLimit(.minutes(2)))
    func restartingTheEngineKeepsTheSoundsPlaying() async throws {
        // Perte ou changement de sortie : le moteur redémarre et les sons reprennent là où ils en étaient.
        let (engine, ids) = try await makeEngine()
        let playing = Array(ids.prefix(6))
        for id in playing { await engine.trigger(id) }
        _ = try await engine.renderOffline(frames: 4410)
        var before: [Bool] = []
        for id in playing { before.append(await engine.state(of: id).isActive) }

        await engine.rebuild()
        let out = try await engine.renderOffline(frames: 8820)
        #expect(out.allSatisfy { $0.isFinite })
        var after: [Bool] = []
        for id in playing { after.append(await engine.state(of: id).isActive) }
        #expect(after == before)
        #expect(out.map { abs($0) }.max() ?? 0 > 0)  // du son sort encore
    }
}
