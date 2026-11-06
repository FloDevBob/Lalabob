import Foundation
import Testing

@testable import LalabobImport
@testable import LalabobModel

/// Un vrai Live Set de la troupe (Live 11.3.25) : 6 pistes audio, 2 pistes MIDI de lumières, 13 scènes, 53 clips audio.
/// Les valeurs attendues viennent de l'analyse du XML du fichier avec un script indépendant (Python).
@Suite("Vrai Live Set (BobEte.als)")
struct RealLiveSetTests {
    private func load() throws -> AbletonLiveSet {
        let url = try #require(Bundle.module.url(forResource: "BobEte", withExtension: "als", subdirectory: "Fixtures"))
        return try AbletonLiveSetReader.read(fileData: Data(contentsOf: url))
    }

    @Test("Structure : pistes, scènes, clips")
    func structure() throws {
        let set = try load()
        #expect(set.creator == "Ableton Live 11.3.25")
        #expect(set.audioTracks.map(\.name) == ["1-VoilaLEte", "Final", "3-sensuelle", "4-ActuEte", "5-Grotte", "6-Mer"])
        #expect(set.ignoredMidiTrackCount == 2)
        #expect(set.sceneCount == 13)
        #expect(set.clipCount == 53)
        #expect(set.audioTracks[0].clips.count == 9)
        // L'identifiant d'une case ne donne pas la scène (la 7e case de la piste 1 a l'Id 8) : c'est la position qui compte.
        #expect(Set(set.audioTracks[0].clips.keys) == Set(0...8))
        #expect(set.usedSceneCount == 10)
        #expect(set.exceedsSingleGrid)  // 10 scènes > 8
    }

    @Test("Références de son : chemin relatif qui sort du projet, chemin absolu, nom du fichier")
    func sampleReference() throws {
        let sample = try #require(try load().audioTracks[0].clips[0]?.sample)
        #expect(sample.relativePath == "../../bob play/Été/NegresseVerte-VoilaLEte.mp3")
        #expect(sample.absolutePath == "/Users/fcaillet/Music/bob play/Été/NegresseVerte-VoilaLEte.mp3")
        #expect(sample.fileName == "NegresseVerte-VoilaLEte.mp3")
    }

    @Test("Élagage, volume et boucle de clips choisis")
    func clips() throws {
        let tracks = try load().audioTracks
        func check(_ track: Int, _ slot: Int, _ name: String, loops: Bool = false, start: Double, end: Double?, gain: Double) throws {
            let clip = try #require(tracks[track].clips[slot])
            #expect(clip.name == name)
            #expect(clip.loops == loops)
            #expect(abs(clip.trimStart - start) < 0.01, "début de \(name)")
            if let end {
                let actual = try #require(clip.trimEnd)
                #expect(abs(actual - end) < 0.01, "fin de \(name)")
            } else {
                #expect(clip.trimEnd == nil, "fin de \(name)")
            }
            #expect(clip.gainDB == gain, "volume de \(name)")
        }
        try check(0, 0, "VoilaLEte", start: 0, end: 243.28, gain: 0)
        try check(0, 2, "Jain-Makeba", start: 0, end: nil, gain: 0)  // le clip va jusqu'à la fin du fichier
        try check(0, 3, "Gainsbourg-SeaSexSun", start: 0.448, end: 217.529, gain: 0)
        try check(0, 4, "Cassius-TootpToop", start: 0, end: 135.482, gain: -0.9)
        try check(2, 3, "Intrigue", start: 3.12, end: nil, gain: 5.1)
        try check(3, 7, "Boucle1", loops: true, start: 0, end: 6.881, gain: 0)  // clip warpé : battements convertis
        try check(4, 5, "ascenseur", start: 0, end: nil, gain: 0)  // warpé, fin = fin du fichier
        try check(5, 1, "Pluie", loops: true, start: 0.828, end: nil, gain: -2.8)
        try check(5, 2, "Nuit", start: 0.959, end: nil, gain: -10.5)
    }

    @Test("Construction : deux grilles (10 scènes), 53 pads, spectacle valide")
    func builds() throws {
        let set = try load()
        let plan = AbletonShowBuilder.build(set, baseName: "BobEte", overflow: .splitIntoGrids) { $0.fileName }
        #expect(plan.grids.count == 2)
        #expect(plan.report.importedClips == 53)
        #expect(plan.report.ignoredMidiTracks == 2)
        #expect(plan.report.missingSamples.isEmpty)
        try Show(name: "t", grids: plan.grids).validate()
        // Piste 4 (« 4-ActuEte »), scène 10 → seconde grille, colonne 3, ligne 1.
        #expect(plan.grids[1][GridPosition(column: 3, row: 1)] != nil)
        #expect(plan.grids[0].columns[3].name == "4-ActuEte")

        let truncated = AbletonShowBuilder.build(set, baseName: "BobEte", overflow: .truncate) { $0.fileName }
        #expect(truncated.grids.count == 1)
        #expect(truncated.report.truncatedClips > 0)
    }
}
