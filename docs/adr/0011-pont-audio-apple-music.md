# ADR 0011 — Pont audio : le son d'Apple Music passe par le moteur de Lalabob

Date : 27/11/2026 · Statut : accepté (essai réel à faire)

## Contexte
Les pads Apple Music (ADR 0010) n'ont ni volume de colonne, ni filtre, ni vumètre, et Music sort sur sa propre sortie. La capture audio de
macOS (`CATapDescription`, macOS 14.2+) peut **rendre Music muet** pendant qu'on le capte (`mutedWhenTapped`) et nous donner son son.

## Décision
- Option « Son de Music par Lalabob » (réglage de ce Mac, désactivée par défaut). Activée : le son de Music est capté (`ProcessAudioBridge`),
  Music devient muet, et Lalabob joue ce son dans **la colonne du morceau** : fader de colonne, filtre, vumètre, sortie choisie dans Lalabob.
  Les fondus se font dans Lalabob (gain lissé échantillon par échantillon), plus avec le volume de Music.
- Entre le fil de capture et le fil de rendu : un **tampon circulaire à un écrivain et un lecteur** (`AudioRingBuffer`), mémoire réservée une
  fois, indices atomiques, ni verrou ni allocation. Il garde ~43 ms d'avance et lit **à vitesse fixe** (chaque échantillon ressort tel quel) ; s'il manque de son, il rend du
  silence ; saut en avant seulement en dernier recours (> 4 × l'avance).
- **Exception à la règle « pas de `@unchecked Sendable` »** : `AudioRingBuffer` l'est, parce que sa mémoire est un pointeur brut partagé entre
  deux fils temps réel. Sûr par construction : un seul fil écrit les échantillons et `writeIndex`, un seul lit et avance `readIndex`, et
  chaque côté publie ses indices par `Atomic` (ordre acquisition / libération) après avoir fini d'écrire ou de lire.

## Sécurité en scène
- Si Lalabob s'arrête ou plante, macOS détruit la capture : **Music redevient audible tout seul**.
- Si la capture cesse de fournir du son pendant une lecture (> 1 s), Lalabob la défait (Music redevient audible) et le dit.
- Si la capture est refusée (autorisation, morceau protégé muet), l'option se désactive et la lecture continue comme avant (volume de Music).

## Conséquences
- Latence d'environ 40 ms sur les morceaux (sans gêne pour de la musique) ; un seul morceau à la fois (Music).
- Le 9e fader règle toujours le volume de Music (avant capture) ; le fader de la colonne s'y ajoute.

## Révision du 28/11/2026 : fidélité du son (retour d'essai : « un peu d'écho ou de reverb, la musique n'est pas exactement la même »)
- **Lecture à vitesse fixe** : la lecture à vitesse ajustée (±1 %, interpolation linéaire) est retirée. La capture suit déjà l'horloge de la
  sortie de Lalabob avec la compensation de dérive de macOS : rien à rattraper. Elle faisait onduler la hauteur (effet chorus) et ternissait
  les aigus. Test : une sinusoïde aiguë traverse le tampon par blocs de tailles différentes et ressort identique, échantillon par échantillon.
- **Tous les processus audio de Music** sont captés et rendus muets (processus principal, même PID, mêmes identifiants d'app ou dérivés) ;
  un son resté audible hors de la capture s'entendait ~40 ms avant la copie : un écho. Capture aussi par identifiant d'app
  (`CATapDescription.bundleIDs`, `isProcessRestoreEnabled`, macOS 26) avec repli sur la capture par processus.
- Avance ramenée de 65 à ~43 ms (2 048 trames à 48 kHz). Diagnostic du panneau : « N processus captés ».
- Si l'écho persiste : piste de l'ADR à écrire, rendre le son directement vers la sortie dans la fonction de rappel de l'appareil agrégé
  (sans tampon), au prix de refaire fader, filtre et vumètre hors AVAudioEngine.
