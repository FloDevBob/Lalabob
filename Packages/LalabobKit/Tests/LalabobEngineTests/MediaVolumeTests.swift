import Foundation
import LalabobMIDI
import Testing

@testable import LalabobEngine

/// Faux Apple Music : enregistre les volumes reçus.
actor FakeMediaVolume: MediaVolumeControlling {
    var state: MediaVolumeStatus = .running
    private(set) var sent: [Int] = []
    func setState(_ new: MediaVolumeStatus) { state = new }
    func status() async -> MediaVolumeStatus { state }
    func setVolume(percent: Int) async throws { sent.append(percent) }
}

@Suite("Volume d'Apple Music", .serialized)
struct MediaVolumeTests {
    @Test("Conversion comme le script : 0, 64, 127 → 0, 50, 100")
    func conversion() {
        #expect(MediaVolumeRelay.percent(forFader: 0) == 0)
        #expect(MediaVolumeRelay.percent(forFader: 64.0 / 127) == 50)
        #expect(MediaVolumeRelay.percent(forFader: 1) == 100)
        #expect(MediaVolumeRelay.percent(forFader: 5) == 100)
        #expect(MediaVolumeRelay.percent(forFader: .nan) == 0)
    }

    @Test("Un écart de moins de 2 % est ignoré, les extrêmes partent toujours")
    func threshold() async {
        let fake = FakeMediaVolume()
        let relay = MediaVolumeRelay(target: fake, minimumInterval: .milliseconds(5))
        await relay.faderMoved(to: 0.50)
        try? await Task.sleep(for: .milliseconds(40))
        await relay.faderMoved(to: 0.51)  // 51 : écart 1
        try? await Task.sleep(for: .milliseconds(40))
        await relay.faderMoved(to: 0.53)  // 53 : écart 3
        try? await Task.sleep(for: .milliseconds(40))
        await relay.faderMoved(to: 0.995)  // 99 puis…
        try? await Task.sleep(for: .milliseconds(40))
        await relay.faderMoved(to: 1)  // 100 : écart 1 mais extrême
        try? await Task.sleep(for: .milliseconds(40))
        #expect(await fake.sent == [50, 53, 99, 100])
    }

    @Test("Une rafale de 20 valeurs en 100 ms : peu d'envois, et la dernière part")
    func burst() async {
        let fake = FakeMediaVolume()
        let relay = MediaVolumeRelay(target: fake)
        for step in 1...20 {
            await relay.faderMoved(to: Double(step) * 0.04)
            try? await Task.sleep(for: .milliseconds(5))
        }
        try? await Task.sleep(for: .milliseconds(250))
        let sent = await fake.sent
        #expect(sent.count <= 4)
        #expect(sent.last == 80)
    }

    @Test("Music fermé : aucun envoi (et on le dit) ; désactivé : aucun envoi")
    func closedOrDisabled() async {
        let fake = FakeMediaVolume()
        await fake.setState(.notRunning)
        let relay = MediaVolumeRelay(target: fake, minimumInterval: .milliseconds(5))
        await relay.faderMoved(to: 0.8)
        try? await Task.sleep(for: .milliseconds(40))
        #expect(await fake.sent.isEmpty)
        await fake.setState(.running)
        await relay.setEnabled(false)
        await relay.faderMoved(to: 0.3)
        try? await Task.sleep(for: .milliseconds(40))
        #expect(await fake.sent.isEmpty)
        await relay.setEnabled(true)
        await relay.faderMoved(to: 0.3)
        try? await Task.sleep(for: .milliseconds(40))
        #expect(await fake.sent == [30])
    }
}

@MainActor
@Suite("9e fader dans la session", .serialized)
struct MediaVolumeSessionTests {
    @Test("Le 9e fader règle Apple Music, sans toucher aux volumes des colonnes ; désactivé, rien ne part")
    func ninthFader() async {
        let fake = FakeMediaVolume()
        let defaults = UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!
        let transport = FakeMIDITransport()
        let session = ControllerSession(transport: transport, defaults: defaults, mediaVolume: fake)
        let runner = Task { await session.run() }
        defer { runner.cancel() }
        await transport.setPorts(sources: [ControllerSessionTests.apcSource], destinations: [ControllerSessionTests.apcDestination])
        try? await Task.sleep(for: .milliseconds(150))
        await transport.receive([.controlChange(channel: 0, controller: 56, value: 127)], from: ControllerSessionTests.apcSource.id)
        #expect(await waitUntil { await fake.sent == [100] })
        #expect(await waitUntil { await session.musicVolume == 100 })
        session.setMusicVolumeEnabled(false)
        await transport.receive([.controlChange(channel: 0, controller: 56, value: 0)], from: ControllerSessionTests.apcSource.id)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(await fake.sent == [100])
        #expect(defaults.bool(forKey: ControllerSession.musicVolumeKey) == false)
    }
}
