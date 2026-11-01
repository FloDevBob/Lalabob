# Retour de LightKey vers Lalabob — relevé (J7, étape 0)

**À remplir sur le vrai Mac de régie.** Lalabob crée la destination MIDI virtuelle **« Lalabob Retour Lumière »**
(en plus de la source « Lalabob Lumière »). Tout ce que LightKey y envoie est journalisé, tel quel, sans rien déclencher.

## Mise en place

1. Lancer Lalabob (les deux ports apparaissent dans LightKey, Réglages MIDI).
2. Dans LightKey : entrée = « Lalabob Lumière », *Send Feedback To* = « Lalabob Retour Lumière ».
3. Lire le journal, dans Terminal :
   `log stream --level info --predicate 'subsystem == "fr.lalabob.app" AND category == "lighting"'`
   (ou la Console, filtre « lighting »). Chaque ligne : `Retour LightKey : Note On · canal 1 · note 36 · vélocité 5 [20902405]`.
4. Le journal montre les **mots UMP bruts** : un Note On de vélocité 0 reste un Note On, les messages que Lalabob
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
