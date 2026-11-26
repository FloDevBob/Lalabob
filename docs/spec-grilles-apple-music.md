# Spec — Grilles Apple Music

Brouillon du 27/11/2026, à valider avant le plan d'implémentation. Maquette : artefact « Grilles Apple Music ».

## Idée
Une **grille Apple Music** est une grille dont les pads lancent des **morceaux d'une playlist d'Apple Music**. On la prépare
déverrouillé, avec un panneau à gauche qui liste les playlists et leurs morceaux ; on glisse un ou plusieurs morceaux sur les
pads. En scène, un appui (contrôleur ou double-clic) lance le morceau dans l'app Music.

## Décisions (27/11/2026)
| Sujet | Décision |
| --- | --- |
| Technique | **Apple Events** : Lalabob pilote l'app Music ouverte (pas de compte développeur). MusicKit plus tard, peut-être |
| Contenu d'une grille Music | Colonnes **Music** + colonnes **lumière** possibles (cues sur le canal LightKey de la grille). Pas de colonne son |
| Un 2ᵉ pad Music pendant qu'un morceau joue | **Fondu enchaîné** (≈ 1 s) : l'ancien descend, le nouveau démarre et remonte |
| Ré-appui sur le pad qui joue | **Pause / reprise** |
| Fin du morceau | **Silence** : Music n'enchaîne pas la suite de la playlist (`play … with once`) |
| Pré-écoute dans le panneau | **Extrait de 30 s** d'Apple (internet), joué par Lalabob sur sa pré-écoute, sans toucher à Music |
| Dépôt de plusieurs morceaux | Depuis la case visée **vers le bas, puis colonne Music suivante** ; cases occupées sautées ; ordre de la playlist |
| Volume | Volume **général** de Music = **9ᵉ fader de l'APC** (fiche 03). Pas de volume par pad ni par colonne |
| Vumètre / filtre | **Prototype d'abord** : capturer le son de Music (Core Audio, « process tap », macOS 14.2+) ; sinon carte condamnée |

## Ce que voit l'utilisateur
**Créer** : le bouton + des onglets ouvre « Nouvelle grille » : **Sons et lumière** (⌘T) ou **Apple Music** (⌥⌘T) ; aussi dans le menu
Grilles. L'onglet d'une grille Apple Music porte une petite note rose.
**Changer le type** : clic droit sur l'onglet › Type de grille. Même règle que les colonnes : rien de perdu = appliqué tout de suite
(grille vide, ou seulement des colonnes lumière) ; sinon confirmation qui nomme les pads supprimés (sons ↔ morceaux), colonnes lumière
gardées, une annulation (⌘Z).

**Panneau de gauche** (déverrouillé, à la place de la bibliothèque de sons, sur une grille Music) :
1. État de Music : ouvert / fermé (bouton « Ouvrir Music ») / à autoriser.
2. Bascule **Mes playlists / Internet** et un champ de recherche.
   - **Mes playlists** : la recherche filtre les noms de playlists **et** les morceaux de toute la bibliothèque.
   - **Internet** : recherche dans le catalogue Apple Music (recherche publique d'Apple, sans clé) : pochette, titre, artiste,
     durée, extrait de 30 s. **Limite** : sans compte développeur, Lalabob ne peut pas ajouter un morceau à la bibliothèque.
     « Ajouter… » ouvre le morceau dans Music, où l'on clique + ; il apparaît alors dans « Mes playlists », prêt à glisser.
     (Avec MusicKit plus tard : ajout direct depuis Lalabob.)
3. **Arborescence des playlists** : les dossiers de Music (repliables, ▸ / ▾) avec leurs playlists, comme dans Music.
   Liste des **playlists**, puis les **morceaux** de la playlist choisie : titre, artiste, durée, nuage si non téléchargé,
   point rose si déjà sur la grille.
   **Téléchargés** : compte des morceaux non téléchargés (☁), filtre « Téléchargés seulement », bouton « Télécharger les N »
   (commande `download` de Music). ⚠︎ À vérifier à l'étape 0 : comment Music signale un morceau d'abonnement téléchargé
   (`cloud status`, `location`) ; avant une représentation, une vérification « tous les morceaux de la grille sont téléchargés ».
4. Sélection multiple : **Maj-clic** (plage), **⌘-clic** (ajout) ; glisser la sélection sur la grille.
5. Bouton ▶ par ligne (au survol) : extrait de 30 s ; zone de pré-écoute en bas comme aujourd'hui.

**Pad Music** : titre (morceau), sous-titre (artiste), durée ; pochette en vignette si disponible ; en lecture : contour + halo, barre de
progression (position lue dans Music 4×/s), égaliseur animé ; en pause : icône pause ; **nuage** ambré si non téléchargé
(« Internet nécessaire ») ; **introuvable** (rouge) si le morceau n'est plus dans la bibliothèque.

**Sous les colonnes Music** : pas de fader. Selon le prototype :
- capture OK → vumètre (et filtre si le son peut être routé par Lalabob) ;
- sinon → carte grisée : « Volume : 9ᵉ fader de l'APC (Apple Music) ». Le bouton ■ stop de colonne reste.

**Panneau du bas (pad Music)** : **pochette de l'album** (≈ 116 pt, à gauche de la barre de position ; lue dans Music, sinon
la pochette du catalogue, sinon une vignette à la teinte du pad), titre / sous-titre modifiables, couleur, morceau d'origine (titre · artiste · album · playlist),
temps écoulé / durée + barre de progression cliquable (aller à), lecture / pause / stop, « Remplacer le morceau… », état
(téléchargé ou non). Bandeau discret : « Fondus, élagage et volume du pad : non disponibles pour un morceau Apple Music ».

**Verrouillé** : panneau de gauche masqué ; appui = lecture / pause ; stop de colonne et Échap arrêtent Music (fondu court).

**Contrôleur** : LED du pad à sa teinte, pulsation en lecture, atténuée en pause ; boutons ■ des colonnes Music = arrêt en fondu.

## Règles
- **Un seul morceau à la fois** (Music n'a qu'un lecteur). Fondu enchaîné : volume de Music → 0 en ≈ 1 s, changement de morceau,
  remontée au volume du 9ᵉ fader. Le 9ᵉ fader bougé pendant le fondu change la cible, sans à-coup.
- **Music fermé** à l'appui : rien ne part, bandeau « Apple Music est fermé ». Lalabob **ne lance jamais Music** tout seul en scène
  (bouton « Ouvrir Music » dans le panneau, déverrouillé).
- Les **sons classiques des autres grilles** continuent de jouer par-dessus (moteur de Lalabob, indépendant).
- Un pad Music garde l'**identifiant persistant** du morceau (et titre / artiste pour le retrouver s'il change d'identifiant).
- Pas de fondu d'entrée/sortie réglable, pas d'élagage, pas de forme d'onde (morceaux protégés : Lalabob ne lit pas le son).

## Modèle et format (piste)
- `PadGrid.kind` : `.standard` / `.appleMusic` ; `ColumnKind.music` ; `Pad.music: MusicTrackRef?`
  (`persistentID`, `title`, `artist`, `album`, `duration`, `playlistName`). Format `.lalabob` **version 3**.
- Moteur : `MusicPlayerControlling` (Apple Events : lister playlists / morceaux, `play … with once`, pause, position, état,
  volume) ; `MusicPlaybackCoordinator` (un morceau, fondu enchaîné, propriétaire du volume de Music avec le 9ᵉ fader).
- Pré-écoute et recherche internet : recherche publique d'Apple (iTunes Search, sans clé) → extrait, pochette, lien vers le morceau → `PreviewController` existant.
- Pochette : `artwork` du morceau dans Music (Apple Events), mise en cache disque comme les formes d'onde.

## Étapes proposées
0. **Socle** : finir la fiche 03 (Apple Events vers Music qui marchent vraiment) + **prototype de capture** du son de Music (go / no-go).
1. Modèle, format v3, type de grille et de colonne Music, menu « Nouvelle grille Apple Music ».
2. Panneau des playlists et des morceaux, sélection multiple, glisser-déposer.
3. Lecture : appui, pause / reprise, fin = silence, fondu enchaîné, progression, LED, stop de colonne, Échap.
4. Pré-écoute de 30 s, recherche internet, pochettes.
5. Vumètre (et filtre) si le prototype l'a permis.
6. Documentation, aide intégrée, check-list d'essai.

## Questions encore ouvertes
- Échap (« Tout arrêter ») : arrêter Music avec un fondu court (0,3 s) ou net ?
- Durée du fondu enchaîné : fixe (1 s) ou réglable par grille ?
- Point de départ dans le morceau (démarrer à 0:42) : utile tout de suite ou plus tard ?
- Rappel des droits : l'abonnement Apple Music est personnel (pas de diffusion publique) ; à voir côté troupe (SACEM).
