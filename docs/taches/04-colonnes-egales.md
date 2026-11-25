# Fiche 04 — Colonnes de même largeur

Branche `j10/colonnes-egales`. Petite fiche, visuelle. Maquette : planche 1.

## Pour l'utilisateur
Les 8 colonnes ont la même largeur et restent dans leur ordre réel (1 à 8). Le type de chaque colonne se lit dans la
pastille de l'en-tête et un **liseré** de 2 pt sous l'en-tête : rien (blanc à 6 %) pour Son, **ambre plein** pour Lumière
(et, à partir de la fiche 05, **ambre pointillé** pour Son et lumière).

## Aujourd'hui (code, `App/GridView.swift`)
`GridView.body` sépare les colonnes par type (`indices(of: .audio …)` puis `indices(of: .light …)`), avec une ligne
verticale ambrée et une zone lumière de largeur fixe **264 pt**. Conséquence : une colonne lumière est toujours affichée à
droite, quel que soit son index.

## À faire
- `GridView` : un seul `HStack(spacing: Metrics.columnSpacing)` avec `ForEach(0..<PadGrid.size)` → `ColumnView(index:)`,
  chaque colonne `.frame(maxWidth: .infinity)`. Supprimer la ligne ambrée, la zone de 264 pt et `indices(of:in:)` s'il ne
  sert plus.
- `ColumnView` (même fichier) : ajouter le liseré sous l'en-tête (`Rectangle` 2 pt, coins 1 pt, marges horizontales 4 pt),
  couleur selon `column.kind`. Garder la pastille actuelle (note de musique / projecteur).
- Vérifier la largeur minimale de la fenêtre (1320 pt, `ContentView`) : à cette largeur, bibliothèque ouverte, les 8 colonnes
  tiennent sans couper le potard ni le bouton stop des cartes de fader (`ColumnView`, `.frame(minWidth: 110…)`).
- Le surlignage de survol, les cibles de dépôt, l'animation de page (`PadsPager`) ne doivent pas changer.

## Tests
Pas de cible de tests sur `App/`. Ajouter ou mettre à jour un aperçu Xcode (« Grille — colonnes égales », avec une
colonne lumière en position 3 pour vérifier l'ordre). Les tests existants doivent rester verts.

## Essai
☐ Une colonne lumière déplacée (si possible via un spectacle de test édité à la main) s'affiche à sa place ☐ fenêtre à
1320 pt, bibliothèque ouverte ☐ plein écran d'un portable (aperçu « Plein écran portable ») ☐ glisser-déposer et sélection
multiple inchangés.

## Terminé quand
8 colonnes égales dans l'ordre réel, rien de coupé à la largeur minimale.
