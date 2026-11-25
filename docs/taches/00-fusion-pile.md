# Fiche 00 — Fusion de la pile J6 / J7 dans `main`

## Objectif
Repartir d'un `main` qui contient tout le travail fait (J6, J7, J8 brouillon), pour que chaque nouvelle PR ne montre que
son propre changement.

## État au 25/11/2026
- `main` = version 1.0.0. La branche de travail `j7/filtre-colonne` (1.1.1) est empilée sur ~18 branches `j6/…`, `j7/…`.
- `PR-J6-J7.md` (non suivi par git, à la racine) donne l'ordre des PR et leurs descriptions.
- Une PR #9 est déjà ouverte sur le dépôt ; la PR #10 contient le plan et ces fiches.

## À faire
1. Lister les PR ouvertes (`gh pr list`) et les branches non fusionnées (`git branch --no-merged main`).
2. Proposer à Florian **une** des deux voies, et attendre son accord avant toute fusion :
   - **A (simple)** : une seule PR `j7/filtre-colonne` → `main` qui contient toute la pile ; fermer les PR intermédiaires.
   - **B (historique fin)** : fusionner les PR de bas en haut dans l'ordre de `PR-J6-J7.md`, en changeant la base de la suivante.
3. Après fusion : `make test` sur `main`, puis rebaser `docs/plan-types-et-grilles` sur `main` si elle n'est pas encore fusionnée.

## Règles
- **Ne jamais fusionner ni pousser sans l'accord explicite de Florian** (une PR est relue avant fusion).
- Ne pas supprimer de branche distante sans accord.

## Terminé quand
`main` contient `j7/filtre-colonne`, `make test` est vert sur `main`, les PR intermédiaires sont fusionnées ou fermées.
