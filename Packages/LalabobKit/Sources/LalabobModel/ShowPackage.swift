import Foundation

public enum ShowPackageError: Error, Equatable, Sendable {
    /// Le document n'est pas un dossier `.lalabob`.
    case notAPackage
    case missingShowFile
    /// `show.json` illisible (pas du JSON, ou pas un spectacle).
    case corrupt
    /// `show.json` démesuré : refusé avant décodage.
    case tooLarge
    /// Spectacle lu mais refusé par `Show.validate()`.
    case invalid(ShowValidationError)
}

/// Format du document `.lalabob` : un paquet (dossier) contenant `show.json` et un dossier `Audio/`
/// où sont copiés les sons. Lecture et écriture pures, sur des `FileWrapper`.
public enum ShowPackage {
    public static let showFileName = "show.json"
    public static let audioFolderName = "Audio"
    /// Taille maximale acceptée pour `show.json` (un vrai spectacle fait quelques dizaines de Ko).
    public static let maximumShowFileSize = 10 * 1024 * 1024

    /// Ce qu'on lit d'un paquet.
    public struct Contents: Equatable, Sendable {
        public var show: Show
        /// Sons présents dans `Audio/` (noms sûrs uniquement), triés.
        public var audioFileNames: [String]
        /// Sons utilisés par un pad mais absents de `Audio/`, triés. Le spectacle s'ouvre quand même.
        public var missingAudio: [String]
    }

    // MARK: - show.json

    public static func encode(_ show: Show) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(show)
    }

    /// Décode et valide. Toute donnée lue d'un fichier passe par ici avant usage.
    public static func decode(_ data: Data) throws(ShowPackageError) -> Show {
        guard data.count <= maximumShowFileSize else { throw .tooLarge }
        let show: Show
        do { show = try JSONDecoder().decode(Show.self, from: data) } catch { throw .corrupt }
        do { try show.validate() } catch { throw .invalid(error) }
        return show
    }

    // MARK: - Paquet

    public static func read(_ package: FileWrapper) throws(ShowPackageError) -> Contents {
        guard package.isDirectory, let children = package.fileWrappers else { throw .notAPackage }
        guard let file = children[showFileName], file.isRegularFile, let data = file.regularFileContents else {
            throw .missingShowFile
        }
        let show = try decode(data)
        let audio = audioFileNames(in: children[audioFolderName])
        let used = Set(
            show.grids.flatMap(\.columns).flatMap(\.slots).compactMap { pad -> String? in
                if case .audio(let clip) = pad?.content { clip.fileName } else { nil }
            })
        return Contents(show: show, audioFileNames: audio, missingAudio: used.subtracting(audio).sorted())
    }

    /// Le dossier `Audio/` d'un paquet lu, à conserver pour le réécrire sans recopier les sons.
    public static func audioFolder(of package: FileWrapper) -> FileWrapper? {
        guard let folder = package.fileWrappers?[audioFolderName], folder.isDirectory else { return nil }
        return folder
    }

    /// Paquet à écrire : `show.json`, plus le dossier `Audio/` existant complété par `adding` (nom → fichier).
    public static func wrapper(
        for show: Show, audio: FileWrapper?, adding added: [String: FileWrapper] = [:]
    ) throws -> FileWrapper {
        let showFile = FileWrapper(regularFileWithContents: try encode(show))
        showFile.preferredFilename = showFileName

        var audioChildren = audio?.fileWrappers ?? [:]
        for (name, file) in added where AudioClip.isSafeFileName(name) && audioChildren[name] == nil {
            file.preferredFilename = name
            audioChildren[name] = file
        }
        let audioFolder = FileWrapper(directoryWithFileWrappers: audioChildren)
        audioFolder.preferredFilename = audioFolderName

        return FileWrapper(directoryWithFileWrappers: [showFileName: showFile, audioFolderName: audioFolder])
    }

    private static func audioFileNames(in folder: FileWrapper?) -> [String] {
        guard let folder, folder.isDirectory, let children = folder.fileWrappers else { return [] }
        return children.filter { AudioClip.isSafeFileName($0.key) && $0.value.isRegularFile }.keys.sorted()
    }
}

extension AudioClip {
    /// Transforme un nom de fichier quelconque en nom sûr pour `Audio/` (voir `isSafeFileName`).
    public static func safeFileName(from name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:\0").union(.controlCharacters)
        var cleaned = String(String.UnicodeScalarView(name.unicodeScalars.map { forbidden.contains($0) ? "-" : $0 }))
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        if cleaned.isEmpty { cleaned = "son" }
        if cleaned.count > 255 {
            let ext = (cleaned as NSString).pathExtension
            let suffix = ext.isEmpty ? "" : "." + ext
            cleaned = String(((cleaned as NSString).deletingPathExtension).prefix(255 - suffix.count)) + suffix
        }
        return cleaned
    }

    /// `name`, ou « nom 2.ext », « nom 3.ext »… s'il est déjà pris.
    public static func uniqueFileName(_ name: String, avoiding taken: Set<String>) -> String {
        guard taken.contains(name) else { return name }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var index = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            if !taken.contains(candidate) { return candidate }
            index += 1
        }
    }
}
