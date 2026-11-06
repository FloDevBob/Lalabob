import Foundation
import Testing

@testable import LalabobImport
@testable import LalabobModel

@Suite("Live Set → grilles")
struct AbletonShowBuilderTests {
    /// Un set de `tracks` pistes × `scenes` scènes, un clip partout, sons « t-s.wav ».
    private func fullSet(tracks: Int, scenes: Int) -> AbletonLiveSet {
        var set = AbletonLiveSet()
        set.sceneCount = scenes
        for t in 0..<tracks {
            var clips: [Int: AbletonClip] = [:]
            for s in 0..<scenes {
                let file = "\(t)-\(s).wav"
                clips[s] = AbletonClip(name: "Clip \(t)-\(s)", loops: false,
                    sample: AbletonSampleReference(relativePath: "Samples/\(file)", absolutePath: "", fileName: file))
            }
            set.audioTracks.append(AbletonAudioTrack(name: "Piste \(t + 1)", clips: clips))
        }
        return set
    }

    private func build(_ set: AbletonLiveSet, overflow: LiveSetOverflow = .splitIntoGrids, maximumGrids: Int = 64,
        found: (String) -> Bool = { _ in true }) -> AbletonImportPlan {
        AbletonShowBuilder.build(set, baseName: "Match", overflow: overflow, maximumGrids: maximumGrids) { ref in
            found(ref.fileName) ? ref.fileName : nil
        }
    }

    @Test("Un set qui tient dans une grille : pistes → colonnes son, scènes → lignes, colonnes lumière vides")
    func singleGrid() throws {
        let plan = build(fullSet(tracks: 3, scenes: 4))
        #expect(plan.grids.count == 1)
        let grid = plan.grids[0]
        #expect(grid.name == "Match")
        #expect(Array(grid.columns.map(\.name).prefix(3)) == ["Piste 1", "Piste 2", "Piste 3"])
        #expect(grid.columns.map(\.kind) == [.audio, .audio, .audio, .audio, .audio, .audio, .light, .light])
        let pad = try #require(grid[GridPosition(column: 2, row: 3)])
        #expect(pad.title == "Clip 2-3")
        guard case .audio(let clip) = pad.content else { Issue.record("pad son attendu"); return }
        #expect(clip.fileName == "2-3.wav")
        #expect(grid[GridPosition(column: 3, row: 0)] == nil)
        #expect(grid.columns[6].slots.allSatisfy { $0 == nil })
        #expect(plan.report.importedClips == 12)
        #expect(plan.report.gridCount == 1)
    }

    @Test("Le résultat passe Show.validate()")
    func resultIsValid() throws {
        let plan = build(fullSet(tracks: 14, scenes: 19))
        let show = Show(name: "t", grids: plan.grids)
        try show.validate()
    }

    @Test("Dépassement, découpage : blocs de 6 pistes × 8 scènes, sans clip perdu")
    func splitsIntoGrids() {
        let plan = build(fullSet(tracks: 7, scenes: 9))
        // 2 blocs de pistes × 2 blocs de scènes, tous non vides.
        #expect(plan.grids.count == 4)
        #expect(plan.report.importedClips == 63)
        #expect(plan.report.truncatedClips == 0)
        #expect(plan.grids[0].name == "Match · pistes 1–6 · scènes 1–8")
        #expect(plan.grids[1].name == "Match · pistes 7–7 · scènes 1–8")
        #expect(plan.grids[3].name == "Match · pistes 7–7 · scènes 9–9")
        // Piste 7, scène 9 → grille 4, colonne 0, ligne 0.
        #expect(plan.grids[3][GridPosition(column: 0, row: 0)]?.title == "Clip 6-8")
    }

    @Test("Dépassement, troncature : seul le bloc 6 × 8 en haut à gauche, le reste est compté")
    func truncates() {
        let plan = build(fullSet(tracks: 7, scenes: 9), overflow: .truncate)
        #expect(plan.grids.count == 1)
        #expect(plan.report.importedClips == 48)
        #expect(plan.report.truncatedClips == 63 - 48)
    }

    @Test("Les blocs sans clip ne créent pas de grille")
    func skipsEmptyBlocks() {
        var set = fullSet(tracks: 1, scenes: 1)
        set.audioTracks[0].clips[20] = set.audioTracks[0].clips[0]  // scène 21 : bloc de scènes 3 ; blocs 2 vides
        let plan = build(set)
        #expect(plan.grids.count == 2)
    }

    @Test("Un set sans clip donne zéro grille (l'appelant décide quoi dire)")
    func noClips() {
        let plan = build(AbletonLiveSet())
        #expect(plan.grids.isEmpty)
        #expect(plan.report.importedClips == 0)
    }

    @Test("Limite de grilles : les clips en trop sont comptés, les sons des blocs écartés ne sont pas cherchés")
    func gridLimit() {
        var resolved: [String] = []
        let plan = AbletonShowBuilder.build(fullSet(tracks: 7, scenes: 1), baseName: "M", overflow: .splitIntoGrids, maximumGrids: 1) { ref in
            resolved.append(ref.fileName)
            return ref.fileName
        }
        #expect(plan.grids.count == 1)
        #expect(plan.report.clipsOverGridLimit == 1)
        #expect(!resolved.contains("6-0.wav"))
    }

    @Test("Son introuvable : le pad existe, muet, et le nom est signalé une fois")
    func missingSample() {
        var set = fullSet(tracks: 2, scenes: 1)
        set.audioTracks[1].clips[0]?.sample?.fileName = "disparu.wav"
        let plan = build(set) { $0 != "disparu.wav" }
        #expect(plan.report.missingSamples == ["disparu.wav"])
        #expect(plan.report.importedClips == 2)
        #expect(plan.grids[0][GridPosition(column: 1, row: 0)] != nil)
    }

    @Test("Clip sans fichier son : ignoré et compté ; piste MIDI : comptée")
    func clipWithoutSample() {
        var set = fullSet(tracks: 1, scenes: 2)
        set.audioTracks[0].clips[1]?.sample = nil
        set.ignoredMidiTrackCount = 2
        let plan = build(set)
        #expect(plan.report.importedClips == 1)
        #expect(plan.report.clipsWithoutSample == 1)
        #expect(plan.report.ignoredMidiTracks == 2)
        #expect(plan.report.summary.contains("MIDI"))
    }

    @Test("Boucle reprise ; titre long tronqué à 80 caractères ; nom de fichier dangereux nettoyé")
    func padDetails() throws {
        var set = AbletonLiveSet()
        let sample = AbletonSampleReference(relativePath: "", absolutePath: "/x/../a:b.wav", fileName: "a:b.wav")
        set.audioTracks = [AbletonAudioTrack(name: "P", clips: [0: AbletonClip(name: String(repeating: "x", count: 200), loops: true, sample: sample)])]
        let plan = build(set) { _ in false }
        let pad = try #require(plan.grids[0][GridPosition(column: 0, row: 0)])
        #expect(pad.title.count == 80)
        guard case .audio(let clip) = pad.content else { Issue.record("pad son attendu"); return }
        #expect(clip.loops)
        #expect(AudioClip.isSafeFileName(clip.fileName))
        #expect(clip.fileName == "a-b.wav")
    }

    @Test("La teinte est stable d'un import à l'autre")
    func stableTint() {
        #expect(AbletonShowBuilder.stableTint(for: "rire.wav") == AbletonShowBuilder.stableTint(for: "rire.wav"))
        #expect(AbletonShowBuilder.stableTint(for: "rire.wav") != .blanc)
    }
}
