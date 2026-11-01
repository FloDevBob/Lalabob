import Foundation

/// Une astuce d'utilisation, affichée dans l'écran de repos de la barre du bas.
struct Tip: Identifiable, Equatable, Sendable {
    /// Dans quel mode l'astuce a du sens : verrouillé (on joue), déverrouillé (on prépare), ou les deux.
    enum Mode: Sendable {
        case always, unlockedOnly, lockedOnly
    }

    let id: String
    let title: String
    let text: String
    /// Raccourcis montrés comme de petites touches de clavier.
    let keys: [String]
    let mode: Mode

    func applies(locked: Bool) -> Bool {
        switch mode {
        case .always: true
        case .unlockedOnly: !locked
        case .lockedOnly: locked
        }
    }
}

/// Les astuces, en langage simple pour quelqu'un qui découvre l'app. Le mot « pad » est expliqué dans la première.
enum Tips {
    static let all: [Tip] = [
        Tip(
            id: "pad", title: "C'est quoi, un pad ?",
            text: "Un pad, c'est une case de la grille, comme les boutons lumineux de votre Launchpad. Il joue un son, ou envoie une commande à la lumière.",
            keys: [], mode: .always),
        Tip(
            id: "cadenas", title: "Verrouillez pour jouer",
            text: "Cadenas fermé, c'est le mode spectacle : vous pouvez jouer, mais plus rien ne se déplace ni ne s'efface par erreur.",
            keys: ["⌘L"], mode: .always),
        Tip(
            id: "verrouille-reglages", title: "Même verrouillé, vous gardez la main",
            text: "Le volume du son en cours, ses entrées et sorties en douceur, les curseurs, la grille active et « Tout arrêter » restent réglables.",
            keys: [], mode: .lockedOnly),
        Tip(
            id: "double-clic", title: "Un clic choisit, un double-clic joue",
            text: "Aucun son ne part par accident : il faut deux clics pour lancer un pad.",
            keys: [], mode: .always),
        Tip(
            id: "clavier", title: "Tout au clavier",
            text: "Espace met en pause ou reprend le pad choisi. Retour le lance, ou le relance depuis le début.",
            keys: ["espace", "retour"], mode: .always),
        Tip(
            id: "echap", title: "Un souci en scène ?",
            text: "Tout s'arrête en douceur, sans « clac ».",
            keys: ["échap"], mode: .always),
        Tip(
            id: "grilles", title: "Une grille par scène",
            text: "Passez d'une grille à l'autre avec ⌘ et son numéro.",
            keys: ["⌘1 à ⌘9"], mode: .always),
        Tip(
            id: "copier", title: "Copier un pad d'un geste",
            text: "Gardez Option enfoncée en glissant un pad pour en faire une copie. Sans Option, vous le déplacez.",
            keys: ["⌥ + glisser"], mode: .unlockedOnly),
        Tip(
            id: "multi", title: "Plusieurs pads d'un coup",
            text: "Sélectionnez toute une série de pads d'un coup, ou ajoutez-les un par un à la sélection.",
            keys: ["⇧ clic", "⌘ clic"], mode: .unlockedOnly),
        Tip(
            id: "renommer", title: "Renommer en deux clics",
            text: "Double-cliquez sur le nom d'un pad, ou d'une colonne, pour le changer.",
            keys: [], mode: .unlockedOnly),
        Tip(
            id: "nouvel-appui", title: "Et si on rappuie sur un son en cours ?",
            text: "Choisissez pour chaque pad : il repart du début, ou il s'arrête.",
            keys: [], mode: .unlockedOnly),
        Tip(
            id: "fondus", title: "Des entrées et des sorties tout en douceur",
            text: "Sous la courbe du son, cliquez sur « + Fondu » : à gauche pour une entrée progressive, à droite pour une sortie progressive. Glissez la poignée pour régler la durée.",
            keys: [], mode: .always),
        Tip(
            id: "volume-pad", title: "Un volume propre à chaque pad",
            text: "Il est séparé du curseur de la colonne. Double-cliquez dessus pour revenir à la valeur d'origine. Le changement s'entend tout de suite, même pendant la lecture.",
            keys: [], mode: .always),
    ]

    /// Les astuces qui ont du sens dans le mode courant.
    static func visible(locked: Bool) -> [Tip] {
        all.filter { $0.applies(locked: locked) }
    }
}
