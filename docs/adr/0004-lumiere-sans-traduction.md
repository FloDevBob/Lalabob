# ADR 0004 — Lumière : LightKey écoute le contrôleur, Lalabob ne traduit rien

- Date : 30 octobre 2026
- État : acceptée (remplace la « traduction note → message » prévue au J3)

## Contexte

Les notes des pads des colonnes lumière sont déjà apprises dans le mapping MIDI de LightKey,
directement depuis le contrôleur (Launchpad ou APC). Plusieurs apps peuvent lire le même contrôleur.

## Décision

- **Appui physique** sur un pad lumière : LightKey le reçoit seul. Lalabob n'envoie rien (sinon la cue partirait deux fois).
- **Clic à l'écran** (mode Live) sur un pad lumière : Lalabob envoie **la note que le contrôleur aurait envoyée**
  (Note On vélocité 127, puis Note Off 100 ms plus tard, canal 1) sur un port virtuel **« Lalabob Lumière »**.
  LightKey doit écouter aussi ce port, avec le même mapping (mapping en double, accepté).
- La note suit le contrôleur connecté, sinon le dernier contrôleur connu (mémorisé) ; sans contrôleur connu, rien n'est envoyé.
- **LED** des pads lumière : Lalabob les allume en permanence de la couleur choisie dans l'app. LightKey ne renvoie rien au contrôleur.
- Le port virtuel garde son identifiant unique d'un lancement à l'autre (LightKey le retrouve) ; Lalabob ne l'écoute jamais.

## Conséquences

- Aucun message MIDI à configurer par pad : `LightCue.output` et `LightCue.behavior` ne sont plus utilisés (conservés
  dans le format pour l'instant ; à retirer ou réutiliser lors d'un prochain changement de format, avec migration).
- Comportements « bascule » / « maintenu » : gérés par LightKey, pas par Lalabob.
- Le panneau « traduction MIDI » de l'inspecteur lumière (maquette) n'a plus lieu d'être ; il reste le titre et la couleur.
