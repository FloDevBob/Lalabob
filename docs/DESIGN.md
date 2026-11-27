# Maquette de Lalabob — description pour les agents de code

Maquette interactive d'origine (Claude Design) : https://claude.ai/artifact/B82jshC6LzSB3FBxi7cAia.
Les agents ne pouvant pas l'ouvrir, ce fichier en décrit tout ce qui compte pour l'implémentation.
Les valeurs de couleur et de dimension sont déjà dans `LalabobModel/Tint.swift` et `LalabobDesign/Theme.swift`.

## Principes

- **Vocabulaire** (27/11/2026) : voir `docs/LEXIQUE.md`. On parle de **lumières** et de **projecteurs** (« Relier », « Reliée ✓ », « Intensité »), jamais de cue, d'appairage, de note ou de CC dans l'interface ; les paragraphes plus bas qui gardent les anciens mots décrivent les mêmes écrans.

- Mode sombre uniquement. Fond de fenêtre `#0E0F12`, panneaux `#121317` / `#15161B`, creux `#0B0C0F`.
- Coins arrondis partout : pads 14 px, panneaux 18 px, boutons 8–12 px.
- Texte : SF Pro (système) ; logo « Lalabob » en police très arrondie (Fredoka, à intégrer au J5).
- Icônes : **Iconoir**, style regular (trait 1,5) — ADR 0005 ; projecteur et cadenas ouvert dessinés sur mesure dans le même style.
- Le texte d'un pad est une déclinaison très claire de sa teinte (`TintSpec.label`) sur un fond profond (`TintSpec.surface`) ; la couleur vive (`TintSpec.vivid`) est réservée aux LED et aux états actifs.

## Fenêtre principale (1600 × 1000 dans la maquette)

### Barre d'en-tête (56 px)
De gauche à droite : bouton masquer la bibliothèque · logo « Lalabob » + nom du spectacle ·
**onglets de grilles** au centre (pastille numérotée 1…n, nom, nombre de sons ; bouton +). Le **canal LightKey** de la grille n'est pas affiché
en permanence (décision du 25/11/2026, trop de place) : clic droit sur l'onglet › « Canal LightKey » (avec confirmation) ; l'infobulle de l'onglet le rappelle ·
(**Réglages du spectacle**, menu Spectacle, ⌥⌘, , déverrouillé : interrupteur « Colonnes lumière communes à toutes les grilles », canal commun,
confirmation qui liste ce qui est mis de côté grille par grille ; une colonne commune porte un petit badge ambré « Commune » dans son en-tête) ·
**sélecteur de contrôleur** (nom du modèle + pastille verte « Connecté ») · **sélecteur de sortie audio** (à ajouter) ·
**cadenas** Verrouillé / Déverrouillé (⌘L, remplace la bascule Édition / Live de la maquette) · bouton rouge **Tout arrêter** (raccourci Échap).

### Bibliothèque (colonne gauche, 272 px)
Champ de recherche · Favoris (dossiers épinglés) · liste des fichiers du dossier courant
(icône forme d'onde colorée, nom, durée en police mono, point turquoise si déjà sur la grille) ·
« Glissez un son sur un pad » · zone de **pré-écoute** en bas (bouton lecture, titre, mini forme d'onde).

### Grille (centre)
- **8 colonnes de même largeur**, dans leur ordre réel (plus de zone lumière à droite : une colonne lumière peut être n'importe où).
  Par défaut, les 6 premières sont des colonnes sons et les 2 dernières des colonnes lumière.
- En-tête de colonne : pastille de **type** (note de musique pour le son, projecteur ambre pour la lumière, **les deux** pour son et lumière),
  nom, numéro, et un **liseré** de 2 pt dans le bas de l'en-tête : blanc à 6 % pour un son, ambre plein pour la lumière, **ambre pointillé** pour son et lumière.
  - **Type de la colonne** (déverrouillé seulement) : la pastille est un bouton avec un petit chevron ; elle ouvre un popover (Son · Son et lumière · Lumière,
    avec une ligne d'explication chacun, la ligne devient la raison quand le choix est impossible). Le **clic droit** sur l'en-tête donne : Renommer… · Type de colonne ›
    (coche sur le type actuel, « … » sur les choix qui retireraient quelque chose) · Arrêter les sons de la colonne · Vider la colonne…. Verrouillé : seulement « Arrêter les sons ».
  - **Feuille de confirmation** quand un changement retire quelque chose : titre « Passer « Nom » en colonne Son ? », une ligne par catégorie avec pastille (rouge = supprimé,
    ambre = perd sa lumière ou son son, vert = reste tel quel) avec le nombre et les titres des pads, « Annulable avec ⌘Z. Aucun son en cours n'est arrêté » (ou quel son s'arrête net),
    boutons Annuler · [« Passer en Son et lumière » quand c'est la sortie sans perte] · **Convertir** (rouge). Un changement sans perte s'applique tout de suite.
  - Avec les **colonnes lumière communes** actives : une colonne commune ne change pas de type et aucune colonne ne devient lumière (le popover donne la raison).
- 8 pads par colonne, 56 px de haut : titre (13 px, demi-gras), sous-titre (11,5 px) + durée en mono.
  - Case vide : bordure pointillée blanche à 11 %, « + Déposer un son » (ou « + Nouvelle lumière »). **Colonne son et lumière** : la case est coupée en deux, « + Son »
    (un son déposé n'importe où fait un pad son) et « + Lumière » (bouton ambre : crée une lumière).
  - **Pad son et lumière** : une **capsule** (fond noir 30 %, contour blanc 6 %) à droite avec le bouton lecture / stop au-dessus de l'ampoule, 22 pt chacun (26 pt sur un grand pad) ;
    **côte à côte** sur un pad bas (< 54 pt), pour que la capsule tienne. L'ampoule ne lance **que la lumière** (« Essayer la lumière »). Pad « en attente de son » : badge ambre « + Son ».
    Son et lumière sont indépendants : le contour suit le son (ou la lumière allumée) ; pas de badge sur un pad bas (< 50 pt).
  - En lecture : contour et halo dans la couleur vive, mini-égaliseur animé, barre de progression de 3 px en bas.
  - En pause : contour atténué, icône pause, barre de progression figée et estompée.
  - Lumière active : contour + badge « ON ».
  - Sélectionné : contour blanc 2 px. Cible de dépôt : contour pointillé blanc ; badge « Copie » si ⌥.
- Sous chaque colonne : **fader vertical** (poignée blanche arrondie), vumètre (vert, ambre au-delà de 82 %),
  valeur en dB (sons) ou « Intensité 75 % » (lumière, icône soleil dont l'opacité suit le niveau ; le CC n'est plus affiché).
- Colonne son : à droite du fader, le **potard de filtre** (36 pt, 28 pt quand la piste des faders rétrécit). Repère au sommet = neutre ; un arc à la couleur de la colonne part du sommet
  vers la gauche (passe-bas : il reste les basses) ou vers la droite (passe-haut : il reste les aigus). Étiquette dessous, sur deux lignes : « Neutre », ou « Bas » / « Haut » et la coupure
  (« Bas 800 Hz », « Haut 2 kHz »). Glisser vers le haut ou la droite = passe-haut, vers le bas ou la gauche = passe-bas ; double-clic = neutre ; flèches du clavier ; VoiceOver réglable.
  Actif même verrouillé (on règle en jouant). Curseur : main ouverte / fermée, comme le fader. Le vumètre mesure après le filtre.

### Inspecteur (panneau du bas, s'ouvre quand on clique un pad) — solution B, décision du 31/10/2026

Deux bandes, au plus `Metrics.inspectorHeight` (196 px, ≈ 1/5 d'une fenêtre de régie). Aucune information n'apparaît deux
fois ; des filets verticaux séparent les groupes sans rapport.

**Bande du haut (52 px), pad son**, de gauche à droite :
1. Transport : **un seul bloc (capsule)** regroupant Lecture / Relancer (bouton rond à la couleur du pad), Pause (ambre
   quand le son est en pause), Stop et, après un filet, Boucle (verte si active) ; puis temps écoulé / durée utile en mono
   (pas de badge « PAUSE » : le bouton ambre suffit, décision du 01/11/2026).
2. Titre (gras) et sous-titre (double-clic pour renommer, Entrée valide, Échap annule).
3. À droite : nom du fichier d'origine (mono, discret, tronqué au milieu) · « Nouvel appui » + segmenté
   Relancer / Arrêter · **bouton couleur** (la pastille de la teinte en cours, **sans son nom**, plus une flèche) qui ouvre un
   **popover** avec les 16 teintes et l'intensité de la LED · menu « Actions »
   (couper, copier, coller, dupliquer, vider).

**Bande du bas (120 px)** : **jauge de volume du pad** (rail, poignée blanche arrondie, valeur en dB ; −60…+12 dB,
indépendante du fader de colonne, double-clic = 0 dB, **appliquée en direct, même sur un son qui joue**) puis la forme d'onde pleine
largeur (zones élaguées assombries, poignées d'élagage, tête de lecture). **Les fondus se règlent sur l'onde** (décision du
31/10/2026, retour d'essai : « très pratique ») : une puce « + Fondu » sous la courbe, en bas à gauche (entrée) et en bas à
droite (sortie) ; une fois actif, la puce affiche la durée (« 0,8 s ») avec une croix pour le retirer, et une poignée au
bout de la courbe pointillée en règle la durée en glissant (un seul ⌘Z). Il n'y a plus de bouton « Fondus ».

**Pad son et lumière** (colonne mixte) : même bande du haut que le pad son, plus un **groupe Lumière** après le titre (ampoule, « Reliée ✓ », bouton Tester = la cue seule)
et, à droite, un menu **Nouvel appui** unique (son : relancer ou arrêter ; lumière : allumer seulement ou basculer à chaque appui) et le **type du pad** en segmenté
[Son | Lumière | Les deux]. Écart avec la maquette (variante A) : pour tenir dans la largeur minimale, le canal n'est plus écrit dans le groupe (infobulle), les deux réglages « nouvel appui »
sont réunis dans un menu, et le nom du fichier est abrégé d'abord. Un pad son ou lumière d'une colonne mixte a aussi le segmenté « Type du pad ».

**Pad lumière** (ADR 0006) : une seule bande — titre, bouton **Essayer** et rappel de la note envoyée
à LightKey, puis couleur (popover) et actions. L'état allumé / éteint ne vient pas de l'inspecteur : il se lit sur le pad
(voir « Relier aux projecteurs » plus bas).

### Grilles Apple Music (27/11/2026, maquette https://claude.ai/artifact/D4SxFzh7BsjY6vbmTasWoZ, spec `docs/spec-grilles-apple-music.md`)
- **Créer** : le + des onglets propose « Sons et lumière » (⌘T) ou « Apple Music » (⌥⌘T) ; clic droit sur un onglet › Type de grille. Onglet marqué d'une
  note rose (`Surface.musicAccent`, #FF5A8C). Colonnes **Music** (liseré rose) et colonnes lumière.
- **Panneau de gauche** (déverrouillé) : état de Music (« Ouvrir Music », refus d'accès), bascule **Mes playlists / Internet**, recherche, dossiers de
  playlists repliables, morceaux (point rose = déjà sur une grille, ☁ = dans le nuage, ▶ = extrait de 30 s), « Téléchargés seulement »,
  « Télécharger les N », sélection Maj / ⌘, glisser (cases d'arrivée numérotées) ; interrupteur **« Son de Music par Lalabob »** et sa ligne de diagnostic.
- **Pad Music** : titre (morceau), sous-titre (artiste), bouton lecture / pause ; ☁ ambre ou « Introuvable » rouge ; lueur, progression et LED comme un son.
- **Sous une colonne Music** : carte « Volume : 9e fader » ; avec le pont audio, fader, vumètre et filtre comme une colonne son ; bouton ■ (fondu de sortie).
- **Panneau du bas** : lecture / pause, stop, temps, titre, morceau d'origine et playlist, **pochette** (116 pt), barre de position cliquable, ce qui n'est pas disponible.

## Interactions

- **Clic et double-clic (01/11/2026, verrouillé ou non)** : un **clic** sélectionne le pad (verrouillé : le panneau de jeu s'ouvre pour un son), un **double-clic** le joue ; seul le contrôleur physique joue d'un appui. Évite un départ de son sur un clic accidentel.
- **Cadenas fermé** (verrouillé) : le double-clic joue (jouer n'est pas modifier). Bibliothèque et inspecteur
  masqués ; glisser-déposer, presse-papiers, onglets et ⌘Z refusés, avec un bandeau « Spectacle verrouillé : ouvrez le cadenas (⌘L) ».
  Faders, changement d'onglet, Tout arrêter et contrôleur restent actifs.
- Un spectacle déjà enregistré s'ouvre verrouillé ; un nouveau spectacle s'ouvre déverrouillé.
- Glisser un fichier de la bibliothèque vers un pad : crée le pad (titre, sous-titre, couleur pré-remplis).
- Glisser un pad sur une autre case : déplace ou échange. Avec ⌥ : duplique.
- Les sons ne vont que dans les colonnes sons, les lumières que dans les colonnes lumière.
- ⌘X / ⌘C / ⌘V / ⌘D / ⌫ / ⌘Z ; Échap = Tout arrêter ; Espace = pause du pad sélectionné.

**Retouches du 31/10/2026** : cliquer ou glisser sur l'onde déplace la tête de lecture ; les actions du pad (Couper, Copier, Coller, Dupliquer, Vider) sont dans un menu à trois petits points qui affiche leurs raccourcis (⌘X ⌘C ⌘V ⌘D ⌘⌫).

**Menu contextuel d'un pad** (clic droit) : Lecture / Relancer, Pause / Reprendre, Arrêter, Boucle, Nouvel appui, Couleur,
puis Couper, Copier, Coller, Dupliquer, Vider avec leurs raccourcis. Verrouillé : seulement la lecture.

**Panneau du bas verrouillé** : même disposition, en lecture seule, affiché pour le dernier son lancé (il apparaît dès le
lancement d'une piste). Actifs : lecture / relance, pause, stop, tête de lecture sur l'onde, **volume du pad et fondus** (réglages de jeu).
Figés ou masqués : titre et sous-titre, couleur, actions, nouvel appui, boucle, élagage (poignées masquées).

**Barre du bas au repos** (02/11/2026) : la barre est toujours là (196 px), pour que la grille ne bouge pas. Quand il n'y a
aucun réglage à montrer (rien de sélectionné, case vide, ou verrouillé sans son lancé), elle affiche l'écran de repos :
une bande d'invite en haut (avec le menu d'actions si une case vide est sélectionnée), puis trois indicateurs —
**grille en cours** (nombre de sons, pads en lecture), **contrôleur et audio** (contrôleur branché, sortie audio),
**éclairage** (« Port Lalabob Lumière actif » : Lalabob ne peut pas savoir si LightKey écoute vraiment) — et une
**astuce** (ampoule ambre, flèches pour en changer, une différente à chaque retour). Les astuces suivent le cadenas :
certaines n'apparaissent que déverrouillé (préparer), une seule que verrouillé. Le mot « pad » est gardé partout ; la
première astuce l'explique. Un pad lumière affiche aussi les indicateurs et l'astuce sous son en-tête.
Textes des astuces : `App/Tips.swift`.

**Curseurs, infobulles et survol (01/11/2026)** : les boutons du système (bordés, menus, sélecteurs) gardent la flèche, comme
partout dans macOS ; la main (`.link`) n'est posée que sur les zones sans apparence de bouton (onglets, cadenas, transport,
pastilles de teinte, puces de fondu, lignes de la bibliothèque, flèches des astuces). Main ouverte / fermée (`.grabIdle` /
`.grabActive`) sur ce qu'on saisit : pads remplis (déverrouillé), faders, jauge de volume du pad. Double flèche
(`.columnResize`) sur les poignées d'élagage et de fondu. Curseur de texte sur les titres, sous-titres et noms de colonnes
quand on peut les renommer. Un contrôle verrouillé ou désactivé garde la flèche. Un léger éclaircissement (7 % de blanc, sans
animation) au survol des onglets, du cadenas, du transport et des lignes de la bibliothèque ; **jamais sur les pads ni les
vumètres**. Toute icône seule a une infobulle (verbe d'action, raccourci entre parenthèses) ; les actions cachées (double-clic,
glisser) sont annoncées ; un contrôle refusé parce que verrouillé dit pourquoi. Code : `LalabobDesign/Interaction.swift`
(`interactiveCursor`, `hoverHighlight`, `HelpText`).

**Relier aux projecteurs** (ex-« Appairage lumière », 01/11/2026, ADR 0006) : bouton « Relier » dans l'en-tête (déverrouillé). Barre du bas dédiée (196 px) : trois étapes (LightKey › External Control › Add Trigger…, appui sur un pad
ou clic sur son ampoule, nom de la cue), case cible, état « En attente des projecteurs… » / « Reliée ✓ », boutons « C'est relié », « Délier », « Terminer ». Cases lumière : pointillés ambrés ; cible : pointillés qui pulsent ;
appairée : contour plein ; ampoule ambrée en bas à droite de chaque case lumière. Cue allumée dans LightKey : contour, halo et ampoule à la couleur du pad ; éteinte : ampoule atténuée.
Les **faders** des colonnes lumière s'appairent de la même façon : la carte du fader a le même contour et une étiquette « Relier / En attente… / Relié ✓ » ; bouger le fader (main ou écran) le désigne comme cible. Échap reste « Tout arrêter » pendant l'appairage.

**Banc d'essai lumière** (Fenêtre ▸ Banc d'essai lumière, ⌥⌘L) : fenêtre d'essai séparée (état du contrôleur et des ports, grille 8×8 cliquable avec les numéros de note, journal en direct « Contrôleur → / → LightKey / LightKey → », bouton Copier, canal des clics). Ne coûte rien fenêtre fermée.

**Clavier dans la grille** (01/11/2026) : ← → ↑ ↓ changent de pad, Maj + flèche étend la sélection en rectangle, Espace / Retour jouent, ⌘C / ⌘X / ⌘V / ⌘D / ⌫ agissent sur la sélection.
