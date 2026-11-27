#!/usr/bin/env python3
"""Fabrique docs/tutoriel/visite/sons.js : quelques sons préparés, allégés (AAC 64 kb/s pour les ambiances,
96 kb/s pour les bruitages) et mis en base64, pour que la visite guidée joue de vrais sons sans rien demander au
réseau (dans l'app comme en ligne). Les boucles gardent leur longueur exacte (afconvert déclare le décalage AAC).
Usage : python3 sons_visite.py <sons préparés> <dossier temporaire> <sons.js>"""
import base64, os, subprocess, sys

SRC, TMP, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(TMP, exist_ok=True)
# clé dans la page → (fichier préparé, débit)
SONS = {
    "pluie": ("pluie.m4a", 64000), "vent": ("vent-arbres.m4a", 64000),
    "tonnerre": ("tonnerre.m4a", 96000), "porte": ("porte-claque.m4a", 96000), "verre": ("verre-brise.m4a", 96000),
    "applaudissements": ("applaudissements.m4a", 96000), "rires": ("rires.m4a", 96000),
    "cloche": ("cloche.m4a", 96000), "rate": ("rate.m4a", 96000),
}
lines = ["// Fabriqué par docs/tutoriel/sons/sons_visite.py : ne pas modifier à la main.",
         "// Sons CC0 de Freesound (voir docs/tutoriel/CREDITS.md).",
         "window.LALABOB_SONS = {"]
total = 0
for key, (name, rate) in SONS.items():
    wav, m4a = os.path.join(TMP, key + ".wav"), os.path.join(TMP, key + ".m4a")
    subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16", os.path.join(SRC, name), wav], check=True)
    subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", str(rate), wav, m4a], check=True)
    data = open(m4a, "rb").read(); total += len(data)
    lines.append(f'  "{key}": "{base64.b64encode(data).decode()}",')
lines.append("};")
open(OUT, "w").write("\n".join(lines) + "\n")
print(f"{len(SONS)} sons, {total / 1e6:.2f} Mo d'audio, sons.js = {os.path.getsize(OUT) / 1e6:.2f} Mo")
