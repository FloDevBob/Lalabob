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
}

/// La bibliothèque réelle, lue par AppleScript. Ne lance jamais Music : tout est refusé s'il est fermé.
public actor AppleMusicLibrary: MusicLibraryReading {
    public init() {}

    public func status() async -> MediaVolumeStatus { await AppleMusicVolume().status() }

    public func playlists() async throws -> [MusicPlaylist] {
        guard MusicScripting.isRunning else { return [] }
        // Une boucle (et non `… of every user playlist`) : `parent` n'existe pas pour une playlist à la racine.
        let script = """
            set out to {}
            repeat with p in (every user playlist)
                set parentID to ""
                try
                    set parentID to persistent ID of parent of p
                end try
                set isFolder to (class of p is folder playlist)
                set hidden to false
                try
                    if (special kind of p is not none) and not isFolder then set hidden to true
                end try
                if not hidden then set end of out to {persistent ID of p, name of p, parentID, isFolder, count of tracks of p}
            end repeat
            return out
            """
        return try await MainActor.run {
            try MusicScripting.execute(script).listItems.compactMap { row -> MusicPlaylist? in
                let f = row.listItems
                guard f.count == 5, MusicTrackRef.isValidPersistentID(f[0].text) else { return nil }
                let parent = f[2].text
                return MusicPlaylist(
                    id: f[0].text, name: f[1].text, parentID: parent.isEmpty ? nil : parent, isFolder: f[3].booleanValue,
                    trackCount: Int(f[4].int32Value))
            }
        }
    }

    public func tracks(inPlaylist id: String) async throws -> [MusicTrack] {
        guard MusicScripting.isRunning, MusicTrackRef.isValidPersistentID(id) else { return [] }
        let script = """
            set p to first user playlist whose persistent ID is "\(id)"
            set t to every track of p
            if t is {} then return {}
            return {persistent ID of every track of p, name of every track of p, artist of every track of p, ¬
                album of every track of p, duration of every track of p, class of every track of p}
            """
        return try await MainActor.run { Self.parseColumns(try MusicScripting.execute(script)) }
    }

    public func search(_ text: String, limit: Int) async throws -> [MusicTrack] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard MusicScripting.isRunning, !query.isEmpty else { return [] }
        let script = """
            set found to search library playlist 1 for \(MusicScripting.quoted(String(query.prefix(100))))
            set out to {{}, {}, {}, {}, {}, {}}
            set n to 0
            repeat with t in found
                set n to n + 1
                if n > \(max(1, limit)) then exit repeat
                set end of item 1 of out to persistent ID of t
                set end of item 2 of out to name of t
                set end of item 3 of out to artist of t
                set end of item 4 of out to album of t
                set end of item 5 of out to duration of t
                set end of item 6 of out to class of t
            end repeat
            return out
            """
        return try await MainActor.run { Self.parseColumns(try MusicScripting.execute(script)) }
    }

    public func download(tracks ids: [String], inPlaylist playlist: String) async throws {
        let ids = ids.filter(MusicTrackRef.isValidPersistentID)
        guard MusicScripting.isRunning, MusicTrackRef.isValidPersistentID(playlist), !ids.isEmpty else { return }
        let list = ids.map { "\"\($0)\"" }.joined(separator: ", ")
        let script = """
            set p to first user playlist whose persistent ID is "\(playlist)"
            repeat with wanted in {\(list)}
                try
                    download (first track of p whose persistent ID is wanted)
                end try
            end repeat
            """
        try await MainActor.run { _ = try MusicScripting.execute(script) }
    }

    public func openMusic() async {
        await MainActor.run {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: MusicScripting.bundleIdentifier) else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Six listes parallèles (identifiants, titres, artistes, albums, durées, classes) → morceaux.
    @MainActor
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

    /// `file track` (cFlT) = fichier sur ce Mac ; `shared track` (cShT) ou `URL track` (cURT) = dans le nuage.
    private static func isLocal(trackClass code: OSType) -> Bool? {
        switch code {
        case OSType(0x6346_6C54): true  // 'cFlT'
        case OSType(0x6353_6854), OSType(0x6355_5254): false  // 'cShT', 'cURT'
        default: nil
        }
    }
}
