# Maquette de Lalabob — description pour les agents de code

Maquette interactive d'origine (Claude Design) : https://claude.ai/artifact/B82jshC6LzSB3FBxi7cAia.
Les agents ne pouvant pas l'ouvrir, ce fichier en décrit tout ce qui compte pour l'implémentation.
Les valeurs de couleur et de dimension sont déjà dans `LalabobModel/Tint.swift` et `LalabobDesign/Theme.swift`.

## Principes

- Mode sombre uniquement. Fond de fenêtre `#0E0F12`, panneaux `#121317` / `#15161B`, creux `#0B0C0F`.
- Coins arrondis partout : pads 14 px, panneaux 18 px, boutons 8–12 px.
- Texte : SF Pro (système) ; logo « Lalabob » en police très arrondie (Fredoka, à intégrer au J5).
- Icônes : Phosphor, style **Fill** (arrondies, « joufflues ») ; projecteur dessiné sur mesure pour la lumière.
- Le texte d'un pad est une déclinaison très claire de sa teinte (`TintSpec.label`) sur un fond profond (`TintSpec.surface`) ; la couleur vive (`TintSpec.vivid`) est réservée aux LED et aux états actifs.

## Fenêtre principale (1600 × 1000 dans la maquette)

### Barre d'en-tête (56 px)
De gauche à droite : bouton masquer la bibliothèque · logo « Lalabob » + nom du spectacle ·
**onglets de grilles** au centre (pastille numérotée 1…n, nom, nombre de sons ; bouton +) ·
**sélecteur de contrôleur** (nom du modèle + pastille verte « Connecté ») · **sélecteur de sortie audio** (à ajouter) ·
**cadenas** Verrouillé / Déverrouillé (⌘L, remplace la bascule Édition / Live de la maquette) · bouton rouge **Tout arrêter** (raccourci Échap).

### Bibliothèque (colonne gauche, 272 px)
Champ de recherche · Favoris (dossiers épinglés) · liste des fichiers du dossier courant
(icône forme d'onde colorée, nom, durée en police mono, point turquoise si déjà sur la grille) ·
« Glissez un son sur un pad » · zone de **pré-écoute** en bas (bouton lecture, titre, mini forme d'onde).

### Grille (centre)
- 6 colonnes **sons** puis, dans une zone légèrement ambrée (bordure `#FFC93D` à 12 %), 2 colonnes **lumière**.
- En-tête de colonne : pastille icône (note de musique, ou projecteur ambre pour la lumière), nom, numéro.
- 8 pads par colonne, 56 px de haut : titre (13 px, demi-gras), sous-titre (11,5 px) + durée en mono.
  - Case vide : bordure pointillée blanche à 11 %, « + Déposer un son » (ou « + Nouvelle cue »).
  - En lecture : contour et halo dans la couleur vive, mini-égaliseur animé, barre de progression de 3 px en bas.
  - En pause : contour atténué, icône pause, barre de progression figée et estompée.
  - Lumière active : contour + badge « ON ».
  - Sélectionné : contour blanc 2 px. Cible de dépôt : contour pointillé blanc ; badge « Copie » si ⌥.
- Sous chaque colonne : **fader vertical** (poignée blanche arrondie), vumètre (vert, ambre au-delà de 82 %),
  valeur en dB (sons) ou en % + CC (lumière, icône soleil dont l'opacité suit le niveau).

### Inspecteur (panneau du bas, s'ouvre quand on clique un pad)
En-tête : pastille de la teinte, titre, sous-titre, position (« Bruitages · ligne 6 · note 61 »), actions Couper / Copier / Coller / Dupliquer / Vider.

**Pad son**, 3 zones :
1. Transport : grand bouton rond Lecture (ou Relancer pendant la lecture), **Pause / Reprendre**, Stop ;
   temps écoulé / durée utile ; badge « En pause » ; nom du fichier + format ; interrupteurs Fondu entrée,
   Fondu sortie, Boucle ; segmenté « Nouvel appui : Relancer / Arrêter ».
2. Forme d'onde pleine largeur : règle de temps, zones élaguées assombries, **poignées d'élagage** début / fin
   déplaçables, courbes de fondu en pointillés, **tête de lecture** blanche qui avance.
3. Couleur du pad : grille de 16 pastilles (fond + point vif), vélocités Novation / APC, segmenté d'intensité LED (Pastel, 100 %, 50 %, 25 %).

**Pad lumière** : bouton Tester ; comportement Impulsion / Bascule / Maintenu (+ explication) ; retour LED ;
traduction MIDI « Entrée (contrôleur, note) → Sortie (port Lalabob Lumière, note/canal/vélocité) » ; CC du fader ; couleur.

## Interactions

- **Cadenas fermé** (verrouillé) : un clic sur un pad agit comme un appui sur le contrôleur. Bibliothèque et inspecteur
  masqués ; glisser-déposer, presse-papiers, onglets et ⌘Z refusés, avec un bandeau « Spectacle verrouillé : ouvrez le cadenas (⌘L) ».
  Faders, changement d'onglet, Tout arrêter et contrôleur restent actifs.
- **Cadenas ouvert** : un clic sélectionne le pad (inspecteur) sans le jouer ; un double-clic le joue pour l'écouter.
- Un spectacle déjà enregistré s'ouvre verrouillé ; un nouveau spectacle s'ouvre déverrouillé.
- Glisser un fichier de la bibliothèque vers un pad : crée le pad (titre, sous-titre, couleur pré-remplis).
- Glisser un pad sur une autre case : déplace ou échange. Avec ⌥ : duplique.
- Les sons ne vont que dans les colonnes sons, les cues que dans les colonnes lumière.
- ⌘X / ⌘C / ⌘V / ⌘D / ⌫ / ⌘Z ; Échap = Tout arrêter ; Espace = pause du pad sélectionné.
