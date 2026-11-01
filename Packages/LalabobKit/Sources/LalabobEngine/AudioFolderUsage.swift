import Foundation

/// Poids des sons d'un spectacle : ce que des pads utilisent, et ce qui traîne dans le dossier de travail
/// (sons retirés de la grille : ils quitteront le paquet au prochain enregistrement).
public struct AudioFolderUsage: Equatable, Sendable {
    public var usedCount: Int
    public var usedBytes: Int64
    public var unusedCount: Int
    public var unusedBytes: Int64

    public static let empty = AudioFolderUsage(usedCount: 0, usedBytes: 0, unusedCount: 0, unusedBytes: 0)

    public init(usedCount: Int, usedBytes: Int64, unusedCount: Int, unusedBytes: Int64) {
        self.usedCount = usedCount
        self.usedBytes = usedBytes
        self.unusedCount = unusedCount
        self.unusedBytes = unusedBytes
    }

    /// Mesure les fichiers de `directory` (à plat), répartis selon que leur nom est dans `used` ou non.
    public static func measure(directory: URL, used: Set<String>) -> AudioFolderUsage {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        var usage = AudioFolderUsage.empty
        for file in files {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let size = Int64(values.fileSize ?? 0)
            if used.contains(file.lastPathComponent) {
                usage.usedCount += 1
                usage.usedBytes += size
            } else {
                usage.unusedCount += 1
                usage.unusedBytes += size
            }
        }
        return usage
    }

    /// Texte d'infobulle : « Sons : 12 fichiers, 84 Mo », plus ce qui sera retiré à l'enregistrement s'il y en a.
    public var summary: String {
        var text = "Sons : \(Self.files(usedCount)), \(Self.size(usedBytes))"
        if unusedCount > 0 {
            text += " · \(Self.files(unusedCount)) inutilisé\(unusedCount > 1 ? "s" : "") (\(Self.size(unusedBytes))), retiré\(unusedCount > 1 ? "s" : "") à l'enregistrement"
        }
        return text
    }

    private static func files(_ count: Int) -> String { count > 1 ? "\(count) fichiers" : "\(count) fichier" }

    private static func size(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}
