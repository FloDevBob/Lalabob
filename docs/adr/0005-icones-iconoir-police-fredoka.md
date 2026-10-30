# ADR 0005 — Icônes Iconoir et police Fredoka, livrées comme ressources

- Date : 30 octobre 2026
- État : acceptée (remplace « icônes Phosphor (Fill) » de la maquette, à la demande de la troupe)

## Contexte

La maquette prévoyait des icônes Phosphor et le logo en Fredoka. La troupe préfère le jeu **Iconoir**.
Le projet n'accepte aucune dépendance tierce sans accord explicite et sans ADR.

## Décision

- **Iconoir** (https://iconoir.com, licence MIT), style « regular » (trait de 1,5).
  Seules les icônes utilisées sont copiées en SVG dans `LalabobDesign/Resources/Icons.xcassets`
  (images modèles, données vectorielles conservées) ; l'épaisseur du trait est reportée sur chaque tracé
  et `currentColor` remplacé par du noir pour le moteur SVG d'Xcode.
  Le **projecteur** (colonnes lumière) et le **cadenas ouvert** n'existent pas dans Iconoir : ils sont dessinés
  dans le même style.
- **Fredoka** (Google Fonts, licence SIL OFL 1.1), fichier variable `Fredoka.ttf` dans `LalabobDesign/Resources/Fonts`,
  enregistré pour le processus au lancement (`Fonts.register()`), sans modifier `Info.plist`.
- Aucune bibliothèque Swift, aucun gestionnaire de paquets : uniquement des fichiers, avec leurs licences
  dans `LalabobDesign/Resources/Licences`.
- Accès dans le code : `Icon.play.view(size:)`, `IconLabel`, `Button("…", icon: .copy) { … }`.

## Conséquences

- Mettre à jour une icône = remplacer le SVG (ou relancer le script décrit dans la PR du J5).
- Un test (`LalabobDesignTests`) vérifie que chaque `Icon` existe dans le catalogue et que Fredoka se charge.
- Les licences MIT et OFL demandent de livrer leurs textes : ils sont dans le paquet de l'app.
