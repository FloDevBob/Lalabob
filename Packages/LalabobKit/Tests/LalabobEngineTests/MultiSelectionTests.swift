import Foundation
import LalabobAudio
import LalabobModel
import Testing

@testable import LalabobEngine

/// Sélection multiple (Maj = plage rectangulaire, ⌘ = ajout / retrait) et opérations sur plusieurs pads :
/// copier-coller, couper, vider, dupliquer, déplacer ou copier en bloc. Chaque opération = une seule annulation.
@MainActor
@Suite("Sélection multiple")
struct MultiSelectionTests {
    static let a = GridPosition(column: 0, row: 0)
    static let b = GridPosition(column: 1, row: 0)
    static let c = GridPosition(column: 0, row: 1)
    static let d = GridPosition(column: 1, row: 1)

    private func sound(_ title: String) -> Pad {
        Pad(title: title, tint: .vert, content: .audio(clip: AudioClip(fileName: "\(title).wav")))
    }

    /// Un carré 2 × 2 de sons « A B / C D » dans les colonnes 0 et 1, lignes 0 et 1.
    private func makeController() -> (ShowController, UndoManager) {
        var grid = PadGrid.empty(name: "G")
        grid[Self.a] = sound("A")
        grid[Self.b] = sound("B")
        grid[Self.c] = sound("C")
        grid[Self.d] = sound("D")
        let controller = ShowController(
            show: Show(name: "S", grids: [grid]), defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
        let undo = UndoManager()
        undo.groupsByEvent = false
        controller.undoManager = undo
        controller.isLocked = false
        return (controller, undo)
    }

    private func titles(_ controller: ShowController, _ positions: [GridPosition]) -> [String?] {
        positions.map { controller.pad(at: $0)?.title }
    }

    // MARK: Sélection

    @Test func aPlainClickReplacesTheSelection() {
        let (controller, _) = makeController()
        controller.press(at: Self.a)
        controller.press(at: Self.d, mode: .range)
        controller.press(at: Self.b)
        #expect(controller.selectedPositions == [Self.b])
        #expect(controller.selection == Self.b)
    }

    @Test func shiftClickSelectsTheRectangleFromTheAnchor() {
        let (controller, _) = makeController()
        controller.press(at: Self.a)
        controller.press(at: Self.d, mode: .range)
        #expect(controller.selectedPositions == [Self.a, Self.b, Self.c, Self.d])
        #expect(controller.selection == Self.a)  // l'ancre ne bouge pas

        controller.press(at: Self.b, mode: .range)  // le rectangle se redessine autour de la même ancre
        #expect(controller.selectedPositions == [Self.a, Self.b])
    }

    @Test func shiftClickWithoutAnchorJustSelects() {
        let (controller, _) = makeController()
        controller.press(at: Self.d, mode: .range)
        #expect(controller.selectedPositions == [Self.d])
    }

    @Test func commandClickTogglesOnePad() {
        let (controller, _) = makeController()
        controller.press(at: Self.a)
        controller.press(at: Self.d, mode: .toggle)
        #expect(controller.selectedPositions == [Self.a, Self.d])
        controller.press(at: Self.a, mode: .toggle)
        #expect(controller.selectedPositions == [Self.d])
        #expect(controller.selection == Self.d)  // le pad principal passe au restant
        controller.press(at: Self.d, mode: .toggle)
        #expect(controller.selectedPositions.isEmpty)
        #expect(controller.selection == nil)
    }

    @Test func settingSelectionDirectlyCollapsesAMultipleSelection() {
        let (controller, _) = makeController()
        controller.press(at: Self.a)
        controller.press(at: Self.d, mode: .range)
        controller.selection = Self.c
        #expect(controller.selectedPositions == [Self.c])
        controller.selection = nil
        #expect(controller.selectedPositions.isEmpty)
    }

    @Test func lockedClicksPlayInsteadOfSelectingARange() {
        let (controller, _) = makeController()
        controller.isLocked = true
        controller.press(at: Self.a)
        controller.press(at: Self.d, mode: .range)
        controller.press(at: Self.b, mode: .toggle)
        #expect(controller.selectedPositions == [Self.b])  // seul le dernier son lancé est « sélectionné » pour le panneau
    }

    // MARK: Copier, couper, coller

    @Test func copyAndPasteKeepTheLayoutWithNewIdentifiers() {
        let (controller, undo) = makeController()
        controller.press(at: Self.a)
        controller.press(at: Self.d, mode: .range)
        controller.copySelection()

        controller.press(at: GridPosition(column: 3, row: 4))
        #expect(controller.pasteAtSelection())
        let target = (0..<2).flatMap { column in
            (0..<2).map { row in GridPosition(column: 3 + column, row: 4 + row) }
        }
        #expect(titles(controller, target) == ["A", "C", "B", "D"])
        let originalIDs = Set([Self.a, Self.b, Self.c, Self.d].compactMap { controller.pad(at: $0)?.id })
        let pastedIDs = Set(target.compactMap { controller.pad(at: $0)?.id })
        #expect(pastedIDs.count == 4 && pastedIDs.isDisjoint(with: originalIDs))

        undo.undo()  // une seule annulation retire les quatre copies
        #expect(titles(controller, target) == [nil, nil, nil, nil])
    }

    @Test func pasteSkipsWhatDoesNotFitAndKeepsTheRest() {
        let (controller, undo) = makeController()
        controller.press(at: Self.a)
        controller.press(at: Self.b, mode: .range)  // A et B, côte à côte
        controller.copySelection()

        // A tombe dans la colonne 5 (sons), B dans la colonne 6 (lumière) : seul A est collé.
        controller.press(at: GridPosition(column: 5, row: 3))
        #expect(controller.pasteAtSelection())
        #expect(controller.pad(at: GridPosition(column: 5, row: 3))?.title == "A")
        #expect(controller.pad(at: GridPosition(column: 6, row: 3)) == nil)
        undo.undo()
        #expect(controller.pad(at: GridPosition(column: 5, row: 3)) == nil)
    }

    @Test func pasteFailsWhenNothingFits() {
        let (controller, undo) = makeController()
        controller.press(at: Self.a)
        controller.copySelection()
        controller.press(at: GridPosition(column: 6, row: 0))  // un son dans une colonne lumière
        let before = controller.show
        #expect(!controller.pasteAtSelection())
        #expect(controller.show == before)
        #expect(undo.canUndo == false)
    }

    @Test func cutRemovesAllSelectedPadsInOneStep() {
        let (controller, undo) = makeController()
        controller.press(at: Self.a)
        controller.press(at: Self.d, mode: .range)
        controller.cutSelection()
        #expect(titles(controller, [Self.a, Self.b, Self.c, Self.d]) == [nil, nil, nil, nil])
        undo.undo()
        #expect(titles(controller, [Self.a, Self.b, Self.c, Self.d]) == ["A", "B", "C", "D"])
        #expect(controller.canPaste)
    }

    @Test func emptyCellsInTheSelectionAreIgnoredByCopy() {
        let (controller, _) = makeController()
        controller.press(at: Self.b)
        controller.press(at: GridPosition(column: 2, row: 0), mode: .range)  // B + une case vide
        controller.copySelection()
        controller.press(at: GridPosition(column: 4, row: 4))
        controller.pasteAtSelection()
        #expect(controller.pad(at: GridPosition(column: 4, row: 4))?.title == "B")
        #expect(controller.pad(at: GridPosition(column: 5, row: 4)) == nil)
    }

    // MARK: Vider, dupliquer

    @Test func clearRemovesAllSelectedPadsInOneStep() {
        let (controller, undo) = makeController()
        controller.press(at: Self.a)
        controller.press(at: Self.b, mode: .range)
        #expect(controller.clearSelection())
        #expect(titles(controller, [Self.a, Self.b, Self.c, Self.d]) == [nil, nil, "C", "D"])
        undo.undo()
        #expect(titles(controller, [Self.a, Self.b, Self.c, Self.d]) == ["A", "B", "C", "D"])
    }

    @Test func duplicateGoesBelowEachPadAndSelectsTheCopies() {
        let (controller, undo) = makeController()
        controller.press(at: Self.a)
        controller.press(at: Self.b, mode: .range)
        #expect(controller.duplicateSelection())
        // Les lignes 0 et 1 sont prises dans ces colonnes : les copies vont en ligne 2.
        let copies = [GridPosition(column: 0, row: 2), GridPosition(column: 1, row: 2)]
        #expect(titles(controller, copies) == ["A", "B"])
        #expect(controller.selectedPositions == Set(copies))
        undo.undo()
        #expect(titles(controller, copies) == [nil, nil])
    }

    // MARK: Déplacer, copier en bloc

    @Test func moveBlockShiftsAllSelectedPadsByTheSameOffset() {
        let (controller, undo) = makeController()
        controller.press(at: Self.a)
        controller.press(at: Self.d, mode: .range)
        // Glisser A d'une colonne et de deux lignes : tout le carré suit.
        #expect(controller.moveSelection(from: Self.a, to: GridPosition(column: 2, row: 2)))
        #expect(titles(controller, [Self.a, Self.b, Self.c, Self.d]) == [nil, nil, nil, nil])
        let moved = [(2, 2), (2, 3), (3, 2), (3, 3)].map { GridPosition(column: $0.0, row: $0.1) }
        #expect(titles(controller, moved) == ["A", "C", "B", "D"])
        #expect(controller.selectedPositions == Set(moved))  // la sélection suit
        undo.undo()
        #expect(titles(controller, [Self.a, Self.b, Self.c, Self.d]) == ["A", "B", "C", "D"])
    }

    @Test func moveBlockMayOverlapItsOwnSourceCells() {
        let (controller, _) = makeController()
        controller.press(at: Self.a)
        controller.press(at: Self.d, mode: .range)
        #expect(controller.moveSelection(from: Self.a, to: GridPosition(column: 0, row: 1)))  // une ligne plus bas
        #expect(titles(controller, [Self.a, Self.b]) == [nil, nil])
        #expect(titles(controller, [Self.c, Self.d]) == ["A", "B"])
        #expect(titles(controller, [GridPosition(column: 0, row: 2), GridPosition(column: 1, row: 2)]) == ["C", "D"])
    }

    @Test func moveBlockIsRefusedWhenItWouldCrushAnotherPad() {
        let (controller, undo) = makeController()
        controller.place(sound("X"), at: GridPosition(column: 3, row: 3))
        undo.removeAllActions()
        controller.press(at: Self.a)
        controller.press(at: Self.b, mode: .range)
        let before = controller.show
        #expect(!controller.moveSelection(from: Self.a, to: GridPosition(column: 3, row: 3)))  // A tomberait sur X (hors sélection)
        #expect(controller.show == before)
        #expect(!undo.canUndo)
    }

    @Test func moveBlockIsRefusedOutsideTheGridOrIntoTheOtherKindOfColumn() {
        let (controller, _) = makeController()
        controller.press(at: Self.a)
        controller.press(at: Self.b, mode: .range)
        let before = controller.show
        #expect(!controller.moveSelection(from: Self.a, to: GridPosition(column: 7, row: 7)))  // hors grille
        #expect(!controller.moveSelection(from: Self.a, to: GridPosition(column: 5, row: 5)))  // B dans une colonne lumière
        #expect(controller.show == before)
    }

    @Test func aSinglePadStillSwapsWithItsTarget() {
        let (controller, _) = makeController()
        controller.press(at: Self.a)
        #expect(controller.moveSelection(from: Self.a, to: Self.b))
        #expect(titles(controller, [Self.a, Self.b]) == ["B", "A"])
    }

    @Test func draggingAPadOutsideTheSelectionMovesOnlyThatPad() {
        let (controller, _) = makeController()
        controller.press(at: Self.a)
        controller.press(at: Self.b, mode: .range)
        #expect(controller.moveSelection(from: Self.d, to: GridPosition(column: 4, row: 4)))
        #expect(controller.pad(at: GridPosition(column: 4, row: 4))?.title == "D")
        #expect(titles(controller, [Self.a, Self.b]) == ["A", "B"])
    }

    @Test func copyBlockPlacesNewPadsAndLeavesTheOriginals() {
        let (controller, undo) = makeController()
        controller.press(at: Self.a)
        controller.press(at: Self.d, mode: .range)
        #expect(controller.duplicateSelection(from: Self.a, to: GridPosition(column: 3, row: 0)))
        let copies = [(3, 0), (3, 1), (4, 0), (4, 1)].map { GridPosition(column: $0.0, row: $0.1) }
        #expect(titles(controller, copies) == ["A", "C", "B", "D"])
        #expect(titles(controller, [Self.a, Self.b, Self.c, Self.d]) == ["A", "B", "C", "D"])
        undo.undo()
        #expect(titles(controller, copies) == [nil, nil, nil, nil])
    }

    @Test func copyBlockIsRefusedWhenATargetIsOccupied() {
        let (controller, undo) = makeController()
        controller.press(at: Self.a)
        controller.press(at: Self.b, mode: .range)
        let before = controller.show
        #expect(!controller.duplicateSelection(from: Self.a, to: Self.c))  // A → C (occupée)
        #expect(controller.show == before)
        #expect(!undo.canUndo)
    }

    @Test func multiSelectionOperationsAreRefusedWhenLocked() {
        let (controller, undo) = makeController()
        controller.press(at: Self.a)
        controller.press(at: Self.d, mode: .range)
        controller.copySelection()
        controller.isLocked = true
        let before = controller.show
        #expect(!controller.clearSelection())
        #expect(!controller.moveSelection(from: Self.a, to: GridPosition(column: 3, row: 3)))
        #expect(!controller.duplicateSelection(from: Self.a, to: GridPosition(column: 3, row: 3)))
        #expect(controller.show == before)
        #expect(!undo.canUndo)
    }

    // MARK: Aperçu des cases cibles pendant un glisser

    @Test func previewShowsEveryTargetCellOfTheGroup() {
        let (controller, _) = makeController()
        controller.press(at: Self.a)
        controller.press(at: Self.d, mode: .range)
        controller.updateDragPreview(source: Self.a, target: GridPosition(column: 2, row: 2), copying: false)
        let cells = [(2, 2), (2, 3), (3, 2), (3, 3)].map { GridPosition(column: $0.0, row: $0.1) }
        let expected = Set(cells)
        #expect(controller.dragPreview?.positions == expected)
        #expect(controller.dragPreview?.isAllowed == true)
        #expect(controller.dragPreview?.isCopy == false)
    }

    @Test func previewIsMarkedRefusedWhenTheDropWouldFail() {
        let (controller, _) = makeController()
        controller.press(at: Self.a)
        controller.press(at: Self.b, mode: .range)
        // B tomberait dans une colonne lumière : le groupe est refusé, mais les cases visées sont montrées.
        controller.updateDragPreview(source: Self.a, target: GridPosition(column: 5, row: 5), copying: false)
        #expect(controller.dragPreview?.isAllowed == false)
        #expect(controller.dragPreview?.positions == [GridPosition(column: 5, row: 5), GridPosition(column: 6, row: 5)])
    }

    @Test func previewOutsideTheGridKeepsOnlyTheCellsInsideIt() {
        let (controller, _) = makeController()
        controller.press(at: Self.a)
        controller.press(at: Self.b, mode: .range)
        controller.updateDragPreview(source: Self.a, target: GridPosition(column: 7, row: 7), copying: false)
        #expect(controller.dragPreview?.isAllowed == false)
        #expect(controller.dragPreview?.positions == [GridPosition(column: 7, row: 7)])
    }

    @Test func copyPreviewIsRefusedOntoOccupiedCellsButMovePreviewIsNotWhenTheyAreInTheGroup() {
        let (controller, _) = makeController()
        controller.press(at: Self.a)
        controller.press(at: Self.d, mode: .range)
        let down = GridPosition(column: 0, row: 1)
        controller.updateDragPreview(source: Self.a, target: down, copying: false)
        #expect(controller.dragPreview?.isAllowed == true)  // déplacer d'une ligne : chevauche ses propres cases
        controller.updateDragPreview(source: Self.a, target: down, copying: true)
        #expect(controller.dragPreview?.isAllowed == false)  // copier exige des cases libres
        #expect(controller.dragPreview?.isCopy == true)
    }

    @Test func noGroupPreviewForASinglePadOrAPadOutsideTheSelection() {
        let (controller, _) = makeController()
        controller.press(at: Self.a)
        controller.updateDragPreview(source: Self.a, target: Self.d, copying: false)
        #expect(controller.dragPreview == nil)

        controller.press(at: Self.a)
        controller.press(at: Self.b, mode: .range)
        controller.updateDragPreview(source: Self.d, target: Self.c, copying: false)  // D n'est pas sélectionné
        #expect(controller.dragPreview == nil)
    }

    @Test func clearingTheDragRemovesThePreview() {
        let (controller, _) = makeController()
        controller.press(at: Self.a)
        controller.press(at: Self.d, mode: .range)
        controller.updateDragPreview(source: Self.a, target: GridPosition(column: 2, row: 2), copying: false)
        controller.endDrag()
        #expect(controller.dragPreview == nil)
        #expect(controller.draggedPosition == nil)
    }

    @Test func previewIsNeverShownWhenLocked() {
        let (controller, _) = makeController()
        controller.press(at: Self.a)
        controller.press(at: Self.d, mode: .range)
        controller.isLocked = true
        controller.updateDragPreview(source: Self.a, target: GridPosition(column: 2, row: 2), copying: false)
        #expect(controller.dragPreview == nil)
    }
}
