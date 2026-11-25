# Fiche 01b — Option « Colonnes lumière communes à toutes les grilles »

Branche `j9/lumiere-commune`, après la fiche 01. **La plus délicate du bloc 1** : lire en entier avant de commencer.

## Pour l'utilisateur
Dans un nouvel écran **Réglages du spectacle** (déverrouillé), une option « Colonnes lumière communes à toutes les grilles ».
- **Activée** : les colonnes de type Lumière sont les mêmes dans toutes les grilles (positions, cues, faders, appairages)
  et envoient sur un **canal commun**. Changer de grille ne change pas la lumière ; on appaire une seule fois.
- **Désactivée** : chaque grille a ses colonnes lumière, sur son canal (fiche 01).

## Règles décidées (25/11/2026)
1. Réglage **du spectacle** (enregistré dans le `.lalabob`).
2. Seules les colonnes de type **Lumière** sont communes. Les colonnes Son et lumière (J10) restent propres à chaque grille.
3. **Activer** : les colonnes lumière de la **grille affichée** (la « grille d'origine ») deviennent communes. Dans les
   autres grilles, les colonnes qui occupent ces positions, et leurs propres colonnes lumière ailleurs, sont **mises de côté**
   (rien n'est perdu) ; une colonne lumière mise de côté hors des positions communes est remplacée par une colonne Son vide.
4. **Désactiver** : la grille d'origine reprend les colonnes communes (avec les modifications faites entre-temps) ; les
   autres grilles retrouvent leurs colonnes mises de côté.
5. Option activée, rendre une colonne Lumière (ou cesser de l'être) s'applique à **toutes les grilles** (avec la
   confirmation de la fiche 06, grille par grille). Avant J10, il n'y a pas encore de changement de type : rien à faire ici.
6. **Canal commun** : par défaut le canal de la grille d'origine (ses appairages restent valables) ; la grille d'origine
   prend alors le premier canal libre. Réglable dans l'écran. Les canaux des grilles évitent le canal commun.

## Modèle (`LalabobModel`)
```swift
public struct SharedLightColumns: Codable, Sendable, Equatable {
    public var channel: Int                 // 1…16
    public var originGridID: PadGrid.ID
    public var columns: [Int: Column]       // index de colonne → colonne commune (kind == .light)
}
// Show
public var sharedLight: SharedLightColumns?    // nil = option désactivée ; decodeIfPresent
// PadGrid
public var parkedColumns: [Int: Column]        // colonnes mises de côté ; [:] par défaut ; decodeIfPresent
```
- **Lecture effective** : `Show.effectiveGrid(at index: Int) -> PadGrid` = la grille avec les colonnes communes
  superposées. **C'est elle que l'interface, les LED, le relais et le moteur audio doivent voir.**
- **Écriture** : ajouter à `Show` un accès unique `subscript(grid: Int, position: GridPosition) -> Pad?` (get / set) et
  `mutating func updateColumn(grid: Int, index: Int, _ change: (inout Column) -> Void)` qui écrivent dans `sharedLight`
  quand la colonne est commune, dans la grille sinon. **Remplacer dans `ShowEditing.swift` et `LightPairing.swift` tous
  les accès directs `updated.grids[g].columns[c]…` / `updated.grids[g][position]`** par ces accès (sinon une modification
  d'une colonne commune serait écrite dans une grille et perdue).
- `Show.enableSharedLight(fromGrid:)` / `disableSharedLight()` : purs, testables, appliquent les règles 3, 4, 6.
- `validate()` : colonnes communes de type `.light`, index 0…7, canal unique (différent de ceux des grilles).

## Moteur
- `ShowController.currentGrid` renvoie `show.effectiveGrid(at: selectedGridIndex)` (vérifier tous ses usages).
- `ShowController.setSharedLight(_ enabled: Bool)` et `setSharedLightChannel(_:)` via `commit`, refusés verrouillé ;
  une seule annulation par bascule.
- `ControllerSession` : pour une colonne commune, envoyer sur `sharedLight.channel` ; sinon canal de la grille. Le retour
  sur le canal commun alimente l'état de ces colonnes **quelle que soit la grille affichée**.
- `syncColumnLevels` / faders : le fader d'une colonne commune est le même dans toutes les grilles.

## Interface
- Menu **Fichier › Réglages du spectacle…** (`App/LalabobCommands.swift`), déverrouillé seulement → feuille avec :
  interrupteur, sélecteur du canal commun (canaux libres), phrase d'explication, rappel « Les colonnes des autres grilles sont
  mises de côté et reviennent si vous désactivez l'option ».
- Activation : feuille de confirmation listant, grille par grille, ce qui est mis de côté.
- En-tête d'une colonne commune : petit pictogramme « lien » + infobulle « Commune à toutes les grilles ».

## Tests (écrire d'abord)
- Modèle : activer → colonnes communes = celles de la grille d'origine ; autres grilles : colonnes mises de côté, lumière
  hors positions communes remplacée par une colonne Son vide ; désactiver → tout revient à l'identique (aller-retour égal à
  l'original quand rien n'a été modifié) ; modification d'une cue commune visible dans toutes les grilles ; canaux
  (origine déplacée, unicité) ; décodage sans les nouveaux champs.
- Engine : édition d'une case commune depuis la grille 3 → visible en grille 1 ; ⌘Z annule la bascule en une fois ; relais
  et retour sur le canal commun ; verrouillé → refusé.

## Essai sur le matériel
☐ Option activée : une cue appairée une fois répond depuis toutes les grilles ☐ changer de grille : LED des colonnes
lumière inchangées ☐ désactiver : les anciennes colonnes des autres grilles reviennent ☐ aucun son ne s'arrête.

## Terminé quand
Tests verts, aller-retour activer / désactiver sans perte, `docs/FORMAT.md` à jour.
