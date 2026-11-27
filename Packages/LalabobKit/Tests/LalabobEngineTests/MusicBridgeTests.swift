import Foundation
import LalabobAudio
import LalabobModel
import Testing

@testable import LalabobEngine

/// Fausse capture du son de Music (pont audio, ADR 0011).
actor FakeCapture: MusicAudioCapturing {
    var refuses = false
    private(set) var starts = 0
    private(set) var stops = 0
    func refuse() { refuses = true }
    func start(pid: pid_t, into ring: AudioRingBuffer) async throws -> Double {
        if refuses { throw ProcessAudioBridge.Failure.tapRefused(-1) }
        starts += 1
        return 48_000
    }
    func stop() async { stops += 1 }
}

@MainActor
@Suite("Pont audio Apple Music", .serialized)
struct MusicBridgeTests {
    let first = Pad.track(MusicTrackRef(persistentID: "0A", title: "Générique", duration: 160), tint: .rose)
    let second = Pad.track(MusicTrackRef(persistentID: "0B", title: "Rappel", duration: 120), tint: .orange)

    struct Rig {
        let controller: ShowController
        let music: MusicPlaybackCoordinator
        let player: FakeMusicPlayer
        let capture: FakeCapture
        let audio: RecordingAudioEngine
    }

    private func makeRig(bridge: Bool = true, refuse: Bool = false) async -> Rig {
        var grid = PadGrid.emptyAppleMusic(name: "M")
        grid[GridPosition(column: 0, row: 0)] = first
        grid[GridPosition(column: 1, row: 0)] = second
        let audio = RecordingAudioEngine()
        let controller = ShowController(
            show: Show(name: "S", grids: [grid]), audio: audio, audioDirectory: URL(filePath: "/tmp/lalabob-audio"),
            defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!, isLocked: true)
        let player = FakeMusicPlayer()
        await player.configure(library: ["0A", "0B"])
        let capture = FakeCapture()
        if refuse { await capture.refuse() }
        let music = MusicPlaybackCoordinator(
            player: player, capture: capture, defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!, musicPID: { 42 })
        music.crossfadeDuration = 0.1
        music.stopFadeDuration = 0.05
        music.stopAllFadeDuration = 0.05
        music.rampStep = 0.01
        music.pollInterval = .milliseconds(20)
        music.bridgeGrace = 10  // les tests de sécurité le baissent
        if bridge { music.setBridgeEnabled(true) }
        controller.musicPlayer = music
        return Rig(controller: controller, music: music, player: player, capture: capture, audio: audio)
    }

    private func attached(_ rig: Rig) async -> [Int] {
        await rig.audio.commands.compactMap { if case .attachExternal(let column) = $0 { column } else { nil } }
    }

    @Test("Pont actif : la capture démarre, le son va dans la colonne du pad, puis suit le pad suivant")
    func routes() async {
        let rig = await makeRig()
        rig.controller.audition(at: GridPosition(column: 0, row: 0))
        #expect(await waitUntil { await self.attached(rig) == [0] })
        #expect(await rig.capture.starts == 1)
        #expect(rig.music.isBridging)
        rig.controller.audition(at: GridPosition(column: 1, row: 0))
        #expect(await waitUntil { await self.attached(rig) == [0, 1] })
        #expect(await waitUntil { await rig.player.plays == ["0A", "0B"] })
        // Fondu enchaîné fait dans Lalabob : le volume de Music ne descend pas à 0.
        #expect(await !rig.player.volumes.contains(0))
        #expect(await rig.capture.starts == 1)  // une seule capture pour tous les morceaux
    }

    @Test("Le fader physique d'une colonne Music agit quand le pont est actif, pas sinon")
    func columnFader() async {
        var rig = await makeRig()
        #expect(rig.controller.moveHardwareFader(column: 0, value: 1) || rig.controller.moveHardwareFader(column: 0, value: 1))
        rig = await makeRig(bridge: false)
        #expect(!rig.controller.moveHardwareFader(column: 0, value: 0.5))
    }

    @Test("Capture refusée : message, et Music joue directement (fondus par son volume)")
    func refused() async {
        let rig = await makeRig(refuse: true)
        rig.controller.audition(at: GridPosition(column: 0, row: 0))
        #expect(await waitUntil { await rig.player.plays == ["0A"] })
        #expect(rig.music.bridgeProblem != nil)
        #expect(!rig.music.isBridging)
        #expect(await self.attached(rig).isEmpty)
        rig.controller.audition(at: GridPosition(column: 1, row: 0))
        #expect(await waitUntil { await rig.player.volumes.contains(0) })
    }

    @Test("La capture ne fournit plus rien pendant un morceau : le pont est défait, Music redevient audible")
    func stale() async {
        let rig = await makeRig()
        rig.music.bridgeGrace = 0
        rig.music.bridgeStaleLimit = 0.05
        rig.controller.audition(at: GridPosition(column: 0, row: 0))
        #expect(await waitUntil { await rig.capture.stops == 1 })
        #expect(!rig.music.isBridging)
        #expect(rig.music.bridgeProblem?.contains("arrêtée") == true)
        #expect(await waitUntil { await rig.audio.commands.contains(.detachExternal) })
    }

    @Test("Le son capté reste muet (morceau protégé ?) : pont défait et option désactivée")
    func silent() async {
        let rig = await makeRig()
        rig.music.bridgeGrace = 0
        rig.music.bridgeSilenceLimit = 0.1
        rig.controller.audition(at: GridPosition(column: 0, row: 0))
        #expect(await waitUntil { await rig.player.plays == ["0A"] })
        #expect(await waitUntil { await rig.music.isBridging })
        try? await rig.player.seek(to: 5)
        let zeros = [Float](repeating: 0, count: 256)
        let feeder = Task {
            while !Task.isCancelled {
                zeros.withUnsafeBufferPointer { p in rig.music.ring.write(left: p.baseAddress!, right: p.baseAddress!, frames: 256) }
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        defer { feeder.cancel() }
        #expect(await waitUntil { await rig.capture.stops == 1 })
        #expect(!rig.music.isBridgeEnabled)
        #expect(rig.music.bridgeProblem?.contains("muet") == true)
    }

    @Test("Couper l'option arrête la capture")
    func disable() async {
        let rig = await makeRig()
        rig.controller.audition(at: GridPosition(column: 0, row: 0))
        #expect(await waitUntil { await rig.music.isBridging })
        rig.music.setBridgeEnabled(false)
        #expect(await waitUntil { await rig.capture.stops == 1 })
        #expect(!rig.music.isBridging)
    }
}
