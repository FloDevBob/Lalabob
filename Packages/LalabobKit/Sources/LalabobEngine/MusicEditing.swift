import Foundation
import LalabobModel

/// Déposer des morceaux d'Apple Music sur une grille (spec « Grilles Apple Music », étape 2).
extension ShowController {
    /// Où tombent `count` morceaux déposés sur `target` : de la case visée vers le bas, puis la colonne Music suivante (depuis
    /// le haut) ; les cases occupées sont sautées. Vide si la case visée n'est pas dans une colonne Music. Peut en contenir
    /// moins que `count` (plus de place).
    public func musicDropPositions(count: Int, at target: GridPosition) -> [GridPosition] {
        guard count > 0, target.isValid, currentGrid.columns[target.column].kind == .music else { return [] }
        var positions: [GridPosition] = []
        for column in target.column..<PadGrid.size where currentGrid.columns[column].kind == .music {
            let firstRow = column == target.column ? target.row : 0
            for row in firstRow..<PadGrid.size {
                let position = GridPosition(column: column, row: row)
                guard currentGrid[position] == nil else { continue }
                positions.append(position)
                if positions.count == count { return positions }
            }
        }
        return positions
    }

    /// Dépose des morceaux (une seule annulation, refusé verrouillé) ; renvoie combien ont trouvé une place. Ceux qui n'en
    /// trouvent pas sont signalés. Le dépôt sélectionne les pads créés.
    @discardableResult
    public func dropMusicTracks(_ tracks: [MusicTrackRef], at target: GridPosition) -> Int {
        let tracks = tracks.filter { MusicTrackRef.isValidPersistentID($0.persistentID) }
        let positions = musicDropPositions(count: tracks.count, at: target)
        guard !positions.isEmpty else { return 0 }
        let placed = commit(tracks.count == 1 ? "Déposer un morceau" : "Déposer des morceaux") { show, grid in
            for (track, position) in zip(tracks, positions) {
                show.grids[grid][position] = .track(track, tint: Self.tint(forTrack: track.persistentID))
            }
            return true
        }
        guard placed else { return 0 }
        selection = positions.first  // la case principale…
        selectedPositions = Set(positions)  // …puis tous les pads déposés
        if positions.count < tracks.count {
            let missing = tracks.count - positions.count
            conversionNotice = "\(missing) \(missing == 1 ? "morceau n'a" : "morceaux n'ont") pas trouvé de case libre dans les colonnes Music."
        }
        return positions.count
    }

    /// Une teinte stable pour un morceau (la même à chaque dépôt), comme pour un son importé.
    static func tint(forTrack persistentID: String) -> Tint {
        let tints = Tint.allCases.filter { $0 != .blanc && $0 != .graphite }
        let index = persistentID.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % tints.count
        return tints[index]
    }

    // MARK: - Aperçu pendant le glisser

    /// Début d'un glisser de morceaux depuis le panneau (le nombre sert à l'aperçu numéroté).
    public func beginMusicDrag(count: Int) {
        musicDragCount = max(0, count)
        musicDropPreview = []
    }

    /// Le glisser survole une case : les cases d'arrivée, numérotées dans l'ordre.
    public func updateMusicDropPreview(at target: GridPosition) {
        guard musicDragCount > 0, !isLocked else { return }
        let positions = musicDropPositions(count: musicDragCount, at: target)
        if positions != musicDropPreview { musicDropPreview = positions }
    }

    public func clearMusicDropPreview() {
        if !musicDropPreview.isEmpty { musicDropPreview = [] }
    }

    /// Fin du glisser (dépôt ou abandon).
    public func endMusicDrag() {
        musicDragCount = 0
        clearMusicDropPreview()
    }
}

/// Ce que transporte un glisser de morceaux (texte : préfixe + JSON). Venu d'ailleurs, il est relu et validé comme un fichier.
public enum MusicDragToken {
    static let prefix = "lalabob-music:"

    public static func make(_ tracks: [MusicTrackRef]) -> String {
        let data = (try? JSONEncoder().encode(tracks)) ?? Data("[]".utf8)
        return prefix + String(decoding: data, as: UTF8.self)
    }

    /// Les morceaux d'un jeton, au plus 64, identifiants vérifiés ; `nil` si ce n'en est pas un.
    public static func parse(_ text: String) -> [MusicTrackRef]? {
        guard text.hasPrefix(prefix), text.utf8.count < 512_000 else { return nil }
        guard let tracks = try? JSONDecoder().decode([MusicTrackRef].self, from: Data(text.dropFirst(prefix.count).utf8)) else { return nil }
        return Array(tracks.filter { MusicTrackRef.isValidPersistentID($0.persistentID) }.prefix(PadGrid.size * PadGrid.size))
    }
}
