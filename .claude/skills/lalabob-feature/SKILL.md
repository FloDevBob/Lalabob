---
name: lalabob-feature
description: Déroulé standard pour réaliser une tâche du plan Lalabob (nouvelle fonctionnalité, correction) de la branche à la pull request. À utiliser pour toute modification de code dans ce dépôt.
---

# Réaliser une tâche Lalabob

1. **Cadrer** : relire `CLAUDE.md`, le jalon concerné dans le README et, si besoin, l'ADR liée.
   Reformuler en 2–3 lignes ce qui sera livré et comment on saura que c'est fini.
2. **Brancher** : `git switch -c jN/sujet-court` depuis `main` à jour.
3. **Tester d'abord** : écrire ou modifier les tests Swift Testing dans `Packages/LalabobKit/Tests`
   (cas normal, limites, entrée invalide). Pour le MIDI, utiliser des octets enregistrés.
4. **Coder** au bon endroit :
   - données → `LalabobModel` ; matériel → `ControllerDrivers` ; son → `LalabobAudio` ;
   - orchestration → `LalabobEngine` ; affichage → `App/` + jetons de `LalabobDesign`.
   - Respecter les dépendances autorisées de `CLAUDE.md`.
5. **Vérifier** : `make test`. Si l'app change, `make build` (sur Mac).
   Sans Mac disponible, le signaler clairement dans la PR.
6. **Documenter** : mettre à jour le README (tableau des jalons), `docs/hardware` ou une ADR si nécessaire.
7. **Ouvrir la PR** avec : résumé, captures si l'interface change, check-list d'essai manuel
   (contrôleur branché, sortie audio, LightKey selon le cas).
