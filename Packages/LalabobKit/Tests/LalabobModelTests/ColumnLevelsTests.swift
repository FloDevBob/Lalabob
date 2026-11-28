import Foundation
import Testing

@testable import LalabobModel

/// Volume des colonnes commun à toutes les grilles (décision du 28/11/2026) ; les colonnes lumière gardent le leur.
@Suite("Volume de colonne commun aux grilles")
struct ColumnLevelsTests {
    private static func show(_ levels: [[Double]]) -> Show {
        let grids = levels.enumerated().map { index, values in
            var grid = PadGrid.empty(name: "G\(index + 1)")
            for (column, level) in values.enumerated() { grid.columns[column].level = level }
            return grid
        }
        return Show(name: "S", grids: grids)
    }

    @Test("Le volume commun vient de la grille préférée")
    func fromPreferredGrid() {
        let show = Self.show([[0.2, 0.3], [0.7, 0.9]])
        #expect(show.sharedColumnLevels(preferring: 0)[0] == 0.2)
        #expect(show.sharedColumnLevels(preferring: 1)[1] == 0.9)
    }

    @Test("Aligner les grilles : chaque colonne son prend le volume de la grille préférée")
    func shareAligns() {
        var show = Self.show([[0.2, 0.3], [0.7, 0.9], [0.5, 0.5]])
        show.shareColumnLevels(preferring: 0)
        #expect(show.grids.map { $0.columns[0].level } == [0.2, 0.2, 0.2])
        #expect(show.grids.map { $0.columns[1].level } == [0.3, 0.3, 0.3])
    }

    @Test("Les colonnes lumière gardent leur intensité, grille par grille")
    func lightColumnsAreSeparate() {
        var show = Self.show([[], []])
        show.grids[0].columns[6].level = 0.1
        show.grids[1].columns[6].level = 0.9
        show.shareColumnLevels(preferring: 0)
        show.setSharedColumnLevel(0.4, column: 6)  // une colonne lumière partout : rien n'est commun
        #expect(show.grids[0].columns[6].level == 0.1)
        #expect(show.grids[1].columns[6].level == 0.9)
        #expect(show.sharedColumnLevels(preferring: 0)[6] == nil)
    }

    @Test("Même colonne : son dans une grille, lumière dans l'autre ; les deux réglages restent séparés")
    func mixedKindsAcrossGrids() {
        var show = Self.show([[0.6, 0.6, 0.6], [0.2, 0.2, 0.2]])
        show.grids[0].columns[2].kind = .light
        show.grids[0].columns[2].level = 1
        // La grille préférée a une lumière en colonne 3 : le volume commun vient de la première grille où c'est du son.
        #expect(show.sharedColumnLevels(preferring: 0)[2] == 0.2)
        show.setSharedColumnLevel(0.5, column: 2)
        #expect(show.grids[0].columns[2].level == 1)  // la lumière ne bouge pas
        #expect(show.grids[1].columns[2].level == 0.5)
    }

    @Test("Une colonne qui devient du son prend le volume commun gardé ; sinon celui de la grille préférée")
    func applyKeepsKnownLevels() {
        var show = Self.show([[0.3], [0.3]])
        let kept = show.sharedColumnLevels(preferring: 0)
        show.grids.append(PadGrid.empty(name: "Nouvelle"))  // une nouvelle grille arrive avec 0,8
        show.applySharedColumnLevels(kept, preferring: 0)
        #expect(show.grids[2].columns[0].level == 0.3)
        // La colonne 7 (lumière par défaut) devient du son dans la grille 1 : personne n'avait de volume commun pour elle.
        show.grids[0].columns[6].kind = .audio
        show.grids[0].columns[6].level = 0.45
        show.applySharedColumnLevels(kept, preferring: 0)
        #expect(show.grids[0].columns[6].level == 0.45)
        #expect(show.grids[1].columns[6].level != 0.45)  // toujours une lumière dans la grille 2
    }

    @Test("Les colonnes Music partagent aussi le volume (pont audio)")
    func musicColumns() {
        var show = Self.show([[0.5], [0.9]])
        show.grids[1].kind = .appleMusic
        show.grids[1].columns[0].kind = .music
        show.shareColumnLevels(preferring: 0)
        #expect(show.grids[1].columns[0].level == 0.5)
    }
}
