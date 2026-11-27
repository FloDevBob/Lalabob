# Plan — Lumière autonome en DMX (J14, à l'étude)

État : **proposition du 27/11/2026**, maquette faite, rien n'est codé. Les questions ouvertes sont en fin de page.
Maquette (27/11/2026) : https://claude.ai/artifact/CZZXroPPftVsPD9Zkd8CTT — planches :
- [Colonnes lumière + carte de jeu](https://claude.ai/artifact/CZZXroPPftVsPD9Zkd8CTT#artboard-Main) · [Tous les types de pads](https://claude.ai/artifact/CZZXroPPftVsPD9Zkd8CTT#artboard-TypesDePads)
- Panneau du bas : [Couleurs, chacun](https://claude.ai/artifact/CZZXroPPftVsPD9Zkd8CTT#artboard-Inspecteur) · [Couleurs, ensemble](https://claude.ai/artifact/CZZXroPPftVsPD9Zkd8CTT#artboard-InspEnsemble) ·
  [Alternance](https://claude.ai/artifact/CZZXroPPftVsPD9Zkd8CTT#artboard-InspAlternance) · [Programme](https://claude.ai/artifact/CZZXroPPftVsPD9Zkd8CTT#artboard-InspProgramme) · [Sur le son](https://claude.ai/artifact/CZZXroPPftVsPD9Zkd8CTT#artboard-InspSon)
- [Réglages du spectacle](https://claude.ai/artifact/CZZXroPPftVsPD9Zkd8CTT#artboard-Reglages)
- Page « Pistes · commandes de la barre » : pistes A à D ; **retenue : [piste C](https://claude.ai/artifact/CZZXroPPftVsPD9Zkd8CTT#artboard-PisteC)** (voir plus bas).
  La planche « Colonnes lumière + carte de jeu » (carte fusionnée sur deux colonnes) est **remplacée** par la piste C.

## L'idée

Aujourd'hui Lalabob **délègue** la lumière à LightKey (ADR 0006) : un pad lumière envoie une note MIDI, LightKey
déclenche sa cue et renvoie l'état. Parfait pour un plan de feu riche.

Pour les petites salles, la troupe a **un seul appareil** : une barre de **4 projecteurs** (Chauvet DJ 4BAR LT BT) pilotée en **DMX (15 canaux)**,
branchée au Mac par un **petit boîtier USB-DMX**. Lancer LightKey pour ça est lourd. Proposition : Lalabob devient sa
propre petite console pour ce cas, **sans retirer LightKey**.

- Un réglage choisit le **mode lumière** : **LightKey** (comme aujourd'hui) ou **Projecteurs pilotés par Lalabob** (DMX).
- En mode DMX, un pad lumière contient un **état lumineux**, de l'un de ces types :
  - **Couleurs** : pour chaque projecteur, allumé ou non, sa couleur (roue libre), son intensité — réglés **chacun** ou **ensemble** ;
    strobo en option ;
  - **Alternance** : deux couleurs en damier qui s'échangent **au tempo du son en cours** ;
  - **Programme de la barre** (programmes intégrés 1–12 + vitesse) ;
  - **Sur le son** (le micro de la barre, avec sa sensibilité) ;
  - un pad **Noir** n'est qu'un état Couleurs tout éteint.
  Chaque état a un fondu d'entrée ; un appui y va **en fondu**.
- Sous les colonnes lumière, la carte du fader **Général** avec une mini-barre (4 projecteurs cliquables) et **Noir** ; les faders des colonnes lumière ont un rôle
  (Général, Couleurs…), quelle que soit leur place ; sur l'APC, le bouton rond d'une colonne lumière fait un **Noir en fondu**.

## Est-ce jouable ? Oui, avec un point à vérifier d'abord : le boîtier USB-DMX

Le DMX lui-même est simple : une trame d'au plus 512 octets (une valeur 0–255 par canal) répétée ~30 à 40 fois par seconde. Ce qui
change tout, c'est le boîtier :

| Boîtier | Comment on lui parle | Verdict |
| --- | --- | --- |
| **Enttec DMX USB Pro** et compatibles (DMXKing ultraDMX, beaucoup de boîtiers « USB Pro ») | Port série (`/dev/cu.usbserial-…`, pilote FTDI intégré à macOS), petits messages encadrés (`7E 06 … E7`). **Le boîtier fabrique le signal DMX lui-même et répète la dernière trame.** | **Idéal.** Si Lalabob se fige, la lumière reste telle quelle. |
| **Enttec Open DMX USB** et câbles FTDI bon marché (~20 €) | Port série, mais **c'est le Mac qui fabrique le signal** (250 kbit/s, « break » avant chaque trame, en continu). | Faisable (fil dédié à haute priorité), timing moins régulier ; si Lalabob se fige, le signal s'arrête (le projecteur garde ou s'éteint, selon son menu). |
| uDMX, boîtiers USB « propriétaires » | Accès USB direct (IOKit) | Possible mais à éviter. |
| Nœud **Art-Net / sACN** (réseau) | UDP | Simple, option pour plus tard. |

Côté macOS : l'app est en bac à sable ; l'accès au port série demande l'autorisation `com.apple.security.device.serial`
(dans `project.yml`), sans compte développeur. Les boîtiers à puce CH340 / CP210x passent aussi par un port série
(pilote à vérifier selon la version de macOS).

### Relevé du 27/11/2026

**Boîtier de la troupe** : puce **FTDI FT232R** (USB 0403:6001, nom « FT232R USB UART », n° de série AU0483EN), vu par macOS
sans pilote à installer : `/dev/cu.usbserial-AU0483EN`. Il **ne répond pas** aux demandes du protocole Enttec Pro
(« Get Widget Parameters », « Get Serial Number ») → c'est un boîtier **de type Open DMX** : **Lalabob fabrique le signal**
(250 kbit/s, 8 bits, 2 bits d'arrêt, « break » ≥ 88 µs puis « mark » ≥ 8 µs avant chaque trame). Conséquences :
- un fil dédié, à haute priorité, envoie la trame en continu ; **30 Hz suffisent** (la barre le supporte bien, retour de la
  troupe) ; on peut n'envoyer que les premiers canaux utiles (trame courte, plus régulière) ;
- vitesse non standard par `IOSSIOSPEED`, break par `TIOCSBRK` / `TIOCCBRK` (ou l'astuce d'un octet 0 à vitesse réduite) ;
- **si Lalabob se fige ou se ferme, le signal s'arrête** : comportement de la barre à relever (garde-t-elle la dernière
  couleur ?). C'est le point de sécurité principal de ce boîtier ; un boîtier Enttec Pro (~150 €) le supprimerait.

**Barre de la troupe : Chauvet DJ 4BAR LT BT** (manuel « 4BAR LTBT User Manual », rév. 2). 4 projecteurs à LED **rouge, vert,
bleu** (pas d'ambre ni de blanc : les blancs et les tons chauds se font par mélange RVB). Modes DMX : 3, 5 et **15 canaux**.
Tableau **confirmé par le manuel papier de la troupe** (photo du 27/11/2026). Adresse de départ réglée **sur la barre** (MENU → 15Ch → d 1–510 ; 498 au plus pour garder les 15 canaux). Mode 15 canaux,
à partir de l'adresse A :

| Canal | Rôle | Valeurs |
| --- | --- | --- |
| A | Programme | 0–9 : **pilotage DMX direct** (à tenir à 0) ; 10–249 : programmes auto ; 250–255 : son |
| A+1 | Gradateur général | 0–255 = 0–100 % |
| A+2 | Strobo (si programme 0–9) | 0–9 : aucun ; 10–255 : lent → rapide |
| A+3 … A+5 | Projecteur 1 : rouge, vert, bleu | 0–255 |
| A+6 … A+8 | Projecteur 2 : rouge, vert, bleu | 0–255 |
| A+9 … A+11 | Projecteur 3 : rouge, vert, bleu | 0–255 |
| A+12 … A+14 | Projecteur 4 : rouge, vert, bleu | 0–255 |

Donc : **pas de gradateur par projecteur** (l'intensité d'un projecteur = ses 3 couleurs mises à l'échelle) et **un seul
strobo pour toute la barre**. Le gradateur général sert d'intensité générale (carte de jeu, fader 7 de l'APC).
La barre a aussi un mode Bluetooth (app BTAir) et des modes autonomes : ils doivent être désactivés (afficheur sur 15Ch).

## Effet « Alternance » et fader des couleurs (décisions du 27/11/2026)

Pour ne rien perdre par rapport aux jeux de lumière faits dans LightKey.

- **Alternance** : un état lumineux peut être un effet. Deux couleurs A et B **en damier** : projecteurs 1 et 3 en A, 2 et 4 en B,
  puis on échange (B A B A), et ainsi de suite. Réglages : les deux couleurs, la bascule tous les 1 temps / 2 temps / 1 mesure, un
  **fondu court réglable** à chaque bascule (de 0 = net à la moitié de l'intervalle).
- **Tempo = celui du son en cours** (choix de l'utilisateur) :
  - **Analyse hors ligne** de chaque son (comme la forme d'onde : Accelerate, cache disque, jamais sur le fil audio) : enveloppe des
    attaques → **BPM** et **position des temps** (grille de temps). Résultat affiché sur le pad son et dans son panneau, **corrigeable**
    (×2, ÷2, taper le tempo, « pas de tempo »), enregistré avec le spectacle.
  - **En jeu** : Lalabob connaît la position exacte de lecture du son (élagage et tête de lecture compris) → la bascule tombe **sur les
    temps du morceau**, avec une avance réglable pour compenser le délai de la barre (quelques dizaines de ms, à mesurer).
  - **Quel son ?** Le dernier son lancé qui a un tempo (à confirmer à l'essai) ; quand il s'arrête, on revient au précédent qui joue
    encore, sinon au **tempo de repli** du pad (ex. 120 BPM, ou tapé).
  - Risque : en impro beaucoup de sons n'ont pas de rythme net (ambiances, bruitages) → pas de BPM, repli. L'analyse de tempo est la
    partie la plus incertaine : prototype et essai sur les vrais sons de la troupe avant de la brancher.
- **Faders en mode Projecteurs** : par **rôle de colonne** (voir Interface ; par défaut 1re colonne lumière = **intensité générale**,
  2e = **rotation des couleurs**) : toutes les couleurs tournent ensemble sur la roue des teintes, les écarts entre projecteurs restent (rouge / bleu → orange / violet → jaune / rose…) ;
  en bas = couleurs d'origine du pad. Les blancs restent blancs (pas de teinte). Le **strobo** passe à l'écran seulement.

## Option : lumière qui suit le son (idée du 27/11/2026)

Deux façons de faire, à ne pas confondre :

1. **Programme « son » de la barre** (canal 1 à 250–255, sensibilité au canal 3 : 0–10 coupé, 11–255 faible → forte). La barre
   écoute **son propre petit micro** et change de couleur ou clignote à chaque pic de son. C'est elle qui choisit les couleurs et le
   rythme : Lalabob ne fait qu'allumer ce mode et régler la sensibilité. Idem pour les **programmes automatiques** 1–12 (canal 1 à
   10–249, vitesse au canal 3). Limites : le micro entend **toute la salle** (voix des comédiens, rires, applaudissements), les
   couleurs ne sont pas les nôtres, et l'effet du gradateur général dans ces modes est à vérifier.
   → Proposé : un état lumineux peut être de type **« Programme de la barre »** (auto 1–12 + vitesse, ou son + sensibilité) au lieu des
   4 projecteurs. Peu de travail. Le strobo et ce mode s'excluent (même canal 3).
2. **Lumière pilotée par le son de Lalabob** : Lalabob mesure déjà le vrai signal de chaque colonne (vumètres, J6). Il peut s'en servir
   pour moduler l'intensité (ou passer d'un projecteur à l'autre) au rythme **des sons qu'il joue**, et seulement d'eux, avec nos couleurs.
   30 Hz suffisent pour suivre un rythme. Plus de travail (suivi d'enveloppe, choix de la colonne, réglages), à garder pour plus tard.

## Sans câble ? (question du 27/11/2026)

- **Bluetooth de la barre (app BTAir de Chauvet)** : protocole **privé et non documenté**. Il faudrait l'espionner et le
  reproduire (CoreBluetooth, autorisation `device.bluetooth`) ; il peut changer avec un micrologiciel ; connexion BLE fragile en salle
  (2,4 GHz encombré par les téléphones du public), portée ~10 m, sans doute une seule app connectée à la fois, et comportement inconnu
  si la liaison tombe. **Écarté** pour la scène.
- **Sans fil officiel : D-Fi USB de Chauvet** (prévu par la barre, port « D-Fi USB ») : un récepteur D-Fi branché sur la barre, un
  émetteur D-Fi au bout du boîtier USB-DMX. **Lalabob ne change pas** (même DMX), seul le câble disparaît. Même famille : émetteurs /
  récepteurs DMX sans fil génériques. **Recommandé** si le câble gêne ; à garder en option matérielle, rien à coder.

## Ce que ça ne change pas

- **Le son ne s'arrête jamais à cause de la lumière** : le DMX vit dans son propre module et son propre fil.
- **Échap / Tout arrêter ne touche pas la lumière** (règle actuelle) ; le Noir est un geste séparé.
- Le mode LightKey reste identique : relais, retour, « Relier aux projecteurs », canaux par grille.
- Pads son et lumière, colonnes communes à toutes les grilles, cadenas : marchent pareil, quel que soit le mode.

## Architecture proposée

Respecte `docs/adr/0001-architecture.md` : un module par responsabilité, pas de dépendance tierce.

- **`LalabobModel`** (valeurs pures)
  - `LightingMode` dans `Show` : `.lightKey` (défaut, anciens fichiers) ou `.dmx(DMXRig)`.
  - `DMXRig` : l'appareil (profil + adresse de départ). Un seul appareil pour commencer ; une liste plus tard.
  - `FixtureProfile` : nom, nombre de canaux, rôle de chaque canal (rouge / vert / bleu / [blanc] par projecteur,
    gradateur général, strobo, canal « mode » à valeur fixe…). **Donnée, pas code** : un profil intégré pour la barre de la
    troupe, d'autres appareils s'ajoutent sans recompiler.
  - `LightLook` (« état lumineux ») : fondu d'entrée + un contenu parmi :
    `.colors(heads: [{ allumé, couleur, intensité }] × 4, linked: Bool, strobe: Double?)` (`linked` = réglé « ensemble »),
    `.alternate(a: couleur, b: couleur, every: .beat | .twoBeats | .bar, switchFade: 0…0,5, fallbackBPM)`,
    `.fixtureProgram(number: 1…12, speed: 0…1)`, `.soundActive(sensitivity: 0…1)`. Les deux derniers dépendent du profil de
    l'appareil (`FixtureProfile` dit s'il les a et sur quels canaux / valeurs).
  - `LightCue` gagne une cible : note MIDI (LightKey) **ou** `LightLook` (DMX). Format **version 4**, écrite seulement si
    nécessaire (comme la 3). `Show.validate()` borne tout (adresse 1…512, profil cohérent, valeurs 0…1).
  - Couleur (décision du 27/11/2026 : **roue des couleurs libre**, pas une palette fermée) : stockée en **teinte (0–360°) +
    saturation (0 = blanc, 100 = le plus intense)**, jamais en code RVB ; le profil de l'appareil la traduit en rouge / vert / bleu
    (avec une correction réglable à l'œil, la barre n'ayant ni blanc ni ambre). L'intensité reste un réglage à part. Le spectacle garde
    ses **couleurs favorites** (pastilles sous la roue). Esprit de la règle « une teinte est stockée, jamais un code couleur » :
    à acter dans l'ADR 0012.
- **`LalabobDMX`** (nouveau module, dépend de Model)
  - `DMXFrame` (512 octets), `DMXTransport` (protocole, comme `MIDITransport`), `EnttecProPort`, `OpenDMXPort` (si besoin),
    `SilentDMX` (tests).
  - Détection et rebranchement à chaud des ports série (notifications IOKit), dans un `actor`.
  - **Fil de rafraîchissement** à 30 Hz (réglable), hors `MainActor` : l'interface qui rame ne fige pas la lumière.
- **`LalabobEngine`**
  - `LightConsole` (pure, testable hors ligne) : état courant → trame, à un instant t. Fondu enchaîné entre deux états,
    boutons des projecteurs en direct, intensité générale, strobo, Noir. Tout se calcule sur des valeurs, pas sur des envois.
  - `ShowController` : appui sur un pad lumière → selon le mode, relais MIDI (actuel) ou état lumineux ; « Nouvel appui »
    réutilise `lightRetrigger` (allume seulement / allume ou éteint). Édition des états avec ⌘Z ; gestes de jeu (boutons des
    projecteurs, intensité, strobo, Noir) sans ⌘Z et actifs verrouillé, comme les faders.
  - **État des pads** : en DMX, Lalabob *est* la console, donc l'état allumé / éteint est connu (pas de retour à attendre). La
    règle « jamais d'état allumé déduit d'un envoi » reste vraie pour LightKey. Limite : le DMX ne dit pas si la barre est
    réellement branchée.
  - Contrôleur : appuis sur les colonnes lumière → états ; chaque fader suit le **rôle** de sa colonne (Général, Couleurs, strobo) ;
    bouton rond d'une colonne lumière → **Noir en fondu** (`ShowController.blackout(fade:)`), LED rouge (`stopButtonMessages`).
- **`App/`**
  - **Où régler l'adresse** : dans **Réglages du spectacle** (⌥⌘,, déjà là pour les lumières communes) : mode lumière, appareil,
    **adresse DMX** (doit être celle affichée par la barre, 1–498 ; l'écran le rappelle). Le spectacle voyage d'un Mac à l'autre avec
    son réglage. Le **boîtier** USB-DMX, lui, se choisit **par Mac** (comme la sortie audio), dans l'en-tête ou les Réglages de l'app (⌘,).
  - En-tête : pastille « Projecteurs » (boîtier branché / absent), comme le contrôleur.
  - **Colonnes libres, commandes de la barre (décision du 27/11/2026, piste C)**. Les colonnes peuvent être de n'importe quel type,
    n'importe où (lumière, son et lumière, son) : il n'y a **pas de carte fusionnée**. Chaque colonne garde sa carte de fader :
    - **colonne son, ou son et lumière** : fader = volume du son, comme aujourd'hui ;
    - **colonne lumière seule** (mode Projecteurs) : son fader a un **rôle** — **Général**, **Couleurs** (rotation des teintes), **Vitesse
      du strobo** ou **Aucun** — choisi d'un clic droit sur la carte et affiché en étiquette ; par défaut, 1re colonne lumière de la
      grille = Général, 2e = Couleurs, suivantes = Aucun ; deux colonnes au même rôle pilotent le même réglage ;
    - la carte dont le fader est **Général** porte une **mini-barre dessinée** : les 4 projecteurs, à la couleur et à l'intensité réelles
      de la barre, clic = allumer / éteindre en fondu (sur l'état en cours, sans modifier le pad), et un bouton **Noir** ;
    - sans colonne au rôle Général (grille sans colonne lumière, ou rôles retirés) : les mêmes commandes restent accessibles par le menu
      Lumière et le panneau du bas au repos (à maqueter) ;
    - le strobo d'un état se règle dans le pad ; un réglage direct « Strobo » reste dans le menu Lumière ;
    - quand une alternance joue : son tempo s'affiche sur la carte Général (« ⇄ 124 BPM ») avec un point qui bat.
  - **APC mini mk2 en mode Projecteurs** : chaque fader physique suit **sa colonne** (fader 3 = Général si la colonne 3 a ce rôle). Le
    **bouton rond au-dessus du fader** (notes 100–107, aujourd'hui « stop de colonne ») d'une **colonne lumière** devient **Noir** : LED
    **rouge**, un appui éteint toute la barre **en fondu** (pas une coupure : durée « Fondu du noir » réglable dans les Réglages du
    spectacle, **1,5 s** par défaut), comme le stop des colonnes son. Les colonnes son et son et lumière gardent leur stop de son (le
    stop ne touche jamais la lumière). Le même Noir à l'écran (bouton de la mini-barre) utilise le même fondu.
  - **Repère des projecteurs sur chaque pad lumière** (en bas à droite, 4 points dans l'ordre 1 → 4) : un point par projecteur à
    sa couleur, plus pâle si l'intensité est basse, gris si éteint ; ⇄ pour une alternance (les points s'échangent au tempo quand
    elle joue) ; ϟ si strobo ; barre arc-en-ciel + « P3 » pour un programme, + « MIC » pour « sur le son ». Sous-titre par défaut :
    « Ensemble · 2 et 3 », « ⇄ 124 BPM · son en cours », « Programme 3 · 40 % »… États : en cours = contour ambré + halo ;
    sélectionné = contour blanc.
  - **Panneau du bas** d'un pad lumière en DMX (196 px comme aujourd'hui) :
    - bande du haut : Essayer, titre / sous-titre, interrupteur **« Aperçu sur la barre »**, fondu d'entrée (− / +), Nouvel appui
      (Laisse allumé / Allume ou éteint), couleur du pad (LED et écran), menu ⋯ ;
    - bande du bas : à gauche le **type** (Couleurs · Alternance · Programme · Sur le son), puis selon le type :
      **Couleurs** → sélecteur **Chacun / Ensemble**, puis 4 cartes (interrupteur, couleur, intensité) ou une carte « Les 4 projecteurs
      ensemble » (couleur, boutons 1 2 3 4 allumés, intensité), et la carte Strobo (arrêté par défaut) ;
      **Alternance** → couleurs A (1 et 3) et B (2 et 4), aperçu du damier qui bascule, tempo du son en cours (nom, BPM), bascule
      1 temps / 2 temps / 1 mesure, fondu à la bascule (net → 50 %), tempo de repli + « Taper le tempo » ;
      **Programme** → programme 1–12, vitesse ; **Sur le son** → sensibilité du micro + mise en garde (le micro entend toute la salle) ;
    - **roue des couleurs** en fenêtre surgissante au-dessus de la carte choisie : roue (centre blanc → bord intense), curseurs
      Teinte et « Pâle → intense », pastille d'aperçu, **couleurs du spectacle** (favoris) avec « + » pour garder la couleur en cours.
  - **Réglages du spectacle** : deux grands choix (Logiciel lumière / Projecteurs pilotés par Lalabob) ; en mode Projecteurs : appareil,
    adresse (− / +) avec le schéma des 15 canaux occupés et le rappel « MENU → 15Ch → d 001 », boîtier USB-DMX de ce Mac et son
    état (« Branché · 30 Hz »), « Essayer : 4 projecteurs en blanc », « Banc d'essai DMX… », « En quittant Lalabob » (Fondu au noir /
    Laisser la lumière) ; en mode Logiciel lumière : le rappel du fonctionnement actuel.
  - Bouton « Relier » masqué en mode DMX (inutile).
  - **Cadenas compact dans l'en-tête** (demande du 27/11/2026, vu sur la maquette des pistes ; indépendant du DMX, peut être fait à
    part) : `LockButton` (`App/HeaderView.swift`) passe de « icône + Verrouillé / Déverrouillé » à un **petit bouton carré** (~30 pt)
    avec la seule icône (cadenas fermé / ouvert). Pour ne rien perdre : infobulle « Verrouiller (⌘L) » / « Déverrouiller (⌘L) »,
    libellé VoiceOver inchangé, état lisible sans le texte (cadenas ouvert sur fond légèrement ambré quand on peut modifier), ⌘L et
    l'animation de bascule conservés. Libère de la place pour la pastille du contrôleur et le reste de l'en-tête.
  - **Aperçu en direct sur la barre** (demande du 27/11/2026) : déverrouillé, chaque réglage d'un pad (couleur, intensité, strobo,
    effet) s'applique **tout de suite** sur la barre si elle est branchée, sans fondu, pour régler à l'œil. Quand on quitte le pad,
    la barre revient en fondu à la lumière qui était en cours. Interrupteur « Aperçu sur la barre » dans le panneau (actif par défaut) ;
    jamais d'aperçu verrouillé (en scène, seul le jeu pilote la barre).
  - **Réglage « Chacun » / « Ensemble »** (demande du 27/11/2026) : en mode Couleurs, « Ensemble » donne une seule couleur et une
    seule intensité aux 4 projecteurs (avec le choix de ceux qui sont allumés) ; « Chacun » garde une carte par projecteur. Passer à
    « Ensemble » applique aux 4 la couleur du projecteur choisi ; c'est une option d'édition, mémorisée avec le pad.
  - **Banc d'essai DMX** (Fenêtre ▸ …) : un curseur par canal (15), pour vérifier le tableau de la barre.

## Étapes (une branche + une PR chacune)

0. **Relevé matériel** (`j14/releve-dmx`) — boîtier et tableau de la barre : **faits**, recopiés dans
   `docs/hardware/chauvet-4bar-ltbt.md`. **Banc d'essai livré** (27/11/2026) : `tools/banc-dmx/banc-dmx.swift`, outil en ligne de
   commande hors de l'app (blanc, couleur, chenillard, canaux bruts, noir ; option `--noir-a-la-fin`). Essayé sur le boîtier : vitesse
   250 kbit/s et break acceptés par le pilote FTDI de macOS, 30 Hz tenus (moyenne 33,3 ms, pire ≈ 40 ms). ADR 0012 rédigée (proposée).
   Essais sur la barre (adresse 50) : chenillard conforme au tableau, gradateur ✅, **perte du signal : la barre garde la dernière
   couleur**, strobo ✅. **Étape 0 terminée** ; seul le délai de la barre (alternance au tempo) sera mesuré à l'étape 3b.
   La fenêtre « Banc d'essai DMX » dans l'app viendra avec le module (étape 1).
1. **Module `LalabobDMX`** (`j14/module-dmx`) — trames, transports, détection, rebranchement, fil à 30 Hz. Tests avec un faux
   port (octets attendus enregistrés). **Code fait le 27/11/2026** (avec la fenêtre « Banc d'essai DMX ») ; essai sur la barre à faire,
   voir `docs/PLAN.md` (J14). Écart : rebranchement par essai chaque seconde plutôt que par notifications IOKit.
2. **Modèle** (`j14/modele-dmx`) — `LightingMode`, `DMXRig`, `FixtureProfile` (profil de la barre), `LightLook` (4 types), couleurs
   teinte + saturation et favoris du spectacle, format v4 + migration, validation. Tests d'abord.
3. **Console et moteur** (`j14/console-dmx`) — `LightConsole` (fondus, boutons en direct, Noir, strobo), branchement
   `ShowController` et contrôleur, LED. Tests hors ligne (trames à t = 0, mi-fondu, fin).
3b. **Tempo des sons** (`j14/tempo-sons`) — prototype d'analyse (BPM + grille de temps) essayé sur les vrais sons de la troupe,
   puis cache, correction à la main, effet « Alternance » calé sur le son en cours. Tests hors ligne (clics à 120 BPM, boucle de batterie).
4. **Interface** (`j14/interface-dmx`) — réglages, en-tête, carte de jeu, repère des projecteurs sur les pads, panneau du bas
   (4 types, Chacun / Ensemble, roue des couleurs), aperçu en direct, d'après la maquette (planches ci-dessus).
5. **Documentation et essai** — `GUIDE.md`, aide intégrée, `LEXIQUE.md`, `DESIGN.md`, check-list sur la vraie barre.

Estimation grossière : l'étape 0 est courte et lève l'essentiel du risque ; 1 à 3 forment le gros du travail ; 4 dépend
de la maquette.

## Points de sécurité de scène

- Boîtier débranché en cours de spectacle : aucun son coupé, bandeau discret, la lumière reprend au rebranchement (trame
  renvoyée).
- Fermeture de Lalabob : réglage du spectacle « En quittant Lalabob » — **Fondu au noir** proposé par défaut (avec ce boîtier, le
  signal s'arrête de toute façon) ; à confirmer (question 5).
- Fondus calculés hors du fil principal ; aucun envoi DMX sur le fil audio.
- Strobo : borné, jamais déclenché par erreur (désactivé par défaut dans un nouvel état), mise en garde dans le guide.

## Questions ouvertes

1. ~~Boîtier~~ et ~~barre~~ : relevés (voir plus haut). Reste : vérifier que la barre est bien en **15Ch** et noter son adresse.
2. ~~Perte du signal~~ : relevé le 27/11/2026, **la barre garde la dernière couleur**. Un plantage fige la lumière (pas de noir) ;
   le « Fondu au noir » à la fermeture doit être envoyé par Lalabob avant de fermer le port.
3. **Où se règle le mode et l'adresse** : proposé dans Réglages du spectacle (le boîtier par Mac).
4. ~~Couleurs~~ : roue des couleurs libre (teinte + saturation) et couleurs favorites du spectacle.
5. **À la fermeture** : la maquette propose un réglage, « Fondu au noir » par défaut — à confirmer.
6. **Les 4 projecteurs de la mini-barre** : ils agissent sur l'état en cours, sans modifier le pad — à confirmer à l'essai.
9. **Durée du Noir** : 1,5 s proposé par défaut (bouton de l'APC et écran), à régler à l'essai.
8. **Quel son donne le tempo** quand plusieurs sons rythmés jouent : le dernier lancé (proposé) ?
7. ~~Faders 7 et 8~~ : décidé (intensité générale, rotation des couleurs).
