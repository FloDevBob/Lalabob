# Lalabob — guide d'utilisation (une page)

Matériel de la troupe : **AKAI APC mini mk2** (grille + faders) et **Novation Launchpad Mini MK3** (grille, sans fader). La version complète est dans l'app : **Aide ▸ Aide de Lalabob** (⌘?).

## Avant la représentation
1. Brancher le contrôleur (Launchpad ou APC mini mk2) : l'indicateur vert apparaît dans l'en-tête.
2. Choisir la **sortie audio** dans l'en-tête.
3. Dans LightKey : entrée **et** sortie « Lalabob Lumière » activées, contrôleur physique **désactivé**.
4. Ouvrir le spectacle (`.lalabob`). Un spectacle enregistré s'ouvre **verrouillé** : c'est le mode jeu.

## Jouer (cadenas fermé)
| Geste | Effet |
| --- | --- |
| Appui sur un pad du contrôleur | Lance le son (relance s'il joue déjà) ; sur les 2 colonnes de droite, lance la cue LightKey |
| Clic / double-clic à l'écran | Sélectionne / joue |
| ← → ↑ ↓ | Passe d'un pad à l'autre |
| Espace / Retour | Pause-reprise / lecture du pad sélectionné |
| **Échap** | **Tout arrêter** (fondu de 40 ms) |
| Bouton ■ de la colonne / bouton rouge sous la colonne (APC) | Arrête tous les sons de cette colonne |
| Faders | Volume des sons ; intensité côté LightKey pour les 2 colonnes de droite |
| Potard à côté du fader (colonnes sons) | **Filtre** : centre = son intact ; vers la gauche, il reste les basses ; vers la droite, il reste les aigus. Double-clic = neutre |
| ⌘1 … ⌘9 | Changer de grille |

Un son ne s'arrête jamais tout seul. Débrancher le contrôleur ne coupe rien : les clics à l'écran continuent de marcher.

## Préparer (⌘L pour déverrouiller)
- **Ajouter un son** : glisser un fichier (Finder ou bibliothèque) sur un pad. ⌥-glisser = copier.
- **Éditer** : titre / sous-titre au double-clic, couleur, volume, élagage, fondus et boucle dans le panneau du bas. ⌘Z annule.
- **Sélection multiple** : Maj + clic ou Maj + flèches ; ⌘C ⌘X ⌘V ⌘D ⌫ agissent sur tout le groupe.
- **Grilles** : onglets en haut (+ ou ⌘T pour en ajouter, double-clic pour renommer).
- **Enregistrer** : ⌘S (sauvegarde automatique aussi). Les sons sont dans le fichier : copier le `.lalabob` suffit pour l'autre Mac.

## Appairer la lumière (déverrouillé)
1. Bouton **Appairage** dans l'en-tête.
2. Dans LightKey : clic droit sur la cue › External Control › Add Trigger…
3. Appuyer sur un pad des 2 colonnes de droite (ou cliquer son ampoule). Quand LightKey répond, la case est appairée : la nommer ; la case libre suivante s'arme. Sinon cliquer **C'est appairé**.
4. Fader : « Add Trigger… » sur le réglage, puis bouger le fader.
5. **Terminer** (Échap reste « Tout arrêter »).

Sur la grille : une cue **allumée** dans LightKey a un contour, un halo et une ampoule à sa couleur ; **éteinte**, l'ampoule est atténuée ; sans ampoule, LightKey n'a rien dit. La couleur réelle de la cue n'est pas connue de Lalabob.

## En cas de problème
- **Une cue ne se lance pas ou deux fois** : LightKey écoute-t-il encore le contrôleur ? Le désactiver.
- **Aucun état sur les pads** : sortie de « Lalabob Lumière » activée dans LightKey ? Ouvrir le **Banc d'essai lumière** (⌥⌘L) : une ligne « LightKey → » doit apparaître quand on lance une cue.
- **Contrôleur absent** : le rebrancher, les LED reviennent seules ; en attendant, tout se joue à l'écran.
- **Sons manquants à l'ouverture** : un message les liste ; leurs pads restent muets.

## Importer un Live Set Ableton (brouillon, à essayer)

1. Déverrouiller le spectacle (⌘L), puis Fichier › **Importer un Live Set Ableton…**
2. Choisir **un dossier qui contient le projet Live et ses sons** (par exemple `Bob play`), pas seulement le fichier `.als` : sans cela, l'app ne peut pas lire les sons.
3. Si le set a plus de 6 pistes audio ou 8 scènes, choisir : découper en plusieurs grilles, ou garder le premier bloc 6 × 8.
4. Les grilles sont ajoutées à la suite ; un seul ⌘Z les retire. Le compte rendu liste les sons introuvables (leurs pads restent muets).
Seuls les clips **audio** de la vue Session sont importés (nom, boucle, début/fin et volume sont repris ; fondus et couleurs sont à refaire dans l'inspecteur).
