# Fiche 03 — 9e fader de l'APC → volume d'Apple Music

Branche `j9/fader-apple-music`. Skill `midi-driver`. Maquette : planche 5 (colonne de droite) et en-tête de la planche 1.
Écrire **ADR 0009** (« Piloter Apple Music depuis Lalabob ») dans la même PR.

## Pour l'utilisateur
Le 9e fader de l'APC règle le volume d'Apple Music, sans le script Python. Une pastille « Apple Music 62 % » dans
l'en-tête (seulement si l'APC est branché) ; un clic ouvre un réglage : activer / désactiver, volume actuel, explication.
États de la pastille : actif (rose), « fermé » (Music n'est pas lancé : rien n'est envoyé), « à autoriser » (macOS a refusé).

## Ce que faisait le script (`~/Documents/scripts_midi/midi_applemusic_volume.py`)
Écoute **CC 7, canal 3** ; volume = `int(valeur / 127 * 100)` ; n'envoie que si l'écart avec le dernier envoi est ≥ 2 % ;
lance `osascript -e 'tell application "Music" to set sound volume to N'` à chaque fois (ce qui **ouvre Music** s'il est fermé).

## ⚠︎ Étape préalable : relever le vrai message
Le script lit CC 7 / canal 3, mais `APCMiniMK2Driver.masterFaderCC = 56` (canal 1) et `docs/hardware/apc-mini-mk2.md`
annonce CC 56 ⚠︎. Demander à Florian de bouger le 9e fader avec le banc d'essai ouvert (⌥⌘L, Copier le journal) ;
reporter le résultat dans `docs/hardware/apc-mini-mk2.md`. Coder la valeur relevée ; sinon accepter **les deux** (CC 56
canal 1 et CC 7 canal 3) en constantes commentées ⚠︎, et le dire dans la PR.

## Pilote
- Nouveau cas `ControllerInput.auxiliaryFader(value: Double)` (0…1). APC : le CC relevé → ce cas. Aujourd'hui
  `interpret` écarte tout CC ≥ 56 : garder les faders 1–8 inchangés.

## Moteur
- Protocole `MediaVolumeControlling: Sendable` (LalabobEngine) :
  `func status() async -> MediaVolumeStatus` (`.running`, `.notRunning`, `.notAuthorized`) et
  `func setVolume(percent: Int) async throws`.
- `MediaVolumeRelay` (pur, testable, horloge injectée) : reçoit les valeurs du fader ; convertit comme le script ;
  **seuil 2 %** ; **au plus un envoi toutes les 66 ms**, la dernière valeur gagne (la valeur finale part toujours) ;
  rien si désactivé.
- `AppleMusicVolume` (actor, `LalabobEngine/AppleMusicVolume.swift`) : **ScriptingBridge**,
  `SBApplication(bundleIdentifier: "com.apple.Music")`, `isRunning` vérifié **avant chaque envoi** (ne jamais lancer
  Music), `setValue(percent, forKey: "soundVolume")`. `SBApplication` n'est pas `Sendable` : la garder dans l'acteur.
  Erreur d'autorisation (code −1743, `errAEEventNotPermitted`) → `.notAuthorized`. Rien sur le fil principal.
- `ControllerSession` : `.auxiliaryFader` → relais ; propriété observable `musicVolume: Int?` et `musicStatus` ;
  réglage « activé » dans `UserDefaults` (préférence de ce Mac, comme l'étalonnage des LED).
- **Ne jamais** toucher au volume des pads, des colonnes, ni à la sortie audio de Lalabob.

## Projet (`project.yml`, puis `make project`)
- Entitlements de l'app : `com.apple.security.temporary-exception.apple-events: [com.apple.Music]` et
  `com.apple.security.automation.apple-events: true`.
- Info : `NSAppleEventsUsageDescription` = « Lalabob règle le volume d'Apple Music avec le 9e fader de l'APC mini mk2. »

## Interface (`App/HeaderView.swift`)
Pastille à gauche du contrôleur (icône note de musique rose, mini-barre, valeur mono) ; popover avec interrupteur
« Piloter le volume d'Apple Music », barre de volume, texte : « Ne touche que le volume d'Apple Music. N'ouvre jamais Music.
Désactivez ceci si un autre logiciel s'en charge déjà. » Infobulle et libellé VoiceOver.

## Tests (écrire d'abord)
- Pilote : CC relevé → `.auxiliaryFader` ; faders 1–8 inchangés ; CC 56 n'est plus « jamais produit » (adapter le test existant).
- `MediaVolumeRelay` avec un faux contrôleur de volume : conversion 0/64/127 → 0/50/100 ; écart < 2 % ignoré ; rafale de 20
  valeurs en 100 ms → ≤ 3 envois et la dernière part ; Music fermé → aucun envoi ; désactivé → aucun envoi.
- `AppleMusicVolume` : pas de test automatique (Apple Events réels) — le dire dans la PR.

## Essai sur le matériel
☐ Arrêter le script Python ☐ première utilisation : macOS demande l'autorisation ☐ fader → volume de Music, sans à-coups
☐ Music fermé : rien ne se passe, Music ne s'ouvre pas ☐ refuser l'autorisation : pastille « à autoriser » ☐ aucun effet
sur les sons de Lalabob ☐ latence des pads inchangée en bougeant le fader pendant un son.

## Terminé quand
Tests verts ; Music suit le fader ; Music jamais ouvert ; ADR 0009 écrite.
