import ControllerDrivers
import Foundation
import LalabobAudio
import LalabobMIDI
import LalabobModel
import Testing

@testable import LalabobEngine

/// Plusieurs spectacles ouverts : une seule session MIDI, rattachée à la fenêtre active.
@MainActor
@Suite("Plusieurs documents", .serialized)
struct MultiDocumentTests {
    private func controller(padTitle: String, tint: Tint, audio: RecordingAudioEngine) -> (ShowController, Pad) {
        var grid = PadGrid.empty(name: "G")
        let pad = Pad(title: padTitle, tint: tint, content: .audio(clip: AudioClip(fileName: "\(padTitle).wav")))
        grid.columns[0].slots[0] = pad
        let controller = ShowController(
            show: Show(name: padTitle, grids: [grid]), audio: audio, audioDirectory: URL(filePath: "/tmp/lalabob-audio"),
            defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
        return (controller, pad)
    }

    @Test func pressesGoToTheAttachedShowAndLEDsFollowIt() async {
        let audioA = RecordingAudioEngine()
        let audioB = RecordingAudioEngine()
        let (a, padA) = controller(padTitle: "A", tint: .vert, audio: audioA)
        let (b, padB) = controller(padTitle: "B", tint: .rouge, audio: audioB)
        let transport = FakeMIDITransport()
        let session = ControllerSession(transport: transport)
        let runner = Task { await session.run() }
        defer { runner.cancel() }

        session.attach(a)
        await transport.setPorts(sources: [ControllerSessionTests.lpxSource], destinations: [ControllerSessionTests.lpxDestination])
        #expect(await waitUntil { await a.connectedController == .launchpadX })

        await transport.receive([.noteOn(channel: 0, note: 81, velocity: 100)], from: ControllerSessionTests.lpxSource.id)
        #expect(await waitUntil { await audioA.commands.contains(.trigger(padA.id)) })

        // La fenêtre B devient active : toutes les LED sont renvoyées avec ses couleurs, les appuis vont à B.
        await transport.clearSent()
        session.attach(b)
        let driver = ControllerModel.launchpadX.driver
        let expectedFirstPad = driver.ledMessages([GridPosition(column: 0, row: 0): .lit(.rouge, .full)])
        #expect(await waitUntil {
            let sent = await transport.sentEvents(to: ControllerSessionTests.lpxDestination.id)
            return sent.contains { event in
                guard case .systemExclusive(let bytes) = event, case .systemExclusive(let one)? = expectedFirstPad.first else { return false }
                let spec = Array(one.dropFirst(7).dropLast())
                return bytes.count >= spec.count && (0...(bytes.count - spec.count)).contains { Array(bytes[$0..<($0 + spec.count)]) == spec }
            }
        })
        #expect(b.connectedController == .launchpadX)

        await transport.receive([.noteOn(channel: 0, note: 81, velocity: 100)], from: ControllerSessionTests.lpxSource.id)
        #expect(await waitUntil { await audioB.commands.contains(.trigger(padB.id)) })
        // Rien n'a été arrêté dans A.
        #expect(!(await audioA.commands.contains(.stopAll)))
    }

    @Test func detachingTheActiveShowStopsRoutingPresses() async {
        let audio = RecordingAudioEngine()
        let (a, padA) = controller(padTitle: "A", tint: .vert, audio: audio)
        let transport = FakeMIDITransport()
        let session = ControllerSession(transport: transport)
        let runner = Task { await session.run() }
        defer { runner.cancel() }

        session.attach(a)
        await transport.setPorts(sources: [ControllerSessionTests.lpxSource], destinations: [ControllerSessionTests.lpxDestination])
        #expect(await waitUntil { await a.connectedController != nil })
        session.detach(a)
        #expect(a.connectedController == nil)

        await transport.receive([.noteOn(channel: 0, note: 81, velocity: 100)], from: ControllerSessionTests.lpxSource.id)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(!(await audio.commands.contains(.trigger(padA.id))))
    }

    @Test func detachingAnotherShowDoesNothing() async {
        let (a, _) = controller(padTitle: "A", tint: .vert, audio: RecordingAudioEngine())
        let (b, _) = controller(padTitle: "B", tint: .rouge, audio: RecordingAudioEngine())
        let session = ControllerSession(transport: FakeMIDITransport())
        session.attach(a)
        session.detach(b)
        #expect(session.attachedController === a)
    }

    @Test func lightClicksOfTheAttachedShowReachLightKey() async {
        var grid = PadGrid.empty(name: "G")
        grid[GridPosition(column: 6, row: 0)] = Pad(
            title: "Feu", tint: .ambre, content: .light(cue: LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 0))))
        let a = ShowController(
            show: Show(name: "A", grids: [grid]), defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
        let b = ShowController(
            show: Show(name: "B", grids: [grid]), defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
        a.mode = .live
        b.mode = .live
        let transport = FakeMIDITransport()
        let session = ControllerSession(transport: transport)
        let runner = Task { await session.run() }
        defer { runner.cancel() }
        session.attach(a)
        await transport.setPorts(sources: [ControllerSessionTests.lpxSource], destinations: [ControllerSessionTests.lpxDestination])
        #expect(await waitUntil { await a.connectedController != nil })
        session.attach(b)

        a.press(at: GridPosition(column: 6, row: 0))  // fenêtre inactive : ignoré
        try? await Task.sleep(for: .milliseconds(200))
        #expect(await transport.lighting.isEmpty)
        b.press(at: GridPosition(column: 6, row: 0))
        #expect(await waitUntil { await !transport.lighting.isEmpty })
    }
}

@MainActor
@Suite("Copie du spectacle pour l'enregistrement")
struct ShowMirrorTests {
    @Test func everyChangeIsReported() {
        let controller = ShowController(defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
        let mirror = ShowMirror(controller.show)
        controller.onShowChange = { mirror.update($0) }

        controller.addGrid()
        #expect(mirror.current.grids.count == 2)
        controller.setColumnLevel(0, level: 0.3)
        #expect(mirror.current.grids[controller.selectedGridIndex].columns[0].level == 0.3)
        controller.renameGrid(at: 0, to: "Acte I")
        #expect(mirror.current.grids[0].name == "Acte I")
    }

    @Test func undoIsReportedToo() {
        let controller = ShowController(defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
        let undo = UndoManager()
        undo.groupsByEvent = false
        controller.undoManager = undo
        let mirror = ShowMirror(controller.show)
        controller.onShowChange = { mirror.update($0) }

        controller.addGrid()
        undo.undo()
        #expect(mirror.current.grids.count == 1)
    }
}
