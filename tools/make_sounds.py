#!/usr/bin/env python3
"""Synthesises every sound effect in audio/ (no third-party samples).

Run:  python3 tools/make_sounds.py
Each sound is built from noise, filters and oscillators so the whole
soundscape is reproducible and tweakable here, in code.
"""
import os
import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")
rng = np.random.default_rng(7)


def t(sec):
    return np.arange(int(SR * sec)) / SR


def noise(sec):
    return rng.uniform(-1, 1, int(round(SR * sec)))


def lp(x, hz, order=2):
    b, a = signal.butter(order, hz / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def hp(x, hz, order=2):
    b, a = signal.butter(order, hz / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def bp(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), hi / (SR / 2)], "band")
    return signal.lfilter(b, a, x)


def env(n, attack, decay_tau, sustain=0.0):
    """Exponential decay envelope with a short linear attack."""
    tt = np.arange(n) / SR
    e = np.exp(-tt / decay_tau) * (1 - sustain) + sustain
    a = np.clip(tt / max(attack, 1e-4), 0, 1)
    return e * a


def fade_out(x, sec=0.03):
    n = int(SR * sec)
    x[-n:] *= np.linspace(1, 0, n)
    return x


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def save(name, x, peak=0.9):
    x = fade_out(norm(np.asarray(x, dtype=np.float64), peak))
    wavfile.write(os.path.join(OUT, name + ".wav"), SR, (x * 32767).astype(np.int16))


def sweep(f0, f1, sec, kind="sin"):
    tt = t(sec)
    f = f0 * (f1 / f0) ** (tt / sec)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) if kind == "sin" else signal.sawtooth(ph, 0.5)


def charge_loop():
    # 2 s seamless hum: detuned saws through a low-pass, slow shimmer.
    sec = 2.0
    tt = t(sec)
    x = np.zeros_like(tt)
    for f, a in [(110, 1.0), (110.5, 0.8), (220.3, 0.5), (329.6, 0.25)]:
        x += a * signal.sawtooth(2 * np.pi * f * tt)
    x = lp(x, 900)
    x *= 0.8 + 0.2 * np.sin(2 * np.pi * 3 * tt)  # 3 Hz = 6 cycles, loops
    x += 0.15 * lp(noise(sec), 3000) * (0.6 + 0.4 * np.sin(2 * np.pi * 1.5 * tt))
    return x


def throw():
    sec = 0.45
    x = bp(noise(sec), 400, 4000) * env(int(SR * sec), 0.02, 0.12)
    x += 0.4 * sweep(900, 300, sec) * env(int(SR * sec), 0.005, 0.08)
    return x


def implode():
    # Reverse-swell suction: rising filtered noise + rising tone.
    sec = 0.9
    n = int(SR * sec)
    rise = np.linspace(0, 1, n) ** 2.2
    x = lp(noise(sec), 2500) * rise
    x += 0.5 * sweep(60, 240, sec) * rise
    x += 0.25 * sweep(400, 1600, sec) * rise ** 3
    return x


def burst():
    sec = 2.2
    n = int(SR * sec)
    boom = sweep(90, 32, sec) * env(n, 0.003, 0.5)
    crack = hp(noise(sec), 1500) * env(n, 0.001, 0.05)
    body = lp(noise(sec), 700) * env(n, 0.004, 0.45)
    tail = lp(noise(sec), 250) * env(n, 0.05, 0.9)
    return 1.4 * boom + 0.6 * crack + 0.9 * body + 0.5 * tail


def crumble(sec, lo, hi, grains, grain_len, decay):
    """Many short filtered noise grains: rocks, debris."""
    n = int(SR * sec)
    out = np.zeros(n)
    for _ in range(grains):
        start = int(rng.exponential(decay) * SR)
        if start >= n:
            continue
        g = int(SR * grain_len * rng.uniform(0.5, 1.5))
        grain = bp(rng.uniform(-1, 1, g), lo * rng.uniform(0.7, 1.3), hi) * env(g, 0.001, grain_len * 0.3)
        end = min(n, start + g)
        out[start:end] += grain[: end - start] * rng.uniform(0.3, 1.0)
    return out


def break_concrete():
    sec = 0.9
    n = int(SR * sec)
    hit = lp(noise(sec), 1800) * env(n, 0.001, 0.06)
    return 1.2 * hit + crumble(sec, 300, 3500, 40, 0.03, 0.12)


def break_wood():
    sec = 0.7
    n = int(SR * sec)
    snap = hp(noise(sec), 2000) * env(n, 0.0005, 0.015)
    tt = t(sec)
    knock = sum(a * np.sin(2 * np.pi * f * tt) for f, a in [(210, 1), (480, 0.6), (930, 0.3)])
    knock = knock * env(n, 0.001, 0.07)
    splinter = crumble(sec, 1500, 6000, 18, 0.015, 0.06)
    return 0.9 * snap + 0.8 * knock + 0.6 * splinter


def break_metal():
    sec = 1.3
    n = int(SR * sec)
    tt = t(sec)
    partials = [(523, 1.0, 0.5), (1347, 0.6, 0.3), (2210, 0.4, 0.2), (3120, 0.25, 0.12), (737, 0.5, 0.35)]
    x = sum(a * np.sin(2 * np.pi * f * tt) * env(n, 0.0005, d) for f, a, d in partials)
    x += 0.5 * hp(noise(sec), 3000) * env(n, 0.0005, 0.02)
    return x


def collapse():
    # Long rumble with a cascade of crumbles.
    sec = 2.8
    n = int(SR * sec)
    rumble = lp(noise(sec), 160, 4) * env(n, 0.02, 1.1)
    thud = sweep(70, 35, sec) * env(n, 0.003, 0.35)
    return 1.3 * rumble + 1.0 * thud + 0.7 * crumble(sec, 200, 2500, 120, 0.04, 0.6)


def creak():
    # Stressed structure groaning before it goes.
    sec = 1.2
    tt = t(sec)
    f = 70 + 25 * np.sin(2 * np.pi * 1.3 * tt) + 10 * rng.standard_normal(len(tt)).cumsum() / SR * 40
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = signal.sawtooth(ph) * (0.6 + 0.4 * np.sin(2 * np.pi * 9 * tt))
    x = bp(x, 80, 1200)
    return x * env(len(tt), 0.15, 0.5)


def click():
    sec = 0.06
    n = int(SR * sec)
    return np.sin(2 * np.pi * 1800 * t(sec)) * env(n, 0.0005, 0.012)


def star(pitch=1.0):
    sec = 0.6
    n = int(SR * sec)
    tt = t(sec)
    base = 880 * pitch
    x = sum(a * np.sin(2 * np.pi * base * m * tt) for m, a in [(1, 1), (2, 0.35), (3, 0.15), (4.2, 0.1)])
    return x * env(n, 0.002, 0.18)


def fanfare():
    notes = [523.25, 659.25, 783.99, 1046.5]
    out = np.zeros(int(SR * 1.4))
    for k, f in enumerate(notes):
        sec = 0.9 - k * 0.1
        n = int(SR * sec)
        tt = t(sec)
        tone = sum(a * np.sin(2 * np.pi * f * m * tt) for m, a in [(1, 1), (2, 0.3), (3, 0.12)])
        tone *= env(n, 0.004, 0.25)
        s = int(SR * 0.11 * k)
        out[s : s + n] += tone
    return out


def chain():
    sec = 0.35
    n = int(SR * sec)
    return (sweep(600, 1400, sec) + 0.4 * sweep(900, 2100, sec)) * env(n, 0.002, 0.09)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    save("charge_loop", charge_loop(), 0.6)
    save("throw", throw())
    save("implode", implode())
    save("burst", burst(), 0.95)
    save("break_concrete", break_concrete())
    save("break_wood", break_wood())
    save("break_metal", break_metal(), 0.7)
    save("collapse", collapse(), 0.95)
    save("creak", creak(), 0.7)
    save("click", click(), 0.5)
    save("star", star())
    save("fanfare", fanfare(), 0.8)
    save("chain", chain(), 0.6)
    print("ok", sorted(os.listdir(OUT)))
