// Fabrique `Entraînement.lalabob`, le spectacle du tutoriel (voir docs/tutoriel/spectacle-entrainement.md).
// Usage : swift run GenerateTrainingShow <dossier des sons préparés> <fichier .lalabob à écrire>
import Foundation
import LalabobModel

/// Un pad son du spectacle : fichier de `sons/prepares`, titre, sous-titre, boucle, volume du pad.
struct Sound {
    let file: String
    let title: String
    let subtitle: String
    var loops = false
    var gainDB: Double = 0
}

func column(_ name: String, tint: Tint, _ sounds: [Sound]) -> Column {
    var column = Column.empty(name: name, kind: .audio)
    for (row, sound) in sounds.enumerated() {
        let clip = AudioClip(fileName: sound.file, loops: sound.loops, gainDB: sound.gainDB)
        column.slots[row] = .sound(title: sound.title, subtitle: sound.subtitle, tint: tint, clip: clip)
    }
    return column
}

func grid(_ name: String, _ soundColumns: [Column]) -> PadGrid {
    var grid = PadGrid.empty(name: name)
    for (index, column) in soundColumns.enumerated() { grid.columns[index] = column }
    for index in PadGrid.defaultLightColumns.sorted() { grid.columns[index].name = "Lumière \(index - 5)" }
    return grid
}

// Les niveaux des fichiers sont déjà homogènes (CREDITS.md) ; le volume du pad compense les quelques sons
// que la limite de crête a laissés sous leur cible (au plus +4 dB, pour ne pas saturer le mélange).
let decouverte = grid("Découverte", [
    column("Ambiances", tint: .azur, [
        Sound(file: "pluie.m4a", title: "Pluie", subtitle: "Pluie douce", loops: true, gainDB: 4),
        Sound(file: "vent-arbres.m4a", title: "Vent dans les arbres", subtitle: "Brise d'été", loops: true, gainDB: 4),
        Sound(file: "foret-nuit.m4a", title: "Forêt la nuit", subtitle: "Grillons, nuit calme", loops: true),
        Sound(file: "rue-ville.m4a", title: "Rue de ville", subtitle: "Passants, voitures", loops: true),
        Sound(file: "cafe.m4a", title: "Café animé", subtitle: "Salle, vaisselle", loops: true),
        Sound(file: "bord-de-mer.m4a", title: "Bord de mer", subtitle: "Vagues", loops: true),
    ]),
    column("Bruitages", tint: .orange, [
        Sound(file: "tonnerre.m4a", title: "Tonnerre", subtitle: "Grondement grave", gainDB: 3),
        Sound(file: "porte-claque.m4a", title: "Porte qui claque", subtitle: "Claquement sec"),
        Sound(file: "pas-parquet.m4a", title: "Pas sur parquet", subtitle: "Quelqu'un entre", gainDB: 4),
        Sound(file: "verre-brise.m4a", title: "Verre brisé", subtitle: "Chute et éclats", gainDB: 3),
        Sound(file: "coups-de-feu-lointains.m4a", title: "Coups de feu", subtitle: "Au loin, trois coups"),
        Sound(file: "telephone-ancien.m4a", title: "Téléphone ancien", subtitle: "Sonnerie à cloche"),
    ]),
    column("Cinéma", tint: .violet, [
        Sound(file: "montee-tension.m4a", title: "Montée de tension", subtitle: "Suspense"),
        Sound(file: "coup-de-theatre.m4a", title: "Coup de théâtre", subtitle: "Impact grave", gainDB: 4),
        Sound(file: "whoosh.m4a", title: "Whoosh", subtitle: "Passage rapide"),
        Sound(file: "battements-coeur.m4a", title: "Battements de cœur", subtitle: "Angoisse", loops: true),
        Sound(file: "horloge.m4a", title: "Horloge", subtitle: "Tic-tac lent", loops: true, gainDB: 4),
    ]),
    column("Public", tint: .rose, [
        Sound(file: "applaudissements.m4a", title: "Applaudissements", subtitle: "Salle de concert", gainDB: 3),
        Sound(file: "rires.m4a", title: "Rires", subtitle: "Public conquis", gainDB: 4),
        Sound(file: "murmures-salle.m4a", title: "Murmures de salle", subtitle: "Avant le spectacle", loops: true),
        Sound(file: "oh-surprise.m4a", title: "« Oh ! »", subtitle: "Surprise du public"),
    ]),
    column("Transitions", tint: .ambre, [
        Sound(file: "cloche.m4a", title: "Cloche", subtitle: "Changement de scène", gainDB: 3),
        Sound(file: "gong.m4a", title: "Gong", subtitle: "Longue résonance"),
        Sound(file: "rate.m4a", title: "Raté !", subtitle: "Jingle comique"),
    ]),
    Column.empty(name: "À vous", kind: .audio),
])

let orage = grid("L'orage", [
    column("Ambiances", tint: .indigo, [
        Sound(file: "pluie-forte.m4a", title: "Pluie forte", subtitle: "Averse", loops: true, gainDB: 3),
        Sound(file: "vent-hurle.m4a", title: "Vent qui hurle", subtitle: "Tempête", loops: true),
        Sound(file: "horloge-orage.m4a", title: "Horloge", subtitle: "Dans la maison", loops: true),
    ]),
    column("Bruitages", tint: .ciel, [
        Sound(file: "tonnerre-proche.m4a", title: "Tonnerre proche", subtitle: "Éclair et fracas"),
        Sound(file: "volet-claque.m4a", title: "Volet qui claque", subtitle: "Vent et volet", gainDB: 4),
        Sound(file: "chiens-au-loin.m4a", title: "Chiens au loin", subtitle: "Aboiements"),
    ]),
])

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage : GenerateTrainingShow <sons préparés> <sortie.lalabob>\n".utf8))
    exit(2)
}
let soundsFolder = URL(fileURLWithPath: arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: arguments[2])

let show = Show(name: "Entraînement", grids: [decouverte, orage])
try show.validate()

var added: [String: FileWrapper] = [:]
for name in show.usedAudioFileNames.sorted() {
    let url = soundsFolder.appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: url.path) else {
        FileHandle.standardError.write(Data("Son introuvable : \(url.path)\n".utf8))
        exit(1)
    }
    // Lu tout de suite : les sons peuvent venir du spectacle qu'on est en train de remplacer (son dossier Audio/).
    added[name] = try FileWrapper(url: url, options: .immediate)
}

let package = try ShowPackage.wrapper(for: show, audio: nil, adding: added)
if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
try package.write(to: output, options: .atomic, originalContentsURL: nil)

// Relecture comme à l'ouverture dans l'app : décodage, validation, sons présents.
let reread = try ShowPackage.read(try FileWrapper(url: output))
guard reread.show == show, reread.missingAudio.isEmpty else {
    FileHandle.standardError.write(Data("Relecture différente ou sons manquants : \(reread.missingAudio)\n".utf8))
    exit(1)
}
let pads = show.grids.flatMap(\.columns).flatMap(\.slots).compactMap { $0 }.count
print("Écrit : \(output.path) — \(show.grids.count) grilles, \(pads) pads, \(reread.audioFileNames.count) sons, format v\(show.formatVersion)")
