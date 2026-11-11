"""Red-alert klaxon for hazard warnings (meteor field, mega asteroid).
    python3 scripts/tools/make_alert_sfx.py [out.mp3]   (needs numpy + ffmpeg)
Three rising "whoop" sweeps, square-ish tone through a soft clip, ~2 s."""
import sys, subprocess, numpy as np
SR = 44100
out = sys.argv[1] if len(sys.argv) > 1 else "assets/audio/sfx/red_alert.mp3"
def whoop(dur=0.55, f0=420.0, f1=780.0):
    t = np.arange(int(SR * dur)) / SR
    f = f0 + (f1 - f0) * (t / dur) ** 0.8
    ph = 2 * np.pi * np.cumsum(f) / SR
    tone = np.tanh(3.0 * np.sin(ph)) * 0.6 + 0.25 * np.sin(2 * ph) + 0.12 * np.sin(0.5 * ph)
    env = np.minimum(1.0, t / 0.02) * np.minimum(1.0, (dur - t) / 0.06)
    return tone * env
gap = np.zeros(int(SR * 0.12))
sig = np.concatenate([whoop(), gap, whoop(), gap, whoop(dur=0.6)])
# light echo for a ship-interior feel
d = int(SR * 0.09)
echo = np.zeros(len(sig) + d); echo[:len(sig)] += sig; echo[d:] += 0.35 * sig
echo = echo / np.max(np.abs(echo)) * 0.85
pcm = (echo * 32767).astype(np.int16).tobytes()
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
                "-c:a", "libmp3lame", "-b:a", "128k", out], input=pcm, check=True)
print("wrote", out, round(len(echo) / SR, 2), "s")
