#!/usr/bin/env python3
"""Synthesises the music and the ambience (no third-party samples).

Run:  python3 tools/make_music.py      (needs numpy, scipy and ffmpeg)
Writes audio/music.ogg and audio/ambience.ogg (seamless loops).

The music is a slow sunset loop in D dorian: a warm pad, a soft electric
piano arpeggio with echoes, a round bass; the ambience is the empty square
round the palace: wind, gusts and a distant hum.
"""
import os
import subprocess
import tempfile

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")
rng = np.random.default_rng(11)


def t(sec):
    return np.arange(int(round(SR * sec))) / SR


def lp(x, hz, order=2):
    b, a = signal.butter(order, hz / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def hp(x, hz, order=2):
    b, a = signal.butter(order, hz / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def bp(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), hi / (SR / 2)], "band")
    return signal.lfilter(b, a, x)


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def reverb_ir(sec, seed):
    r = np.random.default_rng(seed)
    n = int(SR * sec)
    ir = r.standard_normal(n) * np.exp(-np.arange(n) / SR * 6.9 / sec)
    ir = lp(ir, 5000)
    ir[0] = 0
    return ir / np.sqrt(np.sum(ir**2))


def add_loop(dst, x, start):
    """Adds x into dst at start, wrapping the overflow to the beginning so
    the result loops without a seam."""
    n = len(dst)
    start %= n
    end = start + len(x)
    if end <= n:
        dst[start:end] += x
    else:
        k = n - start
        dst[start:] += x[:k]
        rest = x[k:]
        while len(rest) > 0:
            m = min(len(rest), n)
            dst[:m] += rest[:m]
            rest = rest[m:]


def loop_reverb(x, ir, wet):
    y = signal.fftconvolve(x, ir)
    out = x * (1 - wet)
    tail = np.zeros_like(x)
    add_loop(tail, y, 0)
    return out + tail * wet


def save_ogg(name, stereo, quality=4):
    m = np.max(np.abs(stereo)) or 1.0
    data = (stereo / m * 0.89 * 32767).astype(np.int16)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        tmp = f.name
    wavfile.write(tmp, SR, data)
    path = os.path.join(OUT, name + ".ogg")
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", str(quality), path],
        check=True,
    )
    os.remove(tmp)
    print("wrote", path)


# --- Music -------------------------------------------------------------------

BPM = 72.0
BEAT = 60.0 / BPM
BAR = BEAT * 4
# D dorian, two bars per chord, voiced for a warm pad (MIDI notes).
CHORDS = [
    [50, 57, 60, 64, 65],  # Dm9 (D A C E F)
    [46, 53, 57, 62, 65],  # Bbmaj7 (Bb F A D F)
    [48, 55, 59, 64, 67],  # C/E-ish Cmaj7 (C G B E G)
    [45, 52, 55, 60, 64],  # Am7 (A E G C E)
]
ARP = [0, 2, 4, 3, 1, 3, 4, 2]  # chord-tone order for the eighth notes


def saw_voice(freq, sec):
    tt = t(sec)
    x = np.zeros_like(tt)
    for det in (-0.12, 0.0, 0.13):
        f = freq * 2 ** (det / 12)
        x += signal.sawtooth(2 * np.pi * f * tt + rng.uniform(0, 6.28))
    return x / 3


def pad_chord(notes, sec):
    x = sum(saw_voice(midi(n), sec) for n in notes[1:])
    n = len(x)
    a = int(SR * 1.6)
    r = int(SR * 2.2)
    e = np.ones(n)
    e[:a] = np.linspace(0, 1, a) ** 2
    e[-r:] *= np.linspace(1, 0, r) ** 1.5
    # A slow filter sweep breathes through each chord.
    lo = lp(x, 520, 4)
    hi = lp(x, 1250, 4)
    mix = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi * 2, n))
    return (lo * (1 - mix * 0.6) + hi * mix * 0.6) * e


def epiano(freq, sec=2.2, vel=1.0):
    tt = t(sec)
    index = 1.6 * np.exp(-tt * 5.0)
    mod = np.sin(2 * np.pi * freq * tt) * index
    x = np.sin(2 * np.pi * freq * tt + mod) + 0.25 * np.sin(4 * np.pi * freq * tt) * np.exp(-tt * 3)
    e = np.exp(-tt * 1.6) * np.clip(tt / 0.004, 0, 1)
    return x * e * vel


def bass(freq, sec):
    tt = t(sec)
    x = np.sin(2 * np.pi * freq * tt) + 0.3 * np.sin(4 * np.pi * freq * tt)
    e = np.clip(tt / 0.02, 0, 1) * np.exp(-tt * 0.7)
    return lp(x, 400) * e


def music():
    bars = 16  # the four chords twice, the second pass with more piano
    total = bars * BAR
    n = int(SR * total)
    pad = np.zeros(n)
    keys = np.zeros(n)
    low = np.zeros(n)
    for b in range(0, bars, 2):
        chord = CHORDS[(b // 2) % 4]
        start = int(SR * b * BAR)
        add_loop(pad, pad_chord(chord, BAR * 2 + 2.0), start - int(SR * 0.8))
        add_loop(low, bass(midi(chord[0] - 12), BAR * 2), start)
        add_loop(low, bass(midi(chord[0] - 12), BAR) * 0.7, start + int(SR * BAR * 1.5))
        second = b >= bars // 2
        for k in range(16):  # eighth notes over two bars
            if not second and k % 2 == 1:
                continue  # first pass: quarter notes only, sparser
            if rng.random() < 0.18:
                continue
            note = chord[ARP[k % 8]] + 12
            vel = 0.55 + 0.3 * rng.random() + (0.15 if k % 4 == 0 else 0)
            add_loop(keys, epiano(midi(note), vel=vel), start + int(SR * k * BEAT / 2))
    # Echo on the piano: dotted eighths, fading.
    echo = keys.copy()
    d = int(SR * BEAT * 0.75)
    for k in range(1, 5):
        add_loop(echo, keys * (0.42**k), d * k)
    left = pad * 0.55 + echo * 0.5 + low * 0.6
    right = pad * 0.55 + np.roll(echo, int(SR * 0.012)) * 0.5 + low * 0.6
    left = loop_reverb(left, reverb_ir(2.6, 1), 0.35)
    right = loop_reverb(right, reverb_ir(2.6, 2), 0.35)
    return np.stack([left, right], axis=1)


# --- Ambience ----------------------------------------------------------------


def periodic_noise(n, shape):
    """Noise whose spectrum follows shape(freq_hz); built in the frequency
    domain, so it is exactly periodic over n samples (a seamless loop)."""
    f = np.fft.rfftfreq(n, 1 / SR)
    spec = (rng.standard_normal(len(f)) + 1j * rng.standard_normal(len(f))) * shape(f)
    spec[0] = 0
    x = np.fft.irfft(spec, n)
    return x / np.max(np.abs(x))


def cycles(n, k, phase=0.0):
    """A slow sine with exactly k periods over the loop."""
    return np.sin(2 * np.pi * k * np.arange(n) / n + phase)


def ambience():
    """An empty square in the evening: wind over the stones, gusts that
    whistle round the tower, a very distant hum. Everything is periodic
    over the loop length, so it repeats without a seam."""
    sec = 32.0
    n = int(SR * sec)
    out = np.zeros((n, 2))
    for ch in range(2):
        hum = periodic_noise(n, lambda f: np.where(f > 20, 1 / np.maximum(f, 1), 0) * (f < 160))
        body = periodic_noise(n, lambda f: np.exp(-(((f - 520) / 380) ** 2)))
        whistle = periodic_noise(n, lambda f: np.exp(-(((f - 1350) / 160) ** 2)))
        gust = 0.5 + 0.5 * cycles(n, 3, 1.1 + ch * 0.6) * (0.6 + 0.4 * cycles(n, 2, ch))
        out[:, ch] = hum * 0.22 + body * (0.12 + 0.2 * gust) + whistle * 0.05 * gust**3
    return out


if __name__ == "__main__":
    save_ogg("music", music(), quality=3)
    save_ogg("ambience", ambience(), quality=2)
