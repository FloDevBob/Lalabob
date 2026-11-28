# Spec — Fenêtre d'accueil

Version validée le 28/11/2026 (piste « B1·2 » retouchée). Maquette : https://claude.ai/artifact/PBWK8eEPvzXV6o3RDscfm7,
planche **« Version retenue (B1·2 retouchée) — à implémenter »** (réglage Tweaks › État du matériel pour voir chaque état).
Les autres planches sont l'historique des pistes écartées.

## Idée
Au lancement, avant tout spectacle, une petite fenêtre **Bienvenue** :
- vérifie d'un coup d'œil le matériel (son, contrôleur, lumière) ;
- ouvre un spectacle récent, en crée un nouveau ou en ouvre un autre ;
- met en avant la **visite guidée** et le **spectacle d'entraînement**.

Elle **remplace la fenêtre « Ouvrir » de macOS** au lancement et la visite guidée ouverte d'office au premier spectacle
(limite connue du J12).

## Décisions (28/11/2026)
| Sujet | Décision |
| --- | --- |
| Mise en page | En-tête (logo, sous-titre, deux boutons) ; à gauche **Avant de jouer** (3 lignes) ; à droite **Découvrir Lalabob** puis **Spectacles récents** (liste de 3) |
| Taille | **960 × 520 pt**, non redimensionnable, mode sombre, titre masqué (comme la fenêtre principale) |
| Bouton principal | **Nouveau spectacle** à la couleur d'accent de l'app (`AccentColor`, #5D80B5), assombrie à **#4D70A6** pour un texte blanc lisible (5,0 : 1 ; #5D80B5 donne 4,0 : 1) |
| Bouton secondaire | **Ouvrir un spectacle…** (en toutes lettres) |
| Statuts | **Toujours en mots** (étiquette « Prêt » / « Prête » en vert, « À brancher » / « À préparer » en gris) ; le point coloré n'est qu'une décoration |
| Textes | **Suivent l'état en cours** : prêt = ce qui est détecté ; pas prêt = une phrase qui dit ce qui manque et quoi faire. Jamais la liste de toutes les possibilités |
| LightKey | **Pas de bouton** : un lien sur les mots « ouvrez LightKey » dans la phrase |
| Son | Toujours afficher **où sort le son** (nom de la sortie) |
| Rien de bloquant | On peut ouvrir un spectacle même si rien n'est prêt : tout se branche à chaud |

## Ce que voit l'utilisateur

### Mesures (grille de 4 pt, à respecter partout dans la fenêtre)
| Élément | Valeur |
| --- | --- |
| Marges de la fenêtre / écart entre blocs | 24 / 16 pt |
| Cartes | padding 16, rayon 16, fond `Surface.panel` (#15161B) ; carte « Découvrir » en `Tint.ambre` |
| Boutons | **tous 32 pt de haut**, rayon 8, texte 13 demi-gras, 14 pt de marge latérale |
| Étiquettes de statut | 20 pt de haut, rayon 10, texte 11 demi-gras |
| Icônes de ligne | carré de 28 pt (rayon 8), pictogramme de 16 pt |
| Texte | titre de bloc 15/20 demi-gras · corps 13/18 · phrase 12/17 · petites capitales 11/16 (interligne en pt) |
| Lignes de la liste de contrôle | 12 pt au-dessus et au-dessous, filet de 1 pt (blanc 6 %) entre elles, 6 pt entre la ligne et sa phrase |

### En-tête (76 pt)
Icône de l'app (44 pt) · « Lalabob » (Fredoka, 26 pt) · « Régie son et lumière pour l'impro » ·
à droite : **Ouvrir un spectacle… ⌘O** (secondaire) et **Nouveau spectacle ⌘N** (principal, accent).

### Avant de jouer (colonne de gauche, 360 pt)
Titre et résumé à droite : « 2 sur 3 prêts » (gris) ou « Tout est prêt » (vert). Trois lignes alignées sur la même grille :
icône · NOM (petites capitales) + ce qui est détecté · étiquette de statut ; dessous, une phrase sur toute la largeur.
En bas : case **Afficher cette fenêtre au lancement** (cochée par défaut).

| Ligne | État | Étiquette | Ligne principale | Phrase |
| --- | --- | --- | --- | --- |
| Son | sortie autre que les haut-parleurs du Mac | Prêt | nom de la sortie (ex. « Écouteurs externes ») | Le son sort par la prise casque. Sortie à changer en haut de la grille. ¹ |
| Son | haut-parleurs du Mac | À brancher | nom de la sortie (ex. « Haut-parleurs du MacBook ») | Le son sort du Mac lui-même : branchez l'enceinte sur la prise casque (mini-jack). |
| Contrôleur | APC ou Launchpad détecté | Prêt | nom du modèle | Reconnu, les pads s'allument à l'ouverture du spectacle. |
| Contrôleur | rien | À brancher | Aucun contrôleur | Branchez l'APC mini mk2 ou le Launchpad Mini MK3 en USB. |
| Lumière | boîtier USB-DMX branché | Prête | Boîtier USB-DMX | Lalabob pilote les projecteurs lui-même. Fermez LightKey. ² |
| Lumière | LightKey ouvert | Prête | LightKey ouvert | Lalabob lui envoie les appuis des colonnes lumière. |
| Lumière | ni l'un ni l'autre | À préparer | Rien de détecté | Branchez le boîtier USB-DMX, ou [ouvrez LightKey](#). |

¹ Si la sortie n'est pas la prise casque (carte son USB, AirPlay…), la phrase devient « Sortie à changer en haut de la grille. ».
² Boîtier **et** LightKey présents : afficher le boîtier, avec la phrase « Fermez LightKey : les deux enverraient à la barre. »
(règle de l'ADR 0012 / étape 5 du J14).

### Découvrir Lalabob (en haut à droite)
Carte ambre (`Tint.ambre` : fond #755A0E, texte #FFF2C7), ampoule dans un carré de 28 pt : « Découvrir Lalabob » · « Visite guidée en
5 chapitres, puis un spectacle d'entraînement pour essayer sans rien casser. » · deux boutons côte à côte sous le texte :
**Commencer la visite** (ambre vif #FFC93D, texte foncé) et **Spectacle d'entraînement** (fond noir 22 %).

### Spectacles récents
Une carte avec une **liste** des **3** derniers documents ouverts. Chaque ligne : **vignette 40 × 40 pt** = aperçu 8 × 8 de la première
grille (couleur de fond de chaque pad, ambre #755A0E pour une cue lumière, case vide #22252B), nom du spectacle, « 42 sons · 3 grilles »,
date à droite. Clic = ouvrir ; survol = léger éclaircissement de la ligne. Fichier introuvable :
la carte n'apparaît pas. Aucun récent : la zone affiche « Vos spectacles apparaîtront ici. » et l'aperçu disparaît.

## Comportement
- **Au lancement** : la fenêtre s'affiche si la case est cochée **et** qu'aucun document n'est rouvert par macOS (restauration).
  Case décochée : comportement actuel (fenêtre « Ouvrir »).
- **Menu Fenêtre › Bienvenue dans Lalabob** (⇧⌘1) la rouvre à tout moment.
- Elle **se ferme** dès qu'un spectacle s'ouvre (nouveau, ouvert, récent, entraînement). « Commencer la visite » ouvre la visite
  par-dessus, sans la fermer.
- La visite guidée **ne s'ouvre plus d'office** au premier spectacle (`FirstLaunchTour` retiré) : la carte « Découvrir Lalabob » la remplace.
- Les statuts se mettent à jour **en direct** (brancher l'APC fait passer la ligne au vert sans rien faire).
- Clavier : ⌘N, ⌘O, Tab entre les boutons et les cartes, Retour sur une carte = l'ouvrir. Échap ne ferme pas la fenêtre
  (Échap reste « Tout arrêter » partout).

## Technique

### Scène et lancement
- Une scène `Window("Bienvenue dans Lalabob", id: "welcome")` à côté du `DocumentGroup`, `windowResizability(.contentSize)`,
  `.windowStyle(.hiddenTitleBar)`, `.defaultLaunchBehavior(.presented)` (macOS 15+) **seulement si la préférence est cochée**.
- Empêcher la fenêtre « Ouvrir » de macOS au lancement : `AppLifecycle.applicationShouldOpenUntitledFile(_:) -> false`, et vérifier qu'aucune
  fenêtre « Ouvrir » ne s'affiche quand même. **Prototypé le 28/11/2026** : il faut aussi `NSShowAppCentricOpenPanelInsteadOfUntitledFile = false` (domaine d'enregistrement, rien d'écrit dans les préférences). Lancée en arrière-plan (`open -g`), l'app n'affiche pas l'accueil.
- Actions : `@Environment(\.newDocument)`, `@Environment(\.openDocument)` (récents, entraînement via `Tour.openTrainingShow`),
  `NSDocumentController.shared.openDocument(nil)` pour « Ouvrir un spectacle… », `openWindow(id: Tour.windowID)` pour la visite,
  puis fermeture de l'accueil par `Welcome.close()` (AppKit : `dismissWindow` depuis la fenêtre d'un spectacle ne la ferme pas).
- Préférence : `UserDefaults` `showWelcomeAtLaunch` (vrai par défaut).

### État du matériel : un modèle pur, testé
`WelcomeChecklist` (LalabobEngine, `struct`, `Sendable`) : prend les **faits** et rend les 3 lignes (statut, ligne principale, phrase,
lien éventuel) et le résumé. Aucune E/S : c'est lui que les tests couvrent. Les textes du tableau ci-dessus vivent ici.

Faits et où les trouver :
| Fait | Source |
| --- | --- |
| Sortie de Lalabob | `UserDefaults` `ShowController.outputDefaultsKey` (`audioOutputUID`) si cette sortie est branchée, sinon la sortie par défaut du Mac (`AudioOutputDevices.defaultOutputDeviceID`, à rendre publique avec son nom) |
| Sortie = haut-parleurs du Mac ? | Type de transport `kAudioDeviceTransportTypeBuiltIn` **et** source « haut-parleur » (`kAudioDevicePropertyDataSource` = `'ispk'`) ; prise casque = source `'hdpn'` ou périphérique « Écouteurs externes » sur Apple Silicon. ⚠︎ à relever sur le Mac de régie (noms et sources réels) |
| Changements | tout est relu **chaque seconde** tant que la fenêtre est ouverte (`HardwareStatus`) : plus simple que des écouteurs par source, et peu coûteux |
| Contrôleur | `ControllerSession` : modèle actif (`active?.model`), à exposer en propriété observable. **La session doit démarrer au lancement de l'app**, pas à l'ouverture de la première fenêtre de spectacle (aujourd'hui `midiSession?.start()` est dans le `onAppear` du document) |
| Boîtier USB-DMX | `DMXPortDiscovery.candidates(deviceNames:)` sur le contenu de `/dev`, relu chaque seconde tant que la fenêtre est ouverte (comme `DMXRefreshLoop`) ; sans ouvrir le port |
| LightKey ouvert | `NSRunningApplication.runningApplications(withBundleIdentifier: "de.monospc.Lightkey")` (relevé le 28/11/2026), relu chaque seconde |
| Ouvrir LightKey | `NSWorkspace.shared.openApplication(at:configuration:)` d'après l'identifiant ; LightKey absent du Mac : le lien n'apparaît pas, la phrase devient « Branchez le boîtier USB-DMX, ou installez LightKey. » |

**Honnêteté des statuts** (ADR 0006) : « LightKey ouvert » ne dit pas que LightKey écoute « Lalabob Lumière ». On ne prétend rien de plus ;
le détail reste dans le banc d'essai lumière.

### Récents et aperçus
- Liste : `NSDocumentController.shared.recentDocumentURLs` (le contrôleur de documents garde les accès du bac à sable), 3 premiers dont le fichier existe.
- Aperçu : lire **seulement** `show.json` dans le paquet (limite de 10 Mo de `ShowPackage`), `ShowPackage.decodeMigrating` puis `validate()`
  (règle du projet), en arrière-plan. Toute erreur = carte sans aperçu (fond uni), jamais d'alerte.
- `ShowThumbnail` (LalabobModel, pur) : `Show` → 64 teintes (colonne par colonne) + nombre de grilles. La vue convertit en couleurs avec `TintSpec.surface`.
- Date : « Aujourd'hui », « Hier », sinon « 21 nov. » (date de modification du paquet).

### Fichiers
- `App/WelcomeView.swift` (vue), scène dans `App/LalabobApp.swift`, menu dans `App/LalabobCommands.swift`.
- `LalabobEngine/WelcomeChecklist.swift`, `LalabobEngine/HardwareStatus.swift` (lit les faits, observable, démarre / s'arrête avec la fenêtre).
- `LalabobModel/ShowThumbnail.swift`.
- Textes : aussi dans `docs/GUIDE.md` et l'aide intégrée (rubrique « Pour commencer »).

## Tests (écrits d'abord)
- `WelcomeChecklistTests` : chaque ligne du tableau (7 cas + boîtier et LightKey ensemble + LightKey non installé) ; résumé « n sur 3 » / « Tout est prêt ».
- `ShowThumbnailTests` : grille vide, colonnes lumière en ambre, spectacle à plusieurs grilles (seule la 1re), spectacle v1 migré.
- Sortie haut-parleurs / prise casque : fonction pure sur (transport, source, nom), testée avec les valeurs relevées.

## Essai réel (à cocher)
☐ Premier lancement sur un Mac neuf : la fenêtre Bienvenue s'ouvre, pas la fenêtre « Ouvrir » ☐ décocher « Afficher au lancement », relancer
☐ brancher / débrancher l'enceinte sur la prise casque : la ligne Son change, avec le bon nom de sortie ☐ brancher l'APC puis le Launchpad
☐ brancher le boîtier USB-DMX ; ouvrir LightKey par le lien ; les deux ensemble ☐ ouvrir un récent, un nouveau, le spectacle d'entraînement : la fenêtre se ferme
☐ Fenêtre › Bienvenue (⇧⌘1) ☐ VoiceOver lit chaque statut ☐ aucun son ne démarre, aucune LED ne change avant l'ouverture d'un spectacle.

## Hors champ
Ouvrir par glisser-déposer d'un `.lalabob` sur la fenêtre ; épingler un spectacle ; plus de 3 récents (la liste complète reste dans Fichier › Ouvrir l'élément récent).
