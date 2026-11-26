import Foundation

/// Erreurs détectées à l'ouverture d'un spectacle.
public enum ShowValidationError: Error, Equatable, Sendable {
    case unsupportedFormatVersion(Int)
    case noGrid
    case tooManyGrids(Int)
    case wrongColumnCount(grid: Int, count: Int)
    case wrongSlotCount(grid: Int, column: Int, count: Int)
    case padKindMismatch(grid: Int, position: GridPosition)
    case unsafeFileName(String)
    case valueOutOfRange(String)
    /// Deux grilles utilisent le même canal LightKey.
    case duplicateLightChannel(Int)
}

extension Show {
    /// Limite raisonnable pour éviter un fichier piégé ou corrompu.
    public static let maximumGridCount = 64

    /// Vérifie qu'un spectacle lu depuis un fichier est cohérent et sûr.
    /// À appeler systématiquement après le décodage, avant toute utilisation.
    public func validate() throws(ShowValidationError) {
        guard formatVersion <= Show.currentFormatVersion, formatVersion >= 1 else {
            throw .unsupportedFormatVersion(formatVersion)
        }
        guard !grids.isEmpty else { throw .noGrid }
        guard grids.count <= Show.maximumGridCount else { throw .tooManyGrids(grids.count) }

        var lightChannels: Set<Int> = []
        if let sharedLight {
            guard Show.lightChannels.contains(sharedLight.channel) else { throw .valueOutOfRange("canal LightKey") }
            lightChannels.insert(sharedLight.channel)
            let indices = sharedLight.columnIndices
            guard !indices.isEmpty, Set(indices).count == indices.count, indices.allSatisfy({ (0..<PadGrid.size).contains($0) })
            else { throw .valueOutOfRange("colonnes lumière communes") }
            // Chaque grille porte une copie de chaque colonne commune, de type Lumière.
            guard grids.allSatisfy({ grid in
                indices.allSatisfy { grid.columns.indices.contains($0) && grid.columns[$0].kind == .light }
            }) else { throw .valueOutOfRange("colonnes lumière communes") }
        }
        for grid in grids {
            guard let channel = grid.lightChannel else { continue }
            guard Show.lightChannels.contains(channel) else { throw .valueOutOfRange("canal LightKey") }
            guard lightChannels.insert(channel).inserted else { throw .duplicateLightChannel(channel) }
        }

        for (g, grid) in grids.enumerated() {
            guard grid.columns.count == PadGrid.size else {
                throw .wrongColumnCount(grid: g, count: grid.columns.count)
            }
            // Colonnes mises de côté (lumière commune) : lues d'un fichier comme le reste, donc vérifiées de même.
            for parked in grid.parkedColumns {
                guard (0..<PadGrid.size).contains(parked.index) else { throw .valueOutOfRange("colonne mise de côté") }
                guard grid.kind.allows(parked.column.kind) else { throw .valueOutOfRange("type de colonne mise de côté") }
                guard parked.column.slots.count == PadGrid.size else {
                    throw .wrongSlotCount(grid: g, column: parked.index, count: parked.column.slots.count)
                }
                for pad in parked.column.slots.compactMap({ $0 }) { try pad.validate() }
            }
            for (c, column) in grid.columns.enumerated() {
                guard grid.kind.allows(column.kind) else { throw .valueOutOfRange("type de colonne pour cette grille") }
                guard column.slots.count == PadGrid.size else {
                    throw .wrongSlotCount(grid: g, column: c, count: column.slots.count)
                }
                guard (0...1).contains(column.level) else { throw .valueOutOfRange("niveau de colonne") }
                guard (-1...1).contains(column.filter) else { throw .valueOutOfRange("filtre de colonne") }
                for (r, pad) in column.slots.enumerated() {
                    guard let pad else { continue }
                    guard column.kind.accepts(pad.kind) else {
                        throw .padKindMismatch(grid: g, position: GridPosition(column: c, row: r))
                    }
                    try pad.validate()
                }
            }
        }
    }
}

extension Pad {
    func validate() throws(ShowValidationError) {
        if let track = music {
            guard audio == nil, light == nil, !awaitsSound else { throw .valueOutOfRange("pad Music avec son ou cue") }
            guard MusicTrackRef.isValidPersistentID(track.persistentID) else { throw .valueOutOfRange("identifiant de morceau") }
            guard track.duration.isFinite, (0...86_400).contains(track.duration) else { throw .valueOutOfRange("durée du morceau") }
            for text in [track.title, track.artist, track.album, track.playlistName ?? ""] where text.count > 500 {
                throw .valueOutOfRange("texte du morceau")
            }
            return
        }
        guard audio != nil || light != nil else { throw .valueOutOfRange("pad sans son ni lumière") }
        if awaitsSound, audio != nil || light == nil { throw .valueOutOfRange("pad en attente de son") }
        if let clip = audio {
            guard AudioClip.isSafeFileName(clip.fileName) else { throw .unsafeFileName(clip.fileName) }
            guard clip.trimStart >= 0 else { throw .valueOutOfRange("début d'élagage") }
            if let end = clip.trimEnd, end <= clip.trimStart { throw .valueOutOfRange("fin d'élagage") }
            for fade in [clip.fadeIn, clip.fadeOut].compactMap({ $0 }) where fade < 0 || fade > 600 {
                throw .valueOutOfRange("durée de fondu")
            }
            guard (-60...24).contains(clip.gainDB) else { throw .valueOutOfRange("gain") }
        }
        if let cue = light {
            let out = cue.output
            guard out.channel < 16, out.number < 128, out.value < 128 else {
                throw .valueOutOfRange("message MIDI")
            }
        }
    }
}

extension AudioClip {
    /// Un nom de fichier simple, sans chemin ni caractère spécial : le son doit rester
    /// dans le dossier `Audio/` du document.
    public static func isSafeFileName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 255 else { return false }
        guard name != ".", name != "..", !name.hasPrefix(".") else { return false }
        let forbidden = CharacterSet(charactersIn: "/\\:\0").union(.controlCharacters)
        return name.unicodeScalars.allSatisfy { !forbidden.contains($0) }
    }
}
