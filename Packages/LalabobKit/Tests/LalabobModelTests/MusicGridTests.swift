import Foundation
import Testing

@testable import LalabobModel

/// Grilles Apple Music : modèle, format, validation, conversions (spec « Grilles Apple Music », étape 1).
@Suite("Grilles Apple Music · modèle")
struct MusicGridTests {
    let track = MusicTrackRef(
        persistentID: "A1B2C3D4E5F60718", title: "Générique", artist: "Les Planches", album: "Premier acte", duration: 161,
        playlistName: "Spectacle Bob")

    private func musicShow() -> Show {
        var grid = PadGrid.emptyAppleMusic(name: "Musiques")
        grid.columns[0].slots[0] = .track(track, tint: .rose)
        return Show(name: "S", grids: [.empty(name: "Soirée"), grid])
    }

    @Test("Une grille Apple Music neuve : 6 colonnes Music puis 2 colonnes lumière")
    func emptyGrid() {
        let grid = PadGrid.emptyAppleMusic(name: "M")
        #expect(grid.kind == .appleMusic)
        #expect(grid.columns.map(\.kind) == [.music, .music, .music, .music, .music, .music, .light, .light])
        #expect(PadGrid.empty(name: "S").kind == .standard)
    }

    @Test("Types permis : Music et lumière dans une grille Apple Music ; tout sauf Music dans une grille standard")
    func allowedColumns() {
        #expect(GridKind.appleMusic.allows(.music) && GridKind.appleMusic.allows(.light))
        #expect(!GridKind.appleMusic.allows(.audio) && !GridKind.appleMusic.allows(.mixed))
        #expect(GridKind.standard.allows(.audio) && GridKind.standard.allows(.mixed) && GridKind.standard.allows(.light))
        #expect(!GridKind.standard.allows(.music))
    }

    @Test("Une colonne Music n'accepte que des morceaux, et seule elle les accepte")
    func accepts() {
        #expect(ColumnKind.music.accepts(.music))
        for other in [PadKind.audio, .light, .mixed] { #expect(!ColumnKind.music.accepts(other)) }
        for column in [ColumnKind.audio, .light, .mixed] { #expect(!column.accepts(.music)) }
        #expect(!ColumnKind.music.hasAudio && !ColumnKind.music.hasLight)
    }

    @Test("Un pad Music prend le titre et l'artiste du morceau ; son type est Music")
    func trackPad() {
        let pad = Pad.track(track, tint: .rose)
        #expect(pad.kind == .music)
        #expect(pad.title == "Générique" && pad.subtitle == "Les Planches")
        #expect(pad.audio == nil && pad.light == nil)
    }

    @Test("Aller-retour JSON : le type de grille et le morceau sont gardés")
    func roundTrip() throws {
        let show = musicShow()
        let decoded = try ShowPackage.decode(try ShowPackage.encode(show))
        #expect(decoded.grids[1].kind == .appleMusic)
        #expect(decoded.grids[1].columns[0].slots[0]?.music == track)
        #expect(decoded.grids == show.grids)
    }

    @Test("Version écrite : 2 sans Apple Music (lisible par l'ancienne app), 3 avec")
    func formatVersion() throws {
        let plain = Show(name: "S", grids: [.empty(name: "G")])
        let plainJSON = String(decoding: try ShowPackage.encode(plain), as: UTF8.self)
        #expect(plainJSON.contains("\"formatVersion\" : 2"))
        #expect(!plainJSON.contains("\"music\"") && !plainJSON.contains("\"kind\" : \"standard\""))
        let musicJSON = String(decoding: try ShowPackage.encode(musicShow()), as: UTF8.self)
        #expect(musicJSON.contains("\"formatVersion\" : 3"))
    }

    @Test("Une version 5 (inconnue) est refusée")
    func unknownVersion() throws {
        var json = String(decoding: try ShowPackage.encode(musicShow()), as: UTF8.self)
        json = json.replacingOccurrences(of: "\"formatVersion\" : 3", with: "\"formatVersion\" : 5")
        #expect(throws: ShowPackageError.self) { try ShowPackage.decode(Data(json.utf8)) }
    }

    @Test("Validation : colonne interdite dans une grille, morceau hors colonne Music, identifiant piégé, pad mêlé")
    func validation() {
        var show = musicShow()
        show.grids[1].columns[0].kind = .audio
        #expect(throws: ShowValidationError.self) { try show.validate() }

        show = musicShow()
        show.grids[0].columns[0].kind = .music
        #expect(throws: ShowValidationError.self) { try show.validate() }

        show = musicShow()
        show.grids[0].columns[0].slots[0] = .track(track, tint: .rose)
        #expect(throws: ShowValidationError.self) { try show.validate() }

        show = musicShow()
        var bad = track
        bad.persistentID = "1\" to quit"
        show.grids[1].columns[0].slots[0] = .track(bad, tint: .rose)
        #expect(throws: ShowValidationError.self) { try show.validate() }

        show = musicShow()
        show.grids[1].columns[0].slots[0]?.audio = AudioClip(fileName: "a.wav")
        #expect(throws: ShowValidationError.self) { try show.validate() }

        #expect(throws: Never.self) { try musicShow().validate() }
    }

    @Test("Identifiant persistant : hexadécimal, 1 à 32 caractères")
    func persistentID() {
        #expect(MusicTrackRef.isValidPersistentID("A1B2C3D4E5F60718"))
        #expect(!MusicTrackRef.isValidPersistentID(""))
        #expect(!MusicTrackRef.isValidPersistentID("XYZ"))
        #expect(!MusicTrackRef.isValidPersistentID(String(repeating: "A", count: 33)))
    }

    @Test("Convertir une grille standard en Apple Music : sons supprimés, colonnes Music vides, lumière gardée")
    func gridConversion() {
        var grid = PadGrid.empty(name: "G")
        grid.columns[0].slots[0] = .sound(title: "Porte", tint: .vert, clip: AudioClip(fileName: "porte.wav"))
        grid.columns[0].filter = 0.5
        grid.columns[6].slots[0] = .cue(title: "Plein feu", tint: .ambre, cue: .blank)
        let converted = grid.converted(to: .appleMusic)
        #expect(converted.kind == .appleMusic)
        #expect(converted.columns[0].kind == .music)
        #expect(converted.columns[0].slots.allSatisfy { $0 == nil })
        #expect(converted.columns[0].filter == 0)
        #expect(converted.columns[6] == grid.columns[6])
        #expect(throws: Never.self) { try Show(name: "S", grids: [converted]).validate() }
    }

    @Test("Et retour : les morceaux sont supprimés, les colonnes redeviennent son, la lumière reste")
    func gridConversionBack() {
        let grid = musicShow().grids[1]
        let back = grid.converted(to: .standard)
        #expect(back.kind == .standard)
        #expect(back.columns[0].kind == .audio && back.columns[0].level == 0.8)
        #expect(back.columns[0].slots.allSatisfy { $0 == nil })
        #expect(back.columns[6] == grid.columns[6])
    }

    @Test("Un morceau ne se convertit en rien d'autre, et rien ne devient un morceau")
    func padConversion() {
        let pad = Pad.track(track, tint: .rose)
        #expect(pad.converted(to: .audio) == nil && pad.converted(to: .light) == nil && pad.converted(to: .mixed) == nil)
        #expect(pad.converted(to: .music) == pad)
        #expect(Pad.cue(title: "C", tint: .ambre, cue: .blank).converted(to: .music) == nil)
        let plan = ConversionPlan.column(musicShow().grids[1].columns[0], to: .audio)
        #expect(plan.deletedPads.count == 1)
    }
}
