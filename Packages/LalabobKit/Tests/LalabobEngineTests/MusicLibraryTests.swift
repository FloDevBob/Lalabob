import Foundation
import LalabobAudio
import LalabobModel
import Testing

@testable import LalabobEngine

/// Fausse bibliothèque d'Apple Music.
actor FakeMusicLibrary: MusicLibraryReading {
    var state: MediaVolumeStatus = .running
    var lists: [MusicPlaylist] = []
    var content: [String: [MusicTrack]] = [:]
    var found: [MusicTrack] = []
    private(set) var downloads: [[String]] = []
    private(set) var opened = 0

    func configure(lists: [MusicPlaylist], content: [String: [MusicTrack]], found: [MusicTrack] = []) {
        self.lists = lists
        self.content = content
        self.found = found
    }
    func setState(_ new: MediaVolumeStatus) { state = new }
    func status() async -> MediaVolumeStatus { state }
    func playlists() async throws -> [MusicPlaylist] { lists }
    func tracks(inPlaylist id: String) async throws -> [MusicTrack] { content[id] ?? [] }
    func search(_ text: String, limit: Int) async throws -> [MusicTrack] { Array(found.prefix(limit)) }
    func download(tracks ids: [String], inPlaylist playlist: String) async throws {
        downloads.append(ids)
        content[playlist] = content[playlist]?.map { track in
            var t = track
            if ids.contains(t.id) { t.isDownloaded = true }
            return t
        }
    }
    func openMusic() async { opened += 1 }
    var artworkData: [String: Data] = [:]
    private(set) var openedStore: [URL] = []
    func setArtwork(_ data: Data, for id: String) { artworkData[id] = data }
    func artwork(of id: String) async throws -> Data? { artworkData[id] }
    func openInMusic(_ storeURL: URL) async { openedStore.append(storeURL) }
    func availability(of ids: [String]) async throws -> [String: MusicTrackAvailability] {
        let all = content.values.flatMap { $0 }
        return Dictionary(uniqueKeysWithValues: ids.map { id in
            (id, all.first { $0.id == id }.map { $0.isDownloaded == false ? .cloud : .downloaded } ?? .missing)
        })
    }
}

@MainActor
@Suite("Panneau Apple Music", .serialized)
struct MusicLibraryTests {
    static let tracks = [
        MusicTrack(id: "0A", title: "Polka", artist: "Fanfare", duration: 92, isDownloaded: true),
        MusicTrack(id: "0B", title: "Cirque", artist: "Planches", duration: 128, isDownloaded: true),
        MusicTrack(id: "0C", title: "Trompette", artist: "Fanfare", duration: 47, isDownloaded: false),
        MusicTrack(id: "0D", title: "Marche", artist: "Trio", duration: 142, isDownloaded: true),
    ]

    private func makeLibrary() async -> (MusicLibraryController, FakeMusicLibrary) {
        let fake = FakeMusicLibrary()
        await fake.configure(
            lists: [
                MusicPlaylist(id: "F1", name: "Spectacles", isFolder: true),
                MusicPlaylist(id: "P1", name: "Spectacle Bob", parentID: "F1", trackCount: 4),
                MusicPlaylist(id: "P2", name: "Spectacle Noël", parentID: "F1"),
                MusicPlaylist(id: "P3", name: "Jingles"),
            ],
            content: ["P1": Self.tracks, "P3": []],
            found: [Self.tracks[1]])
        let controller = MusicLibraryController(library: fake)
        await controller.refresh()
        return (controller, fake)
    }

    @Test("Arbre : dossiers repliés au départ, enfants en retrait une fois ouverts ; la première playlist est choisie")
    func tree() async {
        let (library, _) = await makeLibrary()
        #expect(library.visibleRows.map(\.id) == ["F1", "P3"])
        #expect(library.selectedPlaylistID == "P1")
        #expect(library.tracks.count == 4)
        await library.selectPlaylist("F1")  // un dossier s'ouvre, il ne se choisit pas
        #expect(library.visibleRows.map(\.id) == ["F1", "P1", "P2", "P3"])
        #expect(library.visibleRows.map(\.depth) == [0, 1, 1, 0])
        #expect(library.selectedPlaylistID == "P1")
    }

    @Test("Recherche : playlists filtrées par nom, morceaux cherchés dans toute la bibliothèque")
    func search() async {
        let (library, _) = await makeLibrary()
        await library.setSearchText("noël")
        #expect(library.visibleRows.map(\.id) == ["P2"])
        #expect(library.shownTracks.map(\.id) == ["0B"])
        await library.setSearchText("")
        #expect(library.shownTracks.count == 4)
    }

    @Test("Sélection : clic, Maj = plage, ⌘ = ajouter / retirer ; on glisse la sélection dans l'ordre affiché")
    func selection() async {
        let (library, _) = await makeLibrary()
        library.clickTrack("0B")
        library.clickTrack("0D", extend: true)
        #expect(library.selectedTrackIDs == ["0B", "0C", "0D"])
        library.clickTrack("0C", toggle: true)
        #expect(library.selectedTrackIDs == ["0B", "0D"])
        #expect(library.dragged(from: "0D").map(\.persistentID) == ["0B", "0D"])
        #expect(library.dragged(from: "0D").first?.playlistName == "Spectacle Bob")
        #expect(library.dragged(from: "0A").map(\.persistentID) == ["0A"])  // hors sélection : ce morceau seul
    }

    @Test("Téléchargés : compte du nuage, filtre, et « Télécharger » demande les manquants à Music")
    func downloads() async {
        let (library, fake) = await makeLibrary()
        #expect(library.cloudCount == 1)
        library.onlyDownloaded = true
        #expect(!library.shownTracks.contains { $0.id == "0C" })
        await library.downloadMissing()
        #expect(await fake.downloads == [["0C"]])
        #expect(library.cloudCount == 0)
    }

    @Test("Music fermé : rien n'est lu, l'état le dit ; « Ouvrir Music » le demande")
    func closed() async {
        let fake = FakeMusicLibrary()
        await fake.setState(.notRunning)
        let library = MusicLibraryController(library: fake)
        await library.refresh()
        #expect(library.status == .notRunning)
        #expect(library.playlists.isEmpty)
        await library.openMusic()
        #expect(await fake.opened == 1)
    }

    @Test("Un dossier qui se contiendrait lui-même ne fait pas boucler l'arbre")
    func loop() async {
        let fake = FakeMusicLibrary()
        await fake.configure(lists: [MusicPlaylist(id: "F1", name: "A", parentID: "F2", isFolder: true), MusicPlaylist(id: "F2", name: "B", parentID: "F1", isFolder: true)], content: [:])
        let library = MusicLibraryController(library: fake)
        await library.refresh()
        #expect(library.visibleRows.count <= 2)
    }

    @Test("Disponibilité des pads : téléchargé, nuage, introuvable")
    func availability() async {
        let (library, _) = await makeLibrary()
        await library.refreshAvailability(of: ["0A", "0C", "ZZ"])
        #expect(library.padAvailability == ["0A": .downloaded, "0C": .cloud, "ZZ": .missing])
    }

    @Test("AppleScript : guillemets et barres obliques échappés, contrôles retirés")
    func quoting() {
        #expect(MusicScripting.quoted("a\"b\\c\nd") == "\"a\\\"b\\\\cd\"")
    }
}

@MainActor
@Suite("Déposer des morceaux", .serialized)
struct MusicDropTests {
    let refs = (1...3).map { MusicTrackRef(persistentID: String(format: "%02X", $0), title: "M\($0)", artist: "A") }

    private func makeController(locked: Bool = false) -> (ShowController, UndoManager) {
        var grid = PadGrid.emptyAppleMusic(name: "M")
        grid[GridPosition(column: 2, row: 5)] = .track(MusicTrackRef(persistentID: "FF", title: "Occupé"), tint: .rose)
        let controller = ShowController(
            show: Show(name: "S", grids: [grid, .empty(name: "Sons")]), audio: RecordingAudioEngine(),
            audioDirectory: URL(filePath: "/tmp/lalabob-audio"), defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!,
            isLocked: locked)
        let undo = UndoManager()
        undo.groupsByEvent = false
        controller.undoManager = undo
        return (controller, undo)
    }

    @Test("De la case visée vers le bas, case occupée sautée, puis la colonne Music suivante depuis le haut")
    func positions() {
        let (controller, _) = makeController()
        #expect(controller.musicDropPositions(count: 3, at: GridPosition(column: 2, row: 4)) == [
            GridPosition(column: 2, row: 4), GridPosition(column: 2, row: 6), GridPosition(column: 2, row: 7),
        ])
        #expect(controller.musicDropPositions(count: 2, at: GridPosition(column: 2, row: 7)) == [
            GridPosition(column: 2, row: 7), GridPosition(column: 3, row: 0),
        ])
        #expect(controller.musicDropPositions(count: 2, at: GridPosition(column: 6, row: 0)).isEmpty)  // colonne lumière
        #expect(controller.musicDropPositions(count: 4, at: GridPosition(column: 5, row: 6)).count == 2)  // plus de place
    }

    @Test("Déposer : pads Music créés (titre, artiste), sélectionnés ; une annulation")
    func drop() {
        let (controller, undo) = makeController()
        #expect(controller.dropMusicTracks(refs, at: GridPosition(column: 0, row: 0)) == 3)
        #expect(controller.pad(at: GridPosition(column: 0, row: 2))?.music?.persistentID == "03")
        #expect(controller.pad(at: GridPosition(column: 0, row: 0))?.subtitle == "A")
        #expect(controller.selectedPositions.count == 3)
        #expect((try? controller.show.validate()) != nil)
        undo.undo()
        #expect(controller.pad(at: GridPosition(column: 0, row: 0)) == nil)
    }

    @Test("Pas assez de place : le reste est signalé ; verrouillé : rien ; grille standard : rien")
    func refusals() {
        var (controller, _) = makeController()
        #expect(controller.dropMusicTracks(refs, at: GridPosition(column: 5, row: 6)) == 2)
        #expect(controller.conversionNotice != nil)
        (controller, _) = makeController(locked: true)
        #expect(controller.dropMusicTracks(refs, at: GridPosition(column: 0, row: 0)) == 0)
        (controller, _) = makeController()
        controller.selectGrid(at: 1)
        #expect(controller.dropMusicTracks(refs, at: GridPosition(column: 0, row: 0)) == 0)
    }

    @Test("Aperçu numéroté pendant le glisser, effacé à la fin")
    func preview() {
        let (controller, _) = makeController()
        controller.beginMusicDrag(count: 2)
        controller.updateMusicDropPreview(at: GridPosition(column: 2, row: 4))
        #expect(controller.musicDropPreview == [GridPosition(column: 2, row: 4), GridPosition(column: 2, row: 6)])
        controller.endMusicDrag()
        #expect(controller.musicDropPreview.isEmpty && controller.musicDragCount == 0)
    }

    @Test("Jeton de glisser : aller-retour ; identifiant piégé écarté ; texte quelconque refusé")
    func token() {
        #expect(MusicDragToken.parse(MusicDragToken.make(refs)) == refs)
        var bad = refs[0]
        bad.persistentID = "1\" & quit"
        #expect(MusicDragToken.parse(MusicDragToken.make([bad, refs[1]])) == [refs[1]])
        #expect(MusicDragToken.parse("lalabob-grid:abc") == nil)
        #expect(MusicDragToken.parse("lalabob-music:{pas du json") == nil)
    }
}
