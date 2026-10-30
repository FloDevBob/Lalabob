import Foundation
import LalabobAudio
import LalabobModel
import Testing

@testable import LalabobEngine

/// Le cadenas : verrouillé, le spectacle se joue mais ne se modifie pas.
@MainActor
@Suite("Verrouillage", .serialized)
struct LockTests {
    static let a = GridPosition(column: 0, row: 0)
    static let b = GridPosition(column: 1, row: 0)

    private func makeController(locked: Bool, audio: RecordingAudioEngine = RecordingAudioEngine()) -> (ShowController, UndoManager, Pad) {
        var grid = PadGrid.empty(name: "G1")
        let pad = Pad(title: "Rire", tint: .vert, content: .audio(clip: AudioClip(fileName: "rire.wav")))
        grid[Self.a] = pad
        let controller = ShowController(
            show: Show(name: "S", grids: [grid]), audio: audio, audioDirectory: URL(filePath: "/tmp/lalabob-audio"),
            defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!, isLocked: locked)
        let undo = UndoManager()
        undo.groupsByEvent = false
        controller.undoManager = undo
        return (controller, undo, pad)
    }

    @Test func aNewControllerIsUnlockedByDefault() {
        let controller = ShowController(defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
        #expect(!controller.isLocked)
    }

    @Test func everyEditIsRefusedWhenLocked() throws {
        let (controller, undo, pad) = makeController(locked: true)
        let before = controller.show

        #expect(!controller.place(pad.duplicated(), at: Self.b))
        #expect(!controller.movePad(from: Self.a, to: Self.b))
        #expect(!controller.duplicatePad(from: Self.a, to: Self.b))
        #expect(!controller.clearPad(at: Self.a))
        #expect(!controller.updatePad(at: Self.a, title: "Autre"))
        #expect(!controller.newLightCue(at: GridPosition(column: 6, row: 0)))
        controller.addGrid()
        controller.renameGrid(at: 0, to: "Acte I")
        controller.removeGrid(at: 0)

        #expect(controller.show == before)
        #expect(!undo.canUndo)
    }

    @Test func refusedEditsShowTheUnlockMessage() {
        let (controller, _, _) = makeController(locked: true)
        #expect(controller.lockNotice == nil)
        controller.clearPad(at: Self.a)
        #expect(controller.lockNotice != nil)
        controller.dismissLockNotice()
        #expect(controller.lockNotice == nil)
    }

    @Test func clipboardIsDisabledWhenLocked() {
        let (controller, _, _) = makeController(locked: true)
        controller.selection = Self.a
        controller.copySelection()
        #expect(!controller.canPaste)
        controller.selection = Self.b
        #expect(!controller.pasteAtSelection())
        #expect(!controller.duplicateSelection())
        #expect(controller.lockNotice != nil)
    }

    @Test func droppingAFileIsRefusedWhenLocked() throws {
        let (controller, _, _) = makeController(locked: true)
        let file = FileManager.default.temporaryDirectory.appending(path: "lalabob-lock-\(UUID().uuidString).wav")
        try Data([1, 2, 3]).write(to: file)
        #expect(!controller.dropAudioFile(file, at: Self.b))
        #expect(controller.pad(at: Self.b) == nil)
        #expect(controller.lockNotice != nil)
    }

    @Test func lockedClickPlaysAndUnlockedClickSelects() async {
        let audio = RecordingAudioEngine()
        let (controller, _, pad) = makeController(locked: true, audio: audio)

        controller.press(at: Self.a)
        #expect(controller.selection == nil)
        #expect(await waitUntil { await audio.commands.contains(.trigger(pad.id)) })

        controller.isLocked = false
        let triggersBefore = await audio.commands.filter { $0 == .trigger(pad.id) }.count
        controller.press(at: Self.a)
        #expect(controller.selection == Self.a)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(await audio.commands.filter { $0 == .trigger(pad.id) }.count == triggersBefore)
    }

    @Test func doubleClickAuditionsWhenUnlocked() async {
        let audio = RecordingAudioEngine()
        let (controller, _, pad) = makeController(locked: false, audio: audio)
        controller.audition(at: Self.a)
        #expect(await waitUntil { await audio.commands.contains(.trigger(pad.id)) })
    }

    @Test func doubleClickDoesNothingMoreWhenLocked() async {
        let audio = RecordingAudioEngine()
        let (controller, _, pad) = makeController(locked: true, audio: audio)
        controller.audition(at: Self.a)  // verrouillé : chaque clic joue déjà, le double-clic n'ajoute rien
        try? await Task.sleep(for: .milliseconds(150))
        #expect(!(await audio.commands.contains(.trigger(pad.id))))
    }

    @Test func lockingClearsTheSelection() {
        let (controller, _, _) = makeController(locked: false)
        controller.selection = Self.a
        controller.isLocked = true
        #expect(controller.selection == nil)
    }

    @Test func fadersAndTabsStillWorkWhenLocked() async {
        var show = Show(name: "S", grids: [.empty(name: "G1"), .empty(name: "G2")])
        show.grids[1].columns[0].level = 0.4
        let audio = RecordingAudioEngine()
        let controller = ShowController(
            show: show, audio: audio, audioDirectory: URL(filePath: "/tmp/lalabob-audio"),
            defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!, isLocked: true)

        controller.setColumnLevel(2, level: 0.5)
        #expect(controller.currentGrid.columns[2].level == 0.5)
        controller.selectGrid(at: 1)
        #expect(controller.selectedGridIndex == 1)
        controller.stopAll()
        #expect(await waitUntil { await audio.commands.contains(.stopAll) })
        #expect(controller.lockNotice == nil)
    }

    @Test func undoStillRestoresAfterUnlocking() {
        let (controller, undo, _) = makeController(locked: false)
        controller.clearPad(at: Self.a)
        controller.isLocked = true
        controller.isLocked = false
        undo.undo()
        #expect(controller.pad(at: Self.a) != nil)
    }

    @Test func undoCannotChangeALockedShow() {
        let (controller, undo, _) = makeController(locked: false)
        controller.clearPad(at: Self.a)
        controller.isLocked = true
        undo.undo()
        #expect(controller.pad(at: Self.a) == nil)  // ⌘Z verrouillé : rien ne change
        #expect(controller.lockNotice != nil)
    }
}
