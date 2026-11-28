import Foundation

/// Volume des colonnes **commun à toutes les grilles** (décision du 28/11/2026).
///
/// Le fader d'une colonne qui joue du son (son, son et lumière, Music) règle cette colonne dans toutes les grilles : changer
/// de grille ne change pas le volume, et les faders physiques restent d'accord avec l'écran. Le dosage propre à chaque son
/// est le volume du pad. Une colonne **lumière** garde son intensité à elle (elle pilote les projecteurs, pas le son) ; si
/// la colonne 3 est un son dans une grille et une lumière dans une autre, les deux réglages restent séparés.
///
/// Le format ne change pas : chaque grille garde son `level`, recopié à l'identique (comme `alignDMXFaders`).
extension Show {
    /// La colonne joue du son : son volume est commun à toutes les grilles.
    public static func hasSharedLevel(_ kind: ColumnKind) -> Bool { kind != .light }

    /// Le volume commun de chaque colonne (par numéro de colonne) : celui de la grille `preferring` si cette colonne y joue du
    /// son, sinon celui de la première grille où elle en joue. Une colonne qui n'est du son nulle part n'a pas d'entrée.
    public func sharedColumnLevels(preferring gridIndex: Int) -> [Int: Double] {
        var levels: [Int: Double] = [:]
        let order = grids.indices.contains(gridIndex) ? [gridIndex] + grids.indices.filter { $0 != gridIndex } : Array(grids.indices)
        for column in 0..<PadGrid.size {
            for index in order {
                guard grids[index].columns.indices.contains(column) else { continue }
                let data = grids[index].columns[column]
                if Self.hasSharedLevel(data.kind) {
                    levels[column] = data.level
                    break
                }
            }
        }
        return levels
    }

    /// Donne à chaque colonne son de chaque grille le volume commun : `levels` d'abord, puis, pour une colonne qui n'y figure
    /// pas (elle vient de devenir du son), celui de la grille `preferring`.
    public mutating func applySharedColumnLevels(_ levels: [Int: Double], preferring gridIndex: Int) {
        let reference = sharedColumnLevels(preferring: gridIndex)
        for column in 0..<PadGrid.size {
            guard let level = levels[column] ?? reference[column] else { continue }
            setSharedColumnLevel(level, column: column)
        }
    }

    /// Aligne toutes les grilles sur la grille `preferring` (ouverture d'un spectacle, dont les anciens avaient un volume par grille).
    public mutating func shareColumnLevels(preferring gridIndex: Int) {
        applySharedColumnLevels(sharedColumnLevels(preferring: gridIndex), preferring: gridIndex)
    }

    /// Règle le volume d'une colonne dans toutes les grilles où elle joue du son.
    public mutating func setSharedColumnLevel(_ level: Double, column: Int) {
        for index in grids.indices where grids[index].columns.indices.contains(column) {
            guard Self.hasSharedLevel(grids[index].columns[column].kind), grids[index].columns[column].level != level else { continue }
            grids[index].columns[column].level = level
        }
    }
}
