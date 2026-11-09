#!/usr/bin/env python3
"""Procedural dark-ambient loop for the story cutscenes (no samples, no licence).

    python3 scripts/tools/make_cutscene_music.py [out.mp3]   (needs numpy + ffmpeg)

Layers: detuned sub drone in D, slow minor pads (Dm, Bbmaj7, Gm6, Dm/A, 18 s
each), sparse inharmonic bell notes, breathy noise swells and a distant
heartbeat, all through a synthetic convolution reverb. The tail is folded
into the head so the file loops seamlessly (Cutscene music loops).
"""
import math, os, subprocess, sys, tempfile, wave
import numpy as np

SR = 44100
DUR = 72.0
N = int(SR * DUR)
rng = np.random.default_rng(20261109)
t = np.arange(N) / SR

def env_ad(n, a, d):
    e = np.ones(n)
    a_n, d_n = int(a * SR), int(d * SR)
    if a_n > 0: e[:a_n] = np.linspace(0, 1, a_n)
    if d_n > 0: e[-d_n:] *= np.linspace(1, 0, d_n)
    return e

def lowpass(x, cutoff):
    # one-pole, cheap and smooth
    rc = 1.0 / (2 * math.pi * cutoff); a = (1 / SR) / (rc + 1 / SR)
    y = np.empty_like(x); acc = 0.0
    # vectorised via lfilter-free recursion in chunks (numpy only)
    b = 1 - a
    # use scipy-free IIR: process with cumulative trick is hard, loop in blocks
    out = np.empty_like(x)
    prev = 0.0
    for i in range(0, len(x), 4096):
        blk = x[i:i+4096]
        # exact recursion in python per block is slow; approximate with powers
        k = np.arange(len(blk))
        decay = b ** (k + 1)
        # y[n] = b*y[n-1] + a*x[n]  -> y = prev*decay + a*conv(x, b^k)
        conv = np.convolve(blk, b ** np.arange(len(blk)))[:len(blk)] * a
        out[i:i+4096] = prev * decay + conv
        prev = out[i+len(blk)-1]
    return out

def note(f):  # tiny helper, Hz of midi
    return 440.0 * 2 ** ((f - 69) / 12)

mix = np.zeros(N)

# 1. Sub drone, D1 + A1, detuned pairs for slow beating, breathing LFO
for f, amp in ((note(38), 0.22), (note(38) * 1.003, 0.18), (note(45), 0.10), (note(45) * 0.998, 0.08)):
    lfo = 0.75 + 0.25 * np.sin(2 * np.pi * 0.05 * t + rng.uniform(0, 6))
    mix += amp * lfo * np.sin(2 * np.pi * f * t + rng.uniform(0, 6))

# 2. Pads: 4 chords x 18 s, 5 partials each, slow filter opening, crossfaded
chords = [[62, 65, 69, 74], [58, 62, 65, 69], [55, 58, 62, 64], [57, 62, 65, 69]]  # Dm, Bb, Gm6, Dm/A
seg = N // 4
pad = np.zeros(N)
for ci, ch in enumerate(chords):
    s0 = ci * seg
    seg_t = t[:seg + SR * 4] if s0 + seg + SR * 4 <= N else t[:N - s0]
    e = env_ad(len(seg_t), 5.0, 5.0)
    chunk = np.zeros(len(seg_t))
    for midi in ch:
        f = note(midi - 12)
        for h in range(1, 6):
            det = 1 + rng.uniform(-0.0015, 0.0015)
            chunk += (0.5 / h) * np.sin(2 * np.pi * f * h * det * seg_t + rng.uniform(0, 6))
    chunk *= e * 0.035
    pad[s0:s0 + len(chunk)] += chunk
pad = lowpass(pad, 900)
mix += pad

# 3. Bells: inharmonic partials, long decay, D minor pentatonic high up
bell_notes = [74, 77, 79, 81, 84, 86, 89]
tm = 3.0
while tm < DUR - 6:
    f = note(int(rng.choice(bell_notes)))
    L = int(5.5 * SR)
    bt = np.arange(L) / SR
    tone = np.zeros(L)
    for ratio, a in ((1.0, 1.0), (2.76, 0.45), (5.4, 0.25), (8.93, 0.12)):
        tone += a * np.sin(2 * np.pi * f * ratio * bt) * np.exp(-bt * (1.1 + ratio * 0.35))
    tone *= 0.06 * rng.uniform(0.6, 1.0)
    s0 = int(tm * SR)
    end = min(N, s0 + L)
    mix[s0:end] += tone[:end - s0]
    tm += rng.uniform(4.5, 9.5)

# 4. Breath swells: band-ish noise with slow envelopes
for k in range(5):
    s0 = int(rng.uniform(2, DUR - 14) * SR)
    L = int(rng.uniform(7, 11) * SR)
    nz = rng.standard_normal(L)
    nz = lowpass(nz, 1400) - lowpass(nz, 350)
    nz *= env_ad(L, 3.5, 3.5) * 0.045
    end = min(N, s0 + L)
    mix[s0:end] += nz[:end - s0]

# 5. Distant heartbeat (two thumps every ~7.5 s, very low)
tm = 6.0
while tm < DUR - 2:
    for off in (0.0, 0.42):
        s0 = int((tm + off) * SR); L = int(0.35 * SR)
        bt = np.arange(L) / SR
        th = np.sin(2 * np.pi * 48 * bt * (1 - bt * 0.8)) * np.exp(-bt * 14) * 0.16
        end = min(N, s0 + L)
        mix[s0:end] += th[:end - s0]
    tm += 7.5

# 6. Reverb: convolution with a synthetic 3.2 s decaying-noise IR
ir_len = int(3.2 * SR)
ir = rng.standard_normal(ir_len) * np.exp(-np.arange(ir_len) / SR * 1.9)
ir = lowpass(ir, 2500)
ir /= np.sqrt(np.sum(ir ** 2))
wet = np.fft.irfft(np.fft.rfft(mix, N + ir_len) * np.fft.rfft(ir, N + ir_len))[:N]
mix = 0.65 * mix + 0.55 * wet

# 7. Seamless loop: fold the last 4 s onto the first 4 s
xf = int(4.0 * SR)
ramp = np.linspace(0, 1, xf)
head = mix[:xf] * ramp + mix[-xf:] * (1 - ramp)
mix = np.concatenate([head, mix[xf:-xf]])

# Soft stereo: tiny delayed copy on the right
d = int(0.0007 * SR)
left = mix
right = np.concatenate([mix[d:], mix[:d]])
stereo = np.stack([left, right], axis=1)
stereo /= np.max(np.abs(stereo)) * 1.12   # about -1 dBFS peak
pcm = (stereo * 32767).astype(np.int16)

out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..', '..', 'assets', 'audio', 'music', 'cutscene_mystery.mp3')
with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp:
    with wave.open(tmp.name, 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', tmp.name, '-c:a', 'libmp3lame', '-b:a', '128k', out], check=True)
    os.unlink(tmp.name)
print('wrote', os.path.abspath(out), f'{len(stereo)/SR:.1f}s')
