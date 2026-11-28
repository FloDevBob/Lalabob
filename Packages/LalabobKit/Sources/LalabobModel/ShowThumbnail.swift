import Foundation

/// Aperçu d'un spectacle pour la fenêtre d'accueil : la **première grille** en 8 × 8 et un résumé (« 42 sons · 3 grilles »).
///
/// Une teinte reste une teinte (`Tint`) : la vue la traduit en couleur. Pure, donc testable.
public struct ShowThumbnail: Equatable, Sendable {
    public enum Cell: Equatable, Sendable {
        /// Case libre.
        case empty
        /// Pad son, son et lumière, ou morceau : sa teinte.
        case tint(Tint)
        /// Cue lumière seule : toujours en ambre, comme les colonnes lumière de l'app.
        case light
    }

    /// 64 cases, colonne par colonne : la colonne 1 de haut en bas, puis la colonne 2…
    public let cells: [Cell]
    public let gridCount: Int
    /// Pads qui ont un son (toutes grilles).
    public let soundCount: Int
    /// Pads Apple Music (toutes grilles).
    public let trackCount: Int

    public init(show: Show) {
        let size = PadGrid.size
        var cells = [Cell](repeating: .empty, count: size * size)
        if let grid = show.grids.first {
            for (column, columnData) in grid.columns.prefix(size).enumerated() {
                for (row, pad) in columnData.slots.prefix(size).enumerated() {
                    guard let pad else { continue }
                    cells[column * size + row] = pad.audio == nil && pad.music == nil && pad.light != nil ? .light : .tint(pad.tint)
                }
            }
        }
        let pads = show.grids.flatMap { $0.columns.flatMap(\.slots) }.compactMap { $0 }
        self.cells = cells
        self.gridCount = show.grids.count
        self.soundCount = pads.filter { $0.audio != nil }.count
        self.trackCount = pads.filter { $0.music != nil }.count
    }

    /// « 42 sons · 3 grilles », « 1 morceau · 1 grille », « Aucun son · 1 grille ».
    public var summary: String {
        var parts: [String] = []
        if soundCount > 0 { parts.append(Self.count(soundCount, "son", "sons")) }
        if trackCount > 0 { parts.append(Self.count(trackCount, "morceau", "morceaux")) }
        if parts.isEmpty { parts.append("Aucun son") }
        parts.append(Self.count(gridCount, "grille", "grilles"))
        return parts.joined(separator: " · ")
    }

    private static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(value) \(value > 1 ? plural : singular)"
    }
}
