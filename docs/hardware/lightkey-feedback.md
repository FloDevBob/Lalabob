# Retour de LightKey vers Lalabob — relevé (J7, étape 0)

**À remplir sur le vrai Mac de régie.** Lalabob crée la destination MIDI virtuelle **« Lalabob Retour Lumière »**
(en plus de la source « Lalabob Lumière »). Une **seconde destination du même nom que la source**, « Lalabob Lumière », reçoit le même retour : LightKey voit ainsi un seul appareil avec entrée et sortie (hypothèse à vérifier : il associe peut-être entrée et sortie par le nom). Les deux destinations sont équivalentes ; le journal indique laquelle a reçu le message. Tout ce que LightKey y envoie est journalisé, tel quel, sans rien déclencher.

## Mise en place

1. Lancer Lalabob (les deux ports apparaissent dans LightKey, Réglages MIDI).
2. Dans LightKey : entrée = « Lalabob Lumière », *Send Feedback To* = « Lalabob Retour Lumière ».
3. Dans Lalabob : menu **Fenêtre ▸ Banc d'essai lumière** (⌥⌘L). La fenêtre montre l'état des ports, une grille 8×8 du
   contrôleur (avec les numéros de note) et le **journal en direct** : « Contrôleur → », « → LightKey », « LightKey → ».
   Le bouton **Copier** met le journal dans le presse-papiers (pour me le coller).
   (Le même journal existe dans OSLog : `log stream --level info --predicate 'subsystem == "fr.lalabob.app" AND category == "lighting"'`.)
4. Le journal OSLog montre les **mots UMP bruts** : un Note On de vélocité 0 reste un Note On, les messages que Lalabob
   ignore (changement de programme, pitch bend…) apparaissent aussi.
5. Regarder aussi la fenêtre *External Control* de LightKey : les messages de retour y sont personnalisables.

## Relevé

| Scénario | Type | Canal | Numéro | Vélocité / valeur | Remarque |
| --- | --- | --- | --- | --- | --- |
| Cue lancée | | | | | |
| Cue arrêtée | | | | | |
| Cue changée de couleur | | | | | |
| Cue supprimée | | | | | |
| Démarrage de LightKey | | | | | |
| Ouverture du spectacle | | | | | |

## Conclusion (à cocher)

- ☐ **Cas A** : retour on/off seulement → Lalabob affiche la teinte choisie, allumée quand la cue est active.
- ☐ **Cas B** : retour en couleur (vélocité = couleur, canal = comportement, ou personnalisé) → table vers RVB.

Ensuite : copier les lignes relevées dans `Tests/…/Fixtures` (un fichier de messages par cas), puis passer à l'étape 2.
