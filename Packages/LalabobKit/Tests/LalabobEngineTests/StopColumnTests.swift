import ControllerDrivers
import Foundation
import LalabobAudio
import LalabobMIDI
import LalabobModel
import Testing

@testable import LalabobEngine

/// Boutons « stop » sous les colonnes son (APC mini mk2) et bouton stop de l'interface ; extinction en quittant l'app.
@MainActor
@Suite("Stop de colonne et extinction", .serialized)
struct StopColumnTests {
    let soundA = Pad(title: "A", tint: .vert, content: .audio(clip: AudioClip(fileName: "a.wav")))
    let soundB = Pad(title: "B", tint: .rouge, content: .audio(clip: AudioClip(fileName: "b.wav")))
    let otherColumn = Pad(title: "C", tint: .violet, content: .audio(clip: AudioClip(fileName: "c.wav")))
    let idle = Pad(title: "D", tint: .vert, content: .audio(clip: AudioClip(fileName: "d.wav")))
    let cue = Pad(title: "Feu", tint: .ambre, content: .light(cue: LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 0))))

    struct Rig {
        let audio: RecordingAudioEngine
        let controller: ShowController
        let transport: FakeMIDITransport
        let session: ControllerSession
        let observer: Task<Void, Never>
        let runner: Task<Void, Never>
    }

    private func makeRig(locked: Bool = false) -> Rig {
        var grid = PadGrid.empty(name: "G")
        grid.columns[0].slots[0] = soundA
        grid.columns[0].slots[1] = soundB
        grid.columns[0].slots[2] = idle
        grid.columns[1].slots[0] = otherColumn
        grid.columns[6].slots[0] = cue
        let audio = RecordingAudioEngine()
        let controller = ShowController(
            show: Show(name: "S", grids: [grid]), audio: audio, audioDirectory: URL(filePath: "/tmp/lalabob-audio"),
            defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
        controller.isLocked = locked
        let transport = FakeMIDITransport()
        let session = ControllerSession(
            controller: controller, transport: transport, defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
        return Rig(
            audio: audio, controller: controller, transport: transport, session: session,
            observer: Task { await controller.observePlayback() }, runner: Task { await session.run() })
    }

    private func play(_ rig: Rig, _ pads: [Pad]) async {
        for pad in pads { await rig.audio.send(PlaybackEvent(pad: pad.id, state: .playing(startedAt: 0), duration: 10)) }
        let ids = pads.map(\.id)
        _ = await waitUntil {
            for id in ids where await rig.controller.playback[id] == nil { return false }
            return true
        }
    }

    private func plugAPC(_ rig: Rig) async {
        await rig.transport.setPorts(sources: [ControllerSessionTests.apcSource], destinations: [ControllerSessionTests.apcDestination])
        _ = await waitUntil { await rig.controller.connectedController == .apcMiniMK2 }
    }

    private func stops(_ rig: Rig) async -> [Pad.ID] {
        await rig.audio.commands.compactMap { if case .stop(let id) = $0 { id } else { nil } }
    }

    // MARK: Moteur

    @Test("Stop de colonne : arrête les sons qui jouent ou sont en pause dans cette colonne, et seulement eux")
    func stopsOnlyThatColumnsSounds() async {
        let rig = makeRig()
        defer { rig.observer.cancel(); rig.runner.cancel() }
        await play(rig, [soundA, otherColumn])
        await rig.audio.send(PlaybackEvent(pad: soundB.id, state: .paused(elapsed: 1), duration: 10))
        _ = await waitUntil { await rig.controller.playback[soundB.id] != nil }

        rig.controller.stopColumn(0)
        #expect(await waitUntil { await self.stops(rig).count >= 2 })
        let stopped = await stops(rig)
        #expect(Set(stopped) == [soundA.id, soundB.id])  // le son en pause aussi
        #expect(!stopped.contains(idle.id))  // un pad à l'arrêt n'est pas touché
        #expect(!stopped.contains(otherColumn.id))
    }

    @Test("Une colonne lumière, une colonne invalide ou sans son qui joue : rien")
    func lightAndInvalidColumnsDoNothing() async {
        let rig = makeRig()
        defer { rig.observer.cancel(); rig.runner.cancel() }
        await play(rig, [soundA])
        rig.controller.stopColumn(6)  // colonne lumière
        rig.controller.stopColumn(7)
        rig.controller.stopColumn(-1)
        rig.controller.stopColumn(8)
        rig.controller.stopColumn(3)  // colonne son vide
        try? await Task.sleep(for: .milliseconds(150))
        #expect(await stops(rig).isEmpty)
    }

    @Test("Marche verrouillé (c'est du jeu) et n'est pas un « Tout arrêter »")
    func worksWhenLocked() async {
        let rig = makeRig(locked: true)
        defer { rig.observer.cancel(); rig.runner.cancel() }
        await play(rig, [soundA, otherColumn])
        rig.controller.stopColumn(0)
        #expect(await waitUntil { await self.stops(rig) == [self.soundA.id] })
        #expect(!(await rig.audio.commands.contains(.stopAll)))
    }

    @Test("Les boutons actifs sont les colonnes son de la grille affichée")
    func activeButtonsAreTheSoundColumns() {
        let rig = makeRig()
        defer { rig.observer.cancel(); rig.runner.cancel() }
        #expect(rig.controller.stopButtonColumns == [0, 1, 2, 3, 4, 5])
    }

    // MARK: Session

    @Test("APC : un appui sur le bouton sous la colonne arrête ses sons ; sous une colonne lumière, rien")
    func physicalButtonStopsTheColumn() async {
        let rig = makeRig()
        defer { rig.observer.cancel(); rig.runner.cancel() }
        await plugAPC(rig)
        await play(rig, [soundA, otherColumn])

        await rig.transport.receive([.noteOn(channel: 0, note: 106, velocity: 127)], from: ControllerSessionTests.apcSource.id)  // colonne 7 : lumière
        await rig.transport.receive([.noteOn(channel: 0, note: 100, velocity: 0)], from: ControllerSessionTests.apcSource.id)  // relâchement
        try? await Task.sleep(for: .milliseconds(150))
        #expect(await stops(rig).isEmpty)

        await rig.transport.receive([.noteOn(channel: 0, note: 100, velocity: 127)], from: ControllerSessionTests.apcSource.id)
        #expect(await waitUntil { await self.stops(rig) == [self.soundA.id] })
    }

    @Test("APC : à la connexion, les boutons des colonnes son sont allumés en rouge, ceux des colonnes lumière éteints")
    func stopButtonsAreLit() async {
        let rig = makeRig()
        defer { rig.observer.cancel(); rig.runner.cancel() }
        await plugAPC(rig)
        let destination = ControllerSessionTests.apcDestination.id
        _ = await waitUntil { await rig.transport.sentEvents(to: destination).contains(.noteOn(channel: 0, note: 100, velocity: 1)) }
        let sent = await rig.transport.sentEvents(to: destination)
        for column in 0..<6 { #expect(sent.contains(.noteOn(channel: 0, note: UInt8(100 + column), velocity: 1))) }
        #expect(!sent.contains(.noteOn(channel: 0, note: 106, velocity: 1)))
        #expect(!sent.contains(.noteOn(channel: 0, note: 107, velocity: 1)))
    }

    @Test("Le Launchpad n'a pas de bouton stop : rien n'est envoyé pour eux")
    func launchpadSendsNoStopButtons() async {
        let rig = makeRig()
        defer { rig.observer.cancel(); rig.runner.cancel() }
        await rig.transport.setPorts(sources: [ControllerSessionTests.lpxSource], destinations: [ControllerSessionTests.lpxDestination])
        _ = await waitUntil { await rig.controller.connectedController == .launchpadX }
        try? await Task.sleep(for: .milliseconds(150))
        let sent = await rig.transport.sentEvents(to: ControllerSessionTests.lpxDestination.id)
        #expect(!sent.contains { if case .noteOn(_, let note, _) = $0 { note >= 100 } else { false } })
    }

    // MARK: Extinction

    @Test("APC : en quittant, tous les pads et tous les boutons sont éteints, puis plus rien n'est envoyé")
    func apcShutdown() async {
        let rig = makeRig()
        defer { rig.observer.cancel(); rig.runner.cancel() }
        await plugAPC(rig)
        let destination = ControllerSessionTests.apcDestination.id
        _ = await waitUntil { await rig.transport.sentEvents(to: destination).contains(.noteOn(channel: 0, note: 100, velocity: 1)) }
        await rig.transport.clearSent()

        await rig.session.shutdown()
        let sent = await rig.transport.sentEvents(to: destination)
        for note in 0..<64 { #expect(sent.contains(.noteOn(channel: 0, note: UInt8(note), velocity: 0))) }
        for note in 100..<108 { #expect(sent.contains(.noteOn(channel: 0, note: UInt8(note), velocity: 0))) }

        // Après la fermeture, un changement d'état n'allume plus rien.
        await rig.transport.clearSent()
        rig.controller.isLocked.toggle()
        rig.controller.selection = GridPosition(column: 0, row: 0)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(await rig.transport.sentEvents(to: destination).isEmpty)
    }

    @Test("Launchpad : en quittant, les LED sont éteintes puis le mode Programmeur est quitté, dans cet ordre")
    func launchpadShutdown() async {
        let rig = makeRig()
        defer { rig.observer.cancel(); rig.runner.cancel() }
        await rig.transport.setPorts(sources: [ControllerSessionTests.lpxSource], destinations: [ControllerSessionTests.lpxDestination])
        _ = await waitUntil { await rig.controller.connectedController == .launchpadX }
        try? await Task.sleep(for: .milliseconds(100))
        await rig.transport.clearSent()

        await rig.session.shutdown()
        let sent = await rig.transport.sentEvents(to: ControllerSessionTests.lpxDestination.id)
        let exit = MIDIEvent.systemExclusive([0xF0, 0x00, 0x20, 0x29, 0x02, 0x0C, 0x0E, 0x00, 0xF7])
        #expect(sent.last == exit)
        #expect(sent.count == 2)  // les 64 LED en un message, puis la sortie du mode Programmeur
    }

    @Test("Sans contrôleur branché, la fermeture ne fait rien et ne bloque pas ; deux fermetures de suite non plus")
    func shutdownWithoutController() async {
        let rig = makeRig()
        defer { rig.observer.cancel(); rig.runner.cancel() }
        await rig.session.shutdown()
        await rig.session.shutdown()
        #expect(await rig.transport.sentEvents(to: ControllerSessionTests.apcDestination.id).isEmpty)
    }

    @Test("La fermeture ne coupe aucun son")
    func shutdownDoesNotStopSounds() async {
        let rig = makeRig()
        defer { rig.observer.cancel(); rig.runner.cancel() }
        await plugAPC(rig)
        await play(rig, [soundA])
        await rig.session.shutdown()
        #expect(await stops(rig).isEmpty)
        #expect(!(await rig.audio.commands.contains(.stopAll)))
    }
}
