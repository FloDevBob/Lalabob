import Foundation

/// Spectacle d'entraînement du tutoriel. Il est livré dans l'app et ouvert **en copie neuve** à chaque fois
/// (Aide ▸ Ouvrir le spectacle d'entraînement) : on peut tout y essayer, l'original ne change jamais.
public enum TrainingShow {
    /// Nom de la copie, qui devient le titre de la fenêtre.
    public static let documentName = "Entraînement.lalabob"

    /// Copie `source` dans un nouveau sous-dossier de `parent` et renvoie l'adresse de la copie.
    /// Les copies précédentes ne sont pas effacées (elles peuvent être encore ouvertes) : `parent` est un dossier
    /// temporaire que macOS vide tout seul.
    public static func freshCopy(of source: URL, in parent: URL, fileManager: FileManager = .default) throws -> URL {
        let folder = parent.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appending(path: documentName, directoryHint: .isDirectory)
        try fileManager.copyItem(at: source, to: copy)
        return copy
    }
}
