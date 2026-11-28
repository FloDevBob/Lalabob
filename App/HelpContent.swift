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
    static let topics: [HelpTopic] = [start, hardware, play, prepare, appleMusic, lighting, dmxLighting, shortcuts, troubleshooting]

    static func topics(matching query: String) -> [HelpTopic] { topics.filter { $0.matches(query) } }

    // MARK: - Rubriques

    static let start = HelpTopic(
        id: "start", title: "Pour commencer", symbol: .music,
        blocks: [
            .paragraph(
                "Lalabob est la régie son et lumière de la troupe : une grille de 8 colonnes de 8 pads. Les **6 colonnes de gauche** lancent des sons, les **2 colonnes de droite** allument et éteignent les **projecteurs**."),
            .steps([
                "Branchez votre contrôleur (**AKAI APC mini mk2** ou **Novation Launchpad Mini MK3**). L'indicateur vert « Connecté » apparaît en haut à droite.",
                "Choisissez la **sortie audio** dans la barre d'en-tête.",
                "Créez un spectacle (Fichier ▸ Nouveau) ou ouvrez un fichier `.lalabob`. Un spectacle enregistré s'ouvre **verrouillé** : c'est le mode jeu.",
                "Pour le préparer, ouvrez le cadenas (⌘L), puis glissez des sons sur les pads.",
            ]),
            .paragraph("Un spectacle est un seul fichier `.lalabob` qui contient aussi ses sons : pour le passer à l'autre Mac, copiez ce fichier."),
            .paragraph("**Vous découvrez Lalabob ?** Faites la **visite guidée** (Aide ▸ Visite guidée) : cinq minutes sur une copie de Lalabob, avec de vrais sons. Puis entraînez-vous sur le spectacle d'entraînement (Aide ▸ Ouvrir le spectacle d'entraînement), que vous pouvez modifier sans risque."),
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
            .paragraph("Les LED du contrôleur reflètent l'écran : un pad allumé à la couleur de son pad, qui **pulse** quand le son joue, **atténué** en pause ou quand une lumière est éteinte, éteint pour une case vide."),
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
                "Les **vumètres** sous chaque colonne montrent le signal réel, après le fader et le filtre.",
                "Le **potard de filtre**, à droite du fader de chaque colonne son : au centre (« Neutre »), le son est intact ; en le tournant vers la **gauche**, les aigus disparaissent et il reste les basses (« Bas 800 Hz ») ; vers la **droite**, les basses disparaissent et il reste les aigus (« Haut 2 kHz »). Glissez vers le haut ou le bas, ou utilisez les flèches ; un **double-clic** le ramène au neutre en douceur (en 1,5 s : le son s'ouvre progressivement). Il se règle aussi cadenas fermé.",
                "Changer de grille (onglets ou ⌘1 à ⌘9) ne coupe aucun son.",
            ]),
            .paragraph("Cadenas **fermé** : on peut jouer, régler les faders et les filtres, le volume d'un pad et ses fondus, changer de grille et tout arrêter. Rien d'autre ne se modifie."),
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

    static let appleMusic = HelpTopic(
        id: "apple-music", title: "Grilles Apple Music", symbol: .music,
        blocks: [
            .paragraph("Une **grille Apple Music** joue des morceaux de vos playlists dans l'app Music, un à la fois. Music doit être ouvert sur ce Mac."),
            .steps([
                "**Créer** : bouton + des onglets › Apple Music (⌥⌘T). Une note rose marque l'onglet.",
                "**Remplir** : déverrouillé, choisissez une playlist à gauche, sélectionnez des morceaux (Maj-clic, ⌘-clic) et glissez-les sur une colonne Music.",
                "**Écouter avant** : ▶ joue un extrait de 30 s sans toucher à Music. L'onglet **Internet** cherche dans tout Apple Music ; « Ajouter… » ouvre le morceau dans Music pour l'ajouter.",
                "**Jouer** : un appui lance le morceau, un autre l'arrête (fondu d'une seconde) ; l'appui suivant repart du début. La **pause** est dans la barre du bas (et Espace) ; un appui sur un morceau en pause le reprend. Un autre pad enchaîne en fondu. ■ sous la colonne arrête en fondu, Échap arrête tout.",
            ]),
            .bullets([
                "**Volume** : celui de Music, réglé par le 9e fader de l'APC. Pas de volume par pad, pas de fondus ni d'élagage (morceaux protégés).",
                "**☁ sur un pad** : le morceau est dans le nuage, Internet est nécessaire. Téléchargez-le avant la représentation (« Télécharger » dans le panneau).",
                "**Introuvable** : le morceau n'est plus dans votre bibliothèque ; glissez-en un autre sur le pad.",
                "**Son de Music par Lalabob** : interrupteur du panneau. Le morceau sort par Lalabob, dans sa colonne (fader, filtre, vumètre, sortie choisie). macOS demande l'autorisation d'enregistrement audio. Si la capture s'arrête, Music redevient audible tout seul.",
            ]),
        ])

    static let lighting = HelpTopic(
        id: "lighting", title: "La lumière", symbol: .spotlight,
        blocks: [
            .paragraph("Les **2 colonnes de droite** commandent les **projecteurs** : chaque pad est une **lumière** (« Plein feu », « Douche bleue »). Un appui l'allume ou l'éteint ; le **fader** en dessous règle l'**intensité**. Sur la grille, une lumière **allumée** a un contour, un halo et une ampoule à la couleur du pad ; **éteinte**, l'ampoule est atténuée."),
            .paragraph("Ce qui suit vaut pour le mode **Logiciel lumière**. Pour piloter la barre directement par un boîtier USB-DMX, voir la rubrique « Projecteurs pilotés par Lalabob »."),
            .paragraph("Les lumières elles-mêmes se préparent dans le **logiciel des projecteurs** (LightKey). Lalabob lui envoie le bon signal et lit en retour ce qui est allumé. La couleur réelle des projecteurs n'est pas connue de Lalabob : la teinte du pad est celle que vous avez choisie."),
            .paragraph("**Mise en route** (une fois, dans LightKey) :"),
            .steps([
                "Dans les réglages MIDI de LightKey, activez l'**entrée et la sortie** « Lalabob Lumière ».",
                "**Désactivez** le contrôleur (APC ou Launchpad) dans LightKey : sinon chaque appui compte deux fois et semble ne rien faire.",
            ]),
            .paragraph("**Relier un pad aux projecteurs** (cadenas ouvert) :"),
            .steps([
                "Cliquez **Relier** dans l'en-tête.",
                "Dans LightKey : clic droit sur la lumière ▸ External Control ▸ Add Trigger…",
                "Dans Lalabob : appuyez sur le pad (ou cliquez son **ampoule**).",
                "Quand les projecteurs répondent, le pad est **relié** : nommez la lumière, la case suivante est prête. S'ils ne répondent pas (une lumière éteinte peut rester muette), cliquez **C'est relié**.",
            ]),
            .paragraph("**Relier un fader d'intensité** : « Add Trigger… » sur le réglage dans LightKey, puis bougez le fader (sur le contrôleur ou à l'écran). **Terminer** quitte le mode ; Échap reste « Tout arrêter »."),
            .warning("On ne relie rien en scène : fermer le cadenas termine le mode « Relier »."),
            .paragraph("Pour les curieux : **Fenêtre ▸ Banc d'essai lumière** (⌥⌘L) montre les signaux MIDI échangés avec LightKey (notes, canal)."),
        ])

    static let dmxLighting = HelpTopic(
        id: "dmx-lighting", title: "Projecteurs pilotés par Lalabob", symbol: .spotlight,
        blocks: [
            .paragraph("Pour une petite salle, Lalabob peut piloter lui-même la barre de projecteurs (4 projecteurs RVB) par un **boîtier USB-DMX**, sans LightKey. Chaque spectacle choisit : **Logiciel lumière** ou **Projecteurs pilotés par Lalabob**. On peut changer de mode sans rien perdre."),
            .paragraph("**Mise en route** (une fois) :"),
            .steps([
                "Branchez le boîtier USB-DMX et la barre. Sur la barre : MENU ▸ `15Ch`, puis l'adresse de départ (celle de la troupe : **050**).",
                "Spectacle ▸ **Réglages du spectacle…** (cadenas ouvert) ▸ **Projecteurs pilotés par Lalabob**. Réglez l'**adresse**, le **boîtier** de ce Mac, le **fondu du noir**, l'**avance de la lumière** et **En quittant Lalabob**.",
                "Cliquez **Essayer : 4 projecteurs en blanc**. La pastille « Projecteurs » de l'en-tête indique l'état du boîtier.",
            ]),
            .paragraph("**Les pads lumière** décrivent un état des projecteurs, réglé dans le panneau du bas :"),
            .bullets([
                "**Couleurs** : *Chacun* (une couleur par projecteur) ou *Ensemble*. Roue des couleurs (teinte et saturation), couleurs favorites du spectacle, **strobo** (arrêté par défaut) et fondu d'entrée.",
                "**Alternance** : deux couleurs qui basculent au tempo du dernier son lancé (détecté automatiquement), ou au tempo de repli du pad sans son.",
                "**Programme** : l'un des 12 programmes de la barre. **Sur le son** : la barre suit le son avec son micro.",
                "**Aperçu** : chaque réglage s'applique tout de suite à la barre ; en quittant le pad, elle revient en fondu à la lumière d'avant.",
                "Un pad sans état précis allume les 4 projecteurs à la couleur du pad.",
            ]),
            .paragraph("**En jeu** : un appui joue l'état du pad avec son fondu. Clic droit sur la carte d'un fader lumière pour choisir son **rôle** : **Général** (intensité), **Couleurs** (fait tourner la roue), **Strobo** ou Aucun. Il n'y a qu'un Général et qu'un fader Couleurs pour tout le spectacle : changer de grille ne change jamais la lumière. La carte Général montre la mini-barre (clic sur un projecteur = le couper ou le rallumer) et le bouton **Noir**. Sur l'APC, le bouton rond d'une colonne lumière est aussi **Noir**. Échap ne touche jamais à la lumière."),
            .warning("LightKey et Lalabob ne doivent jamais piloter le boîtier en même temps : les deux envoient à la barre sans aucune erreur affichée. En mode Projecteurs, fermez LightKey."),
            .warning("Strobo : les flashs rapides peuvent déclencher des crises chez les personnes photosensibles. Prévenez la salle et n'allez pas au-delà de ce qui a été essayé en répétition."),
            .paragraph("Si le boîtier est débranché en jeu, aucun son ne s'arrête ; la lumière reprend au rebranchement. La barre garde sa dernière couleur si Lalabob se ferme brutalement. **Fenêtre ▸ Banc d'essai DMX** permet d'essayer canal par canal (il prend la main sur la sortie du spectacle tant qu'il est ouvert)."),
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
                "**Une lumière ne s'allume pas, ou s'allume puis s'éteint aussitôt** : dans LightKey, le contrôleur est-il encore activé ? LightKey ne doit écouter que « Lalabob Lumière ».",
                "**Les pads ne montrent jamais si la lumière est allumée** : dans LightKey, la **sortie** « Lalabob Lumière » est-elle activée ? Le banc d'essai (⌥⌘L) doit afficher des lignes « LightKey → » quand on allume une lumière.",
                "**Projecteurs pilotés par Lalabob : rien ne s'allume** : la pastille « Projecteurs » de l'en-tête est-elle en erreur ? Vérifiez le boîtier, l'adresse (identique sur la barre et dans les réglages) et le mode 15Ch de la barre, puis essayez « 4 projecteurs en blanc ».",
                "**La lumière fait des choses étranges** : LightKey est-il encore ouvert et relié au boîtier ? Fermez-le.",
                "**Rien ne se passe au clic** : un clic sélectionne, le **double-clic** joue.",
                "**« Spectacle verrouillé »** : ouvrez le cadenas (⌘L) pour modifier.",
                "**Sons manquants à l'ouverture** : un message les liste ; leurs pads restent muets. Retrouvez les fichiers et glissez-les à nouveau.",
                "**Plus de son** : vérifiez la sortie audio choisie dans l'en-tête ; si elle a été débranchée, le son continue sur la sortie par défaut.",
            ]),
        ])
}
