import ControllerDrivers
import Foundation
import LalabobAudio
import LalabobMIDI
import LalabobModel
import Testing

@testable import LalabobEngine

/// Colonnes lumière (ADR 0006) : LightKey n'écoute que « Lalabob Lumière ». Un clic à l'écran et un appui physique y
/// envoient la même note (Note On, puis Note Off au relâchement) ; un fader physique y envoie son CC. Aucun son n'est touché.
@MainActor
@Suite("Lumière", .serialized)
struct LightingTests {
    static let light = GridPosition(column: 6, row: 1)

    struct Rig {
        let audio: RecordingAudioEngine
        let controller: ShowController
        let transport: FakeMIDITransport
        let runner: Task<Void, Never>
    }

    private func makeRig(defaults: UserDefaults = UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!) -> Rig {
        var grid = PadGrid.empty(name: "G1")
        grid[Self.light] = Pad(
            title: "Plein feu", tint: .ambre,
            content: .light(cue: LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 0))))
        let audio = RecordingAudioEngine()
        let controller = ShowController(
            show: Show(name: "S", grids: [grid]), audio: audio, audioDirectory: URL(filePath: "/tmp/lalabob-audio"),
            defaults: defaults)
        controller.isLocked = true
        let transport = FakeMIDITransport()
        let session = ControllerSession(controller: controller, transport: transport)
        let runner = Task { await session.run() }
        return Rig(audio: audio, controller: controller, transport: transport, runner: runner)
    }

    private func plugLaunchpad(_ rig: Rig) async {
        await rig.transport.setPorts(
            sources: [ControllerSessionTests.lpxSource], destinations: [ControllerSessionTests.lpxDestination])
        _ = await waitUntil { await rig.controller.connectedController == .launchpadX }
    }

    @Test("Un clic sur un pad lumière envoie la note du Launchpad (Note On puis Note Off)")
    func clickSendsControllerNote() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugLaunchpad(rig)

        rig.controller.audition(at: Self.light)
        // Colonne 7, 2e rangée depuis le haut → rangée 7 depuis le bas → note 77.
        let expected: [MIDIEvent] = [.noteOn(channel: 0, note: 77, velocity: 127), .noteOff(channel: 0, note: 77, velocity: 0)]
        #expect(await waitUntil { await rig.transport.lighting == expected })
    }

    @Test("Sans contrôleur branché, on utilise le dernier modèle connu")
    func usesLastKnownController() async {
        let defaults = UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!
        do {
            let first = makeRig(defaults: defaults)
            await first.transport.setPorts(
                sources: [ControllerSessionTests.apcSource], destinations: [ControllerSessionTests.apcDestination])
            _ = await waitUntil { await first.controller.connectedController == .apcMiniMK2 }
            first.runner.cancel()
        }
        let rig = makeRig(defaults: defaults)
        defer { rig.runner.cancel() }
        #expect(rig.controller.lastControllerModel == .apcMiniMK2)

        rig.controller.audition(at: Self.light)
        // APC : note = rangée depuis le bas × 8 + colonne = 6 × 8 + 6 = 54.
        #expect(await waitUntil { await rig.transport.lighting.first == .noteOn(channel: 0, note: 54, velocity: 127) })
    }

    @Test("Aucun contrôleur connu : rien n'est envoyé")
    func noKnownController() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        rig.controller.audition(at: Self.light)
        try? await Task.sleep(for: .milliseconds(250))
        #expect(await rig.transport.lighting.isEmpty)
    }

    @Test("Un appui physique sur un pad lumière est relayé à LightKey (Note On puis Note Off au relâchement) et ne touche aucun son")
    func physicalPressIsRelayed() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugLaunchpad(rig)

        await rig.transport.receive([.noteOn(channel: 0, note: 77, velocity: 100)], from: ControllerSessionTests.lpxSource.id)
        #expect(await waitUntil { await rig.transport.lighting == [.noteOn(channel: 0, note: 77, velocity: 127)] })
        try? await Task.sleep(for: .milliseconds(250))  // pas de Note Off tant que le pad est tenu
        #expect(await rig.transport.lighting.count == 1)

        await rig.transport.receive([.noteOff(channel: 0, note: 77, velocity: 0)], from: ControllerSessionTests.lpxSource.id)
        let expected: [MIDIEvent] = [.noteOn(channel: 0, note: 77, velocity: 127), .noteOff(channel: 0, note: 77, velocity: 0)]
        #expect(await waitUntil { await rig.transport.lighting == expected })
        #expect(!(await rig.audio.commands.contains { if case .trigger = $0 { true } else { false } }))
    }

    @Test("Un simple clic sélectionne sans rien envoyer, verrouillé ou non")
    func singleClickSelects() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugLaunchpad(rig)
        rig.controller.press(at: Self.light)  // verrouillé : le clic ne joue plus, il faut double-cliquer
        try? await Task.sleep(for: .milliseconds(250))
        #expect(rig.controller.selection == Self.light)
        #expect(await rig.transport.lighting.isEmpty)

        rig.controller.isLocked = false
        rig.controller.press(at: Self.light)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(await rig.transport.lighting.isEmpty)
    }

    @Test("La LED d'un pad lumière reste allumée à sa couleur")
    func ledIsFixed() {
        let rig = makeRig()
        rig.runner.cancel()
        #expect(rig.controller.ledStates[Self.light] == .lit(.ambre, .full))
    }

    // MARK: Faders des colonnes lumière

    @Test("Un fader lumière déplacé à l'écran envoie le CC du fader de l'APC sur « Lalabob Lumière »")
    func screenFaderSendsTheControllerCC() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await rig.transport.setPorts(sources: [ControllerSessionTests.apcSource], destinations: [ControllerSessionTests.apcDestination])
        _ = await waitUntil { await rig.controller.connectedController == .apcMiniMK2 }

        rig.controller.setLightFader(column: 6, level: 1)
        #expect(await waitUntil { await rig.transport.lighting == [.controlChange(channel: 0, controller: 54, value: 127)] })
        #expect(rig.controller.currentGrid.columns[6].level == 1)

        rig.controller.setLightFader(column: 7, level: 0.25)
        #expect(await waitUntil { await rig.transport.lighting.last == .controlChange(channel: 0, controller: 55, value: 32) })
        #expect(rig.controller.currentGrid.columns[7].level == 0.25)
    }

    @Test("Les valeurs partent dans l'ordre et une valeur inchangée n'est pas renvoyée")
    func faderValuesAreOrderedAndDeduplicated() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await rig.transport.setPorts(sources: [ControllerSessionTests.apcSource], destinations: [ControllerSessionTests.apcDestination])
        _ = await waitUntil { await rig.controller.connectedController == .apcMiniMK2 }

        for level in [0.1, 0.2, 0.2, 0.2001, 0.3] { rig.controller.setLightFader(column: 6, level: level) }
        let expected: [MIDIEvent] = [13, 25, 38].map { .controlChange(channel: 0, controller: 54, value: $0) }
        #expect(await waitUntil { await rig.transport.lighting.count >= 3 })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await rig.transport.lighting == expected)
    }

    @Test("Avec un Launchpad (sans fader), l'écran utilise la correspondance de l'APC")
    func launchpadFallsBackToTheAPCMapping() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugLaunchpad(rig)

        rig.controller.setLightFader(column: 6, level: 1)
        #expect(await waitUntil { await rig.transport.lighting == [.controlChange(channel: 0, controller: 54, value: 127)] })
    }

    @Test("Aucun contrôleur connu : le niveau change à l'écran, rien n'est envoyé")
    func noKnownControllerForFaders() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }

        rig.controller.setLightFader(column: 6, level: 0.5)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(rig.controller.currentGrid.columns[6].level == 0.5)
        #expect(await rig.transport.lighting.isEmpty)
    }

    @Test("Un fader physique règle l'écran et est relayé à LightKey, une fois par valeur")
    func physicalFaderIsRelayed() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await rig.transport.setPorts(sources: [ControllerSessionTests.apcSource], destinations: [ControllerSessionTests.apcDestination])
        _ = await waitUntil { await rig.controller.connectedController == .apcMiniMK2 }

        rig.controller.setColumnLevel(6, level: 0.5)  // à l'écran (hors LightKey : pas de CC, voir plus bas)
        try? await Task.sleep(for: .milliseconds(50))
        // Le fader rejoint d'abord la valeur de l'écran, puis monte : l'écran le suit, et LightKey reçoit chaque valeur une fois.
        await rig.transport.receive([.controlChange(channel: 0, controller: 54, value: 64)], from: ControllerSessionTests.apcSource.id)
        await rig.transport.receive([.controlChange(channel: 0, controller: 54, value: 127)], from: ControllerSessionTests.apcSource.id)
        #expect(await waitUntil { await rig.controller.currentGrid.columns[6].level == 1 })
        let expected: [MIDIEvent] = [.controlChange(channel: 0, controller: 54, value: 64), .controlChange(channel: 0, controller: 54, value: 127)]
        #expect(await waitUntil { await rig.transport.lighting == expected })
    }

    @Test("Après un fader physique, une valeur différente à l'écran est renvoyée ; la même valeur ne l'est pas")
    func screenValueIsResentAfterAPhysicalMove() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await rig.transport.setPorts(sources: [ControllerSessionTests.apcSource], destinations: [ControllerSessionTests.apcDestination])
        _ = await waitUntil { await rig.controller.connectedController == .apcMiniMK2 }

        let half = ControllerModel.apcMiniMK2.driver.faderEvent(column: 6, value: 0.5)
        rig.controller.setLightFader(column: 6, level: 0.5)
        #expect(await waitUntil { await rig.transport.lighting.count == 1 })
        // Le fader physique rejoint 0,5 (déjà connu de LightKey : rien de plus), puis monte (relayé).
        await rig.transport.receive([.controlChange(channel: 0, controller: 54, value: 64)], from: ControllerSessionTests.apcSource.id)
        await rig.transport.receive([.controlChange(channel: 0, controller: 54, value: 127)], from: ControllerSessionTests.apcSource.id)
        #expect(await waitUntil { await rig.controller.currentGrid.columns[6].level == 1 })
        #expect(await waitUntil { await rig.transport.lighting.count == 2 })
        rig.controller.setLightFader(column: 6, level: 0.5)
        #expect(await waitUntil { await rig.transport.lighting.count == 3 })
        #expect(await rig.transport.lighting.last == half)
    }

    @Test("L'interface connaît le CC du fader d'une colonne lumière (APC, ou celui de l'APC pour un Launchpad)")
    func faderCCIsShownToTheUser() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        #expect(rig.controller.lightFaderCC(forColumn: 6) == nil)  // aucun contrôleur connu

        await plugLaunchpad(rig)
        #expect(rig.controller.lightFaderCC(forColumn: 6) == 54)
        #expect(rig.controller.lightFaderCC(forColumn: 7) == 55)
        #expect(rig.controller.lightFaderCC(forColumn: 2) == nil)  // colonne son : pas de CC lumière
    }

    @Test("Les colonnes sons ne passent pas par la lumière")
    func soundColumnsAreNotForwarded() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await rig.transport.setPorts(sources: [ControllerSessionTests.apcSource], destinations: [ControllerSessionTests.apcDestination])
        _ = await waitUntil { await rig.controller.connectedController == .apcMiniMK2 }

        rig.controller.setLightFader(column: 2, level: 1)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(await rig.transport.lighting.isEmpty)
        #expect(rig.controller.currentGrid.columns[2].level == 0.8)  // inchangé
    }
}
