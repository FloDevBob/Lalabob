# ADR 0012 — Lumière autonome en DMX, à côté de LightKey

Date : 27/11/2026 · Statut : proposé (étape 0 du J14 : relevé et banc d'essai ; plan : `docs/plan-lumiere-dmx.md`)

## Contexte
Aujourd'hui Lalabob délègue la lumière à LightKey (ADR 0006). Dans les petites salles, la troupe n'a qu'une barre de 4 projecteurs
(Chauvet DJ 4BAR LT BT, DMX 15 canaux) et un boîtier USB-DMX à puce FTDI, sans microprogramme DMX (relevé : `docs/hardware/chauvet-4bar-ltbt.md`).
Lancer LightKey pour ça est lourd.

## Décision
- Un **mode lumière** par spectacle : **LightKey** (défaut, anciens fichiers, inchangé) ou **Projecteurs pilotés par Lalabob** (DMX).
  LightKey n'est pas retiré.
- En DMX, Lalabob **est** la console : un pad lumière porte un **état lumineux** (couleurs par projecteur, alternance, programme de la
  barre, réaction au son) ; son état allumé / éteint est connu sans retour. La règle « jamais d'état allumé déduit d'un envoi » reste vraie
  pour LightKey.
- Nouveau module **`LalabobDMX`** (dépend de Model seulement) : trames, transports (`DMXTransport`), port **Open DMX** (le Mac fabrique le
  signal : 250 kbit/s, 2 bits d'arrêt, break par `TIOCSBRK`), plus tard Enttec Pro / Art-Net. Un **fil dédié** envoie la trame à 30 Hz,
  hors `MainActor` et hors du fil audio. Pas de dépendance tierce.
- Les appareils sont décrits par des **profils** (données : rôle de chaque canal), pas par du code ; un profil intégré pour la barre.
- **Couleurs** stockées en teinte (0–360°) + saturation, jamais en code RVB ; le profil les traduit (même esprit que `Tint`).
- Accès au port série en bac à sable : autorisation `com.apple.security.device.serial` dans `project.yml`.

## Sécurité en scène
- Le son ne dépend jamais de la lumière : boîtier débranché ou port en erreur = bandeau discret, aucun son coupé ; la trame est renvoyée au
  rebranchement.
- Échap / Tout arrêter ne touche pas la lumière ; le Noir est un geste séparé, en fondu.
- Avec un boîtier Open DMX, **le signal s'arrête si Lalabob se fige ou se ferme** ; la barre **garde alors la dernière couleur**
  (relevé du 27/11/2026) : pas de noir subit en scène. Le noir à la fermeture doit donc être envoyé par Lalabob avant de fermer le port.
  Un boîtier Enttec Pro (option matérielle) répéterait lui-même la dernière trame, même si le Mac se fige.
- Strobo désactivé par défaut dans un nouvel état, borné.

## Conséquences
- Format de fichier version 4 (écrite seulement si nécessaire) quand le modèle arrive (étape 2).
- Les faders des colonnes lumière prennent un rôle (Général, Couleurs…) en mode DMX ; le bouton rond de l'APC d'une colonne lumière fait un Noir.
- Écarté : Bluetooth de la barre (protocole privé, fragile en salle). Le sans-fil passe par du DMX sans fil (D-Fi), sans rien changer à Lalabob.
