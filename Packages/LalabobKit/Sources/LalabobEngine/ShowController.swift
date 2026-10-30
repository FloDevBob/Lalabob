import Foundation
import LalabobModel
import Observation

/// Détient le spectacle ouvert : la seule source de vérité de l'app.
///
/// L'écran et les LED du contrôleur en sont deux reflets. Toute modification passe par
/// une méthode de ce type, pour pouvoir l'annuler (⌘Z) et la répercuter sur le matériel.
@MainActor
@Observable
public final class ShowController {
    public private(set) var show: Show
    public var selectedGridIndex: Int
    public var selection: GridPosition?

    public init(show: Show = .new()) {
        self.show = show
        self.selectedGridIndex = 0
    }

    public var currentGrid: Grid { show.grids[selectedGridIndex] }

    public func selectGrid(at index: Int) {
        guard show.grids.indices.contains(index) else { return }
        selectedGridIndex = index
    }

    public func pad(at position: GridPosition) -> Pad? {
        guard position.isValid else { return nil }
        return currentGrid[position]
    }
}
