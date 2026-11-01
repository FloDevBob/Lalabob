import Foundation
import LalabobDesign

/// Le contenu de l'aide de Lalabob (menu Aide ▸ Aide de Lalabob). Du texte français, rangé en rubriques ;
/// `HelpView` l'affiche. Garder ce fichier d'accord avec `docs/GUIDE.md` et `docs/DESIGN.md`.
enum HelpBlock: Equatable {
    /// Un paragraphe (Markdown en ligne : **gras**, *italique*, `code`).
    case paragraph(String)
    /// Étapes numérotées.
    case steps([String])
    case bullets([String])
    /// Tableau « geste / effet » ; la première colonne s'affiche comme une touche.
    case shortcuts([(keys: String, effect: String)])
    /// Encadré d'attention.
    case warning(String)

    static func == (lhs: HelpBlock, rhs: HelpBlock) -> Bool {
        switch (lhs, rhs) {
        case (.paragraph(let a), .paragraph(let b)), (.warning(let a), .warning(let b)): a == b
        case (.steps(let a), .steps(let b)), (.bullets(let a), .bullets(let b)): a == b
        case (.shortcuts(let a), .shortcuts(let b)): a.elementsEqual(b) { $0 == $1 }
        default: false
        }
    }

    /// Tout le texte du bloc, pour la recherche.
    var searchableText: String {
        switch self {
        case .paragraph(let text), .warning(let text): text
        case .steps(let items), .bullets(let items): items.joined(separator: " ")
        case .shortcuts(let rows): rows.map { "\($0.keys) \($0.effect)" }.joined(separator: " ")
        }
    }
}

struct HelpTopic: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: Icon
    let blocks: [HelpBlock]

    /// La rubrique contient ce texte (sans tenir compte de la casse ni des accents).
    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        let haystack = ([title] + blocks.map(\.searchableText)).joined(separator: " ")
        return haystack.localizedStandardContains(query)
    }
}

enum HelpContent {
    static let topics: [HelpTopic] = [start, hardware, play, prepare, lighting, shortcuts, troubleshooting]

    static func topics(matching query: String) -> [HelpTopic] { topics.filter { $0.matches(query) } }

    // MARK: - Rubriques

    static let start = HelpTopic(
        id: "start", title: "Pour commencer", symbol: .music,
        blocks: [
            .paragraph(
                "Lalabob est la régie son et lumière de la troupe : une grille de 8 colonnes de 8 pads. Les **6 colonnes de gauche** lancent des sons, les **2 colonnes de droite** pilotent les cues de LightKey."),
            .steps([
                "Branchez votre contrôleur (**AKAI APC mini mk2** ou **Novation Launchpad Mini MK3**). L'indicateur vert « Connecté » apparaît en haut à droite.",
                "Choisissez la **sortie audio** dans la barre d'en-tête.",
                "Créez un spectacle (Fichier ▸ Nouveau) ou ouvrez un fichier `.lalabob`. Un spectacle enregistré s'ouvre **verrouillé** : c'est le mode jeu.",
                "Pour le préparer, ouvrez le cadenas (⌘L), puis glissez des sons sur les pads.",
            ]),
            .paragraph("Un spectacle est un seul fichier `.lalabob` qui contient aussi ses sons : pour le passer à l'autre Mac, copiez ce fichier."),
            .warning("Règle d'or : le son ne s'arrête jamais tout seul. Débrancher le contrôleur ne coupe rien."),
        ])

    static let hardware = HelpTopic(
        id: "hardware", title: "Votre matériel", symbol: .note,
        blocks: [
            .paragraph("Lalabob reconnaît seul le contrôleur branché. Les deux de la troupe sont pris en charge :"),
            .bullets([
                "**AKAI APC mini mk2** : grille 8×8 et **faders**. Les faders 1 à 8 règlent les colonnes (volume pour les sons, intensité pour les 2 colonnes lumière). Le **9ᵉ fader est ignoré** : il reste libre pour un autre logiciel (par exemple le volume d'Apple Music).",
                "**Novation Launchpad Mini MK3** : grille 8×8 sans fader. Lalabob le met en **mode Programmeur** à la connexion ; il y reste jusqu'au débranchement.",
            ]),
            .paragraph("Les 6 **boutons ronds rouges** sous les colonnes son de l'APC arrêtent les sons de leur colonne ; ceux des colonnes lumière restent éteints. Quand vous quittez Lalabob, le contrôleur est **éteint** et remis dans son mode d'origine."),
            .paragraph("Les LED du contrôleur reflètent l'écran : un pad allumé à la couleur de son pad, qui **pulse** quand le son joue, **atténué** en pause ou quand une cue lumière est éteinte, éteint pour une case vide."),
            .paragraph("**Couleurs pâles sur le Launchpad ?** Ses LED rendent les teintes de l'écran délavées. Cliquez sur le **nom du contrôleur** en haut à droite : l'**étalonnage des LED** règle saturation, profondeur (gamma) et luminosité, et les 64 LED suivent chaque mouvement. Le réglage est mémorisé. (L'APC mini mk2 a sa propre palette : rien à régler.) Sur l'**APC mini mk2**, le même panneau propose le mode **RVB libre** (essai) : les teintes de l'écran sont envoyées en couleurs libres et s'étalonnent de la même façon ; « Palette Akai » remet les couleurs d'origine."),
            .paragraph("Les faders se **raccrochent** : après un changement de grille, un fader physique n'agit qu'une fois revenu à la valeur affichée, pour que le volume ne saute pas."),
            .warning("Lalabob ne supporte pas deux contrôleurs en même temps. Si les deux sont branchés, le premier reconnu est utilisé."),
        ])

    static let play = HelpTopic(
        id: "play", title: "Jouer", symbol: .play,
        blocks: [
            .paragraph("Sur le **contrôleur**, un appui joue le pad. À la **souris**, un clic sélectionne et un **double-clic** joue : on ne lance jamais un son par un clic accidentel."),
            .bullets([
                "Un nouvel appui sur un son qui joue le **relance** depuis le début (réglable par pad : l'**arrêter**). Un son en pause **reprend**.",
                "**Échap** arrête tout, avec un fondu de 40 ms pour éviter le clac.",
                "Le bouton rond sur un pad lance ou arrête ce son (carré = arrêter).",
                "Le petit bouton rouge ■ à côté du volume d'une colonne arrête **tous ses sons** (joués ou en pause). Sur l'**APC mini mk2**, c'est le bouton rond rouge sous la colonne ; les colonnes lumière n'en ont pas.",
                "Les **vumètres** sous chaque colonne montrent le signal réel, après le fader.",
                "Changer de grille (onglets ou ⌘1 à ⌘9) ne coupe aucun son.",
            ]),
            .paragraph("Cadenas **fermé** : on peut jouer, régler les faders, le volume d'un pad et ses fondus, changer de grille et tout arrêter. Rien d'autre ne se modifie."),
        ])

    static let prepare = HelpTopic(
        id: "prepare", title: "Préparer un spectacle", symbol: .wave,
        blocks: [
            .paragraph("Ouvrez le cadenas (⌘L). La bibliothèque apparaît à gauche, le panneau de réglage en bas."),
            .steps([
                "**Ajouter un son** : glissez un fichier du Finder ou de la bibliothèque sur un pad. Le titre et la couleur sont pré-remplis.",
                "**Régler** : cliquez le pad. Le panneau du bas donne lecture, pause, boucle, volume du pad, fondus d'entrée et de sortie, et les poignées d'**élagage** sur la forme d'onde.",
                "**Renommer** : double-clic sur le titre ou le sous-titre, directement sur le pad. Entrée valide, Échap annule.",
                "**Déplacer** : glissez un pad sur une autre case (échange si elle est occupée). **⌥-glisser** copie.",
            ]),
            .bullets([
                "**Sélection multiple** : Maj + clic ou Maj + flèches (rectangle), ⌘ + clic (ajout / retrait). ⌘C, ⌘X, ⌘V, ⌘D et ⌫ agissent sur tout le groupe.",
                "**Annuler** : ⌘Z et ⇧⌘Z pour chaque opération.",
                "**Grilles** : le bouton + (ou ⌘T) ajoute une grille ; double-clic sur un onglet pour le renommer, glisser pour réordonner.",
                "**Pré-écoute** : double-clic sur un son de la bibliothèque (sur la sortie choisie, indisponible une fois verrouillé).",
                "**Enregistrer** : ⌘S ; l'enregistrement automatique est aussi actif. Un son qu'aucun pad n'utilise quitte le fichier.",
            ]),
        ])

    static let lighting = HelpTopic(
        id: "lighting", title: "Lumière et LightKey", symbol: .spotlight,
        blocks: [
            .paragraph("Lalabob crée un appareil MIDI virtuel nommé **« Lalabob Lumière »**. LightKey n'écoute que lui : Lalabob lui **relaie** les appuis et les faders des 2 colonnes de droite, et lit en retour l'état de chaque cue."),
            .steps([
                "Dans les réglages MIDI de LightKey, activez l'**entrée et la sortie** de « Lalabob Lumière ».",
                "**Désactivez** le contrôleur physique dans LightKey : sinon chaque cue bascule deux fois et semble ne rien faire.",
                "Dans Lalabob, déverrouillé, cliquez **Appairage** dans l'en-tête.",
            ]),
            .paragraph("**Appairer une cue** :"),
            .steps([
                "Dans LightKey : clic droit sur la cue ▸ External Control ▸ Add Trigger…",
                "Dans Lalabob : appuyez sur un pad des 2 colonnes de droite, ou cliquez son **ampoule**. La note part vers LightKey.",
                "Quand LightKey répond, la case est appairée. Nommez la cue : la case libre suivante s'arme. Si LightKey ne répond pas (une cue éteinte peut rester muette), cliquez **C'est appairé**.",
            ]),
            .paragraph("**Appairer un fader** : « Add Trigger… » sur le réglage dans LightKey, puis bougez le fader (du contrôleur ou à l'écran). **Terminer** quitte l'appairage ; Échap reste « Tout arrêter »."),
            .paragraph("**Sur la grille** : une cue **allumée** dans LightKey a un contour, un halo et une ampoule à la couleur du pad ; **éteinte**, l'ampoule est atténuée ; sans ampoule, LightKey n'a encore rien dit. La couleur réelle de la cue n'est pas transmise par LightKey : la teinte du pad est celle que vous avez choisie."),
            .warning("Aucun appairage en scène : verrouiller le spectacle quitte le mode d'appairage."),
            .paragraph("Pour voir ce qui circule, ouvrez **Fenêtre ▸ Banc d'essai lumière** (⌥⌘L) : on y envoie une note à la souris et on lit le journal contrôleur / Lalabob / LightKey."),
        ])

    static let shortcuts = HelpTopic(
        id: "shortcuts", title: "Raccourcis", symbol: .stopAll,
        blocks: [
            .shortcuts([
                ("Échap", "Tout arrêter"),
                ("Espace", "Pause / reprise du pad sélectionné (lecture s'il est à l'arrêt)"),
                ("Retour", "Lecture / relance du pad sélectionné"),
                ("← → ↑ ↓", "Passer d'un pad à l'autre"),
                ("⇧ + flèches", "Étendre la sélection en rectangle"),
                ("⌘L", "Verrouiller / déverrouiller"),
                ("⌘1 … ⌘9", "Aller à la grille 1 … 9"),
                ("⌘T", "Nouvelle grille"),
                ("⌘C  ⌘X  ⌘V", "Copier, couper, coller les pads sélectionnés"),
                ("⌘D", "Dupliquer (case libre en dessous)"),
                ("⌫", "Vider les pads sélectionnés"),
                ("⌘Z  ⇧⌘Z", "Annuler / rétablir"),
                ("⌘S", "Enregistrer"),
                ("⌥⌘L", "Banc d'essai lumière"),
                ("⌘?", "Cette aide"),
            ]),
            .paragraph("Les flèches, Espace, Retour et ⌘C / ⌘X / ⌘V / ⌫ agissent quand la grille a le focus : un clic sur un pad le lui donne."),
        ])

    static let troubleshooting = HelpTopic(
        id: "troubleshooting", title: "En cas de problème", symbol: .warning,
        blocks: [
            .bullets([
                "**Le contrôleur n'est pas reconnu** : vérifiez qu'il est branché en direct et attendez une seconde ; l'indicateur de l'en-tête passe au vert. Les LED reviennent seules après un rebranchement.",
                "**Les couleurs du contrôleur sont pâles ou fausses** : cliquez sur le nom du contrôleur dans l'en-tête et réglez l'étalonnage des LED (essayez « Réglage conseillé », puis montez le gamma).",
                "**Un pad n'allume pas sa LED** : changez de grille et revenez, ou rebranchez le contrôleur ; Lalabob renvoie alors toutes les LED.",
                "**Une cue lumière ne se lance pas ou semble ne rien faire** : LightKey écoute-t-il encore le contrôleur ? Il ne doit écouter que « Lalabob Lumière ».",
                "**Aucun état de cue sur les pads** : la **sortie** de « Lalabob Lumière » est-elle activée dans LightKey ? Le banc d'essai (⌥⌘L) doit afficher des lignes « LightKey → » quand on lance une cue.",
                "**Rien ne se passe au clic** : un clic sélectionne, le **double-clic** joue.",
                "**« Spectacle verrouillé »** : ouvrez le cadenas (⌘L) pour modifier.",
                "**Sons manquants à l'ouverture** : un message les liste ; leurs pads restent muets. Retrouvez les fichiers et glissez-les à nouveau.",
                "**Plus de son** : vérifiez la sortie audio choisie dans l'en-tête ; si elle a été débranchée, le son continue sur la sortie par défaut.",
            ]),
        ])
}
