import Foundation

/// Le type d'une grille (spec « Grilles Apple Music »).
public enum GridKind: String, Codable, Sendable {
    /// Sons de Lalabob et lumière : colonnes son, lumière ou son et lumière.
    case standard
    /// Morceaux d'Apple Music joués par l'app Music, un à la fois : colonnes Music et colonnes lumière.
    case appleMusic

    /// Le type des colonnes de contenu de cette grille (hors lumière) : son, ou Music.
    public var contentColumn: ColumnKind { self == .appleMusic ? .music : .audio }

    /// Une colonne de ce type peut-elle exister dans une grille de ce type ?
    public func allows(_ column: ColumnKind) -> Bool {
        switch self {
        case .standard: column != .music
        case .appleMusic: column == .music || column == .light
        }
    }
}

/// Un morceau de la bibliothèque d'Apple Music, désigné par son identifiant persistant (ne change pas dans le temps).
/// Le titre, l'artiste et la durée sont une copie au moment du dépôt : pour l'affichage, et pour retrouver le morceau si
/// son identifiant venait à changer.
public struct MusicTrackRef: Codable, Sendable, Equatable, Hashable {
    /// `persistent ID` de Music : 16 chiffres hexadécimaux.
    public var persistentID: String
    public var title: String
    public var artist: String
    public var album: String
    /// Durée en secondes.
    public var duration: TimeInterval
    /// La playlist d'où vient le morceau (information, rien n'en dépend).
    public var playlistName: String?

    public init(persistentID: String, title: String, artist: String = "", album: String = "", duration: TimeInterval = 0, playlistName: String? = nil) {
        self.persistentID = persistentID
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.playlistName = playlistName
    }

    /// Un identifiant sûr à placer dans une commande AppleScript : hexadécimal seulement.
    public static func isValidPersistentID(_ id: String) -> Bool {
        (1...32).contains(id.count) && id.allSatisfy(\.isHexDigit)
    }
}

extension PadGrid {
    /// Colonnes Music par défaut d'une grille Apple Music (les 6 premières) ; les 2 dernières sont lumière.
    public static func emptyAppleMusic(name: String) -> PadGrid {
        PadGrid(
            name: name, kind: .appleMusic,
            columns: (0..<size).map { index in
                Column.empty(name: "Colonne \(index + 1)", kind: defaultLightColumns.contains(index) ? .light : .music)
            })
    }

    /// La grille convertie à un autre type : les colonnes interdites deviennent des colonnes du type par défaut (Music
    /// pour une grille Apple Music, son pour une grille standard), en gardant ce qui y rentre (`Column.converted`).
    /// Les colonnes lumière ne bougent pas.
    public func converted(to target: GridKind) -> PadGrid {
        guard target != kind else { return self }
        var grid = self
        grid.kind = target
        for index in grid.columns.indices where !target.allows(grid.columns[index].kind) {
            grid.columns[index] = grid.columns[index].converted(to: target.contentColumn)
        }
        // Colonnes mises de côté (lumière commune) : elles reviendront dans cette grille, elles doivent y être permises.
        for index in grid.parkedColumns.indices where !target.allows(grid.parkedColumns[index].column.kind) {
            grid.parkedColumns[index].column = grid.parkedColumns[index].column.converted(to: target.contentColumn)
        }
        return grid
    }

    /// Les pads que la conversion vers `target` supprime (colonnes affichées et colonnes mises de côté).
    public func padsRemoved(convertingTo target: GridKind) -> [Pad] {
        guard target != kind else { return [] }
        let columns = self.columns + parkedColumns.map(\.column)
        return columns.filter { !target.allows($0.kind) }.flatMap { column in
            column.slots.compactMap { $0 }.filter { column.convertedPad($0, to: target.contentColumn) == nil }
        }
    }
}

extension Show {
    /// Version de format nécessaire pour écrire ce spectacle : la plus petite qui le contient, pour qu'un spectacle sans
    /// fonction récente reste lisible par une app plus ancienne. 4 s'il sert au DMX (mode, appareil réglé ou état lumineux),
    /// 3 s'il contient une grille Apple Music ou un pad Music, sinon 2.
    public var requiredFormatVersion: Int {
        let usesDMX =
            lighting != LightingSettings() || allPads.contains { $0.light?.look != nil }
            || grids.contains { ($0.columns + $0.parkedColumns.map(\.column)).contains { $0.faderRole != nil } }
        if usesDMX { return 4 }
        let usesMusic = grids.contains { grid in
            grid.kind == .appleMusic || grid.columns.contains { $0.kind == .music }
        }
        return usesMusic ? 3 : 2
    }

    /// Tous les pads du spectacle, colonnes mises de côté comprises.
    var allPads: [Pad] {
        grids.flatMap { ($0.columns + $0.parkedColumns.map(\.column)).flatMap(\.slots).compactMap { $0 } }
    }
}
