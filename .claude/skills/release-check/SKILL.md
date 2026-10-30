---
name: release-check
description: Vérifications avant de livrer une version de Lalabob pour une répétition ou une représentation — build, tests, essais matériel, installation sur les Mac de régie.
---

# Avant une représentation

1. `main` est à jour, `make test` passe, `make build` en configuration Release passe.
2. Numéro de version incrémenté dans `project.yml` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`).
3. Archive signée (équipe « Personal Team ») installée sur **chaque** Mac de régie (macOS 26 et 27) ;
   au premier lancement : Réglages › Confidentialité et sécurité › « Ouvrir quand même ».
4. Essais en conditions réelles, sur chaque contrôleur disponible :
   - [ ] 16 sons simultanés sans craquement ;
   - [ ] relance, pause, « Tout arrêter » (Échap) ;
   - [ ] débrancher / rebrancher le contrôleur puis la carte son pendant la lecture ;
   - [ ] cues reçues par LightKey ; 9e fader de l'APC toujours actif dans l'autre logiciel ;
   - [ ] ouverture du spectacle depuis une clé USB sur l'autre Mac.
5. Copie de sauvegarde du dossier du spectacle et de l'app sur une clé USB de secours.
6. Noter la version livrée et les écarts dans la PR ou une issue « Représentation du JJ/MM ».
