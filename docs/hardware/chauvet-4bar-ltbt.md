# Chauvet DJ 4BAR LT BT et boîtier USB-DMX de la troupe

Relevé du 27/11/2026 (J14, étape 0). Sources : manuel papier de la troupe (« 4BAR LTBT User Manual », rév. 2, photo du
27/11/2026) et essais avec le banc d'essai `tools/banc-dmx`. Les points marqués ⚠︎ sont à vérifier sur le matériel.

## Boîtier USB-DMX : type « Open DMX » (puce FTDI)

- Puce **FTDI FT232R** (USB `0403:6001`, nom « FT232R USB UART », n° de série `AU0483EN`). macOS le voit **sans pilote à
  installer** : `/dev/cu.usbserial-AU0483EN`.
- Il **ne répond pas** au protocole Enttec DMX USB Pro (« Get Widget Parameters », « Get Serial Number ») : c'est un boîtier
  **sans microprogramme DMX**. **C'est le Mac qui fabrique le signal** :
  - 250 kbit/s, 8 bits, **2 bits d'arrêt**, sans parité ;
  - avant chaque trame : **break ≥ 88 µs** (`TIOCSBRK` / `TIOCCBRK`), **mark ≥ 8 µs**, puis le code de départ `00` et une valeur
    0–255 par canal ;
  - vitesse non standard posée par `ioctl(IOSSIOSPEED)` : **acceptée par le pilote FTDI de macOS** (vérifié) ;
  - on n'envoie que les canaux utiles (15 pour la barre à l'adresse 1) : trame courte (~0,8 ms), cadence régulière.
- **Cadence mesurée** (banc d'essai, 30 Hz, fil ordinaire sans priorité particulière) : intervalle moyen **33,3 ms**, pire
  **≈ 40 ms** sur 120 trames. Largement dans ce qu'accepte un appareil DMX (une trame au moins par seconde).
- **Sécurité** : si Lalabob se fige ou se ferme, **le signal s'arrête** (aucun boîtier ne répète la dernière trame).
- **Deux logiciels à la fois** (essai du 27/11/2026) : Lalabob et LightKey peuvent envoyer **en même temps** sur ce boîtier, sans erreur
  d'un côté ni de l'autre. LightKey passe vraisemblablement par le pilote USB de FTDI (D2XX) et non par le port série : l'accès exclusif
  demandé par Lalabob ne l'arrête pas. Deux signaux mélangés = lumière incohérente. **N'en garder qu'un ouvert sur le boîtier.**
- **Rebranchement** (essai du 27/11/2026) : débrancher est détecté ; au rebranchement, Lalabob renvoie la trame en cours, y compris les
  changements faits pendant que le boîtier était débranché.
  **La barre garde alors la dernière couleur** (relevé du 27/11/2026) : un plantage ne plonge pas la scène dans le noir, mais
  la lumière reste figée ; à la fermeture normale, Lalabob doit envoyer lui-même le noir s'il le faut. Un boîtier Enttec DMX USB Pro (~150 €) supprimerait ce
  point (il répète lui-même la dernière trame).

## Barre : Chauvet DJ 4BAR LT BT

4 projecteurs à LED **rouge, vert, bleu** (ni ambre ni blanc : blancs et tons chauds par mélange RVB). Modes DMX : 3, 5 et
**15 canaux** ; Lalabob utilise le **15 canaux**.

Réglage **sur la barre** : MENU → `15Ch` → `d 001` (adresse de départ 1–510 ; **498 au plus** pour garder les 15 canaux).
Les modes Bluetooth (app BTAir) et autonomes doivent être désactivés (l'afficheur montre le mode DMX).

À partir de l'adresse A :

| Canal | Rôle | Valeurs |
| --- | --- | --- |
| A | Programme | 0–9 : **pilotage DMX direct** (Lalabob le tient à 0) ; 10–249 : programmes automatiques ; 250–255 : réaction au son (micro) |
| A+1 | Gradateur général | 0–255 = 0–100 % |
| A+2 | Strobo (si programme 0–9) ; vitesse (programmes) ; sensibilité (son) | 0–9 : aucun ; 10–255 : lent → rapide |
| A+3 … A+5 | Projecteur 1 : rouge, vert, bleu | 0–255 |
| A+6 … A+8 | Projecteur 2 : rouge, vert, bleu | 0–255 |
| A+9 … A+11 | Projecteur 3 : rouge, vert, bleu | 0–255 |
| A+12 … A+14 | Projecteur 4 : rouge, vert, bleu | 0–255 |

Conséquences : **pas de gradateur par projecteur** (l'intensité d'un projecteur = ses 3 couleurs mises à l'échelle) ; **un seul
strobo** pour la barre ; strobo et programmes partagent le canal A+2 (ils s'excluent).

## À relever sur la barre (banc d'essai)

**Adresse actuelle de la barre de la troupe : 50** (27/11/2026). Ajouter `--adresse 50` à chaque commande ci-dessous.

Compiler puis lancer depuis la racine du dépôt :

```bash
swiftc -O tools/banc-dmx/banc-dmx.swift -o /tmp/banc-dmx
```

| Essai | Commande | Résultat |
| --- | --- | --- |
| Le signal arrive | `/tmp/banc-dmx blanc 5 --noir-a-la-fin` | ✅ (27/11/2026) |
| Ordre des projecteurs et des couleurs (1 → 4, R V B) | `/tmp/banc-dmx chenillard 2 --noir-a-la-fin` | ✅ conforme au tableau (27/11/2026) |
| Gradateur général | dernier pas du chenillard (blanc à 25 %) | ✅ (27/11/2026) |
| Strobo | `/tmp/banc-dmx canaux 2=255 3=128 4=255 5=255 6=255 7=255 8=255 9=255 10=255 11=255 12=255 13=255 14=255 15=255 5 --noir-a-la-fin` (4 en blanc, strobo à mi-vitesse) | ✅ clignote (27/11/2026) |
| **Perte du signal** | `/tmp/banc-dmx couleur 255 0 0 5` (sans noir de fin) | ✅ **la barre garde la dernière trame** (restée rouge, 27/11/2026) |
| Délai de la barre | à mesurer plus tard (alternance au tempo) | ⚠︎ |
