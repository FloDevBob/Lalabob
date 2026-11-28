#!/usr/bin/env python3
"""Prépare les sons du spectacle d'entraînement : coupe, boucle sans clic (fondu enchaîné à puissance constante),
48 kHz stéréo, niveau homogène (LUFS, crête vraie ≤ -1 dBTP), encodage AAC 256 kb/s (.m4a, sans trou de boucle).
Usage : python3 prepare_sons.py <originaux> <sortie> <dossier temporaire>. Demande ffmpeg (Homebrew) et afconvert (macOS)."""
import glob, json, os, re, subprocess, sys

SRC, DST, TMP = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(DST, exist_ok=True); os.makedirs(TMP, exist_ok=True)

AMB, FX = -20.0, -16.0   # cibles LUFS : ambiances sous les bruitages
# (sortie, id, cible, début, durée utile, fondu enchaîné de boucle X ou None, fondu de sortie)
SPEC = [
    ("pluie", 177479, AMB, 0, 71.0, 2.0, 0),
    ("vent-arbres", 523374, AMB, 0, 25.8, 2.0, 0),
    ("foret-nuit", 662095, AMB, 5, 60, 2.0, 0),
    ("rue-ville", 261473, AMB, 5, 60, 2.0, 0),
    ("cafe", 382314, AMB, 60, 60, 2.0, 0),
    ("bord-de-mer", 827530, AMB, 20, 60, 2.0, 0),
    ("tonnerre", 683420, FX, 0, None, None, 0),
    ("porte-claque", 571797, FX, 0, None, None, 0),
    ("pas-parquet", 459970, FX, 0, 8, None, 0.5),
    ("verre-brise", 115916, FX, 0, None, None, 0),
    ("coups-de-feu-lointains", 337242, FX, 0, None, None, 0),
    ("telephone-ancien", 275163, FX, 0, None, None, 0),
    ("montee-tension", 789101, FX, 0, None, None, 0),
    ("coup-de-theatre", 754421, FX, 0, None, None, 0),
    ("whoosh", 486234, FX, 0, None, None, 0),
    ("battements-coeur", 332820, AMB, 0, 27.0, 1.5, 0),   # période 1,5 s : 18 battements
    ("horloge", 813355, AMB, 0.5, 56, 2.0, 0),            # période 1 s
    ("applaudissements", 478414, FX, 0, None, None, 2.0),
    ("rires", 581528, FX, 0, None, None, 1.5),
    ("murmures-salle", 452483, AMB, 30, 60, 2.0, 0),
    ("oh-surprise", 264376, FX, 0, None, None, 0.5),
    ("cloche", 437333, FX, 0, None, None, 0),
    ("gong", 486629, FX, 0, None, None, 0),
    ("rate", 181354, FX, 0, None, None, 0),
    ("pluie-forte", 200272, AMB, 2, 60, 2.0, 0),
    ("vent-hurle", 591664, AMB, 0, 22.0, 2.0, 0),
    ("tonnerre-proche", 840628, FX, 0, None, None, 0),
    ("volet-claque", 468209, FX, 0, None, None, 0),
    ("chiens-au-loin", 820267, FX, 0, None, None, 0),
    ("horloge-orage", 412751, AMB, 0.132, 6.631, 0.5, 0),  # 25 tics exactement
]

def run(args):
    return subprocess.run(args, capture_output=True, text=True, check=True)

def measure(path):
    err = run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"]).stderr
    summary = err[err.rfind("Summary:"):]
    i = float(re.search(r"I:\s+(-?[\d.]+|-inf)", summary).group(1))
    p = float(re.search(r"Peak:\s+(-?[\d.]+|-inf)", summary).group(1))
    return i, p

def duration(path):
    return float(run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path]).stdout)

FMT = "aresample=48000:filter_size=64:cutoff=0.97,aformat=sample_fmts=fltp:channel_layouts=stereo"
report = []
for name, sid, target, start, length, xfade, fade_out in SPEC:
    src = glob.glob(os.path.join(SRC, f"{sid}__*"))[0]
    raw = os.path.join(TMP, f"{name}.wav")
    if xfade:  # boucle : corps [start+X, start+X+L] dont la fin se fond dans la tête [start, start+X]
        fc = (f"[0:a]{FMT},asplit[a][b];"
              f"[a]atrim={start + xfade}:{start + xfade + length},asetpts=N/SR/TB[body];"
              f"[b]atrim={start}:{start + xfade},asetpts=N/SR/TB[head];"
              f"[body][head]acrossfade=d={xfade}:c1=qsin:c2=qsin[out]")
        run(["ffmpeg", "-y", "-v", "error", "-i", src, "-filter_complex", fc, "-map", "[out]", "-c:a", "pcm_f32le", raw])
    else:
        chain = [FMT]
        if length: chain.insert(0, f"atrim={start}:{start + length},asetpts=N/SR/TB")
        if target == FX and not length:  # bruitage : silence de tête retiré
            chain.append("silenceremove=start_periods=1:start_threshold=-60dB:start_silence=0.02")
        chain.append("afade=t=in:d=0.004")
        run(["ffmpeg", "-y", "-v", "error", "-i", src, "-af", ",".join(chain), "-c:a", "pcm_f32le", raw])
        if fade_out:
            d = duration(raw); tmp2 = raw + ".f.wav"
            run(["ffmpeg", "-y", "-v", "error", "-i", raw, "-af", f"afade=t=out:st={d - fade_out}:d={fade_out}:curve=qsin",
                 "-c:a", "pcm_f32le", tmp2]); os.replace(tmp2, raw)
    i, p = measure(raw)
    gain = min(target - i, -1.0 - p)          # niveau visé, sans dépasser -1 dBTP
    final = os.path.join(TMP, f"{name}.norm.wav")
    run(["ffmpeg", "-y", "-v", "error", "-i", raw, "-af", f"volume={gain:.2f}dB", "-c:a", "pcm_s24le", final])
    out = os.path.join(DST, f"{name}.m4a")
    run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "256000", "-q", "127", final, out])
    i2, p2 = measure(out)
    report.append(dict(file=f"{name}.m4a", id=sid, loop=bool(xfade),
                       start=start, length=round(duration(out), 2), gain=round(gain, 1), lufs=i2, peak=p2,
                       bytes=os.path.getsize(out)))
    print(f"{name:24} {duration(out):6.1f}s  gain {gain:+5.1f} dB  → {i2:6.1f} LUFS, crête {p2:5.1f}")
json.dump(report, open(os.path.join(TMP, "report.json"), "w"), indent=1, ensure_ascii=False)
print("total", round(sum(r["bytes"] for r in report) / 1e6, 1), "Mo")
