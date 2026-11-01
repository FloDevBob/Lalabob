# Retour de LightKey vers Lalabob — relevé (J7, étape 0)

**À remplir sur le vrai Mac de régie.** Lalabob crée la destination MIDI virtuelle **« Lalabob Retour Lumière »**
(en plus de la source « Lalabob Lumière »). Une **seconde destination du même nom que la source**, « Lalabob Lumière », reçoit le même retour : LightKey voit ainsi un seul appareil avec entrée et sortie (hypothèse à vérifier : il associe peut-être entrée et sortie par le nom). Les deux destinations sont équivalentes ; le journal indique laquelle a reçu le message. Tout ce que LightKey y envoie est journalisé, tel quel, sans rien déclencher.

## Mise en place

1. Lancer Lalabob (les deux ports apparaissent dans LightKey, Réglages MIDI).
2. Dans LightKey : entrée = « Lalabob Lumière », *Send Feedback To* = « Lalabob Retour Lumière ».
3. Dans Lalabob : menu **Fenêtre ▸ Banc d'essai lumière** (⌥⌘L). La fenêtre montre l'état des ports, une grille 8×8 du
   contrôleur (avec les numéros de note) et le **journal en direct** : « Contrôleur → », « → LightKey », « LightKey → ».
   Le bouton **Copier** met le journal dans le presse-papiers (pour me le coller).
   (Le même journal existe dans OSLog : `log stream --level info --predicate 'subsystem == "fr.lalabob.app" AND category == "lighting"'`.)
4. Le journal OSLog montre les **mots UMP bruts** : un Note On de vélocité 0 reste un Note On, les messages que Lalabob
   ignore (changement de programme, pitch bend…) apparaissent aussi.
5. Regarder aussi la fenêtre *External Control* de LightKey : les messages de retour y sont personnalisables.

## Relevé (01/11/2026, APC mini mk2) — journal brut : `lightkey-feedback-session-2026-11-01.txt`

**Condition qui a débloqué le retour** : LightKey envoie son retour à la destination du **même nom que l'entrée**. Avec une destination « Lalabob Retour Lumière »
seule, rien n'arrivait ; avec une destination « Lalabob Lumière » (même nom que la source), le retour arrive.

| Scénario | Type | Canal | Numéro | Vélocité | Remarque |
| --- | --- | --- | --- | --- | --- |
| Cue allumée | Note On | 1 | note de la case (disposition APC) | 127 | aussi quand on la bascule dans LightKey lui-même |
| Cue éteinte | Note Off | 1 | note de la case | 0 | |
| Une cue en éteint d'autres (même groupe) | Note Off pour chacune éteinte, puis Note On pour la nouvelle | 1 | | 0 puis 127 | l'état affiché suit l'état réel de LightKey |
| Démarrage / ouverture du spectacle (14:35:53) | rafale : un message par note appairée, On ou Off | 1 | toutes les notes appairées | 127 / 0 | donne l'état complet d'un coup ; les notes non appairées ne sont jamais citées |
| Cue changée de couleur / supprimée | non relevé | | | | à essayer |

Observations : la vélocité ne vaut que **127 ou 0** (aucune couleur dans le retour) ; une cue **bascule à chaque Note On** reçu (le Note Off envoyé au relâchement ne change rien) ;
LightKey répond au Note On par le nouvel état (On si la cue démarre, Off si elle s'arrête).

## Conclusion

- ☑ **Cas A** : retour on/off seulement → Lalabob affiche la teinte choisie, allumée quand la cue est active. (Cas B écarté tant qu'aucune vélocité autre que 127 / 0 n'est vue.)
- ☐ Cas B : retour en couleur.

Ensuite : fixtures Swift d'après ce journal (étape 2), puis étape 1 (relais).
