#!/usr/bin/env python3
"""Synthesises the music and the city ambience (no third-party samples).

Run:  python3 tools/make_music.py      (needs numpy, scipy and ffmpeg)
Writes audio/music.ogg, audio/ambience.ogg (seamless loops) and the
one-shots audio/siren.ogg and audio/birds_flap.wav.

The music is a slow sunset loop in D dorian: a warm pad, a soft electric
piano arpeggio with echoes, a round bass; the ambience is the city around
the district: traffic rumble, cars passing, wind, birds.
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


# --- Ambience ------------------------------------------------------------------


def car_pass(sec, pan_dir):
    """One car passing a few blocks away: a swelling hiss and engine hum
    that pans across."""
    tt = t(sec)
    shape = np.exp(-(((tt - sec / 2) / (sec / 5)) ** 2))
    hiss = bp(rng.standard_normal(len(tt)), 250, 1400) * 0.6
    f = 55 + 10 * np.tanh((tt - sec / 2) * 2) * -1  # a hint of Doppler
    hum = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.5
    x = (hiss + hum) * shape
    pan = 0.5 + 0.45 * np.tanh((tt - sec / 2) * 1.5) * pan_dir
    return np.stack([x * np.sqrt(1 - pan), x * np.sqrt(pan)], axis=1)


def chirp(sec=0.09, f0=3800.0, f1=5200.0):
    tt = t(sec)
    f = np.linspace(f0, f1, len(tt))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR)
    return x * np.sin(np.pi * tt / sec) ** 2


def ambience():
    sec = 32.0
    n = int(SR * sec)
    out = np.zeros((n, 2))
    # Rumble of the city: brown noise, slowly swelling.
    brown = np.cumsum(rng.standard_normal(n + SR))[SR:]
    brown = hp(brown - np.mean(brown), 25)
    rumble = lp(brown, 180)
    swell = 0.75 + 0.25 * np.sin(2 * np.pi * np.arange(n) / n * 3)
    rumble = rumble / np.max(np.abs(rumble)) * swell * 0.45
    out[:, 0] += rumble
    out[:, 1] += np.roll(rumble, SR // 3)
    # Wind between the buildings.
    wind = bp(rng.standard_normal(n), 300, 1100)
    gust = 0.5 + 0.5 * np.sin(2 * np.pi * np.arange(n) / n * 2 + 1.0)
    wind = wind / np.max(np.abs(wind)) * (0.08 + 0.12 * gust)
    out[:, 0] += wind
    out[:, 1] += np.roll(wind, SR)
    out[:, 0] = lp(out[:, 0], 2400, 4)
    out[:, 1] = lp(out[:, 1], 2400, 4)
    # Cars passing in the distance (muffled by the blocks between).
    for k in range(7):
        c = car_pass(rng.uniform(5.0, 8.0), 1 if k % 2 else -1) * rng.uniform(0.12, 0.22)
        c = np.stack([lp(c[:, 0], 1800, 4), lp(c[:, 1], 1800, 4)], axis=1)
        start = int(SR * (k * sec / 7 + rng.uniform(0, 2.0)))
        for ch in range(2):
            col = np.zeros(n)
            add_loop(col, c[:, ch], start)
            out[:, ch] += col
    # Birds: little phrases of chirps here and there.
    for k in range(9):
        start = int(SR * rng.uniform(0, sec))
        side = rng.uniform(0.15, 0.85)
        phrase = np.zeros(int(SR * 1.2))
        base = rng.uniform(3200, 4600)
        for j in range(rng.integers(2, 5)):
            c = chirp(rng.uniform(0.05, 0.11), base * rng.uniform(0.9, 1.1), base * rng.uniform(1.15, 1.45))
            s = int(SR * j * rng.uniform(0.12, 0.2))
            phrase[s : s + len(c)] += c[: len(phrase) - s]
        phrase *= rng.uniform(0.05, 0.1)
        for ch, g in ((0, np.sqrt(1 - side)), (1, np.sqrt(side))):
            col = np.zeros(n)
            add_loop(col, phrase * g, start)
            out[:, ch] += col
    out[:, 0] = loop_reverb(out[:, 0], reverb_ir(1.4, 3), 0.25)
    out[:, 1] = loop_reverb(out[:, 1], reverb_ir(1.4, 4), 0.25)
    return out


def siren():
    """A siren far away: the two-tone wail, muffled by the city."""
    sec = 7.0
    tt = t(sec)
    f = 760 + 340 * (0.5 + 0.5 * np.sin(2 * np.pi * tt / 1.9))
    x = signal.sawtooth(2 * np.pi * np.cumsum(f) / SR, 0.5)
    x = lp(x, 1500) * np.clip(tt / 1.2, 0, 1) * np.clip((sec - tt) / 2.0, 0, 1)
    wet = signal.fftconvolve(x, reverb_ir(2.0, 5))[: len(x)]
    y = x * 0.4 + wet * 0.8
    return np.stack([y, np.roll(y, int(SR * 0.02))], axis=1)


def birds_flap():
    """A flock taking off: fast wing claps and a few alarm chirps."""
    sec = 1.6
    n = int(SR * sec)
    x = np.zeros(n)
    for _ in range(70):
        s = int(SR * rng.uniform(0, 1.1) ** 1.6)
        clap = bp(rng.standard_normal(int(SR * 0.025)), 500, 3500) * np.hanning(int(SR * 0.025))
        x[s : s + len(clap)] += clap[: n - s] * rng.uniform(0.3, 1.0)
    for _ in range(4):
        c = chirp(0.07, 2800, 3600) * 0.5
        s = int(SR * rng.uniform(0.05, 0.6))
        x[s : s + len(c)] += c
    x *= np.exp(-np.arange(n) / SR * 1.4)
    m = np.max(np.abs(x)) or 1.0
    wavfile.write(os.path.join(OUT, "birds_flap.wav"), SR, (x / m * 0.85 * 32767).astype(np.int16))
    print("wrote birds_flap.wav")


if __name__ == "__main__":
    save_ogg("music", music(), quality=3)
    save_ogg("ambience", ambience(), quality=2)
    save_ogg("siren", siren(), quality=3)
    birds_flap()
