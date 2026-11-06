# ADR 0007 — Import d'un Live Set Ableton (Live 12)

- Date : 2 novembre 2026
- État : **proposée** — structure vérifiée sur un vrai Live Set (Live 11.3.25, `BobEte.als`) ; code écrit sans Mac, **non compilé**

## Contexte

La troupe prépare ses sons dans la vue Session d'Ableton Live 12 : une piste par famille de sons, une scène par ligne.
Refaire ce classement à la main dans Lalabob est long. On veut **importer un Live Set** dans un spectacle ouvert.

Un `.als` est du XML compressé en gzip (ni documenté ni garanti par Ableton ; format établi par rétro-ingénierie communautaire).
Les clips audio y portent leur nom, l'interrupteur de boucle et une référence de fichier : chemin relatif au dossier du `.als`
(`<RelativePath>`) et chemin absolu mémorisé (`<Path>`). Les positions de boucle et d'élagage sont en **temps musical (battements)**,
liées au tempo et aux marqueurs de warp.

## Décision

- **Portée** (choix du 02/11/2026) : clips **audio** de la vue Session uniquement. Pistes MIDI, retours, arrangement, effets,
  automations : ignorés (les pistes MIDI sont comptées dans le compte rendu).
- **Correspondances** : piste audio → colonne son (de gauche à droite, 6 par grille) ; scène → ligne (de haut en bas, 8 par grille) ;
  nom du clip → titre du pad ; interrupteur Loop → boucle ; nom de la piste → nom de la colonne ; teinte stable d'après le nom du
  fichier (comme un son glissé depuis le Finder). Colonnes lumière : vides.
- **Dépassement** (choix du 02/11/2026) : l'utilisateur choisit à chaque import — découper en blocs 6 × 8 (une grille par bloc non vide,
  nommée « Live Set · pistes 7–12 · scènes 1–8 ») ou ne garder que le bloc 6 × 8 en haut à gauche.
- **Sons** (choix du 02/11/2026) : d'abord le chemin relatif au dossier du `.als`, puis le chemin absolu, puis le nom de fichier n'importe où
  sous le dossier du projet ou sous le dossier choisi par l'utilisateur. Trouvés : copiés dans `Audio/` par `AudioImporter` (mêmes règles que le glisser-déposer : formats,
  noms sûrs, homonymes, dédoublonnage). Introuvables : le pad est créé **muet** et listé dans le compte rendu (le spectacle s'ouvre
  de la même façon avec un son manquant, voir `docs/FORMAT.md` § 4). Le chemin relatif d'un vrai projet remonte hors du dossier (`../../bob play/Été/x.mp3`) : les `..` sont **acceptés** ; le garde-fou est le bac à sable et le filtre des formats audio, pas le chemin.
- **Où le mettre** : un nouveau module `LalabobImport` (dépend de `LalabobModel`, rien d'autre, pas d'accès aux fichiers de sons) :
  décompression gzip (`Compression` via `NSData`), lecture du XML en flux (`XMLParser`), construction pure des grilles.
  Les entrées-sorties (lecture du `.als`, recherche et copie des sons) sont dans `LalabobEngine` (`AbletonImporter`).
  Aucune dépendance tierce.
- **Intégration au spectacle** : `ShowController.importLiveSet` **ajoute** les grilles au spectacle ouvert (un seul ⌘Z), ne remplace rien,
  refusé si le spectacle est verrouillé, limité à 64 grilles. Menu Fichier › « Importer un Live Set Ableton… ».
- **Sandbox** : l'app n'a accès qu'au fichier choisi. Pour lire les sons à côté du `.als`, l'utilisateur doit choisir **le dossier du projet Live**
  (le sélecteur accepte un dossier ou un `.als`). Dans le vrai projet de la troupe, les sons sont **hors** du dossier du projet (`~/Music/bob play/…`, le projet étant dans `~/Music/Bob play/BobEte Project`) : il faut choisir le dossier qui contient les deux (`Bob play`). Si le dossier choisi ne contient pas de `.als` à sa racine, l'import cherche dans ses sous-dossiers directs (hors `Backup`) et s'arrête s'il y en a plusieurs. Avec le seul `.als`, les sons du projet sont signalés introuvables (sauf s'ils sont déjà
  accessibles par ailleurs).
- **Sécurité** : le fichier est une entrée non fiable. Fichier ≤ 100 Mio, XML ≤ 256 Mio (taille annoncée contrôlée avant la
  décompression, résultat contrôlé après), entités externes désactivées, 256 pistes au plus, aucun chemin ne sort du dossier du projet,
  tout nom de son passe `AudioClip.safeFileName`, le spectacle importé est valide (`Show.validate()` testé).

## Repris et non repris

**Repris** : nom du clip, boucle (`Loop > LoopOn`), élagage, volume.
- **Élagage** : `Loop > LoopStart` / `LoopEnd` sont le début et la fin de la partie jouée. **Secondes** dans un clip non warpé, **battements** dans un clip
  warpé (`IsWarped`) : conversion par les `WarpMarkers` (interpolation linéaire, prolongée au-delà du dernier marqueur). Vérifié sur 53 clips :
  pour les 46 clips non warpés, `LoopEnd` ≤ durée du fichier sans exception ; pour un clip warpé à deux marqueurs, la conversion retombe sur la
  durée exacte du fichier. Sans durée du fichier (`DefaultDuration` / `DefaultSampleRate`) ou sans marqueurs exploitables : tout le fichier (jamais
  de valeur inventée). `StartRelative` (départ décalé d'un clip en boucle) n'est pas repris.
- **Volume** : `SampleVolume` est le gain du clip, en linéaire (valeurs vues : 0,3 à 1,79) → dB, borné à −60…+12, arrondi au dixième. À confirmer à l'oreille
  sur un clip réglé dans Live (par exemple « Nuit », −10,5 dB).

**Non repris** : fondus (tous à 0 dans l'exemple, unités non vérifiées), couleurs (palette de 70 couleurs non documentée de façon fiable),
mode de déclenchement (`LaunchMode`), actions suivantes, scènes nommées, pistes MIDI (les deux pistes « Lumières » de l'exemple : voir ci-dessous).
Le compte rendu de l'import le rappelle.

## Constats sur le vrai fichier (Live 11.3.25)

- Même structure que décrit pour Live 12 (`AudioTrack > DeviceChain > MainSequencer > ClipSlotList > ClipSlot > ClipSlot > Value > AudioClip`) ;
  `FreezeSequencer` a bien une seconde `ClipSlotList`, ignorée.
- **L'`Id` d'un `ClipSlot` n'est pas la scène** (la 7e case porte l'`Id` 8) : seule la **position** dans la liste compte. Un test le verrouille.
- Un nom de piste automatique (`1-VoilaLEte`) est dans `EffectiveName` ; `UserName` est vide tant que l'utilisateur n'a rien tapé.
- Les clips non warpés conservent des `WarpMarkers` (inutilisés) ; `HiddenLoopStart` / `HiddenLoopEnd` sont dans l'autre unité : ignorés.

## À vérifier (avec un Live Set enregistré par Live 12)

L'exemple vient de Live 11.3.25. À confirmer sur un fichier de Live 12 : la racine `MainTrack` (au lieu de `MasterTrack`, sans effet ici), et que les
chemins ci-dessus n'ont pas bougé. Pistes pour une v2 : fondus, couleurs, pistes MIDI « Lumières » → cues lumière (à définir avec la troupe).

## Conséquences

- Un module de plus dans `LalabobKit` (7 au lieu de 6 ; ADR 0001 mis à jour implicitement).
- Le format `.lalabob` ne change pas (`formatVersion` reste 1) : l'import n'écrit que des grilles ordinaires.
- Si Ableton change la structure de ses fichiers, seul `AbletonLiveSetReader` est à adapter ; un Live Set sans clip trouvé donne
  un message clair (« aucun clip audio ») plutôt qu'un spectacle vide.
- Un son manquant qui porte le même nom qu'un autre son déjà présent dans le spectacle jouera ce dernier (le pad référence un nom de fichier).

## Sources

Format décrit par la communauté, non officiel : dépôt « ableton-under-the-hood » (gzip, `SampleRef/FileRef`), « ALS Generation Findings »
et « Clip Timing Reference » du projet Audio-Haxor (racine `Ableton`, `MainTrack` en Live 12, `AudioClip`, `Loop`, `WarpMarkers`, unités en battements,
palette de 70 couleurs), documentation « ableton-als-structure » du dépôt aesthetic.computer.
