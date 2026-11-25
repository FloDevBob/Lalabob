import ControllerDrivers
import Foundation
import LalabobAudio
import LalabobMIDI
import LalabobModel
import Testing

@testable import LalabobEngine

/// Changer de grille depuis le contrôleur (fiche 02).
@MainActor
@Suite("Changer de grille au contrôleur", .serialized)
struct GridButtonsSessionTests {
    struct Rig {
        let controller: ShowController
        let transport: FakeMIDITransport
        let audio: RecordingAudioEngine
        let observer: Task<Void, Never>
        let runner: Task<Void, Never>
    }

    private let sound = Pad(title: "A", tint: .vert, audio: AudioClip(fileName: "a.wav"))

    private func makeRig(grids: Int, locked: Bool = false) -> Rig {
        var first = PadGrid.empty(name: "G1")
        first.columns[0].slots[0] = sound
        var list = [first]
        for index in 1..<grids { list.append(PadGrid.empty(name: "G\(index + 1)")) }
        let audio = RecordingAudioEngine()
        let controller = ShowController(
            show: Show(name: "S", grids: list), audio: audio, audioDirectory: URL(filePath: "/tmp/lalabob-audio"),
            defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
        controller.isLocked = locked
        let transport = FakeMIDITransport()
        let session = ControllerSession(
            controller: controller, transport: transport, defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
        return Rig(
            controller: controller, transport: transport, audio: audio,
            observer: Task { await controller.observePlayback() }, runner: Task { await session.run() })
    }

    private func plugAPC(_ rig: Rig) async {
        await rig.transport.setPorts(sources: [ControllerSessionTests.apcSource], destinations: [ControllerSessionTests.apcDestination])
        _ = await waitUntil { await rig.controller.connectedController == .apcMiniMK2 }
    }

    private func plugLaunchpad(_ rig: Rig) async {
        await rig.transport.setPorts(sources: [ControllerSessionTests.lpxSource], destinations: [ControllerSessionTests.lpxDestination])
        _ = await waitUntil { await rig.controller.connectedController == .launchpadX }
    }

    private func apc(_ rig: Rig, _ event: MIDIEvent) async {
        await rig.transport.receive([event], from: ControllerSessionTests.apcSource.id)
    }

    @Test("APC : le bouton de scène 2 affiche la grille 2, même verrouillé")
    func sceneButton() async {
        let rig = makeRig(grids: 3, locked: true)
        defer { rig.observer.cancel(); rig.runner.cancel() }
        await plugAPC(rig)
        await apc(rig, .noteOn(channel: 0, note: 113, velocity: 127))
        #expect(await waitUntil { await rig.controller.selectedGridIndex == 1 })
    }

    @Test("APC : Shift + scène 1 = grille 9 ; sans Shift, retour à la grille 1")
    func shiftScene() async {
        let rig = makeRig(grids: 10)
        defer { rig.observer.cancel(); rig.runner.cancel() }
        await plugAPC(rig)
        await apc(rig, .noteOn(channel: 0, note: 122, velocity: 127))
        await apc(rig, .noteOn(channel: 0, note: 112, velocity: 127))
        #expect(await waitUntil { await rig.controller.selectedGridIndex == 8 })
        await apc(rig, .noteOff(channel: 0, note: 122, velocity: 0))
        await apc(rig, .noteOn(channel: 0, note: 112, velocity: 127))
        #expect(await waitUntil { await rig.controller.selectedGridIndex == 0 })
    }

    @Test("APC : un bouton de grille qui n'existe pas ne fait rien")
    func missingGrid() async {
        let rig = makeRig(grids: 2)
        defer { rig.observer.cancel(); rig.runner.cancel() }
        await plugAPC(rig)
        await apc(rig, .noteOn(channel: 0, note: 118, velocity: 127))
        try? await Task.sleep(for: .milliseconds(150))
        #expect(rig.controller.selectedGridIndex == 0)
    }

    @Test("Changer de grille ne coupe aucun son")
    func soundContinues() async {
        let rig = makeRig(grids: 2)
        defer { rig.observer.cancel(); rig.runner.cancel() }
        await plugAPC(rig)
        await rig.audio.send(PlaybackEvent(pad: sound.id, state: .playing(startedAt: 0), duration: 10))
        _ = await waitUntil { await rig.controller.playback[sound.id] != nil }
        await apc(rig, .noteOn(channel: 0, note: 113, velocity: 127))
        #expect(await waitUntil { await rig.controller.selectedGridIndex == 1 })
        #expect(rig.controller.playback[sound.id]?.state.isActive == true)
    }

    @Test("Launchpad : ▼ = suivante, ▲ = précédente, arrêt aux bouts")
    func arrows() async {
        let rig = makeRig(grids: 2)
        defer { rig.observer.cancel(); rig.runner.cancel() }
        await plugLaunchpad(rig)
        let source = ControllerSessionTests.lpxSource.id
        await rig.transport.receive([.controlChange(channel: 0, controller: 91, value: 127)], from: source)  // déjà à la première
        try? await Task.sleep(for: .milliseconds(100))
        #expect(rig.controller.selectedGridIndex == 0)
        await rig.transport.receive([.controlChange(channel: 0, controller: 92, value: 127)], from: source)
        #expect(await waitUntil { await rig.controller.selectedGridIndex == 1 })
        await rig.transport.receive([.controlChange(channel: 0, controller: 92, value: 127)], from: source)  // au bout
        try? await Task.sleep(for: .milliseconds(100))
        #expect(rig.controller.selectedGridIndex == 1)
        await rig.transport.receive([.controlChange(channel: 0, controller: 91, value: 127)], from: source)
        #expect(await waitUntil { await rig.controller.selectedGridIndex == 0 })
    }

    @Test("LED : le bouton de la grille affichée s'allume, sans renvoi en double")
    func ledsFollowGrid() async {
        let rig = makeRig(grids: 3)
        defer { rig.observer.cancel(); rig.runner.cancel() }
        await plugAPC(rig)
        let destination = ControllerSessionTests.apcDestination.id
        let on0 = MIDIEvent.noteOn(channel: 0, note: 112, velocity: 1)
        let on1 = MIDIEvent.noteOn(channel: 0, note: 113, velocity: 1)
        #expect(await waitUntil { await rig.transport.sentEvents(to: destination).contains(on0) })
        await apc(rig, .noteOn(channel: 0, note: 113, velocity: 127))
        #expect(await waitUntil { await rig.transport.sentEvents(to: destination).contains(on1) })
        try? await Task.sleep(for: .milliseconds(150))
        let sent = await rig.transport.sentEvents(to: destination)
        #expect(sent.filter { $0 == on1 }.count == 1)
        #expect(sent.filter { $0 == on0 }.count == 1)
    }
}
