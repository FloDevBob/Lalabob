# Akai APC mini mk2

Sources : protocole de communication Akai (APC mini mk2 Communication Protocol v1.0) et
[résumé de la communauté Bome](https://forum.bome.com/t/new-akai-pro-apc-mini-mk2-initial-led-mapping-summary/4752).
Les points marqués ⚠︎ sont à vérifier sur le matériel.

## Grille

Notes 0 à 63 : 0 en bas à gauche, 7 en bas à droite, 56 en haut à gauche, 63 en haut à droite.
Les appuis arrivent en Note On sur le canal 1 (0 en interne).

## LED

- Note On sur la note de la case ; **vélocité = couleur** de la palette ; **canal = comportement** :
  - canaux 0 à 6 (affichés 1 à 7) : luminosité de 10 % à 100 % ;
  - canaux 7 à 15 : pulsation puis clignotement à différentes vitesses ⚠︎ (valeurs exactes à confirmer).
- Un SysEx permet de fixer une couleur RVB libre par case (à évaluer, voir ADR 0003).
- Boutons de piste (notes 100–107, rouge) et de scène (112–119, vert) : non utilisés pour l'instant.

## Faders

| Fader | CC | Usage dans Lalabob |
| --- | --- | --- |
| 1 à 8 | 48 à 55 ⚠︎ | Fader de la colonne correspondante (volume ou intensité) |
| 9 (master) | 56 ⚠︎ | **Ignoré** : mappé dans un autre logiciel pour le volume d'Apple Music |

macOS permet à plusieurs applications d'écouter le même contrôleur : Lalabob et le logiciel qui pilote
Apple Music lisent l'APC en même temps sans se gêner.

## Relevés à faire au jalon 2 (essai matériel)

- Nom réel du port vu par CoreMIDI : _à noter_ (la détection cherche « apc mini mk2 »).
- Réponse à la requête d'identité : _à noter_ ; Lalabob vérifie seulement le fabricant Akai `47`.
- Confirmer les CC 48 à 56 des faders ⚠︎ et les canaux de pulsation (le son en lecture utilise le canal 9).
