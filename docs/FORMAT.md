# Format du fichier `.lalabob`

Spécification du document de sauvegarde d'un spectacle, version de format **1**.
Source de vérité : `LalabobModel` (`Show.swift`, `ShowPackage.swift`, `ShowValidation.swift`). En cas d'écart entre ce
texte et le code, le code fait foi — et ce fichier est à corriger.

> Écrit d'après l'état de la branche `j7/filtre-colonne` (le champ `filter` des colonnes y figure).

## 1. Vue d'ensemble

Un spectacle est un **paquet macOS** (un dossier que le Finder présente comme un seul fichier) :

```
Mon spectacle.lalabob/
├── show.json      ← toute la programmation (grilles, pads, réglages)
└── Audio/         ← les sons, à plat (pas de sous-dossier)
    ├── rire.wav
    └── applaudissements.mp3
```

| Élément | Valeur |
| --- | --- |
| Extension | `.lalabob` |
| Identifiant de type (UTI) | `fr.flodevbob.lalabob.show` |
| Conformité UTI | `com.apple.package`, `public.composite-content` |
| Déclaration | `project.yml` (`UTExportedTypeDeclarations`, `CFBundleDocumentTypes`) |
| Classe de document | `LalabobDocument` (`ReferenceFileDocument`) |
| Lecture / écriture | `ShowPackage.read` / `ShowPackage.wrapper` (pures, sur des `FileWrapper`) |

Copier le dossier `.lalabob` suffit pour transporter un spectacle sur l'autre Mac : les sons y sont inclus.

## 2. `show.json`

JSON UTF-8, écrit **indenté, clés triées, sans échappement des `/`** (`.prettyPrinted`, `.sortedKeys`,
`.withoutEscapingSlashes`) : deux écritures du même spectacle donnent exactement les mêmes octets, ce qui rend le fichier
lisible dans un diff. Taille maximale acceptée à la lecture : **10 Mio** (au-delà : `tooLarge`, refusé avant décodage).
Un vrai spectacle fait quelques dizaines de Ko.

Conventions de codage (celles de `Codable` de Swift, sans personnalisation sauf mention) :

- `UUID` : chaîne canonique en majuscules (`"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"`).
- Durées (`TimeInterval`) : nombre à virgule, en **secondes**.
- Enums à valeur texte : la chaîne (`"restart"`, `"audio"`…).
- Optionnel absent : **la clé est omise** (jamais `null`), sauf une case vide dans `slots`, écrite `null`.
- Enum à valeur associée (`PadContent`) : un objet à une seule clé, `{"audio": {"clip": {…}}}` ou `{"light": {"cue": {…}}}`.

### 2.1 Spectacle (`Show`)

| Clé | Type | Contraintes |
| --- | --- | --- |
| `formatVersion` | entier | 1 ≤ valeur ≤ `Show.currentFormatVersion` (**3**). Plus grand : refusé (`unsupportedFormatVersion`). Écrite = la plus petite version qui contient le spectacle (`requiredFormatVersion`) : **3** s'il a une grille Apple Music, **2** sinon. Un fichier de version 1 se lit (migration, § 5) |
| `name` | texte | nom du spectacle |
| `grids` | tableau de grilles | 1 à **64** grilles (onglets), dans l'ordre d'affichage |
| `sharedLight` | objet, **facultatif** | option « Colonnes lumière communes à toutes les grilles » ; absent = désactivée. `channel` (1…16, canal LightKey commun, qu'aucune grille n'utilise), `originGridID` (UUID de la grille qui reprend les colonnes en désactivant), `columnIndices` (positions 0…7 des colonnes communes, triées, non vides). **Chaque grille porte une copie identique** de chaque colonne commune, de type `light` |

### 2.2 Grille (`PadGrid`)

| Clé | Type | Contraintes |
| --- | --- | --- |
| `id` | UUID | identifiant stable de l'onglet |
| `name` | texte | nom de l'onglet |
| `kind` | `"appleMusic"`, **facultatif** | grille Apple Music (colonnes `music` et `light` seulement). **Absent = grille standard** (colonnes `audio`, `mixed`, `light`) ; `"standard"` n'est jamais écrit. Version 3 |
| `columns` | tableau de colonnes | **exactement 8**, de gauche à droite |
| `parkedColumns` | tableau, **facultatif** | colonnes mises de côté pendant que l'option `sharedLight` est active : `{ "index": 0…7, "column": Colonne }`. Absent = aucune. Leurs sons restent dans `Audio/` |
| `lightChannel` | entier ou `null` | canal MIDI LightKey de la grille, **1 à 16**, unique entre les grilles ; `null` = « Sans canal » (la lumière de la grille n'envoie rien). **Toujours écrit**, `null` compris. **Absent à la lecture** = fichier d'avant le canal par grille : migration (voir § 3) |

### 2.3 Colonne (`Column`)

| Clé | Type | Contraintes / valeur par défaut |
| --- | --- | --- |
| `id` | UUID | |
| `name` | texte | « Colonne 1 »… par défaut |
| `kind` | `"audio"`, `"light"`, `"mixed"` (son et lumière) ou `"music"` (Apple Music, version 3) | `audio` accepte des pads son, `light` des pads lumière, `mixed` les trois types de pads (son, lumière, son et lumière), `music` les pads Music seulement (grille Apple Music). Volume, filtre et stop : `audio` et `mixed` ; fader MIDI vers LightKey : `light` ; `music` : pas de fader (`level` 1, `filter` 0) |
| `level` | nombre | fader de la colonne, **0 à 1** (0,8 par défaut en audio, 1 en lumière) |
| `slots` | tableau de 8 éléments | **exactement 8**, de haut en bas ; `null` = case vide, sinon un pad |
| `isFaderPaired` | booléen | colonne lumière : fader appairé à LightKey. **Facultatif à la lecture** (absent = `false`) |
| `filter` | nombre | filtre DJ de la colonne son (`FilterCurve`), **−1 à +1** (passe-bas ↔ passe-haut), 0 = neutre. **Facultatif à la lecture** (absent = 0) |

Par défaut, les colonnes d'indices 6 et 7 (les deux de droite) sont des colonnes lumière, les six autres des colonnes son.

### 2.4 Pad (`Pad`)

| Clé | Type | Contraintes |
| --- | --- | --- |
| `id` | UUID | un nouvel identifiant à chaque duplication / collage |
| `title` | texte | l'éditeur limite à 80 caractères (`ShowController.maximumTextLength`) ; la lecture ne vérifie pas |
| `subtitle` | texte | idem |
| `tint` | texte | l'une des 16 teintes (§ 2.5). **Jamais un code couleur** : chaque pilote la traduit |
| `ledIntensity` | texte | `"pastel"`, `"full"`, `"half"`, `"quarter"` |
| `audio` | objet `AudioClip`, **facultatif** | le son du pad (§ 2.6) |
| `light` | objet `LightCue`, **facultatif** | la cue envoyée à LightKey (§ 2.7) |
| `awaitsSound` | booléen, facultatif | « son et lumière » choisi, son pas encore déposé : seulement avec `light` et sans `audio`. Absent = `false`. **Écrit seulement s'il est vrai** |
| `lightRetrigger` | `"turnOnOnly"` ou `"toggle"`, facultatif | nouvel appui d'un pad son **et** lumière : n'envoyer la note que si LightKey dit la cue éteinte ou inconnue (défaut), ou à chaque appui. **Écrit seulement s'il n'est pas le défaut** |

| `music` | objet `MusicTrackRef`, **facultatif** | un morceau d'Apple Music (version 3) : `persistentID` (identifiant persistant de Music, **hexadécimal, 1 à 32 caractères** : il entre dans une commande AppleScript), `title`, `artist`, `album`, `duration` (secondes, 0 à 86 400), `playlistName` (facultatif). **Exclusif** : un pad Music n'a ni `audio`, ni `light`, ni `awaitsSound` |

Un pad Music n'a que `music`. Sinon, un pad a **au moins une** des deux parties `audio` / `light` ; son type est déduit : `audio` seul = son, `light` seul = lumière, les deux (ou
`light` avec `awaitsSound`) = son et lumière. **Version 1** : un pad portait `content` = `{"audio": {"clip": …}}` ou `{"light": {"cue": …}}` ; cette
forme est toujours lue et convertie, jamais écrite. Un pad qui mêle les deux formes (`content` avec `audio` ou `light`), ou dont `content` est
vide, est illisible (`corrupt`).

### 2.5 Teintes (`Tint`)

`rouge`, `orange`, `ambre`, `lime`, `vert`, `menthe`, `lagon`, `turquoise`, `ciel`, `azur`, `indigo`, `violet`,
`fuchsia`, `rose`, `blanc`, `graphite`.

### 2.6 Son (`AudioClip`, dans `audio`)

| Clé | Type | Contraintes / valeur par défaut |
| --- | --- | --- |
| `fileName` | texte | nom d'un fichier de `Audio/`, **jamais un chemin** (§ 4) |
| `trimStart` | nombre | début de la partie jouée, secondes, **≥ 0** (0) |
| `trimEnd` | nombre, facultatif | fin de la partie jouée, secondes, **> `trimStart`** ; absent = fin du fichier |
| `fadeIn` | nombre, facultatif | fondu d'entrée, secondes, 0 à 600 ; absent = aucun |
| `fadeOut` | nombre, facultatif | fondu de sortie, secondes, 0 à 600 ; absent = aucun (ignoré en boucle) |
| `loops` | booléen | lecture en boucle |
| `retrigger` | `"restart"` ou `"stop"` | effet d'un nouvel appui sur un pad qui joue (un appui sur un pad en pause reprend toujours) |
| `gainDB` | nombre | volume propre au pad, décibels, **−60 à +24** (l'inspecteur propose −60 à +12) |

### 2.7 Cue lumière (`LightCue`, dans `light`)

| Clé | Type | Contraintes |
| --- | --- | --- |
| `output` | objet `MIDIMessageSpec` | message envoyé à LightKey (§ 2.8) |
| `behavior` | `"impulse"`, `"toggle"` ou `"momentary"` | appui = envoi unique / bascule ON-OFF / actif tant que le pad est enfoncé |
| `ledFeedback` | booléen | la LED suit l'état renvoyé par LightKey |
| `isPaired` | booléen | cue appairée à une cue de LightKey (ADR 0006). **Facultatif à la lecture** (absent = `false`) |

### 2.8 Message MIDI (`MIDIMessageSpec`)

| Clé | Type | Contraintes |
| --- | --- | --- |
| `kind` | `"note"` ou `"controlChange"` | |
| `channel` | entier | **0 à 15** (affiché 1 à 16) |
| `number` | entier | **0 à 127** (note ou numéro de contrôleur) |
| `value` | entier | **0 à 127** (vélocité ou valeur « ON », 127 par défaut) |

### 2.9 Ce qui n'est jamais écrit

L'état vivant n'est pas dans le fichier : lecture en cours, états des cues renvoyés par LightKey (`LightState`), sortie audio
choisie (gardée dans les `UserDefaults`), contrôleur connecté, cadenas (un spectacle enregistré s'ouvre verrouillé, un neuf déverrouillé).

### 2.10 Exemple minimal

```json
{
  "formatVersion" : 2,
  "grids" : [
    {
      "columns" : [
        {
          "id" : "6B8E0B1E-3C0E-4B52-9D77-0A9C2D1F4A10",
          "kind" : "audio",
          "level" : 0.8,
          "name" : "Colonne 1",
          "slots" : [
            {
              "audio" : {
                "fileName" : "rire.wav", "gainDB" : 0, "loops" : false,
                "retrigger" : "restart", "trimStart" : 0 },
              "id" : "0F3A5C52-7C1D-4E0A-8D0B-2B7C9E6A1D33",
              "ledIntensity" : "full",
              "subtitle" : "",
              "tint" : "vert",
              "title" : "Rire"
            },
            null, null, null, null, null, null, null
          ]
        }
      ],
      "id" : "A1D3F2B4-5E6F-4A7B-8C9D-0E1F2A3B4C5D",
      "name" : "Grille 1"
    }
  ],
  "name" : "Match du 14 novembre"
}
```

(Abrégé : un vrai fichier a 8 colonnes de 8 cases par grille — `validate()` refuse le contraire.)

## 3. Validation à la lecture

Toute donnée lue d'un fichier passe par `ShowPackage.decode` (ou `decodeMigrating`), qui enchaîne : taille ≤ 10 Mio → décodage JSON →
migration → `Show.validate()`.

**Migration « canal par grille »** (25/11/2026) : les grilles lues **sans** clé `lightChannel` reçoivent un canal (grille N → canal N s'il est
libre, sinon le premier libre, sinon `null`). Jusque-là tout partait sur le canal 1 : les cues (`isPaired`) et faders (`isFaderPaired`)
appairés des grilles 2 et suivantes sont remis à `false`, et `Contents.lightPairingsReset` donne ces grilles (l'app le signale une fois).
Premier échec = ouverture refusée, avec l'erreur correspondante :

| Erreur | Cause |
| --- | --- |
| `tooLarge` | `show.json` > 10 Mio |
| `corrupt` | JSON illisible, ou clé obligatoire manquante / de mauvais type |
| `invalid(unsupportedFormatVersion)` | `formatVersion` < 1 ou > 2 |
| `invalid(noGrid)` / `tooManyGrids` | 0 grille / plus de 64 |
| `invalid(wrongColumnCount)` | une grille n'a pas 8 colonnes |
| `invalid(wrongSlotCount)` | une colonne n'a pas 8 cases |
| `invalid(padKindMismatch)` | un pad que sa colonne n'accepte pas : un pad son dans une colonne lumière (ou l'inverse), ou un pad son et lumière dans une colonne qui n'est pas `mixed` |
| `invalid(unsafeFileName)` | `fileName` vide, > 255 caractères, `.`/`..`, commençant par un point, ou contenant `/ \ :`, NUL, un caractère de contrôle |
| `invalid(duplicateLightChannel)` | deux grilles sur le même canal LightKey |
| `invalid(valueOutOfRange)` | pad sans son ni lumière, pad « en attente de son » qui a déjà un son (ou pas de cue), canal LightKey hors 1…16, colonnes communes incohérentes (vides, hors 0…7, ou pas de type `light` dans une grille), colonne mise de côté hors 0…7, niveau de colonne hors 0…1, filtre hors −1…1, `trimStart` < 0, `trimEnd` ≤ `trimStart`, fondu < 0 ou > 600 s, gain hors −60…24 dB, MIDI hors plage |

Erreurs de paquet (avant `show.json`) : `notAPackage` (pas un dossier), `missingShowFile` (pas de `show.json` régulier).

## 4. Dossier `Audio/`

- À plat : seuls les **fichiers réguliers** dont le nom passe `AudioClip.isSafeFileName` sont retenus ; le reste est ignoré en silence.
- Formats importés par glisser-déposer : WAV, AIFF, CAF, MP3, M4A, AAC, FLAC (`AudioImporter.supportedExtensions`).
- **Son manquant** (référencé par un pad, absent d'`Audio/`) : le spectacle s'ouvre quand même, le pad reste muet, l'app signale la liste (`Contents.missingAudio`).
- **Écriture** : `show.json` est réécrit, et `Audio/` ne reçoit que les sons que le spectacle utilise encore. Un son retiré de la grille quitte donc
  le paquet à l'enregistrement suivant. Les sons déjà présents ne sont pas recopiés (le `FileWrapper` existant est conservé).
- **Ouverture** : seuls les sons utilisés sont copiés dans un dossier de travail (caches de l'app) ; les imports y arrivent, l'enregistrement les ajoute au paquet.
- Noms : `AudioClip.safeFileName(from:)` nettoie un nom quelconque, `AudioClip.uniqueFileName(_:avoiding:)` ajoute « 2 », « 3 »… en cas d'homonyme.

## 5. Évolution du format

- **Changement compatible** (nouvelle clé facultative) : pas de nouvelle version. Le décodeur personnalisé utilise `decodeIfPresent` avec une
  valeur par défaut, comme pour `isFaderPaired`, `isPaired` et `filter` : un spectacle ancien s'ouvre sans modification.
  *Attention* : un spectacle enregistré par une version récente puis rouvert par une version plus ancienne perd les clés qu'elle ne connaît pas.
- **Changement incompatible** (clé renommée ou retirée, sens modifié) : incrémenter `Show.currentFormatVersion`, écrire la migration
  à la lecture (`ShowPackage.decodeMigrating` et les `init(from:)` concernés), ajouter un fichier d'exemple de l'ancienne version aux tests.
- **Version 2 (25/11/2026, ADR 0008)** : le contenu d'un pad passe de `content` (un son **ou** une cue) à `audio` et `light` à plat (un son, une cue,
  ou les deux), pour les pads « son et lumière » et les colonnes `mixed`. La lecture convertit `content` ; l'écriture est toujours en version 2.
  **Une ancienne version de Lalabob ne peut pas ouvrir un fichier de version 2** (`unsupportedFormatVersion`) : mettre à jour tous les Mac de
  régie en même temps, et garder une copie des spectacles avant la première ouverture avec la nouvelle version.
- **Version 3 (27/11/2026, spec « Grilles Apple Music »)** : `PadGrid.kind`, `ColumnKind.music`, `Pad.music`. Écrite **seulement** si le spectacle a une
  grille Apple Music ou une colonne Music : un spectacle sans Apple Music reste en version 2, lisible par l'app précédente. Une ancienne version ne
  lit pas la version 3. Tests : `MusicGridTests`.
- Un format de fichier ne se modifie jamais sans test (`CLAUDE.md`) : `ShowPackageTests`, `ShowTests`, `ClipSettingsTests`.

## 6. Tests de référence

| Fichier | Couvre |
| --- | --- |
| `Tests/LalabobModelTests/ShowPackageTests.swift` | aller-retour du paquet, JSON stable, sons manquants, paquet invalide, JSON illisible, taille |
| `Tests/LalabobModelTests/ShowTests.swift` | validation du modèle |
| `Tests/LalabobModelTests/PadTypesTests.swift` | types de colonnes et de pads, lecture d'un **vrai** `show.json` de version 1 (`Fixtures/show-v1.json`), aller-retour en version 2 |
| `Tests/LalabobModelTests/ClipSettingsTests.swift` | élagage, fondus, gain |
