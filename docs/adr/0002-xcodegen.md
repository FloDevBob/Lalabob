# ADR 0002 — Projet Xcode généré par XcodeGen

- Date : 30 octobre 2026
- État : acceptée

## Contexte

Le fichier `project.pbxproj` d'Xcode est illisible et source de conflits Git, surtout quand le code est
écrit en partie par une IA qui ne peut pas lancer Xcode.

## Décision

Le projet est décrit dans `project.yml` (lisible, relisible en PR) et généré par
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`make project`). `Lalabob.xcodeproj` n'est pas versionné.
La signature est locale par défaut (`LALABOB_SIGN_IDENTITY = -`, dans `Config/Base.xcconfig`) : aucun compte Apple n'est requis.
Une signature avec identifiant Apple se configure dans `Config/Local.xcconfig`, propre à chaque Mac et non versionné.

## Conséquences

- Il faut installer XcodeGen une fois (`brew install xcodegen`).
- Après un `git pull` qui touche `project.yml`, relancer `make project`.
- Un réglage fait dans l'interface d'Xcode est perdu à la régénération : le reporter dans `project.yml`.
