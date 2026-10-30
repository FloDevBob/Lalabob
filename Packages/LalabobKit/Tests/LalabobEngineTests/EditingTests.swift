import Foundation
import LalabobAudio
import LalabobModel
import Testing

@testable import LalabobEngine

@MainActor
@Suite("Édition du spectacle")
struct EditingTests {
    static let a = GridPosition(column: 0, row: 0)
    static let b = GridPosition(column: 1, row: 3)
    static let lightCell = GridPosition(column: 6, row: 0)

    private func sound(_ title: String, tint: Tint = .vert) -> Pad {
        Pad(title: title, tint: tint, content: .audio(clip: AudioClip(fileName: "\(title).wav")))
    }

    /// Contrôleur avec un gestionnaire d'annulation où chaque opération forme son propre groupe.
    private func makeController(_ show: Show = .new()) -> (ShowController, UndoManager) {
        let controller = ShowController(
            show: show, defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
        let undo = UndoManager()
        undo.groupsByEvent = false
        controller.undoManager = undo
        controller.isLocked = false
        return (controller, undo)
    }

    // MARK: Placer, vider

    @Test func placeASoundThenUndoAndRedo() {
        let (controller, undo) = makeController()
        let pad = sound("Rire")
        #expect(controller.place(pad, at: Self.a))
        #expect(controller.pad(at: Self.a) == pad)
        #expect(undo.canUndo)

        undo.undo()
        #expect(controller.pad(at: Self.a) == nil)
        undo.redo()
        #expect(controller.pad(at: Self.a) == pad)
    }

    @Test func soundsDoNotGoInLightColumns() {
        let (controller, undo) = makeController()
        #expect(!controller.place(sound("Rire"), at: Self.lightCell))
        #expect(controller.pad(at: Self.lightCell) == nil)
        #expect(!undo.canUndo)
    }

    @Test func newLightCueOnlyInLightColumns() {
        let (controller, _) = makeController()
        #expect(controller.newLightCue(at: Self.lightCell))
        guard case .light = controller.pad(at: Self.lightCell)?.content else {
            Issue.record("une cue lumière était attendue")
            return
        }
        #expect(!controller.newLightCue(at: Self.a))
        #expect(controller.pad(at: Self.a) == nil)
    }

    @Test func clearRemovesThePadAndIsUndoable() {
        let (controller, undo) = makeController()
        let pad = sound("Gong")
        controller.place(pad, at: Self.a)
        controller.clearPad(at: Self.a)
        #expect(controller.pad(at: Self.a) == nil)
        undo.undo()
        #expect(controller.pad(at: Self.a) == pad)
    }

    // MARK: Glisser

    @Test func moveToAnEmptyCell() {
        let (controller, _) = makeController()
        let pad = sound("Rire")
        controller.place(pad, at: Self.a)
        #expect(controller.movePad(from: Self.a, to: Self.b))
        #expect(controller.pad(at: Self.a) == nil)
        #expect(controller.pad(at: Self.b) == pad)
    }

    @Test func moveOntoAnotherPadSwapsThemInOneUndoStep() {
        let (controller, undo) = makeController()
        let first = sound("Rire")
        let second = sound("Porte", tint: .rouge)
        controller.place(first, at: Self.a)
        controller.place(second, at: Self.b)

        #expect(controller.movePad(from: Self.a, to: Self.b))
        #expect(controller.pad(at: Self.a) == second)
        #expect(controller.pad(at: Self.b) == first)
        undo.undo()
        #expect(controller.pad(at: Self.a) == first)
        #expect(controller.pad(at: Self.b) == second)
    }

    @Test func soundCannotBeMovedOrSwappedIntoALightColumn() {
        let (controller, _) = makeController()
        controller.place(sound("Rire"), at: Self.a)
        controller.newLightCue(at: Self.lightCell)
        #expect(!controller.movePad(from: Self.a, to: Self.lightCell))
        #expect(!controller.movePad(from: Self.a, to: GridPosition(column: 7, row: 5)))
    }

    @Test func moveOntoItselfDoesNothing() {
        let (controller, undo) = makeController()
        controller.place(sound("Rire"), at: Self.a)
        let steps = undo.canUndo
        #expect(!controller.movePad(from: Self.a, to: Self.a))
        #expect(undo.canUndo == steps)
    }

    @Test func optionDragDuplicatesWithANewIdentifier() {
        let (controller, _) = makeController()
        let pad = sound("Rire")
        controller.place(pad, at: Self.a)
        #expect(controller.duplicatePad(from: Self.a, to: Self.b))
        let copy = controller.pad(at: Self.b)
        #expect(copy?.title == "Rire")
        #expect(copy?.id != pad.id)
        #expect(controller.pad(at: Self.a) == pad)
    }

    @Test func duplicateOntoAnOccupiedCellIsRefused() {
        let (controller, _) = makeController()
        controller.place(sound("Rire"), at: Self.a)
        controller.place(sound("Porte"), at: Self.b)
        #expect(!controller.duplicatePad(from: Self.a, to: Self.b))
        #expect(controller.pad(at: Self.b)?.title == "Porte")
    }

    // MARK: Presse-papiers

    @Test func copyPasteCreatesAnIndependentPad() {
        let (controller, _) = makeController()
        let pad = sound("Rire")
        controller.place(pad, at: Self.a)
        controller.selection = Self.a
        controller.copySelection()
        controller.selection = Self.b
        #expect(controller.pasteAtSelection())
        #expect(controller.pad(at: Self.b)?.title == "Rire")
        #expect(controller.pad(at: Self.b)?.id != pad.id)
        #expect(controller.pad(at: Self.a) == pad)
    }

    @Test func cutRemovesAndPasteRestoresElsewhere() {
        let (controller, _) = makeController()
        controller.place(sound("Rire"), at: Self.a)
        controller.selection = Self.a
        controller.cutSelection()
        #expect(controller.pad(at: Self.a) == nil)
        controller.selection = Self.b
        #expect(controller.pasteAtSelection())
        #expect(controller.pad(at: Self.b)?.title == "Rire")
    }

    @Test func pasteRespectsColumnKind() {
        let (controller, _) = makeController()
        controller.place(sound("Rire"), at: Self.a)
        controller.selection = Self.a
        controller.copySelection()
        controller.selection = Self.lightCell
        #expect(!controller.pasteAtSelection())
        #expect(controller.pad(at: Self.lightCell) == nil)
    }

    @Test func pasteOverAPadReplacesIt() {
        let (controller, undo) = makeController()
        controller.place(sound("Rire"), at: Self.a)
        controller.place(sound("Porte"), at: Self.b)
        controller.selection = Self.a
        controller.copySelection()
        controller.selection = Self.b
        #expect(controller.pasteAtSelection())
        #expect(controller.pad(at: Self.b)?.title == "Rire")
        undo.undo()
        #expect(controller.pad(at: Self.b)?.title == "Porte")
    }

    @Test func duplicateSelectionGoesToTheNextFreeCellBelow() {
        let (controller, _) = makeController()
        controller.place(sound("Rire"), at: GridPosition(column: 2, row: 0))
        controller.place(sound("Porte"), at: GridPosition(column: 2, row: 1))
        controller.selection = GridPosition(column: 2, row: 0)
        #expect(controller.duplicateSelection())
        #expect(controller.pad(at: GridPosition(column: 2, row: 2))?.title == "Rire")
        #expect(controller.selection == GridPosition(column: 2, row: 2))
    }

    @Test func duplicateSelectionInAFullColumnFails() {
        let (controller, _) = makeController()
        for row in 0..<PadGrid.size { controller.place(sound("S\(row)"), at: GridPosition(column: 3, row: row)) }
        controller.selection = GridPosition(column: 3, row: 4)
        #expect(!controller.duplicateSelection())
    }

    // MARK: Inspecteur

    @Test func editTitleSubtitleColorAndIntensity() {
        let (controller, undo) = makeController()
        controller.place(sound("Rire"), at: Self.a)
        controller.updatePad(at: Self.a, title: "Fou rire", subtitle: "Public", tint: .fuchsia, ledIntensity: .half)
        let pad = controller.pad(at: Self.a)
        #expect(pad?.title == "Fou rire")
        #expect(pad?.subtitle == "Public")
        #expect(pad?.tint == .fuchsia)
        #expect(pad?.ledIntensity == .half)
        undo.undo()
        #expect(controller.pad(at: Self.a)?.title == "Rire")
        #expect(controller.pad(at: Self.a)?.tint == .vert)
    }

    @Test func editingWithoutChangeRegistersNoUndo() {
        let (controller, undo) = makeController()
        controller.place(sound("Rire"), at: Self.a)
        undo.removeAllActions()
        controller.updatePad(at: Self.a, title: "Rire")
        #expect(!undo.canUndo)
    }

    @Test func editingAnEmptyCellDoesNothing() {
        let (controller, undo) = makeController()
        controller.updatePad(at: Self.a, title: "Rien")
        #expect(controller.pad(at: Self.a) == nil)
        #expect(!undo.canUndo)
    }

    // MARK: Onglets

    @Test func addRenameMoveAndRemoveGrids() {
        let (controller, undo) = makeController()
        controller.addGrid()
        #expect(controller.show.grids.count == 2)
        #expect(controller.selectedGridIndex == 1)
        #expect(controller.show.grids[1].name == "Grille 2")

        controller.renameGrid(at: 1, to: "Acte II")
        #expect(controller.show.grids[1].name == "Acte II")
        controller.renameGrid(at: 1, to: "   ")  // nom vide refusé
        #expect(controller.show.grids[1].name == "Acte II")

        controller.moveGrid(from: 1, to: 0)
        #expect(controller.show.grids.map(\.name) == ["Acte II", "Grille 1"])
        #expect(controller.selectedGridIndex == 0)  // la sélection suit l'onglet déplacé

        controller.removeGrid(at: 0)
        #expect(controller.show.grids.map(\.name) == ["Grille 1"])
        controller.removeGrid(at: 0)  // jamais la dernière grille
        #expect(controller.show.grids.count == 1)

        undo.undo()
        #expect(controller.show.grids.map(\.name) == ["Acte II", "Grille 1"])
    }

    @Test func gridCountIsLimited() {
        let (controller, _) = makeController()
        for _ in 0..<(Show.maximumGridCount + 5) { controller.addGrid() }
        #expect(controller.show.grids.count == Show.maximumGridCount)
    }

    @Test func undoKeepsSelectedGridIndexValid() {
        let (controller, undo) = makeController()
        controller.addGrid()
        #expect(controller.selectedGridIndex == 1)
        undo.undo()
        #expect(controller.show.grids.count == 1)
        #expect(controller.selectedGridIndex == 0)
    }

    @Test func everyEditKeepsTheShowValid() throws {
        let (controller, _) = makeController()
        controller.place(sound("Rire"), at: Self.a)
        controller.newLightCue(at: Self.lightCell)
        controller.movePad(from: Self.a, to: Self.b)
        controller.duplicatePad(from: Self.b, to: Self.a)
        controller.addGrid()
        try controller.show.validate()
    }

    @Test func editsAreSentToTheAudioEngine() async {
        let audio = RecordingAudioEngine()
        let controller = ShowController(
            audio: audio, audioDirectory: URL(filePath: "/tmp/lalabob-audio"),
            defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
        controller.place(sound("Rire"), at: Self.a)
        #expect(await waitUntil { await audio.commands.contains(.configure(padCount: 1)) })
    }
}
