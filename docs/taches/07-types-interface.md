# Fiche 07 — Interface des types de colonnes et de pads

Branche `j10/types-interface`, après la fiche 06. Tout est dans `App/` (pas de test automatique) : vérifier chaque écran
avec un **aperçu Xcode** et le comparer aux planches. Mode **déverrouillé** seulement pour tout ce qui modifie.

## 1. Type de colonne — planche 2
- **Pastille de l'en-tête** (`ColumnView`, `App/GridView.swift`) : déverrouillé, elle devient un `Button` (curseur main,
  infobulle « Type de colonne ») avec un petit chevron ; icônes : note (Son), projecteur (Lumière), les deux (mixte).
- **Popover** : titre « Type de la colonne « Nom » », trois options (radio) avec une ligne d'explication chacune :
  - Son — « Sons uniquement · fader de volume, filtre, stop »
  - Son et lumière — « Pads son, lumière, ou les deux à la fois · fader de volume »
  - Lumière — « Cues uniquement · fader MIDI vers LightKey (intensité) »
  - pied : « Élargir ne retire rien. Restreindre demande confirmation et s'annule avec ⌘Z. »
- **Clic droit sur l'en-tête** : Renommer… · sous-menu « Type de colonne » (Son… / Son et lumière / Lumière…, coche sur le
  type actuel ; « … » sur les choix qui retireraient quelque chose d'après `conversionPlan`) · Arrêter les sons de la colonne ·
  Vider la colonne…. Verrouillé : seulement « Arrêter les sons de la colonne ».
- **Feuille de confirmation** (si `!plan.isLossless`) : titre « Passer « Nom » en colonne Son ? » ; une ligne par catégorie
  non vide du plan, avec pastille de couleur (rouge = supprimé, ambre = perd une partie, vert = inchangé), **le nombre et les
  titres** des pads ; « Annulable avec ⌘Z. Aucun son en cours n'est arrêté. » (adapter si un pad qui joue perd son son) ;
  boutons Annuler · « Garder « Son et lumière » » (si on venait de mixte ou pour Son ↔ Lumière) · **Convertir** (rouge).
- Liseré sous l'en-tête (fiche 04) : ambre **pointillé** pour mixte.

## 2. Pads — planche 3
- **Capsule verticale** sur un pad mixte, centrée à droite : fond noir 30 %, contour blanc 6 %, rayon 14 ; dedans le bouton
  lecture / stop (22 pt, icônes pleines existantes `playFill` / `stopFill`) au-dessus de l'**ampoule** (22 pt). Ampoule :
  ambre (inconnue), ambre atténuée (éteinte), fond à la couleur vive du pad + icône sombre (allumée). Pad lumière seul :
  ampoule seule, **22 pt** comme le bouton lecture d'un pad son. Reprendre la taille adaptative actuelle
  (`buttonSize(for: density)`) pour les deux boutons.
- Bouton ampoule = « Tester la cue » (envoie la note, comme aujourd'hui sur les pads lumière).
- Pad mixte en attente de son (`awaitsSound`) : badge ambre « + Son » en haut à droite.
- **Case vide d'une colonne mixte** (déverrouillé) : au survol, deux moitiés « + Son » (pointillés blancs) et « + Cue »
  (pointillés ambrés) ; un clic sur « + Cue » = `newLightCue` ; un dépôt de son n'importe où = pad son.
- **Clic droit sur un pad** (menu existant) : ajouter « Type du pad › Son uniquement… / Lumière uniquement… / Son et
  lumière » ; grisé hors colonne mixte avec l'explication « La colonne n'accepte que le son. Changez son type pour mélanger. »
  Confirmation si `conversionPlan(padAt:to:)` n'est pas sans perte (même feuille, texte adapté).
- Glisser : pendant le survol, une case qui refuserait le type est rouge (réutiliser `dragPreview`).
- VoiceOver : un pad mixte se lit « Titre, son et lumière, en lecture, cue allumée » ; actions nommées « Jouer »,
  « Tester la cue ».

## 3. Barre du bas d'un pad mixte — planche 4, variante A
`InspectorView` : pour un pad mixte, ajouter dans la bande du haut, après le titre, un **groupe Lumière** (fond ambre 7 %,
contour ambre 25 %, rayon 10) : ampoule · « Note 52 · Can. 2 » (mono) · « Appairée ✓ » ou « Non appairée » · bouton
**Tester** · « Au nouvel appui » [Allumer seulement | Basculer] (`lightRetrigger`, via `updatePad`, ⌘Z). À droite, avant la
couleur : segmenté **Type du pad** [Son | Lumière | Les deux] (déverrouillé ; mêmes règles et confirmation). La bande du
bas (volume + onde) est celle d'un pad son. Hauteur totale inchangée (`Metrics.inspectorHeight`). À la largeur minimale,
le nom du fichier se tronque en premier, puis le libellé « Au nouvel appui » passe en infobulle.

## 4. Barre de repos et astuces
`IdleBar` / `App/Tips.swift` : compter les pads mixtes ; ajouter une astuce déverrouillée « Une colonne Son et lumière
accepte des pads qui lancent un son et une cue en même temps. »

## Vérifications
Aperçus : colonne de chaque type ; pad mixte dans ses 6 états (planche 3) ; popover ; feuille de confirmation ; inspecteur
d'un pad mixte à 1320 pt de large. Comparer côte à côte avec les planches 2, 3 et 4.

## Essai
☐ Changer le type d'une colonne pleine, lire la feuille, ⌘Z ☐ créer un pad mixte par les trois chemins (menu, glisser un
son sur une cue, appairage d'un pad son) ☐ capsule lisible sur un pad de 38 pt (fenêtre basse) ☐ verrouillé : aucun
menu de type ☐ VoiceOver sur un pad mixte.

## Terminé quand
Tous les écrans des planches 2, 3 et 4 (variante A) existent, verrouillage respecté, aperçus ajoutés.
