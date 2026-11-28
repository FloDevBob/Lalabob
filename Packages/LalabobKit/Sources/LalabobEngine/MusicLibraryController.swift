import Foundation
import LalabobModel
import Observation

/// L'état du panneau Apple Music (grilles Apple Music, déverrouillé) : playlists en arbre, morceaux de la playlist choisie,
/// recherche, sélection multiple (Maj / ⌘), téléchargement des morceaux restés dans le nuage.
@MainActor
@Observable
public final class MusicLibraryController {
    /// Une ligne de l'arbre des playlists.
    public struct Row: Identifiable, Equatable, Sendable {
        public var playlist: MusicPlaylist
        public var depth: Int
        public var id: String { playlist.id }
    }

    @ObservationIgnored private let library: any MusicLibraryReading
    @ObservationIgnored private let catalog: any MusicCatalogSearching
    @ObservationIgnored private let cacheDirectory: URL

    /// Où l'on cherche : les playlists de la bibliothèque, ou le catalogue d'Apple Music sur internet.
    public enum Source: Sendable { case library, internet }
    public var source: Source = .library
    /// Résultats de la recherche sur internet.
    public private(set) var internetResults: [CatalogTrack] = []
    public private(set) var isSearchingInternet = false
    /// Dernier problème de réseau ou d'extrait (affiché dans le panneau).
    public private(set) var networkError: String?
    /// Pochettes déjà chargées, par identifiant de morceau.
    public private(set) var artworks: [String: Data] = [:]
    /// Extraits déjà téléchargés : clé (« lib:<id> », « cat:<id> ») → fichier local.
    @ObservationIgnored private var previewFiles: [String: URL] = [:]

    public private(set) var status: MediaVolumeStatus = .notRunning
    public private(set) var isLoading = false
    public private(set) var playlists: [MusicPlaylist] = []
    public private(set) var expandedFolders: Set<String> = []
    public private(set) var selectedPlaylistID: String?
    public private(set) var tracks: [MusicTrack] = []
    /// Recherche en cours (vide = la playlist choisie).
    public private(set) var searchText = ""
    public private(set) var searchResults: [MusicTrack] = []
    public var onlyDownloaded = false
    public private(set) var selectedTrackIDs: Set<String> = []
    /// Disponibilité des morceaux posés sur les pads (téléchargé, nuage, introuvable), par identifiant.
    public private(set) var padAvailability: [String: MusicTrackAvailability] = [:]
    @ObservationIgnored private var anchor: String?

    /// Au plus ce nombre de résultats de recherche.
    public static let searchLimit = 200

    public init(
        library: any MusicLibraryReading, catalog: any MusicCatalogSearching = ITunesCatalog(),
        cacheDirectory: URL = FileManager.default.temporaryDirectory.appending(path: "lalabob-extraits")
    ) {
        self.library = library
        self.catalog = catalog
        self.cacheDirectory = cacheDirectory
    }

    // MARK: Internet (catalogue d'Apple Music)

    /// Cherche dans le catalogue d'Apple Music (titre, artiste…). Seul le texte cherché part sur le réseau.
    public func searchInternet(_ text: String) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            internetResults = []
            return
        }
        isSearchingInternet = true
        defer { isSearchingInternet = false }
        do {
            internetResults = try await catalog.search(query, limit: 40)
            networkError = nil
        } catch {
            internetResults = []
            networkError = "Recherche impossible : vérifiez la connexion à internet."
        }
    }

    /// « Ajouter… » : ouvre le morceau dans l'app Music, où l'on clique + pour l'ajouter à la bibliothèque.
    public func openInMusic(_ track: CatalogTrack) async {
        guard let url = track.storeURL else { return }
        await library.openInMusic(url)
    }

    /// Le fichier de l'extrait de 30 s d'un morceau du catalogue (téléchargé une fois, gardé ensuite).
    public func previewFile(for track: CatalogTrack) async -> URL? {
        guard let url = track.previewURL else {
            networkError = "Pas d'extrait pour « \(track.title) »."
            return nil
        }
        return await cachedPreview(key: "cat-\(track.id)", from: url)
    }

    /// L'extrait de 30 s d'un morceau de la bibliothèque : cherché dans le catalogue d'après son titre et son artiste.
    public func previewFile(for track: MusicTrack) async -> URL? {
        if let cached = previewFiles["lib-\(track.id)"] { return cached }
        guard let match = await catalogMatch(title: track.title, artist: track.artist), let url = match.previewURL else {
            networkError = networkError ?? "Pas d'extrait trouvé pour « \(track.title) »."
            return nil
        }
        let file = await cachedPreview(key: "cat-\(match.id)", from: url)
        previewFiles["lib-\(track.id)"] = file
        return file
    }

    /// Charge la pochette d'un morceau : celle de Music, sinon celle du catalogue. Gardée en mémoire.
    public func loadArtwork(for track: MusicTrackRef) async {
        guard artworks[track.persistentID] == nil else { return }
        if let data = try? await library.artwork(of: track.persistentID), !data.isEmpty {
            artworks[track.persistentID] = data
            return
        }
        if let match = await catalogMatch(title: track.title, artist: track.artist), let url = match.artworkURL,
            let data = try? await catalog.download(url)
        {
            artworks[track.persistentID] = data
        }
    }

    private func catalogMatch(title: String, artist: String) async -> CatalogTrack? {
        do {
            let found = try await catalog.search("\(title) \(artist)", limit: 10)
            networkError = nil
            let wanted = title.lowercased()
            return found.first { $0.title.lowercased() == wanted } ?? found.first { $0.title.lowercased().contains(wanted) } ?? found.first
        } catch {
            networkError = "Pas de connexion à internet : extraits et pochettes indisponibles."
            return nil
        }
    }

    private func cachedPreview(key: String, from url: URL) async -> URL? {
        if let cached = previewFiles[key] { return cached }
        let file = cacheDirectory.appending(path: "\(key).m4a")
        if FileManager.default.fileExists(atPath: file.path) {
            previewFiles[key] = file
            return file
        }
        do {
            let data = try await catalog.download(url)
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            previewFiles[key] = file
            networkError = nil
            return file
        } catch {
            networkError = "Extrait indisponible : vérifiez la connexion à internet."
            return nil
        }
    }

    // MARK: Chargement

    /// Relit l'état de Music et ses playlists ; garde la playlist choisie si elle existe encore.
    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        status = await library.status()
        guard status == .running else {
            playlists = []
            tracks = []
            return
        }
        do {
            playlists = try await library.playlists()
            if let selected = selectedPlaylistID, playlists.contains(where: { $0.id == selected }) {
                await loadTracks(of: selected)
            } else if let first = playlists.first(where: { !$0.isFolder }) {
                await selectPlaylist(first.id)
            }
        } catch {
            status = Self.status(for: error)
        }
    }

    public func selectPlaylist(_ id: String) async {
        guard let playlist = playlists.first(where: { $0.id == id }) else { return }
        if playlist.isFolder { return toggleFolder(id) }
        selectedPlaylistID = id
        selectedTrackIDs = []
        anchor = nil
        await loadTracks(of: id)
    }

    private func loadTracks(of id: String) async {
        do {
            tracks = try await library.tracks(inPlaylist: id)
        } catch {
            tracks = []
            status = Self.status(for: error)
        }
    }

    public func toggleFolder(_ id: String) {
        if expandedFolders.contains(id) { expandedFolders.remove(id) } else { expandedFolders.insert(id) }
    }

    /// Change le texte de recherche : filtre les playlists par leur nom et cherche les morceaux dans toute la bibliothèque.
    public func setSearchText(_ text: String) async {
        searchText = text
        selectedTrackIDs = []
        anchor = nil
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, status == .running else {
            searchResults = []
            return
        }
        do {
            let found = try await library.search(query, limit: Self.searchLimit)
            if searchText == text { searchResults = found }  // une frappe plus récente a pu passer entre-temps
        } catch {
            searchResults = []
            status = Self.status(for: error)
        }
    }

    /// Relit la disponibilité des morceaux des pads (à l'ouverture d'une grille Apple Music et après un dépôt).
    public func refreshAvailability(of ids: Set<String>) async {
        guard !ids.isEmpty, await library.status() == .running else { return }
        if let found = try? await library.availability(of: Array(ids)) { padAvailability.merge(found) { $1 } }
    }

    public func openMusic() async {
        await library.openMusic()
    }

    /// Demande à Music de télécharger les morceaux de la playlist restés dans le nuage, puis relit la playlist.
    public func downloadMissing() async {
        guard let playlist = selectedPlaylistID else { return }
        let missing = tracks.filter { $0.isDownloaded == false }.map(\.id)
        guard !missing.isEmpty else { return }
        do {
            try await library.download(tracks: missing, inPlaylist: playlist)
            await loadTracks(of: playlist)
        } catch {
            status = Self.status(for: error)
        }
    }

    private static func status(for error: any Error) -> MediaVolumeStatus {
        switch error as? MediaVolumeError {
        case .notAuthorized: .notAuthorized
        case .failed(let message): .failed(message)
        case nil: .failed(error.localizedDescription)
        }
    }

    // MARK: Ce que montre le panneau

    /// Les playlists à afficher. Sans recherche : l'arbre (enfants sous leur dossier ouvert, dans l'ordre de Music). Avec une
    /// recherche : les playlists dont le nom la contient, à plat.
    public var visibleRows: [Row] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return playlists.filter { !$0.isFolder && $0.name.localizedStandardContains(query) }.map { Row(playlist: $0, depth: 0) }
        }
        let known = Set(playlists.map(\.id))
        var children: [String?: [MusicPlaylist]] = [:]
        for playlist in playlists {
            let parent = playlist.parentID.flatMap { known.contains($0) ? $0 : nil }
            children[parent, default: []].append(playlist)
        }
        var rows: [Row] = []
        var visiting: Set<String> = []  // garde-fou contre une boucle de dossiers
        func walk(_ parent: String?, depth: Int) {
            for playlist in children[parent] ?? [] where visiting.insert(playlist.id).inserted {
                rows.append(Row(playlist: playlist, depth: depth))
                if playlist.isFolder, expandedFolders.contains(playlist.id) { walk(playlist.id, depth: depth + 1) }
            }
        }
        walk(nil, depth: 0)
        return rows
    }

    /// Les morceaux affichés : résultats de recherche ou playlist choisie, filtrés sur « téléchargés seulement ».
    public var shownTracks: [MusicTrack] {
        let base = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? tracks : searchResults
        return onlyDownloaded ? base.filter { $0.isDownloaded != false } : base
    }

    /// Morceaux de la playlist choisie restés dans le nuage.
    public var cloudCount: Int { tracks.filter { $0.isDownloaded == false }.count }

    public var selectedPlaylist: MusicPlaylist? { playlists.first { $0.id == selectedPlaylistID } }

    // MARK: Sélection des morceaux

    /// Clic sur un morceau : seul, Maj = plage depuis le dernier clic, ⌘ = ajouter / retirer.
    public func clickTrack(_ id: String, extend: Bool = false, toggle: Bool = false) {
        let shown = shownTracks.map(\.id)
        guard shown.contains(id) else { return }
        if toggle {
            if selectedTrackIDs.contains(id) { selectedTrackIDs.remove(id) } else { selectedTrackIDs.insert(id) }
            anchor = id
        } else if extend, let anchor, let from = shown.firstIndex(of: anchor), let to = shown.firstIndex(of: id) {
            selectedTrackIDs = Set(shown[min(from, to)...max(from, to)])
        } else {
            selectedTrackIDs = [id]
            anchor = id
        }
    }

    /// Ce qu'on glisse depuis `id` : la sélection (dans l'ordre affiché) si `id` en fait partie, sinon ce morceau seul.
    public func dragged(from id: String) -> [MusicTrackRef] {
        let shown = shownTracks
        let ids = selectedTrackIDs.contains(id) ? selectedTrackIDs : [id]
        let playlistName = searchText.isEmpty ? selectedPlaylist?.name : nil
        return shown.filter { ids.contains($0.id) }.map { $0.reference(playlist: playlistName) }
    }
}
