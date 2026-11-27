import Foundation

/// Un morceau du catalogue d'Apple Music (recherche sur internet) : de quoi l'afficher, l'écouter 30 s et l'ouvrir dans Music.
public struct CatalogTrack: Identifiable, Equatable, Sendable {
    public var id: Int
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval
    /// Extrait de 30 s (AAC), servi par Apple.
    public var previewURL: URL?
    public var artworkURL: URL?
    /// La page du morceau dans Apple Music (« Ajouter… » l'ouvre dans l'app Music).
    public var storeURL: URL?

    public init(
        id: Int, title: String, artist: String = "", album: String = "", duration: TimeInterval = 0, previewURL: URL? = nil,
        artworkURL: URL? = nil, storeURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.previewURL = previewURL
        self.artworkURL = artworkURL
        self.storeURL = storeURL
    }
}

/// Chercher dans le catalogue d'Apple Music et télécharger un extrait ou une pochette (fausse version dans les tests).
public protocol MusicCatalogSearching: Sendable {
    func search(_ text: String, limit: Int) async throws -> [CatalogTrack]
    func download(_ url: URL) async throws -> Data
}

/// La recherche publique d'Apple (« iTunes Search », sans clé ni compte). Seul le texte cherché part sur le réseau.
public struct ITunesCatalog: MusicCatalogSearching {
    public init() {}

    public func search(_ text: String, limit: Int) async throws -> [CatalogTrack] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let url = Self.searchURL(for: query, limit: limit) else { return [] }
        return Self.parse(try await fetch(url))
    }

    public func download(_ url: URL) async throws -> Data {
        guard Self.isTrusted(url) else { throw URLError(.badURL) }
        return try await fetch(url)
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Lalabob", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 20_000_000 else { throw URLError(.badServerResponse) }
        return data
    }

    static func searchURL(for query: String, limit: Int) -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: String(query.prefix(100))),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 50)))),
            URLQueryItem(name: "country", value: Locale.current.region?.identifier ?? "FR"),
        ]
        return components?.url
    }

    /// Seules les adresses d'Apple sont suivies (extraits, pochettes, pages) : une réponse ne peut pas nous envoyer ailleurs.
    static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host()?.lowercased() else { return false }
        return host == "apple.com" || host.hasSuffix(".apple.com") || host.hasSuffix(".mzstatic.com")
    }

    /// La réponse JSON → morceaux ; ce qui manque ou paraît étrange est écarté.
    static func parse(_ data: Data) -> [CatalogTrack] {
        struct Response: Decodable { let results: [Item] }
        struct Item: Decodable {
            let trackId: Int?
            let trackName: String?
            let artistName: String?
            let collectionName: String?
            let trackTimeMillis: Double?
            let previewUrl: String?
            let artworkUrl100: String?
            let trackViewUrl: String?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        func trusted(_ text: String?) -> URL? { text.flatMap(URL.init(string:)).flatMap { isTrusted($0) ? $0 : nil } }
        return response.results.compactMap { item in
            guard let id = item.trackId, let title = item.trackName else { return nil }
            // Pochette plus grande que la vignette de 100 px (même adresse, taille dans le nom).
            let artwork = item.artworkUrl100?.replacingOccurrences(of: "100x100bb", with: "300x300bb")
            return CatalogTrack(
                id: id, title: String(title.prefix(300)), artist: String((item.artistName ?? "").prefix(300)),
                album: String((item.collectionName ?? "").prefix(300)), duration: max(0, (item.trackTimeMillis ?? 0) / 1000),
                previewURL: trusted(item.previewUrl), artworkURL: trusted(artwork), storeURL: trusted(item.trackViewUrl))
        }
    }
}
