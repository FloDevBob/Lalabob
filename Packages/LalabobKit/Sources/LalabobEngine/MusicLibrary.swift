import AppKit
import Foundation
import LalabobModel

/// Une playlist (ou un dossier de playlists) de la bibliothèque d'Apple Music.
public struct MusicPlaylist: Identifiable, Equatable, Sendable {
    /// `persistent ID` de Music.
    public var id: String
    public var name: String
    /// Le dossier qui la contient (`nil` = à la racine).
    public var parentID: String?
    public var isFolder: Bool
    public var trackCount: Int

    public init(id: String, name: String, parentID: String? = nil, isFolder: Bool = false, trackCount: Int = 0) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.isFolder = isFolder
        self.trackCount = trackCount
    }
}

/// Un morceau tel que la bibliothèque de Music le décrit.
public struct MusicTrack: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval
    /// Le fichier est sur ce Mac (téléchargé, ou fichier importé) ; `false` = dans le nuage ; `nil` = inconnu.
    /// Déduit de la classe du morceau dans Music (`file track` / `shared track`). ⚠︎ À vérifier sur le Mac de régie.
    public var isDownloaded: Bool?

    public init(id: String, title: String, artist: String = "", album: String = "", duration: TimeInterval = 0, isDownloaded: Bool? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.isDownloaded = isDownloaded
    }

    /// La référence enregistrée dans un pad.
    public func reference(playlist: String?) -> MusicTrackRef {
        MusicTrackRef(persistentID: id, title: title, artist: artist, album: album, duration: duration, playlistName: playlist)
    }
}

/// Où en est un morceau d'un pad dans la bibliothèque de Music.
public enum MusicTrackAvailability: Equatable, Sendable {
    /// Sur ce Mac (téléchargé ou fichier importé) : il jouera sans Internet.
    case downloaded
    /// Dans le nuage : Internet nécessaire.
    case cloud
    /// Plus dans la bibliothèque : « Remplacer le morceau ».
    case missing
}

/// Lire la bibliothèque d'Apple Music (une implémentation réelle par AppleScript, une fausse pour les tests).
public protocol MusicLibraryReading: Sendable {
    func status() async -> MediaVolumeStatus
    func playlists() async throws -> [MusicPlaylist]
    func tracks(inPlaylist id: String) async throws -> [MusicTrack]
    /// Recherche dans toute la bibliothèque (titre, artiste, album), au plus `limit` morceaux.
    func search(_ text: String, limit: Int) async throws -> [MusicTrack]
    /// Demande à Music de télécharger ces morceaux (ceux d'une playlist).
    func download(tracks ids: [String], inPlaylist playlist: String) async throws
    /// Ouvre l'app Music (bouton « Ouvrir Music », déverrouillé seulement).
    func openMusic() async
    /// La disponibilité de ces morceaux (ceux des pads), par identifiant.
    func availability(of ids: [String]) async throws -> [String: MusicTrackAvailability]
    /// La pochette d'un morceau de la bibliothèque (JPEG ou PNG), `nil` s'il n'en a pas.
    func artwork(of id: String) async throws -> Data?
    /// Ouvre la page d'un morceau du catalogue dans l'app Music (pour l'ajouter à la bibliothèque).
    func openInMusic(_ storeURL: URL) async
}

/// La bibliothèque réelle, lue par AppleScript. Ne lance jamais Music : tout est refusé s'il est fermé.
public actor AppleMusicLibrary: MusicLibraryReading {
    public init() {}

    public func status() async -> MediaVolumeStatus { await AppleMusicVolume().status() }

    public func playlists() async throws -> [MusicPlaylist] {
        guard MusicScripting.isRunning else { return [] }
        // Lectures groupées (`… of every user playlist` : une seule demande à Music chacune). Seul le dossier parent se lit
        // playlist par playlist : `parent` n'existe pas pour une playlist à la racine (≈ 1,5 s pour 150 playlists).
        // Variables préfixées « lb » : dans un `tell application "Music"`, un nom comme `hidden` ou `parent` désigne une
        // propriété de Music, et `set hidden to …` tenterait de la modifier (erreur −10003, relevée le 27/11/2026).
        let script = """
            set lbIDs to persistent ID of every user playlist
            set lbNames to name of every user playlist
            set lbClasses to class of every user playlist
            set lbKinds to special kind of every user playlist
            set lbFolders to persistent ID of every folder playlist
            set lbParents to {}
            repeat with lbList in (every user playlist)
                try
                    set end of lbParents to persistent ID of parent of lbList
                on error
                    set end of lbParents to ""
                end try
            end repeat
            return {lbIDs, lbNames, lbClasses, lbKinds, lbParents, lbFolders}
            """
        return try await MusicScripting.run(script) { result in
            let columns = result.listItems.map(\.listItems)
            guard columns.count == 6 else { return [] }
            // Les dossiers se repèrent par leur propre liste : lue en groupe, `class` les donne pour de simples playlists
            // (relevé du 27/11/2026).
            let folders = Set(columns[5].map(\.text))
            let count = columns[0..<5].map(\.count).min() ?? 0
            return (0..<count).compactMap { i -> MusicPlaylist? in
                let id = columns[0][i].text
                let kind = columns[3][i].enumCodeValue
                let isFolder = folders.contains(id) || columns[2][i].typeCodeValue == Self.folderClass
                // Playlists spéciales (bibliothèque, Genius, Achats…) masquées ; « aucune » et « dossier » gardées.
                guard MusicTrackRef.isValidPersistentID(id), kind == Self.kindNone || kind == Self.kindFolder || isFolder else { return nil }
                let parent = columns[4][i].text
                return MusicPlaylist(id: id, name: columns[1][i].text, parentID: parent.isEmpty ? nil : parent, isFolder: isFolder)
            }
        }
    }

    private static let folderClass = OSType(0x6346_6F50)  // 'cFoP'
    private static let kindNone = OSType(0x6B4E_6F6E)  // 'kNon'
    private static let kindFolder = OSType(0x6B53_7046)  // 'kSpF'

    public func tracks(inPlaylist id: String) async throws -> [MusicTrack] {
        guard MusicScripting.isRunning, MusicTrackRef.isValidPersistentID(id) else { return [] }
        let script = """
            set lbList to first user playlist whose persistent ID is "\(id)"
            if (count of tracks of lbList) is 0 then return {}
            return {persistent ID of every track of lbList, name of every track of lbList, artist of every track of lbList, ¬
                album of every track of lbList, duration of every track of lbList, class of every track of lbList}
            """
        return try await MusicScripting.run(script) { Self.parseColumns($0) }
    }

    public func search(_ text: String, limit: Int) async throws -> [MusicTrack] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard MusicScripting.isRunning, !query.isEmpty else { return [] }
        let script = """
            set lbFound to search library playlist 1 for \(MusicScripting.quoted(String(query.prefix(100))))
            set lbOut to {{}, {}, {}, {}, {}, {}}
            set lbCount to 0
            repeat with lbTrack in lbFound
                set lbCount to lbCount + 1
                if lbCount > \(max(1, limit)) then exit repeat
                set end of item 1 of lbOut to persistent ID of lbTrack
                set end of item 2 of lbOut to name of lbTrack
                set end of item 3 of lbOut to artist of lbTrack
                set end of item 4 of lbOut to album of lbTrack
                set end of item 5 of lbOut to duration of lbTrack
                set end of item 6 of lbOut to class of lbTrack
            end repeat
            return lbOut
            """
        return try await MusicScripting.run(script) { Self.parseColumns($0) }
    }

    public func download(tracks ids: [String], inPlaylist playlist: String) async throws {
        let ids = ids.filter(MusicTrackRef.isValidPersistentID)
        guard MusicScripting.isRunning, MusicTrackRef.isValidPersistentID(playlist), !ids.isEmpty else { return }
        let list = ids.map { "\"\($0)\"" }.joined(separator: ", ")
        let script = """
            set lbList to first user playlist whose persistent ID is "\(playlist)"
            repeat with lbWanted in {\(list)}
                try
                    download (first track of lbList whose persistent ID is (lbWanted as text))
                end try
            end repeat
            """
        _ = try await MusicScripting.run(script) { _ in 0 }
    }

    public func availability(of ids: [String]) async throws -> [String: MusicTrackAvailability] {
        let ids = Array(Set(ids.filter(MusicTrackRef.isValidPersistentID))).sorted()
        guard MusicScripting.isRunning, !ids.isEmpty else { return [:] }
        let list = ids.map { "\"\($0)\"" }.joined(separator: ", ")
        let script = """
            set lbOut to {}
            repeat with lbWanted in {\(list)}
                set lbFound to (every track of library playlist 1 whose persistent ID is (lbWanted as text))
                if lbFound is {} then
                    set end of lbOut to ""
                else
                    set end of lbOut to class of item 1 of lbFound
                end if
            end repeat
            return lbOut
            """
        return try await MusicScripting.run(script) { result in
            var out: [String: MusicTrackAvailability] = [:]
            for (id, item) in zip(ids, result.listItems) {
                if item.descriptorType != typeType { out[id] = .missing; continue }
                out[id] = Self.isLocal(trackClass: item.typeCodeValue) == false ? .cloud : .downloaded
            }
            return out
        }
    }

    public func artwork(of id: String) async throws -> Data? {
        guard MusicScripting.isRunning, MusicTrackRef.isValidPersistentID(id) else { return nil }
        let script = """
            set lbTracks to (every track of library playlist 1 whose persistent ID is "\(id)")
            if lbTracks is {} then return ""
            set lbTrack to item 1 of lbTracks
            if (count of artworks of lbTrack) is 0 then return ""
            return raw data of artwork 1 of lbTrack
            """
        return try await MusicScripting.run(script) { result in
            result.descriptorType == typeUnicodeText || result.descriptorType == typeUTF8Text ? nil : result.data
        }
    }

    public func openInMusic(_ storeURL: URL) async {
        // https://music.apple.com/… → music://music.apple.com/… : la page s'ouvre dans l'app Music, pas dans le navigateur.
        guard ITunesCatalog.isTrusted(storeURL), var components = URLComponents(url: storeURL, resolvingAgainstBaseURL: false) else { return }
        components.scheme = "music"
        guard let url = components.url else { return }
        _ = await MainActor.run { NSWorkspace.shared.open(url) }
    }

    public func openMusic() async {
        await MainActor.run {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: MusicScripting.bundleIdentifier) else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Six listes parallèles (identifiants, titres, artistes, albums, durées, classes) → morceaux.
    private static func parseColumns(_ result: NSAppleEventDescriptor) -> [MusicTrack] {
        let columns = result.listItems.map(\.listItems)
        guard columns.count == 6 else { return [] }
        let count = columns.map(\.count).min() ?? 0
        return (0..<count).compactMap { i -> MusicTrack? in
            let id = columns[0][i].text
            guard MusicTrackRef.isValidPersistentID(id) else { return nil }
            return MusicTrack(
                id: id, title: columns[1][i].text, artist: columns[2][i].text, album: columns[3][i].text,
                duration: columns[4][i].doubleValue.isFinite ? max(0, columns[4][i].doubleValue) : 0,
                isDownloaded: Self.isLocal(trackClass: columns[5][i].typeCodeValue))
        }
    }

    /// `file track` (cFlT) = fichier sur ce Mac ; `shared track` (cShT) ou `URL track` (cURT) = dans le nuage. Vérifié sur une
    /// vraie bibliothèque (27/11/2026) : les morceaux d'abonnement téléchargés sont des `file track` avec un emplacement.
    private static func isLocal(trackClass code: OSType) -> Bool? {
        switch code {
        case OSType(0x6346_6C54): true  // 'cFlT'
        case OSType(0x6353_6854), OSType(0x6355_5254): false  // 'cShT', 'cURT'
        default: nil
        }
    }
}
