# ADR 0010 — Grilles Apple Music : piloter l'app Music, ne pas lire son son

Date : 27/11/2026 · Statut : accepté (essai réel à faire)

## Contexte
La troupe veut des pads qui lancent des morceaux de ses playlists Apple Music. Les morceaux du catalogue sont protégés (DRM) :
Lalabob ne peut ni lire leurs échantillons ni les faire passer par son moteur audio. MusicKit (lecteur intégré) demande un compte
développeur payant ; Lalabob est signé en local.

## Décision
- **Piloter l'app Music par AppleScript** (`NSAppleScript`, une file série hors du fil principal, `MusicScripting`). Music n'est **jamais lancé**
  par Lalabob en scène (bouton « Ouvrir Music » seulement déverrouillé).
- Autorisations : `com.apple.security.scripting-targets` (groupes `playback`, `library.read`, `library.read-write` déclarés par Music) et
  l'exception `temporary-exception.apple-events` pour `com.apple.Music` ; `NSAppleEventsUsageDescription`.
- **Un morceau à la fois** (Music n'a qu'un lecteur) ; fondus faits avec le volume général de Music, qui appartient au 9e fader (ADR 0009).
- Recherche, extraits de 30 s et pochettes de secours : **recherche publique d'Apple** (iTunes Search, sans clé) ; `network.client` ; seules
  les adresses https d'Apple sont suivies. Seul le texte cherché part sur le réseau.
- Vumètre : **essai** par la capture audio de macOS (`CATapDescription`, son non modifié), désactivé par défaut (autorisation
  « enregistrement audio », `NSAudioCaptureUsageDescription`).
- Format `.lalabob` version 3 (grille Apple Music, colonne et pad Music), écrite seulement si le spectacle s'en sert.

## Conséquences
- Pas de forme d'onde, d'élagage, de fondus réglables ni de volume par pad pour un morceau.
- Si Music plante, ou si un morceau non téléchargé n'a pas de réseau, le son s'arrête : les pads le signalent (☁, « Introuvable »).
- Leçons relevées sur la vraie bibliothèque : variables AppleScript préfixées (un nom comme `hidden` est une propriété de Music, −10003) ;
  lectures groupées (`… of every user playlist`) ; dossiers repérés par `every folder playlist` ; morceau d'abonnement téléchargé =
  `file track`, nuage = `shared track`.
- Piste ouverte : faire passer le son de Music par Lalabob (capture + lecture dans le moteur) pour un volume par colonne et les filtres.
