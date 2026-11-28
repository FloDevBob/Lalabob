import Foundation
import LalabobAudio
import LalabobModel
import Testing

@testable import LalabobEngine

/// Créer une grille Apple Music, changer le type d'une grille (spec « Grilles Apple Music », étape 1).
@MainActor
@Suite("Grilles Apple Music · édition", .serialized)
struct MusicGridEditingTests {
    struct Rig {
        let controller: ShowController
        let undo: UndoManager
    }

    let sound = Pad(title: "Porte", tint: .vert, audio: AudioClip(fileName: "porte.wav"))
    let cue = Pad(title: "Plein feu", tint: .ambre, light: .blank)
    let track = MusicTrackRef(persistentID: "00AA11BB22CC33DD", title: "Générique", artist: "Les Planches", duration: 161)

    private func makeRig(locked: Bool = false) -> Rig {
        var first = PadGrid.empty(name: "G1")
        first[GridPosition(column: 0, row: 0)] = sound
        first[GridPosition(column: 6, row: 0)] = cue
        let controller = ShowController(
            show: Show(name: "S", grids: [first]), audio: RecordingAudioEngine(), audioDirectory: URL(filePath: "/tmp/lalabob-audio"),
            defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!, isLocked: locked)
        let undo = UndoManager()
        undo.groupsByEvent = false
        controller.undoManager = undo
        return Rig(controller: controller, undo: undo)
    }

    @Test("Nouvelle grille Apple Music : ajoutée, affichée, avec son canal LightKey ; une annulation")
    func addMusicGrid() {
        let rig = makeRig()
        rig.controller.addGrid(kind: .appleMusic)
        #expect(rig.controller.show.grids.count == 2)
        #expect(rig.controller.selectedGridIndex == 1)
        #expect(rig.controller.currentGrid.kind == .appleMusic)
        #expect(rig.controller.currentGrid.lightChannel == 2)
        #expect((try? rig.controller.show.validate()) != nil)
        rig.undo.undo()
        #expect(rig.controller.show.grids.count == 1)
    }

    @Test("Verrouillé : pas de nouvelle grille ni de changement de type")
    func locked() {
        let rig = makeRig(locked: true)
        rig.controller.addGrid(kind: .appleMusic)
        rig.controller.setGridKind(at: 0, to: .appleMusic)
        #expect(rig.controller.show.grids.count == 1)
        #expect(rig.controller.show.grids[0].kind == .standard)
    }

    @Test("Grille standard → Apple Music : le coût est annoncé, les sons partent, la cue reste ; ⌘Z rend tout")
    func convert() {
        let rig = makeRig()
        let before = rig.controller.show
        #expect(rig.controller.gridKindRemovedPads(at: 0, to: .appleMusic).map(\.id) == [sound.id])
        rig.controller.setGridKind(at: 0, to: .appleMusic)
        let grid = rig.controller.show.grids[0]
        #expect(grid.kind == .appleMusic)
        #expect(grid[GridPosition(column: 0, row: 0)] == nil)
        #expect(grid[GridPosition(column: 6, row: 0)] == cue)
        #expect((try? rig.controller.show.validate()) != nil)
        rig.undo.undo()
        #expect(rig.controller.show == before)
    }

    @Test("Une grille sans son change de type sans rien perdre")
    func lossless() {
        let rig = makeRig()
        rig.controller.addGrid(kind: .standard)
        #expect(rig.controller.gridKindRemovedPads(at: 1, to: .appleMusic).isEmpty)
    }

    @Test("Colonnes lumière communes : une grille Apple Music reçoit des colonnes Music, jamais des colonnes son")
    func sharedLight() {
        let rig = makeRig()
        rig.controller.addGrid(kind: .appleMusic)
        // Une colonne lumière en position 2 dans la grille Apple Music.
        rig.controller.selectGrid(at: 1)
        rig.controller.setColumnKind(2, to: .light)
        rig.controller.selectGrid(at: 0)
        rig.controller.setSharedLight(true)
        #expect(rig.controller.show.grids[1].columns[2].kind == .music)
        #expect((try? rig.controller.show.validate()) != nil)
        rig.controller.setSharedLight(false)
        #expect(rig.controller.show.grids[1].columns[2].kind == .light)
        #expect((try? rig.controller.show.validate()) != nil)

        rig.controller.setSharedLight(true)
        rig.controller.addGrid(kind: .appleMusic)
        let added = rig.controller.show.grids[2]
        #expect(added.columns[6].kind == .light && added.columns[0].kind == .music)
        #expect((try? rig.controller.show.validate()) != nil)
    }

    @Test("Dans une grille Apple Music, une colonne ne devient ni son ni mixte ; dans une grille standard, jamais Music")
    func columnKindRules() {
        let rig = makeRig()
        #expect(rig.controller.columnKindProblem(0, to: .music) != nil)
        #expect(!rig.controller.setColumnKind(0, to: .music))
        rig.controller.addGrid(kind: .appleMusic)
        #expect(rig.controller.columnKindProblem(0, to: .audio) != nil)
        #expect(rig.controller.columnKindProblem(0, to: .mixed) != nil)
        #expect(rig.controller.columnKindProblem(0, to: .light) == nil)
        #expect(!rig.controller.setColumnKind(0, to: .audio))
        #expect(rig.controller.currentGrid.columns[0].kind == .music)
    }
}
