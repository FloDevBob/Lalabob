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

        for (g, grid) in grids.enumerated() {
            guard grid.columns.count == Grid.size else {
                throw .wrongColumnCount(grid: g, count: grid.columns.count)
            }
            for (c, column) in grid.columns.enumerated() {
                guard column.slots.count == Grid.size else {
                    throw .wrongSlotCount(grid: g, column: c, count: column.slots.count)
                }
                guard (0...1).contains(column.level) else { throw .valueOutOfRange("niveau de colonne") }
                for (r, pad) in column.slots.enumerated() {
                    guard let pad else { continue }
                    guard pad.kind == column.kind else {
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
        switch content {
        case .audio(let clip):
            guard AudioClip.isSafeFileName(clip.fileName) else { throw .unsafeFileName(clip.fileName) }
            guard clip.trimStart >= 0 else { throw .valueOutOfRange("début d'élagage") }
            if let end = clip.trimEnd, end <= clip.trimStart { throw .valueOutOfRange("fin d'élagage") }
            for fade in [clip.fadeIn, clip.fadeOut].compactMap({ $0 }) where fade < 0 || fade > 600 {
                throw .valueOutOfRange("durée de fondu")
            }
            guard (-60...24).contains(clip.gainDB) else { throw .valueOutOfRange("gain") }
        case .light(let cue):
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
