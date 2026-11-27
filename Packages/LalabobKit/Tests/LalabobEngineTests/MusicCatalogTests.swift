import Foundation
import LalabobModel
import Testing

@testable import LalabobEngine

/// Faux catalogue : réponses fixées, téléchargements comptés.
actor FakeCatalog: MusicCatalogSearching {
    var results: [CatalogTrack] = []
    var failing = false
    private(set) var downloads: [URL] = []
    func configure(_ results: [CatalogTrack], failing: Bool = false) {
        self.results = results
        self.failing = failing
    }
    func search(_ text: String, limit: Int) async throws -> [CatalogTrack] {
        if failing { throw URLError(.notConnectedToInternet) }
        return results
    }
    func download(_ url: URL) async throws -> Data {
        if failing { throw URLError(.notConnectedToInternet) }
        downloads.append(url)
        return Data("extrait".utf8)
    }
}

@Suite("Catalogue Apple Music (internet)")
struct ITunesCatalogTests {
    @Test("Lecture de la réponse : champs, pochette agrandie, adresses hors Apple écartées")
    func parse() {
        let json = """
            {"resultCount":2,"results":[
            {"trackId":1,"trackName":"Polka","artistName":"Fanfare","collectionName":"Cuivres","trackTimeMillis":92000,
             "previewUrl":"https://audio-ssl.itunes.apple.com/x.m4a","artworkUrl100":"https://is1-ssl.mzstatic.com/a/100x100bb.jpg",
             "trackViewUrl":"https://music.apple.com/fr/album/x?i=1"},
            {"trackId":2,"trackName":"Piège","previewUrl":"https://exemple.com/x.m4a","artworkUrl100":"http://is1-ssl.mzstatic.com/b.jpg"},
            {"trackName":"Sans identifiant"}]}
            """
        let tracks = ITunesCatalog.parse(Data(json.utf8))
        #expect(tracks.count == 2)
        #expect(tracks[0].duration == 92 && tracks[0].album == "Cuivres")
        #expect(tracks[0].artworkURL?.absoluteString.contains("300x300bb") == true)
        #expect(tracks[0].storeURL != nil && tracks[0].previewURL != nil)
        #expect(tracks[1].previewURL == nil && tracks[1].artworkURL == nil)
        #expect(ITunesCatalog.parse(Data("pas du json".utf8)).isEmpty)
    }

    @Test("Adresse de recherche : texte encodé, chanson, 50 au plus")
    func searchURL() {
        let url = ITunesCatalog.searchURL(for: "fanfare & cirque", limit: 500)?.absoluteString ?? ""
        #expect(url.hasPrefix("https://itunes.apple.com/search?"))
        #expect(url.contains("term=fanfare%20%26%20cirque"))
        #expect(url.contains("entity=song") && url.contains("limit=50"))
    }

    @Test("Seules les adresses https d'Apple sont suivies")
    func trusted() {
        #expect(ITunesCatalog.isTrusted(URL(string: "https://music.apple.com/x")!))
        #expect(ITunesCatalog.isTrusted(URL(string: "https://is3-ssl.mzstatic.com/x.jpg")!))
        #expect(!ITunesCatalog.isTrusted(URL(string: "http://music.apple.com/x")!))
        #expect(!ITunesCatalog.isTrusted(URL(string: "https://apple.com.exemple.fr/x")!))
    }
}

@MainActor
@Suite("Extraits, recherche internet, pochettes", .serialized)
struct MusicExtrasTests {
    let polka = CatalogTrack(
        id: 7, title: "Polka", artist: "Fanfare", previewURL: URL(string: "https://audio-ssl.itunes.apple.com/p.m4a"),
        artworkURL: URL(string: "https://is1-ssl.mzstatic.com/p.jpg"), storeURL: URL(string: "https://music.apple.com/fr/song/7"))

    private func make(failing: Bool = false) async -> (MusicLibraryController, FakeMusicLibrary, FakeCatalog) {
        let library = FakeMusicLibrary()
        let catalog = FakeCatalog()
        await catalog.configure([CatalogTrack(id: 1, title: "Autre"), polka], failing: failing)
        let cache = FileManager.default.temporaryDirectory.appending(path: "lalabob-tests-\(UUID().uuidString)")
        return (MusicLibraryController(library: library, catalog: catalog, cacheDirectory: cache), library, catalog)
    }

    @Test("Recherche internet ; « Ajouter… » ouvre la page du morceau dans Music")
    func internet() async {
        let (controller, library, _) = await make()
        await controller.searchInternet("polka")
        #expect(controller.internetResults.count == 2)
        await controller.openInMusic(polka)
        #expect(await library.openedStore == [polka.storeURL!])
    }

    @Test("Extrait d'un morceau de la bibliothèque : trouvé par son titre, téléchargé une seule fois")
    func libraryPreview() async {
        let (controller, _, catalog) = await make()
        let track = MusicTrack(id: "0A", title: "Polka", artist: "Fanfare")
        let file = await controller.previewFile(for: track)
        #expect(file != nil)
        #expect(file.map { (try? Data(contentsOf: $0)) == Data("extrait".utf8) } == true)
        _ = await controller.previewFile(for: track)
        #expect(await catalog.downloads == [polka.previewURL!])
    }

    @Test("Pochette : celle de Music d'abord, sinon celle du catalogue")
    func artwork() async {
        let (controller, library, catalog) = await make()
        await library.setArtwork(Data([1, 2, 3]), for: "0A")
        await controller.loadArtwork(for: MusicTrackRef(persistentID: "0A", title: "Polka"))
        #expect(controller.artworks["0A"] == Data([1, 2, 3]))
        await controller.loadArtwork(for: MusicTrackRef(persistentID: "0B", title: "Polka", artist: "Fanfare"))
        #expect(controller.artworks["0B"] == Data("extrait".utf8))
        #expect(await catalog.downloads == [polka.artworkURL!])
    }

    @Test("Sans internet : un message, pas de plantage")
    func offline() async {
        let (controller, _, _) = await make(failing: true)
        await controller.searchInternet("polka")
        #expect(controller.internetResults.isEmpty)
        #expect(controller.networkError != nil)
        #expect(await controller.previewFile(for: MusicTrack(id: "0A", title: "Polka")) == nil)
    }
}
