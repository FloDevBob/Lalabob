# Lalabob — guide d'utilisation (une page)

Matériel de la troupe : **AKAI APC mini mk2** (grille + faders) et **Novation Launchpad Mini MK3** (grille, sans fader). La version complète est dans l'app : **Aide ▸ Aide de Lalabob** (⌘?). Pour apprendre en cinq minutes : **Aide ▸ Visite guidée**.

## Avant la représentation
1. Brancher le contrôleur (Launchpad ou APC mini mk2) : l'indicateur vert apparaît dans l'en-tête.
2. Choisir la **sortie audio** dans l'en-tête.
3. Dans LightKey : entrée **et** sortie « Lalabob Lumière » activées, contrôleur physique **désactivé**.
4. Ouvrir le spectacle (`.lalabob`). Un spectacle enregistré s'ouvre **verrouillé** : c'est le mode jeu.

## Jouer (cadenas fermé)
| Geste | Effet |
| --- | --- |
| Appui sur un pad du contrôleur | Lance le son (relance s'il joue déjà) ; sur les 2 colonnes de droite, allume ou éteint la lumière |
| Clic / double-clic à l'écran | Sélectionne / joue |
| ← → ↑ ↓ | Passe d'un pad à l'autre |
| Espace / Retour | Pause-reprise / lecture du pad sélectionné |
| **Échap** | **Tout arrêter** (fondu de 40 ms) |
| Bouton ■ de la colonne / bouton rouge sous la colonne (APC) | Arrête tous les sons de cette colonne |
| Faders | Volume des sons ; intensité des projecteurs pour les 2 colonnes de droite |
| Potard à côté du fader (colonnes sons) | **Filtre** : centre = son intact ; vers la gauche, il reste les basses ; vers la droite, il reste les aigus. Double-clic = neutre |
| ⌘1 … ⌘9 | Changer de grille |

Un son ne s'arrête jamais tout seul. Débrancher le contrôleur ne coupe rien : les clics à l'écran continuent de marcher.

## Préparer (⌘L pour déverrouiller)
- **Ajouter un son** : glisser un fichier (Finder ou bibliothèque) sur un pad. ⌥-glisser = copier.
- **Éditer** : titre / sous-titre au double-clic, couleur, volume, élagage, fondus et boucle dans le panneau du bas. ⌘Z annule.
- **Sélection multiple** : Maj + clic ou Maj + flèches ; ⌘C ⌘X ⌘V ⌘D ⌫ agissent sur tout le groupe.
- **Grilles** : onglets en haut (+ ou ⌘T pour en ajouter, double-clic pour renommer).
- **Enregistrer** : ⌘S (sauvegarde automatique aussi). Les sons sont dans le fichier : copier le `.lalabob` suffit pour l'autre Mac.

## Grilles Apple Music
- **Créer** : bouton + des onglets › Apple Music (ou ⌥⌘T). Clic droit sur un onglet › Type de grille pour convertir (confirmation, ⌘Z).
- **Remplir** (déverrouillé, **Music ouvert**) : panneau de gauche, dossiers et playlists ; Maj-clic / ⌘-clic pour plusieurs morceaux, glisser
  sur une colonne Music : ils se rangent vers le bas puis dans la colonne suivante. ▶ = extrait de 30 s (sans toucher à Music). Onglet
  **Internet** : chercher dans tout Apple Music, « Ajouter… » ouvre le morceau dans Music (cliquer + pour l'ajouter à la bibliothèque).
- **Jouer** : appui (ou double-clic) = le morceau joue dans Music ; ré-appui = **arrêt** en fondu (1 s), l'appui suivant repart du début ; **pause** : barre du bas ou Espace (un appui sur un morceau en pause le reprend) ; un autre pad = fondu enchaîné ; ■ de la colonne =
  fondu de sortie ; Échap arrête tout. **Un seul morceau à la fois.** Volume : 9e fader de l'APC (volume général de Music).
- **Avant la représentation** : **télécharger** les morceaux (☁ sur un pad = Internet nécessaire ; « Télécharger les N » dans le panneau).
  « Introuvable » = le morceau n'est plus dans la bibliothèque : en glisser un autre.
- **Son de Music par Lalabob** (interrupteur du panneau, autorisation « enregistrement audio » la première fois) : le morceau sort par Lalabob,
  dans sa colonne : **fader, filtre, vumètre, sortie choisie dans Lalabob**, fondus sans à-coups. Si la capture s'arrête, Music redevient audible
  tout seul (et un message le dit). Un morceau protégé capté en silence désactive l'option.
- Droits : l'abonnement Apple Music est personnel ; une diffusion publique relève des droits de la troupe (SACEM).

## La lumière
Les **2 colonnes de droite** commandent les **projecteurs** : chaque pad est une **lumière** (« Plein feu »…), un appui
l'allume ou l'éteint, le **fader** règle l'**intensité**. Une lumière **allumée** a un contour, un halo et une ampoule à
sa couleur ; **éteinte**, l'ampoule est atténuée. Les lumières se préparent dans le logiciel des projecteurs (LightKey).

**Relier un pad aux projecteurs** (cadenas ouvert) :
1. Bouton **Relier** dans l'en-tête.
2. Dans LightKey : clic droit sur la lumière › External Control › Add Trigger…
3. Appuyer sur le pad (ou cliquer son ampoule). Quand les projecteurs répondent, le pad est **relié** : le nommer ; la case
   suivante est prête. Sinon cliquer **C'est relié**.
4. Fader d'intensité : « Add Trigger… » sur le réglage dans LightKey, puis bouger le fader.
5. **Terminer** (Échap reste « Tout arrêter »).

Chaque grille commande **ses propres lumières** : la même touche allume une lumière différente selon la grille affichée,
on relie donc chaque grille à part. Réglage avancé : clic droit sur l'onglet › **Canal des lumières** (les liaisons de la
grille sont alors à refaire).

**Mêmes lumières sur toutes les grilles** (Spectacle › Réglages du spectacle…, cadenas ouvert) : les colonnes lumière de la
grille affichée deviennent les mêmes partout (badge « Commune ») : on les relie une seule fois, et changer de grille ne change
pas la lumière. Ce qui occupait leur place dans les autres grilles est mis de côté et revient si on désactive l'option.

## En cas de problème
- **Une lumière ne s'allume pas, ou s'allume puis s'éteint** : dans LightKey, le contrôleur est-il encore activé ? Le désactiver.
- **Les pads ne montrent jamais si la lumière est allumée** : sortie « Lalabob Lumière » activée dans LightKey ? Le **Banc d'essai lumière** (⌥⌘L) doit montrer une ligne « LightKey → » quand on allume une lumière.
- **Contrôleur absent** : le rebrancher, les LED reviennent seules ; en attendant, tout se joue à l'écran.
- **Sons manquants à l'ouverture** : un message les liste ; leurs pads restent muets.
- **Apple Music ne répond pas** : Music doit être ouvert (Lalabob ne l'ouvre jamais seul en scène). « Accès refusé » : Réglages Système ›
  Confidentialité et sécurité › Automatisation › Lalabob › Music. Le message exact s'affiche dans le panneau ou la pastille « Apple Music ».
