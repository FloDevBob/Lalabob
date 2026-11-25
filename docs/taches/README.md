# Fiches de tâches — J9 et J10

Une fiche = une étape du plan `docs/plan-types-et-grilles.md` = une branche + une PR.
Écrites le 25/11/2026 d'après le code de `j7/filtre-colonne` (version 1.1.1). Les noms de fichiers et d'API cités ont été
vérifiés dans ce code ; **si un nom ne correspond plus, chercher l'équivalent plutôt que l'inventer**, et le noter dans la PR.

Maquettes : https://claude.ai/artifact/8KceUvus4vE8SWtJVY7iqM (planches 1 à 6, citées dans les fiches).

| Fiche | Branche | Dépend de |
| --- | --- | --- |
| [00 — Fusion de la pile J6 / J7](00-fusion-pile.md) | — | — |
| [01 — Canal LightKey par grille](01-canal-par-grille.md) | `j9/canal-par-grille` | 00 |
| [01b — Colonnes lumière communes](01b-lumiere-commune.md) | `j9/lumiere-commune` | 01 |
| [02 — Changer de grille au contrôleur](02-grilles-au-controleur.md) | `j9/grilles-au-controleur` | 00 |
| [03 — 9e fader → Apple Music](03-fader-apple-music.md) | `j9/fader-apple-music` | 00 |
| [04 — Colonnes de même largeur](04-colonnes-egales.md) | `j10/colonnes-egales` | 00 |
| [05 — Modèle : types et format v2](05-types-modele.md) | `j10/types-modele` | 04 |
| [06 — Règles : conversions et jeu](06-types-regles.md) | `j10/types-regles` | 05 (et 01b si fusionnée) |
| [07 — Interface des types](07-types-interface.md) | `j10/types-interface` | 06 |
| [08 — Documentation](08-documentation.md) | `j10/documentation` | 07 |

## Règles communes (à relire avant chaque fiche)

1. **Déroulé** : suivre le skill `lalabob-feature` (branche, tests d'abord, code, `make test`, PR). Pour toute fiche qui
   touche `ControllerDrivers` ou `docs/hardware/`, suivre aussi le skill `midi-driver`.
2. **Tests d'abord** (Swift Testing : `@Test`, `#expect`). Chaque fiche liste les tests attendus ; en ajouter si besoin,
   n'en retirer aucun sans le dire dans la PR. Un pilote ou un format de fichier n'est **jamais** modifié sans test.
3. **Lancer les tests** : `make test`. En terminal, `swift test` peut échouer (module Testing absent, cache du bac à sable) :
   dans ce cas lancer les schémas de test dans Xcode, ou le dire dans la PR. **Ne jamais annoncer « tests verts » sans les
   avoir vus passer.**
4. **Nouveau fichier source** dans le package : `touch Packages/LalabobKit/Package.swift` pour qu'Xcode le voie.
   Modification de `project.yml` : `make project` (ne jamais modifier ni committer `Lalabob.xcodeproj`).
5. **Toute modification du spectacle passe par `ShowController.commit(_:allowedWhenLocked:_:)`**
   (`LalabobEngine/ShowController.swift`) : une modification = une annulation (⌘Z), aucune si rien ne change, refusée
   verrouillé sauf réglage de jeu explicite.
6. **Lumière (ADR 0006)** : LightKey n'écoute que « Lalabob Lumière ». Tout envoi passe par
   `ControllerSession.sendToLightKey` (une seule file). **Jamais d'état « allumé » déduit d'un envoi** : l'état d'une cue ne
   vient que du retour de LightKey (`watchLightingFeedback`).
7. **Le son ne s'arrête jamais tout seul** : aucune des fonctions de ces fiches (changer de grille, de type, de canal)
   n'arrête un son, sauf quand un pad perd sa partie son (fondu de 40 ms, annoncé à l'utilisateur).
8. **Thread audio** : aucune allocation, aucun verrou, aucun `print`, aucune E/S dans un rendu audio.
9. Swift 6 strict ; pas de `@unchecked Sendable` ni `nonisolated(unsafe)` sans ADR ; pas de dépendance tierce.
10. Identifiants en anglais ; commentaires, docs et textes d'interface en **français**.
11. **PR** : description avec ce qui est fait, ce qui ne l'est pas, les tests, et une **check-list d'essai sur le vrai
    matériel** (reprendre celle de la fiche). Mettre à jour `docs/PLAN.md` (section du jalon) dans la même PR.
12. **Ne pas deviner le matériel** : les valeurs marquées ⚠︎ sont à relever (banc d'essai lumière, ⌥⌘L, bouton Copier du
    journal) ; si elles ne sont pas relevées, les isoler dans une constante nommée, commentée « ⚠︎ à confirmer ».
