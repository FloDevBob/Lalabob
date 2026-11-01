# Plan — Appairage lumière et retour de LightKey (J7)

Statut : **réalisé le 01/11/2026 (étapes 0 à 4), essai réel (étape 5) à faire** — voir `docs/PLAN.md` (J7) et l'ADR 0006. Ce fichier garde le plan d'origine ; des écarts sont notés dans PLAN (Échap reste « Tout arrêter », pas d'état `LightPairingMode`, canal 1 et non 16, port « Retour » supprimé). Branches : une par étape, `j7/…`, une PR chacune (voir `CLAUDE.md`).
À fusionner dans `docs/PLAN.md` (section J7) quand la première branche est ouverte.

## Objectif

1. Appairer une cue LightKey depuis Lalabob : mode « Appairage lumière », pad physique ou clic sur l'ampoule.
2. Afficher dans la grille de Lalabob **l'état et la couleur réels** des pads lumière (retour de LightKey),
   et les répercuter sur les LED du contrôleur.
3. Ne dépendre d'aucun réglage fragile : LightKey n'écoute plus que Lalabob.

## Ce qui change par rapport à l'ADR 0004

| | ADR 0004 (actuel) | J7 (proposé) |
| --- | --- | --- |
| Appui physique sur un pad lumière | LightKey le reçoit seul, Lalabob n'envoie rien | **Lalabob le relaie** à LightKey (Note On / Note Off) |
| Faders physiques des colonnes lumière | LightKey les reçoit seul | **Lalabob les relaie** (CC) |
| Clic à l'écran | note envoyée sur « Lalabob Lumière » | inchangé (même chemin que le relais) |
| LED des pads lumière | couleur choisie dans l'app, en permanence | **couleur renvoyée par LightKey**, repli sur la teinte choisie |
| Port « Lalabob Lumière » | sortie seule, jamais écouté | + **entrée** « Lalabob Retour Lumière » (LightKey → Lalabob) |
| Réglage LightKey | écoute le contrôleur **et** le port virtuel (mapping en double) | écoute **uniquement** les ports Lalabob (contrôleurs physiques désactivés) |

→ Écrire l'**ADR 0006** qui remplace la 0004 (la 0004 passe à « remplacée »). Les appairages existants sur
le contrôleur physique sont à refaire une fois, avec le mode d'appairage (c'est son rôle).

## Étape 0 — Relevé du vrai retour de LightKey (avant tout code d'interface)

C'est l'inconnue principale : **on ne sait pas ce que LightKey envoie** à un APC mini mk2 (l'aide ne cite que
l'APC mini d'origine et les APC20/40 en bicolore ; la mk2 est probablement en retour générique).

- Créer la destination virtuelle (étape 1), puis dans LightKey : entrée = « Lalabob Lumière », *Send Feedback To* = « Lalabob Retour Lumière ».
- Journaliser (OSLog, catégorie `lighting`) tous les messages reçus sur cette entrée, pendant : cue lancée, cue arrêtée,
  cue changée de couleur, cue supprimée, démarrage de LightKey, ouverture du spectacle.
- Noter dans `docs/hardware/lightkey-feedback.md` : type (Note On / CC), canal, numéro, vélocité = ? (0/127 ? palette ? couleur de la cue ?).
- Regarder aussi la fenêtre *External Control* de LightKey : les messages de retour y sont personnalisables.

**Décision à prendre selon le relevé** (le plan reste valable dans les deux cas) :
- **Cas A — retour on/off seulement** : Lalabob affiche la teinte choisie par l'utilisateur, allumée quand la cue est active.
- **Cas B — retour en couleur** (vélocité = couleur, canal = comportement, ou personnalisé) : Lalabob décode vers un RVB
  (table de la palette APC mk2) et affiche la couleur réelle.

Terminé quand : un fichier de messages enregistrés existe dans `Tests/…/Fixtures` pour chaque cas relevé.

## Étape 1 — Transport : relais et entrée de retour (`j7/relais-lumiere`)

- `LalabobMIDI` : destination virtuelle « Lalabob Retour Lumière » (`MIDIDestinationCreateWithProtocol`), identifiant unique
  conservé d'un lancement à l'autre comme pour la source. Ses messages arrivent sur un nouveau flux
  `MIDITransport.lightingFeedback: AsyncStream<[MIDIEvent]>` (séparé de `incoming`, pour ne jamais confondre avec un contrôleur).
- `MIDITransport` : ajouter `lightingFeedback` ; `FakeMIDITransport` (tests) à étendre.
- `ControllerSession` :
  - appui physique (`padPressed` / `padReleased`) sur une **colonne lumière** → `sendLighting` (Note On puis Note Off au relâchement réel,
    pas après 100 ms fixes) et **aucun son** ;
  - fader physique d'une colonne lumière → relayer le CC ;
  - le clic à l'écran garde son chemin actuel ;
  - **canal de sortie dédié** (proposition : canal 16) pour tout ce qui part vers LightKey. Raison : même si un contrôleur physique
    reste actif dans LightKey par erreur, ses messages (canal 1) ne correspondent à aucune cue appairée → pas de double déclenchement.
    Le port retour utilise le même canal. À confirmer à l'étape 0.
- Un appui sur une colonne lumière ne passe plus par `pressFromController` (le son n'est jamais touché).
- Tests (avec messages enregistrés, sans matériel) : relais note on/off, relais CC, aucun son déclenché, ordre conservé, relâchement.

Terminé quand : avec LightKey réglé sur les ports Lalabob uniquement, un appui physique lance la cue et le fader lumière physique marche.

## Étape 2 — Modèle : état d'une cue lumière (`j7/etat-lumiere`)

- `LalabobModel` : sur `LightCue`, ajouter `isPaired: Bool` (défaut `false`, `decodeIfPresent` pour ne pas casser les anciens `.lalabob`).
  `output`, `behavior`, `ledFeedback` restent inutilisés (déjà notés dans l'ADR 0004) ; migration repoussée.
  Test : un `show.json` ancien s'ouvre, `isPaired == false`.
- Réutilisation : le **nom** de la cue = `Pad.title` (déjà éditable) ; LightKey ne le donne pas par MIDI.
- État **non enregistré** (vivant seulement) : `LightState` par position — `.off`, `.on(RGB?)`, `.unknown`.
  Vit dans `ShowController` (observable), comme `playback`. Jamais écrit dans le spectacle.
- `ControllerDrivers` : nouveau protocole pur `LightFeedbackDecoder` — `decode(_ event: MIDIEvent) -> (GridPosition, LightState)?`,
  pour l'APC mk2 d'abord (palette vélocité → RVB, ADR 0003 déjà à moitié là via `paletteVelocity`), puis Launchpad si besoin.
  Cas A et B de l'étape 0 = deux implémentations ; l'une est choisie selon le relevé.
- `ShowController.lightState(at:)` + `ControllerSession` : lit `lightingFeedback`, met à jour l'état.
- Test : messages enregistrés → bon état par case ; message hors grille ignoré ; état remis à `.unknown` à la déconnexion de LightKey ?
  (à décider : voir questions ouvertes).

## Étape 3 — Affichage et LED (`j7/affichage-lumiere`)

- `LEDPlanner` : pour une cue lumière, LED = couleur reçue de LightKey si connue, sinon la teinte du pad (comportement actuel).
  `LEDState` gagne un cas pour un RVB libre (APC mk2 : palette la plus proche, ou SysEx RVB si l'essai le permet, ADR 0003).
  Tests : `LEDPlannerTests` (cases lumière avec/sans retour, retour qui change, retour perdu).
- `GridView` : sur un pad lumière, afficher la couleur réelle (halo ambre → couleur reçue), pastille « allumé / éteint »,
  petite ampoule (icône `lightbulb`, déjà dans `Icons`) cliquable = envoi de la cue (identique au double-clic actuel, déjà `audition`).
  Respecter le verrouillage et `Motion` (pas d'animation décorative, coupée si « Réduire les animations »).
- Contrastes : ajouter la couleur affichée aux tests de contraste (`ContrastTests`) si elle sert de fond de texte.

## Étape 4 — Mode « Appairage lumière » (`j7/mode-appairage`)

Un **mode**, pas une modale : l'appairage est un aller-retour avec LightKey (ouvrir la fenêtre d'appairage, appuyer, recommencer).

État (dans `ShowController`, observable, jamais enregistré) :
`LightPairingMode` — `.inactive`, `.idle`, `.waiting(GridPosition)`.

Déroulé :
1. Bouton « Appairage lumière » dans l'en-tête (déverrouillé seulement ; verrouillage = mode quitté, aucun appairage en scène). Échap quitte.
2. Colonnes lumière en évidence : pad libre en pointillés, pad appairé (`isPaired`) avec sa couleur.
3. Appui (pad physique, clic sur l'ampoule) sur un pad lumière → relais à LightKey (étape 1) ; le pad passe en `.waiting` (clignote).
4. **Appairé** = le pad passe à `isPaired = true` quand : a) un retour de LightKey arrive pour cette case, **ou** b) l'utilisateur confirme
   (Entrée / clic sur « Appairé »). b) est indispensable : un pad appairé mais éteint peut n'envoyer aucun retour (voir risques).
5. Champ de nom en place sur le pad (comme `InlinePadText`) ; Entrée valide, le pad suivant s'arme tout seul.
6. Clic droit → « Retirer l'appairage » (`isPaired = false`, ne touche pas à LightKey).
- Toute modification passe par `ShowController` (⌘Z, un seul niveau d'annulation par appairage) ; refusée verrouillé.
- Aide dans le panneau (une phrase) : « Dans LightKey : clic droit sur la cue › External Control › Add Trigger…, puis appuyez sur le pad. »
- Tests : machine d'états (`.idle → .waiting → appairé`), annulation, mode quitté au verrouillage, aucun effet sur les colonnes sons.

## Étape 5 — Essai réel et documentation

Check-list d'essai (à reporter dans la PR) :
☐ LightKey n'écoute que « Lalabob Lumière » ; les contrôleurs physiques sont désactivés dans ses réglages
☐ appairage d'une cue au pad physique, puis à l'ampoule ☐ un appui physique = une seule exécution de la cue
☐ fader lumière physique ☐ couleur affichée = couleur LightKey (cas B) ou teinte du pad allumée/éteinte (cas A)
☐ LED de l'APC = couleur de l'écran ☐ fermer / rouvrir LightKey en jouant : l'app ne plante pas, le son continue
☐ débrancher l'APC : les cues restent déclenchables à l'écran ☐ le logiciel qui pilote Apple Music lit toujours le 9e fader
☐ aucun son ne s'arrête tout seul pendant tout cela (règle d'or de `CLAUDE.md`).

Documentation : ADR 0006, `docs/hardware/lightkey-feedback.md`, section J7 de `PLAN.md`, `DESIGN.md` (mode d'appairage), README (tableau des jalons).

## Risques

| Risque | Parade |
| --- | --- |
| LightKey n'envoie aucun retour pour un pad appairé mais inactif | confirmation manuelle (étape 4, point 4b) ; `isPaired` enregistré dans le spectacle |
| Retour LightKey en on/off uniquement (APC mk2 non listée en bicolore) | cas A de l'étape 0 : teinte choisie dans l'app ; retour personnalisable dans External Control |
| LightKey écrase les LED en parlant directement à l'APC | LightKey désactive les contrôleurs physiques ; en secours, Lalabob renvoie tout l'état à la (re)connexion (déjà le cas) |
| Boucle MIDI (Lalabob ↔ LightKey) | flux de retour séparé de `incoming` ; Lalabob n'écoute jamais sa propre source ; canal dédié |
| Latence ajoutée au relais | le relais est une écriture CoreMIDI immédiate, hors thread principal ; mesurer à l'étape 1 |
| LightKey fermé pendant le spectacle | l'état passe à « inconnu » (teinte du pad), les sons ne sont pas touchés ; journal `OSLog` |
| Anciennes cues appairées sur l'APC physique | à refaire une fois avec le mode d'appairage (migration impossible : LightKey ne les exporte pas) |

## Questions ouvertes

1. Canal MIDI dédié (16) vers LightKey : acceptable, ou LightKey doit-il recevoir le canal 1 d'origine ? (sans effet si les contrôleurs physiques sont bien désactivés)
2. Quand LightKey se ferme : garder la dernière couleur reçue ou repasser à la teinte choisie ?
3. Launchpad : même relais (notes différentes) — à traiter dans la même PR ou après ? (l'APC mini mk2 est le contrôleur de régie)
4. Faut-il récupérer plus tard les **noms** des cues via l'OSC de LightKey ? (hors J7, mais le modèle ne le bloque pas)
