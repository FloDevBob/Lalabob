# Lalabob

Contrôleur de régie son et lumière pour le théâtre d'improvisation, piloté par un Launchpad.
Application macOS native (SwiftUI, CoreMIDI, AVAudioEngine).

- Chaque touche du pad lance un son ; un nouvel appui le relance.
- Plusieurs grilles par spectacle, faciles à basculer ; un spectacle = un fichier `.lalabob` (sons inclus).
- Un cadenas verrouille le spectacle : on joue, on ne modifie plus.
- Les deux colonnes de droite pilotent LightKey : Lalabob relaie les appuis et les faders, lit l'état des cues (allumée / éteinte) et l'affiche sur les pads et les LED. Un mode « Appairage » rattache chaque case à une cue.
- Contrôleurs pris en charge : Novation Launchpad X, Mini MK3, Pro MK3 et Akai APC mini mk2. **Matériel de la troupe : AKAI APC mini et Novation Launchpad Mini MK3.**
- Aide intégrée : menu **Aide ▸ Aide de Lalabob** (⌘?).

## Prérequis

- Mac Apple Silicon sous macOS Tahoe 26.6 ou plus récent (pour Xcode 27).
- [Xcode 27](https://developer.apple.com/xcode/). Aucun compte Apple n'est nécessaire : l'app est signée localement.
- [Homebrew](https://brew.sh), puis `brew install xcodegen`.

L'app elle-même tourne sur macOS 26 et 27.

## Démarrer

```sh
git clone https://github.com/FloDevBob/Lalabob.git
cd Lalabob
make setup      # crée Config/Local.xcconfig
make open       # génère le projet Xcode et l'ouvre
```

Dans Xcode, choisissez le schéma **Lalabob** puis ⌘R.

### Signature

Par défaut, Lalabob est signé « pour une exécution locale » : il se lance sur le Mac qui l'a compilé,
sans compte Apple. Pour l'installer sur un autre Mac de régie, le plus simple est de le compiler
sur ce Mac aussi. Pour signer avec un identifiant Apple plus tard, voir `Config/Local.xcconfig.example`.

> Le projet Xcode est **généré** à partir de `project.yml` et n'est pas versionné.
> Pour changer un réglage de cible, éditez `project.yml` puis `make project`.

## Commandes

| Commande | Effet |
| --- | --- |
| `make test` | Lance les tests des modules cœur (sans matériel) |
| `make build` | Compile l'app en Debug |
| `make format` | Formate le code Swift |
| `make clean` | Supprime les fichiers générés |

## Organisation

```
App/                     Interface SwiftUI (fine : elle ne fait qu'afficher et envoyer des commandes)
Packages/LalabobKit/     Le cœur, en modules testables sans interface
  LalabobModel           Spectacle, grilles, pads, teintes, validation
  LalabobDesign          Couleurs, dimensions, typographie de la maquette
  LalabobMIDI            Messages MIDI, codec UMP, session CoreMIDI (ports virtuels « Lalabob Lumière »)
  ControllerDrivers      Un pilote par contrôleur : notes ↔ cases, LED, faders
  LalabobAudio           Lecture audio (AVAudioEngine), fondus, vumètres, forme d'onde
  LalabobEngine          État du spectacle ouvert, commandes, session contrôleur, état des cues lumière
docs/GUIDE.md            Guide d'utilisation d'une page (régie)
docs/PLAN.md             Plan, jalons, décisions et journal de bord
docs/DESIGN.md           La maquette décrite (écrans, états, interactions)
docs/adr/                Décisions d'architecture
docs/hardware/           Protocoles MIDI des contrôleurs
.claude/skills/          Procédures pour travailler avec Claude Code
```

## Feuille de route

| Jalon | Contenu | État |
| --- | --- | --- |
| J0 | Fondations : projet, modules, tests, règles | ✅ Compile et se lance (30/10/2026) |
| J1 | Moteur audio, grille à la souris, sortie audio | 🟡 code fini, essai matériel à faire |
| J2 | Contrôleurs et LED, faders de l'APC | 🟡 code fini, essai matériel à faire |
| J3 | Colonnes lumière vers LightKey | Remplacé par le J7 |
| J4 | Édition, documents, glisser-déposer — *utilisable en répétition* | 🟡 code fini, essai réel à faire |
| J5 | Inspecteur, forme d'onde, design final (J5b, J5c : inspecteur compact) | 🟡 code fini, validation côte à côte avec la maquette à faire |
| J6 | Fiabilisation — *prêt pour le spectacle* | 🚧 vumètres, fondu anti-clic, raccourcis, barre de repos faits ; tests d'endurance, pannes, installation à faire |
| J7 | Lumière : relais, retour de LightKey, appairage, faders | 🟡 code fini, essai réel à faire (ADR 0006) |

Le détail, les décisions et les listes d'essai sont dans [`docs/PLAN.md`](docs/PLAN.md).

## Brancher LightKey

1. Lancer Lalabob : il crée l'appareil MIDI virtuel **« Lalabob Lumière »**.
2. Dans les réglages MIDI de LightKey, activer **l'entrée et la sortie** de « Lalabob Lumière » et **désactiver** le contrôleur physique (sinon chaque cue bascule deux fois).
3. Dans Lalabob, déverrouillé : bouton **Appairage**, puis pour chaque cue « Add Trigger… » dans LightKey (clic droit sur la cue › External Control) et un appui sur le pad ou le fader.
4. Pour voir ce qui passe : **Fenêtre ▸ Banc d'essai lumière** (⌥⌘L).

Voir [`docs/GUIDE.md`](docs/GUIDE.md) pour l'usage au quotidien et [`docs/hardware/lightkey-feedback.md`](docs/hardware/lightkey-feedback.md) pour le protocole relevé.
