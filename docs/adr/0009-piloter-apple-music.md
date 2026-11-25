# ADR 0009 — Piloter le volume d'Apple Music depuis Lalabob

Date : 25/11/2026 · Statut : accepté (essai matériel à faire)

## Contexte
Le 9e fader de l'APC mini mk2 réglait le volume d'Apple Music par un script Python (`midi_applemusic_volume.py`) : écoute d'un CC,
`osascript` à chaque mouvement. Il fallait le lancer à part, et chaque appel **ouvrait Music** s'il était fermé.

## Décision
Lalabob fait ce travail lui-même, par **Apple Events** (ScriptingBridge, `SBApplication`), sans script ni dépendance :
- `MediaVolumeRelay` (acteur, pur et testable) : conversion `int(valeur / 127 × 100)`, écart minimal de 2 % (sauf 0 % et 100 %),
  au plus un envoi toutes les 66 ms, la dernière valeur gagne ;
- `AppleMusicVolume` (acteur) : vérifie que Music tourne **avant chaque envoi** et ne le lance jamais ; refus de macOS → état « à autoriser » ;
- ne touche **jamais** au volume des pads, des colonnes ni à la sortie audio de Lalabob ;
- préférence de ce Mac (`UserDefaults`), activée par défaut ; interrupteur dans l'en-tête (pastille « Apple Music »), pour éviter un double pilotage si le script tourne encore.

Entitlements : `com.apple.security.automation.apple-events` et l'exception temporaire `com.apple.security.temporary-exception.apple-events` limitée à `com.apple.Music` ;
`NSAppleEventsUsageDescription` explique la demande d'autorisation (une seule fois).

## Message du 9e fader
Le script lit **CC 7 canal 3** ; la doc de l'APC annonce **CC 56 canal 1** ⚠︎. Les deux sont acceptés (`APCMiniMK2Driver`), en attendant le relevé au banc d'essai.

## Conséquences
- Le sandbox impose l'exception temporaire d'Apple Events (acceptable : signature locale, pas de Mac App Store).
- `AppleMusicVolume` n'a pas de test automatique (de vrais Apple Events) : essai à la main.
