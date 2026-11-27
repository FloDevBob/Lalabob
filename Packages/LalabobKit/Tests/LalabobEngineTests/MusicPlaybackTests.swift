import ControllerDrivers
import Foundation
import LalabobAudio
import LalabobMIDI
import LalabobModel
import Testing

@testable import LalabobEngine

/// Faux lecteur de Music : enregistre ce qu'on lui demande.
actor FakeMusicPlayer: MusicPlayerControlling {
    var running = true
    var library: Set<String> = []
    var snap = MusicPlayerSnapshot(state: .stopped)
    var currentVolume = 70
    private(set) var plays: [String] = []
    private(set) var volumes: [Int] = []
    private(set) var pauses = 0
    private(set) var resumes = 0
    private(set) var stops = 0

    func configure(running: Bool = true, library: Set<String>) {
        self.running = running
        self.library = library
    }
    func finishTrack() { snap = MusicPlayerSnapshot(state: .stopped) }
    func isRunning() async -> Bool { running }
    func play(trackID: String) async throws -> Bool {
        guard library.contains(trackID) else { return false }
        plays.append(trackID)
        snap = MusicPlayerSnapshot(state: .playing, trackID: trackID, position: 0)
        return true
    }
    func pause() async throws { pauses += 1; snap.state = .paused }
    func resume() async throws { resumes += 1; snap.state = .playing }
    func stop() async throws { stops += 1; snap = MusicPlayerSnapshot(state: .stopped) }
    func seek(to seconds: TimeInterval) async throws { snap.position = seconds }
    func snapshot() async throws -> MusicPlayerSnapshot { snap }
    func volume() async throws -> Int? { currentVolume }
    func setVolume(_ percent: Int) async throws { currentVolume = percent; volumes.append(percent) }
}

@MainActor
@Suite("Lecture Apple Music", .serialized)
struct MusicPlaybackTests {
    let first = Pad.track(MusicTrackRef(persistentID: "0A", title: "Générique", duration: 160), tint: .rose)
    let second = Pad.track(MusicTrackRef(persistentID: "0B", title: "Rappel", duration: 120), tint: .orange)
    static let a = GridPosition(column: 0, row: 0)
    static let b = GridPosition(column: 1, row: 0)

    private func makeRig(running: Bool = true, library: Set<String> = ["0A", "0B"]) async -> (ShowController, MusicPlaybackCoordinator, FakeMusicPlayer) {
        var grid = PadGrid.emptyAppleMusic(name: "M")
        grid[Self.a] = first
        grid[Self.b] = second
        let controller = ShowController(
            show: Show(name: "S", grids: [grid]), audio: RecordingAudioEngine(), audioDirectory: URL(filePath: "/tmp/lalabob-audio"),
            defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!, isLocked: true)
        let fake = FakeMusicPlayer()
        await fake.configure(running: running, library: library)
        let music = MusicPlaybackCoordinator(player: fake)
        music.crossfadeDuration = 0.1
        music.stopFadeDuration = 0.05
        music.stopAllFadeDuration = 0.05
        music.rampStep = 0.01
        music.pollInterval = .milliseconds(20)
        controller.musicPlayer = music
        return (controller, music, fake)
    }

    private func state(_ controller: ShowController, _ pad: Pad) -> PlaybackState? { controller.playback[pad.id]?.state }

    @Test("Double-clic (verrouillé) : le morceau part une fois ; ré-appui : pause ; encore : reprise")
    func playPauseResume() async {
        let (controller, music, fake) = await makeRig()
        controller.audition(at: Self.a)
        #expect(await waitUntil { await fake.plays == ["0A"] })
        #expect(await waitUntil { await music.state == .playing })
        if case .playing? = state(controller, first) {} else { Issue.record("le pad doit être en lecture") }
        #expect(controller.playback[first.id]?.duration == 160)
        controller.audition(at: Self.a)
        #expect(await waitUntil { await fake.pauses == 1 })
        #expect(await waitUntil { if case .paused? = await self.state(controller, self.first) { true } else { false } })
        controller.audition(at: Self.a)
        #expect(await waitUntil { await fake.resumes == 1 })
        #expect(await waitUntil { await music.state == .playing })
    }

    @Test("Un autre pad pendant un morceau : fondu enchaîné (le volume descend à 0 puis remonte), l'ancien pad s'éteint")
    func crossfade() async {
        let (controller, music, fake) = await makeRig()
        controller.audition(at: Self.a)
        #expect(await waitUntil { await music.state == .playing })
        controller.audition(at: Self.b)
        #expect(await waitUntil { await fake.plays == ["0A", "0B"] })
        #expect(await waitUntil { await fake.currentVolume == 70 })
        #expect(await waitUntil { await !music.isFading })
        let volumes = await fake.volumes
        #expect(volumes.contains(0))
        #expect(volumes.last == 70)
        #expect(state(controller, first) == nil)
        #expect(controller.playback[second.id] != nil)
        #expect(music.currentPad == second.id)
    }

    @Test("Fin du morceau : le pad s'éteint")
    func ends() async {
        let (controller, music, fake) = await makeRig()
        controller.audition(at: Self.a)
        #expect(await waitUntil { await music.state == .playing })
        await fake.finishTrack()
        #expect(await waitUntil { await controller.playback[self.first.id] == nil })
        #expect(music.currentPad == nil)
    }

    @Test("Music fermé : rien ne part, un message le dit")
    func closed() async {
        let (controller, _, fake) = await makeRig(running: false)
        controller.audition(at: Self.a)
        #expect(await waitUntil { await controller.lockNotice?.contains("fermé") == true })
        #expect(await fake.plays.isEmpty)
    }

    @Test("Morceau qui n'est plus dans la bibliothèque : message, rien ne joue")
    func missing() async {
        let (controller, music, _) = await makeRig(library: [])
        controller.audition(at: Self.a)
        #expect(await waitUntil { await controller.lockNotice?.contains("Générique") == true })
        #expect(music.currentPad == nil)
    }

    @Test("Tout arrêter (Échap) et stop de colonne : fondu, arrêt, volume rendu ; le bouton stop existe sur une colonne Music")
    func stops() async {
        let (controller, music, fake) = await makeRig()
        #expect(controller.stopButtonColumns.contains(0))
        controller.audition(at: Self.a)
        #expect(await waitUntil { await music.state == .playing })
        controller.stopAll()
        #expect(await waitUntil { await fake.stops == 1 })
        #expect(await waitUntil { await fake.currentVolume == 70 })
        #expect(await waitUntil { await controller.playback[self.first.id] == nil })

        controller.audition(at: Self.b)
        #expect(await waitUntil { await music.currentPad == self.second.id })
        controller.stopColumn(0)  // pas la colonne du morceau : rien
        try? await Task.sleep(for: .milliseconds(60))
        #expect(await fake.stops == 1)
        controller.stopColumn(1)
        #expect(await waitUntil { await fake.stops == 2 })
    }

    @Test("Le 9e fader bougé pendant un fondu change la cible : le volume remonte à la nouvelle valeur")
    func faderDuringFade() async {
        let (controller, music, fake) = await makeRig()
        music.crossfadeDuration = 0.4
        controller.audition(at: Self.a)
        #expect(await waitUntil { await music.state == .playing })
        controller.audition(at: Self.b)
        #expect(await waitUntil { await music.isFading })
        music.faderMoved(percent: 40)
        #expect(await waitUntil(timeout: 3) { await fake.plays.count == 2 })
        #expect(await waitUntil(timeout: 3) { await !music.isFading })
        #expect(await fake.currentVolume == 40)
    }

    @Test("Contrôleur : un appui sur un pad Music le joue, même verrouillé")
    func controller() async {
        let (controller, _, fake) = await makeRig()
        #expect(controller.controllerPress(at: Self.a).playsMusic)
        #expect(!controller.controllerPress(at: Self.a).playsSound)
        let transport = FakeMIDITransport()
        let session = ControllerSession(controller: controller, transport: transport)
        let runner = Task { await session.run() }
        defer { runner.cancel() }
        await transport.setPorts(sources: [ControllerSessionTests.apcSource], destinations: [ControllerSessionTests.apcDestination])
        _ = await waitUntil { await controller.connectedController == .apcMiniMK2 }
        await transport.receive([.noteOn(channel: 0, note: 56, velocity: 127)], from: ControllerSessionTests.apcSource.id)  // case (0, 0)
        #expect(await waitUntil { await fake.plays == ["0A"] })
    }
}
