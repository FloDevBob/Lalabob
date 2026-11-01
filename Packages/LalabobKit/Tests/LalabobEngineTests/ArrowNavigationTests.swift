import Foundation
import LalabobModel
import Testing

@testable import LalabobEngine

/// Flèches du clavier : déplacent la sélection d'une case ; avec Maj, elles étendent un rectangle depuis la case principale.
@MainActor
@Suite("Navigation aux flèches")
struct ArrowNavigationTests {
    private func makeController(locked: Bool = false) -> ShowController {
        let controller = ShowController(
            show: Show.new(), defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
        controller.isLocked = locked
        return controller
    }

    private func cell(_ column: Int, _ row: Int) -> GridPosition { GridPosition(column: column, row: row) }

    @Test("Sans sélection, la première flèche choisit la case en haut à gauche")
    func firstArrowSelectsTheCorner() {
        for (dx, dy) in [(1, 0), (0, 1), (-1, 0), (0, -1)] {
            let controller = makeController()
            controller.moveSelection(dx: dx, dy: dy)
            #expect(controller.selection == cell(0, 0))
            #expect(controller.selectedPositions == [cell(0, 0)])
        }
    }

    @Test("Une flèche déplace d'une case et remplace la sélection")
    func arrowsMoveOneCell() {
        let controller = makeController()
        controller.selection = cell(3, 3)
        controller.moveSelection(dx: 1, dy: 0)
        #expect(controller.selectedPositions == [cell(4, 3)])
        controller.moveSelection(dx: 0, dy: 1)
        #expect(controller.selectedPositions == [cell(4, 4)])
        controller.moveSelection(dx: -1, dy: 0)
        controller.moveSelection(dx: 0, dy: -1)
        #expect(controller.selection == cell(3, 3))
    }

    @Test("La sélection s'arrête aux bords de la grille")
    func clampedAtTheEdges() {
        let controller = makeController()
        controller.selection = cell(0, 0)
        controller.moveSelection(dx: -1, dy: 0)
        controller.moveSelection(dx: 0, dy: -1)
        #expect(controller.selection == cell(0, 0))
        controller.selection = cell(7, 7)
        controller.moveSelection(dx: 1, dy: 0)
        controller.moveSelection(dx: 0, dy: 1)
        #expect(controller.selection == cell(7, 7))
    }

    @Test("Maj + flèches étend le rectangle depuis la case principale, et le rétrécit en revenant")
    func shiftExtendsAndShrinks() {
        let controller = makeController()
        controller.selection = cell(2, 2)
        controller.moveSelection(dx: 1, dy: 0, extend: true)
        #expect(controller.selectedPositions == [cell(2, 2), cell(3, 2)])
        controller.moveSelection(dx: 0, dy: 1, extend: true)
        #expect(controller.selectedPositions == [cell(2, 2), cell(3, 2), cell(2, 3), cell(3, 3)])
        #expect(controller.selection == cell(2, 2))  // l'ancre ne bouge pas
        controller.moveSelection(dx: -1, dy: 0, extend: true)
        #expect(controller.selectedPositions == [cell(2, 2), cell(2, 3)])
        controller.moveSelection(dx: 0, dy: -1, extend: true)
        #expect(controller.selectedPositions == [cell(2, 2)])
    }

    @Test("Maj + flèche vers le haut ou la gauche étend aussi, et s'arrête au bord")
    func shiftTowardTopLeft() {
        let controller = makeController()
        controller.selection = cell(1, 1)
        controller.moveSelection(dx: -1, dy: 0, extend: true)
        controller.moveSelection(dx: -1, dy: 0, extend: true)  // déjà au bord
        controller.moveSelection(dx: 0, dy: -1, extend: true)
        #expect(controller.selectedPositions == [cell(0, 0), cell(1, 0), cell(0, 1), cell(1, 1)])
    }

    @Test("Une flèche sans Maj après une extension revient à une seule case, à partir de l'extrémité mobile")
    func plainArrowAfterExtension() {
        let controller = makeController()
        controller.selection = cell(2, 2)
        controller.moveSelection(dx: 1, dy: 0, extend: true)
        controller.moveSelection(dx: 1, dy: 0, extend: true)  // curseur en (4, 2)
        controller.moveSelection(dx: 0, dy: 1)
        #expect(controller.selectedPositions == [cell(4, 3)])
    }

    @Test("Un clic repart de la case cliquée")
    func clickResetsTheCursor() {
        let controller = makeController()
        controller.selection = cell(2, 2)
        controller.moveSelection(dx: 3, dy: 0, extend: true)
        controller.press(at: cell(0, 5))
        controller.moveSelection(dx: 1, dy: 0)
        #expect(controller.selection == cell(1, 5))
    }

    @Test("Verrouillé : Maj est ignoré, une seule case à la fois")
    func lockedIgnoresShift() {
        let controller = makeController(locked: true)
        controller.selection = cell(2, 2)
        controller.moveSelection(dx: 1, dy: 0, extend: true)
        #expect(controller.selectedPositions == [cell(3, 2)])
    }

    @Test("Les flèches ne modifient ni le spectacle ni l'annulation")
    func neverEdits() {
        let controller = makeController()
        let before = controller.show
        controller.moveSelection(dx: 1, dy: 1)
        controller.moveSelection(dx: 1, dy: 0, extend: true)
        #expect(controller.show == before)
    }
}
