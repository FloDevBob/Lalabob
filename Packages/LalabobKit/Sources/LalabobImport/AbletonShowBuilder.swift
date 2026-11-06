import Foundation
import LalabobModel

/// Que faire quand le Live Set dépasse une grille (plus de 6 pistes audio ou plus de 8 scènes).
public enum LiveSetOverflow: Sendable {
    /// Découper en blocs de 6 pistes × 8 scènes : une grille (onglet) par bloc.
    case splitIntoGrids
    /// Ne garder que les 6 premières pistes et les 8 premières scènes.
    case truncate
}

/// Ce qui s'est passé à l'import, pour le montrer à l'utilisateur.
public struct AbletonImportReport: Equatable, Sendable {
    public var creator = ""
    public var gridCount = 0
    public var importedClips = 0
    /// Sons dont le fichier n'a pas été retrouvé : leurs pads sont créés mais muets.
    public var missingSamples: [String] = []
    /// Clips sans fichier son identifiable (ignorés).
    public var clipsWithoutSample = 0
    public var ignoredMidiTracks = 0
    /// Clips hors du bloc 6 × 8 gardé (choix « tronquer »).
    public var truncatedClips = 0
    /// Clips ignorés parce que le spectacle serait passé au-dessus de 64 grilles.
    public var clipsOverGridLimit = 0

    public init() {}

    /// Texte pour la fenêtre de compte rendu.
    public var summary: String {
        var lines = ["\(importedClips) clip(s) importé(s) dans \(gridCount) grille(s)."]
        if !missingSamples.isEmpty {
            let shown = missingSamples.prefix(8).joined(separator: ", ")
            let rest = missingSamples.count > 8 ? " et \(missingSamples.count - 8) autre(s)" : ""
            lines.append(
                "Sons introuvables (les pads restent muets) : \(shown)\(rest). "
                    + "Astuce : choisissez un dossier qui contient à la fois le projet Live et les sons, plutôt que le seul fichier .als.")
        }
        if clipsWithoutSample > 0 { lines.append("\(clipsWithoutSample) clip(s) sans fichier son ignoré(s).") }
        if ignoredMidiTracks > 0 { lines.append("\(ignoredMidiTracks) piste(s) MIDI ignorée(s) (non prises en charge).") }
        if truncatedClips > 0 { lines.append("\(truncatedClips) clip(s) au-delà de 6 pistes × 8 scènes ignoré(s).") }
        if clipsOverGridLimit > 0 {
            lines.append("\(clipsOverGridLimit) clip(s) ignoré(s) : le spectacle ne peut pas dépasser \(Show.maximumGridCount) grilles.")
        }
        lines.append("Repris : nom, boucle, élagage, volume (à vérifier à l'oreille). Non repris : fondus, couleurs, mode de déclenchement.")
        return lines.joined(separator: "\n")
    }
}

public struct AbletonImportPlan: Equatable, Sendable {
    public var grids: [PadGrid]
    public var report: AbletonImportReport
}

extension AbletonLiveSet {
    /// Colonnes son d'une grille par défaut (les deux dernières colonnes sont réservées à la lumière).
    public static let columnsPerGrid = 6
    public static let rowsPerGrid = PadGrid.size

    /// Le set ne tient pas dans une seule grille.
    public var exceedsSingleGrid: Bool {
        audioTracks.count > Self.columnsPerGrid || usedSceneCount > Self.rowsPerGrid
    }
}

/// Transforme un Live Set en grilles Lalabob. Pur : la recherche et la copie des sons sont faites par l'appelant
/// (`resolveSample`), ce qui garde ce module sans accès aux fichiers et testable tel quel.
///
/// Correspondances : piste audio → colonne son (de gauche à droite) ; scène → ligne (de haut en bas) ;
/// nom du clip → titre du pad ; interrupteur Loop → boucle ; marqueurs de début et de fin → élagage ; Clip Gain → volume du pad. La teinte est choisie d'après le nom du fichier,
/// comme pour un son glissé depuis le Finder. Les colonnes lumière restent vides.
public enum AbletonShowBuilder {
    /// Même longueur maximale que l'éditeur de pad (`ShowController.maximumTextLength`).
    static let maximumTextLength = 80

    /// - Parameters:
    ///   - baseName: nom du Live Set (nom de la grille, ou préfixe des grilles).
    ///   - maximumGrids: nombre de grilles qu'on peut encore ajouter au spectacle.
    ///   - resolveSample: renvoie le nom du fichier **dans `Audio/`** (après copie), ou `nil` si le son est introuvable.
    ///     Appelée au plus une fois par clip, uniquement pour les clips réellement importés.
    public static func build(
        _ liveSet: AbletonLiveSet,
        baseName: String,
        overflow: LiveSetOverflow,
        maximumGrids: Int = Show.maximumGridCount,
        resolveSample: (AbletonSampleReference) -> String?
    ) -> AbletonImportPlan {
        var report = AbletonImportReport()
        report.creator = liveSet.creator
        report.ignoredMidiTracks = liveSet.ignoredMidiTrackCount

        let perGridColumns = AbletonLiveSet.columnsPerGrid
        let perGridRows = AbletonLiveSet.rowsPerGrid
        let tracks = liveSet.audioTracks
        let trackBlocks = overflow == .truncate ? 1 : max(1, (tracks.count + perGridColumns - 1) / perGridColumns)
        let sceneBlocks = overflow == .truncate ? 1 : max(1, (liveSet.usedSceneCount + perGridRows - 1) / perGridRows)

        struct Block {
            var trackBlock: Int
            var sceneBlock: Int
            var clipCount: Int
        }
        func clips(in block: Block) -> [(column: Int, row: Int, track: AbletonAudioTrack, clip: AbletonClip)] {
            var found: [(column: Int, row: Int, track: AbletonAudioTrack, clip: AbletonClip)] = []
            for column in 0..<perGridColumns {
                let trackIndex = block.trackBlock * perGridColumns + column
                guard trackIndex < tracks.count else { break }
                for row in 0..<perGridRows {
                    if let clip = tracks[trackIndex].clips[block.sceneBlock * perGridRows + row] {
                        found.append((column, row, tracks[trackIndex], clip))
                    }
                }
            }
            return found
        }

        // 1. Quels blocs contiennent des clips ? (sans toucher aux fichiers)
        var blocks: [Block] = []
        for sceneBlock in 0..<sceneBlocks {
            for trackBlock in 0..<trackBlocks {
                var block = Block(trackBlock: trackBlock, sceneBlock: sceneBlock, clipCount: 0)
                block.clipCount = clips(in: block).count
                if block.clipCount > 0 { blocks.append(block) }
            }
        }
        let totalClips = liveSet.clipCount
        let keptBlocks = Array(blocks.prefix(max(maximumGrids, 0)))
        report.clipsOverGridLimit = blocks.dropFirst(keptBlocks.count).reduce(0) { $0 + $1.clipCount }
        report.truncatedClips = max(totalClips - blocks.reduce(0) { $0 + $1.clipCount }, 0)

        // 2. Construire les grilles (c'est là que les sons sont retrouvés et copiés).
        var grids: [PadGrid] = []
        for block in keptBlocks {
            var grid = PadGrid.empty(name: gridName(baseName, block.trackBlock, block.sceneBlock, tracks.count, liveSet.usedSceneCount, multiple: blocks.count > 1))
            for column in 0..<perGridColumns {
                let trackIndex = block.trackBlock * perGridColumns + column
                if trackIndex < tracks.count { grid.columns[column].name = String(tracks[trackIndex].name.prefix(maximumTextLength)) }
            }
            for item in clips(in: block) {
                guard let sample = item.clip.sample else {
                    report.clipsWithoutSample += 1
                    continue
                }
                let fileName: String
                if let resolved = resolveSample(sample) {
                    fileName = resolved
                } else {
                    fileName = AudioClip.safeFileName(from: sample.fileName)
                    if !report.missingSamples.contains(fileName) { report.missingSamples.append(fileName) }
                }
                grid.columns[item.column].slots[item.row] = pad(for: item.clip, fileName: fileName)
                report.importedClips += 1
            }
            grids.append(grid)
        }
        report.gridCount = grids.count
        return AbletonImportPlan(grids: grids, report: report)
    }

    static func pad(for clip: AbletonClip, fileName: String) -> Pad {
        let title = clip.name.isEmpty ? (fileName as NSString).deletingPathExtension : clip.name
        return Pad(
            title: String(title.prefix(maximumTextLength)),
            tint: stableTint(for: fileName),
            content: .audio(
                clip: AudioClip(
                    fileName: fileName, trimStart: clip.trimStart, trimEnd: clip.trimEnd, loops: clip.loops
                ).withGain(clip.gainDB))
        )
    }

    /// Même règle que `AudioImporter.pad(forFileName:)` : un son a toujours la même teinte, d'où qu'il vienne.
    static func stableTint(for fileName: String) -> Tint {
        let tints = Tint.allCases.filter { $0 != .blanc && $0 != .graphite }
        let index = fileName.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % tints.count
        return tints[index]
    }

    private static func gridName(_ base: String, _ trackBlock: Int, _ sceneBlock: Int, _ trackCount: Int, _ sceneCount: Int, multiple: Bool) -> String {
        let name = base.isEmpty ? "Live Set" : base
        guard multiple else { return name }
        let firstTrack = trackBlock * AbletonLiveSet.columnsPerGrid + 1
        let lastTrack = min((trackBlock + 1) * AbletonLiveSet.columnsPerGrid, trackCount)
        let firstScene = sceneBlock * AbletonLiveSet.rowsPerGrid + 1
        let lastScene = min((sceneBlock + 1) * AbletonLiveSet.rowsPerGrid, sceneCount)
        return "\(name) · pistes \(firstTrack)–\(lastTrack) · scènes \(firstScene)–\(lastScene)"
    }
}
