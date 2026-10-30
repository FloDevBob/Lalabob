---
name: midi-driver
description: Ajouter ou modifier un pilote de contrôleur MIDI dans Lalabob (Launchpad, APC mini mk2 ou nouveau modèle) — notes vers cases, LED, faders, identification. À utiliser dès qu'on touche à ControllerDrivers ou docs/hardware.
---

# Pilote de contrôleur

Un pilote est une `struct` pure conforme à `ControllerDriver` : octets ⇄ valeurs, sans état ni E/S.

## Check-list

1. **Sources** : noter dans `docs/hardware/<modele>.md` le manuel officiel (lien), les octets SysEx,
   la disposition des notes, les CC des faders. Marquer ⚠︎ tout ce qui n'est pas vérifié sur le matériel.
2. **Identification** : fabricant et famille renvoyés par `DeviceInquiry` ; ajouter le cas à `ControllerModel`.
3. **Grille** : `note(for:)` et `position(forNote:)`. Tests obligatoires :
   les 4 coins, l'aller-retour sur les 64 cases, les notes hors grille → `nil`.
4. **Entrées** : `interpret(_:)` pour appui, relâchement, faders. Tout message inconnu → `nil`.
5. **LED** : `ledMessages(_:)` pour `.off`, `.lit(tint, intensity)`, `.pulsing(tint)`.
   Tester les octets exacts d'au moins une couleur et le découpage en messages.
6. **Connexion** : `connectionMessages` (mode Programmeur, extinction) et `disconnectionMessages`.
7. **Essai matériel** (dans la PR) : chaque coin s'allume au bon endroit ; les 16 teintes à côté de l'écran ;
   débrancher / rebrancher ; un autre logiciel écoute toujours le contrôleur.
