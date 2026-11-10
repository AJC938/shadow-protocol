"""Procedural audio generator for SHADOW PROTOCOL.

Synthesises every sound effect, ambience bed and music cue with numpy, processes
TTS voice recordings (made by tools/gen_voice.ps1) into radio transmissions, and
writes scripts/core/sound_library.gd mapping sound names -> files.

Everything produced here is original (no third-party samples).

Usage: python -I tools/gen_audio.py <project_root>
"""
import json
import os
import sys
import wave

import numpy as np

ROOT = sys.argv[1]
OUT = os.path.join(ROOT, "assets", "audio")
RNG = np.random.default_rng(1337)
LIB = {}


# ----------------------------------------------------------------------------- io / dsp helpers

def write(name, sig, sr=32000, folder="sfx", variant=None):
    sig = np.asarray(sig, dtype=np.float64)
    peak = np.max(np.abs(sig)) if sig.size else 1.0
    if peak > 0:
        sig = sig / peak * 0.89
    data = (np.clip(sig, -1, 1) * 32767).astype(np.int16)
    fname = f"{name}{'' if variant is None else '_' + str(variant)}.wav"
    d = os.path.join(OUT, folder)
    os.makedirs(d, exist_ok=True)
    with wave.open(os.path.join(d, fname), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(data.tobytes())
    LIB.setdefault(name, []).append(f"res://assets/audio/{folder}/{fname}")


def t_axis(dur, sr):
    return np.arange(int(dur * sr)) / sr


def noise(n):
    return RNG.uniform(-1, 1, n)


def env_exp(n, sr, attack, decay):
    t = np.arange(n) / sr
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-t / max(decay, 1e-4))


def fft_filter(sig, sr, lo=None, hi=None, order=2.0):
    """Smooth band-pass in the frequency domain (order controls slope)."""
    n = len(sig)
    spec = np.fft.rfft(sig)
    f = np.fft.rfftfreq(n, 1 / sr)
    g = np.ones_like(f)
    if lo:
        g *= 1 / np.sqrt(1 + (lo / np.maximum(f, 1e-3)) ** (2 * order))
    if hi:
        g *= 1 / np.sqrt(1 + (f / hi) ** (2 * order))
    return np.fft.irfft(spec * g, n)


def sweep_filter(sig, sr, f0, f1, chunks=48):
    """Time-varying low-pass by processing overlapping chunks."""
    n = len(sig)
    out = np.zeros(n)
    win = n // chunks + 1
    for i in range(chunks):
        a = i * win
        b = min(n, a + win * 2)
        if a >= n:
            break
        frac = i / max(1, chunks - 1)
        cut = f0 * (f1 / f0) ** frac
        seg = fft_filter(sig[a:b], sr, hi=cut)
        w = np.hanning(b - a)
        out[a:b] += seg * w
    return out


def reverb(sig, sr, decay=1.2, mix=0.25, predelay=0.02):
    n_ir = int(sr * decay)
    ir = noise(n_ir) * np.exp(-np.arange(n_ir) / (sr * decay / 6))
    ir = fft_filter(ir, sr, hi=5000)
    ir[: int(predelay * sr)] = 0
    total = len(sig) + n_ir
    nfft = 1 << int(np.ceil(np.log2(total)))
    wet = np.fft.irfft(np.fft.rfft(sig, nfft) * np.fft.rfft(ir, nfft), nfft)[:total]
    wet /= np.max(np.abs(wet)) + 1e-9
    out = np.concatenate([sig, np.zeros(n_ir)])
    out = out / (np.max(np.abs(out)) + 1e-9)
    return out * (1 - mix) + wet * mix


def tone(freq, dur, sr, kind="sine", detune=0.0):
    t = t_axis(dur, sr)
    ph = 2 * np.pi * freq * (1 + detune) * t
    if kind == "sine":
        return np.sin(ph)
    if kind == "saw":
        return 2 * ((freq * (1 + detune) * t) % 1.0) - 1
    if kind == "square":
        return np.sign(np.sin(ph))
    if kind == "tri":
        return 2 * np.abs(2 * ((freq * t) % 1.0) - 1) - 1
    raise ValueError(kind)


def fade(sig, sr, fin=0.005, fout=0.02):
    n = len(sig)
    a = min(n, int(fin * sr))
    b = min(n, int(fout * sr))
    if a:
        sig[:a] *= np.linspace(0, 1, a)
    if b:
        sig[-b:] *= np.linspace(1, 0, b)
    return sig


# ----------------------------------------------------------------------------- weapons

def gunshot(sr, body_hz, crack, length, tail, suppressed=False, low=60):
    n = int(length * sr)
    t = np.arange(n) / sr
    burst = noise(n) * env_exp(n, sr, 0.0005, 0.012 if suppressed else 0.02)
    burst = fft_filter(burst, sr, lo=200 if not suppressed else 120, hi=crack)
    thump = np.sin(2 * np.pi * body_hz * t * np.exp(-t * 6)) * env_exp(n, sr, 0.001, 0.05 if suppressed else 0.09)
    sub = np.sin(2 * np.pi * low * t) * env_exp(n, sr, 0.002, 0.12) * (0.3 if suppressed else 0.8)
    s = burst * (0.6 if suppressed else 1.0) + thump * 0.9 + sub
    if suppressed:
        mech = fft_filter(noise(n), sr, lo=2500, hi=7000) * env_exp(n, sr, 0.0005, 0.006) * 0.5
        s = s * 0.5 + mech
    return reverb(fade(s, sr), sr, decay=tail, mix=0.18 if suppressed else 0.32)


def weapons():
    sr = 32000
    for v in range(3):
        write("pistol_fire", gunshot(sr, 140 + v * 12, 3500, 0.25, 0.25, suppressed=True), sr, "sfx", v)
        write("rifle_fire", gunshot(sr, 95 + v * 6, 9000, 0.35, 0.9), sr, "sfx", v)
        write("rifle_fire_enemy", gunshot(sr, 110 + v * 6, 7000, 0.35, 1.0), sr, "sfx", v)
        write("smg_fire", gunshot(sr, 150 + v * 8, 7500, 0.25, 0.7), sr, "sfx", v)
        write("lmg_fire", gunshot(sr, 80 + v * 5, 6000, 0.4, 1.1, low=45), sr, "sfx", v)
    for v in range(2):
        s = gunshot(sr, 70 + v * 8, 5500, 0.55, 1.4, low=40)
        write("shotgun_fire", s, sr, "sfx", v)
    # dry fire / clicks
    n = int(0.08 * sr)
    click = fft_filter(noise(n), sr, lo=2000, hi=8000) * env_exp(n, sr, 0.0003, 0.004)
    write("dry_fire", click, sr)

    def mech(events, dur):
        out = np.zeros(int(dur * sr))
        for (at, hz_lo, hz_hi, amp, dec) in events:
            n2 = int(0.12 * sr)
            c = fft_filter(noise(n2), sr, lo=hz_lo, hi=hz_hi) * env_exp(n2, sr, 0.0005, dec) * amp
            a = int(at * sr)
            out[a:a + n2] += c[: len(out) - a]
        return reverb(out, sr, 0.3, 0.12)

    write("reload_pistol", mech([(0.05, 800, 4000, 0.7, 0.01), (0.55, 1200, 6000, 1.0, 0.012), (1.05, 1500, 7000, 0.9, 0.008)], 1.3), sr)
    write("reload_rifle", mech([(0.1, 600, 3000, 0.8, 0.015), (0.8, 900, 5000, 1.0, 0.012), (1.6, 1500, 7000, 1.0, 0.008), (1.8, 1000, 5000, 0.8, 0.01)], 2.1), sr)
    write("reload_shotgun", mech([(0.2 + i * 0.45, 700, 4000, 0.9, 0.012) for i in range(5)] + [(2.35, 500, 3000, 1.0, 0.02)], 2.6), sr)
    write("weapon_switch", mech([(0.02, 700, 4000, 0.8, 0.012), (0.2, 1200, 6000, 0.6, 0.008)], 0.4), sr)
    for v in range(4):
        n = int(0.25 * sr)
        ping = fft_filter(noise(n), sr, lo=1500 + v * 300, hi=9000) * env_exp(n, sr, 0.0003, 0.02)
        ping += np.sin(2 * np.pi * (2500 + v * 400) * t_axis(0.25, sr)) * env_exp(n, sr, 0.0005, 0.04) * 0.2
        write("impact", ping, sr, "sfx", v)


# ----------------------------------------------------------------------------- foley

def footsteps():
    sr = 32000
    specs = {
        "concrete": (300, 3500, 0.025, 0.0),
        "tile": (500, 5000, 0.02, 0.15),
        "metal": (250, 6000, 0.04, 0.6),
        "grate": (400, 7000, 0.05, 0.8),
        "gravel": (800, 9000, 0.06, 0.0),
    }
    for name, (lo, hi, dec, ring) in specs.items():
        for v in range(4):
            n = int(0.3 * sr)
            heel = fft_filter(noise(n), sr, lo=lo * (0.9 + 0.2 * RNG.random()), hi=hi) * env_exp(n, sr, 0.001, dec)
            toe = np.roll(fft_filter(noise(n), sr, lo=lo * 1.3, hi=hi) * env_exp(n, sr, 0.001, dec * 0.7) * 0.6, int(0.05 * sr))
            s = heel + toe
            if name == "gravel":
                crunch = noise(n) * (RNG.random(n) > 0.985) * env_exp(n, sr, 0.002, 0.08)
                s += fft_filter(crunch, sr, lo=1500, hi=9000) * 2.0
            if ring > 0:
                tt = t_axis(0.3, sr)
                s += np.sin(2 * np.pi * (380 + v * 40) * tt) * env_exp(n, sr, 0.001, 0.06) * ring * 0.3
            write(f"step_{name}", fade(s, sr), sr, "sfx", v)


def misc_sfx():
    sr = 32000
    # player hit / death, enemy death
    n = int(0.35 * sr)
    hit = fft_filter(noise(n), sr, lo=80, hi=1500) * env_exp(n, sr, 0.001, 0.06)
    hit += np.sin(2 * np.pi * 70 * t_axis(0.35, sr)) * env_exp(n, sr, 0.001, 0.1)
    write("player_hit", hit, sr)
    n = int(1.6 * sr)
    death = fft_filter(noise(n), sr, lo=40, hi=600) * env_exp(n, sr, 0.01, 0.4)
    death += np.sin(2 * np.pi * 55 * t_axis(1.6, sr)) * env_exp(n, sr, 0.01, 0.6)
    write("player_death", reverb(death, sr, 1.5, 0.3), sr)
    for v in range(2):
        n = int(0.8 * sr)
        thud = fft_filter(noise(n), sr, lo=40, hi=400 + v * 100) * env_exp(n, sr, 0.002, 0.12)
        thud += np.roll(thud * 0.5, int(0.18 * sr))
        write("enemy_death", thud, sr, "sfx", v)
    # alarm siren (loopable 2 s)
    t = t_axis(2.0, sr)
    f = 650 + 350 * (0.5 - 0.5 * np.cos(2 * np.pi * t / 2.0))
    ph = 2 * np.pi * np.cumsum(f) / sr
    siren = (np.sign(np.sin(ph)) * 0.4 + np.sin(ph) * 0.6)
    siren = fft_filter(siren, sr, lo=300, hi=3500)
    write("alarm_siren", siren, sr)
    # camera alert / break / beeps
    beep = np.concatenate([tone(1400, 0.08, sr), np.zeros(int(0.04 * sr)), tone(1400, 0.08, sr), np.zeros(int(0.04 * sr)), tone(1900, 0.18, sr)])
    write("camera_alert", fade(beep * 0.8, sr), sr)
    n = int(0.6 * sr)
    brk = fft_filter(noise(n), sr, lo=1500, hi=9000) * env_exp(n, sr, 0.0005, 0.08)
    brk += fft_filter(noise(n), sr, lo=100, hi=900) * env_exp(n, sr, 0.001, 0.15) * 0.6
    write("camera_break", brk, sr)
    write("panel_beep", fade(np.concatenate([tone(880, 0.12, sr, "square") * 0.3, tone(660, 0.25, sr, "square") * 0.3]), sr), sr)
    n = int(0.5 * sr)
    zap = fft_filter(noise(n), sr, lo=2000, hi=8000) * (RNG.random(n) > 0.7) * env_exp(n, sr, 0.001, 0.15)
    write("panel_sabotage", zap, sr)
    # doors
    n = int(1.0 * sr)
    slide = fft_filter(noise(n), sr, lo=150, hi=1200) * np.sin(np.linspace(0, np.pi, n)) ** 0.5
    slide += np.sin(2 * np.pi * 60 * t_axis(1.0, sr)) * 0.2 * np.sin(np.linspace(0, np.pi, n))
    slide[-int(0.12 * sr):] += fft_filter(noise(int(0.12 * sr)), sr, lo=100, hi=2000) * env_exp(int(0.12 * sr), sr, 0.001, 0.03) * 2
    write("door_slide", slide, sr)
    write("door_locked", fade(np.concatenate([tone(300, 0.15, sr, "square"), np.zeros(int(0.05 * sr)), tone(220, 0.25, sr, "square")]) * 0.3, sr), sr)
    write("door_unlock", fade(np.concatenate([tone(660, 0.08, sr), tone(990, 0.15, sr)]) * 0.5, sr), sr)
    n = int(0.5 * sr)
    locker = fft_filter(noise(n), sr, lo=300, hi=4000) * env_exp(n, sr, 0.001, 0.03)
    locker += np.sin(2 * np.pi * 420 * t_axis(0.5, sr)) * env_exp(n, sr, 0.001, 0.15) * 0.4
    write("locker", locker, sr)
    # hacking / gadgets
    seq = np.concatenate([tone(f, 0.06, sr) for f in [880, 1175, 1480, 1760]] + [tone(2349, 0.25, sr)])
    write("hack_complete", fade(seq * 0.5, sr), sr)
    write("gadget_deploy", fade(np.concatenate([tone(1200, 0.05, sr), tone(1800, 0.1, sr)]) * 0.5, sr), sr)
    t = t_axis(1.2, sr)
    emp = np.sin(2 * np.pi * (2000 * np.exp(-t * 3) + 60) * t) * np.exp(-t * 2)
    emp += fft_filter(noise(len(t)), sr, lo=200, hi=5000) * np.exp(-t * 4) * 0.5
    write("gadget_emp", reverb(emp, sr, 0.8, 0.3), sr)
    t = t_axis(1.0, sr)
    scan = np.sin(2 * np.pi * (300 + 1500 * t) * t) * np.exp(-t * 2.5) * 0.7
    write("gadget_scan", reverb(scan, sr, 1.0, 0.35), sr)
    write("pickup_ammo", reverb(fft_filter(noise(int(0.3 * sr)), sr, lo=500, hi=5000) * env_exp(int(0.3 * sr), sr, 0.001, 0.05), sr, 0.3, 0.2), sr)
    write("pickup_med", fade(np.concatenate([tone(523, 0.1, sr), tone(784, 0.2, sr)]) * 0.4, sr), sr)
    write("pickup_key", fade(np.concatenate([tone(1047, 0.07, sr), tone(1568, 0.15, sr)]) * 0.4, sr), sr)
    write("pickup_intel", fade(np.concatenate([tone(f, 0.07, sr, "tri") for f in [784, 988, 1175]] + [tone(1568, 0.3, sr, "tri")]) * 0.4, sr), sr)


def ui_sfx():
    sr = 32000
    write("ui_hover", fade(tone(2200, 0.03, sr) * 0.25, sr, 0.002, 0.02), sr, "ui")
    write("ui_click", fade((tone(1600, 0.04, sr) + tone(800, 0.04, sr) * 0.5) * 0.4, sr, 0.002, 0.03), sr, "ui")
    write("ui_tick", fade(tone(3000, 0.02, sr) * 0.3, sr, 0.001, 0.015), sr, "ui")
    write("ui_open", fade(np.concatenate([tone(600, 0.06, sr), tone(900, 0.1, sr)]) * 0.35, sr), sr, "ui")
    write("ui_error", fade(tone(200, 0.2, sr, "square") * 0.2, sr), sr, "ui")
    write("ui_scan", fade(np.concatenate([tone(1500, 0.05, sr), tone(1500, 0.05, sr) * 0]) * 0.3, sr), sr, "ui")
    write("ui_objective_progress", fade(np.concatenate([tone(880, 0.08, sr, "tri"), tone(1320, 0.14, sr, "tri")]) * 0.4, sr), sr, "ui")
    chord = sum(tone(f, 0.9, sr, "tri") for f in [523.25, 659.25, 783.99]) * env_exp(int(0.9 * sr), sr, 0.01, 0.35)
    write("ui_objective_complete", reverb(chord, sr, 1.2, 0.3), sr, "ui")
    hit = fft_filter(noise(int(0.8 * sr)), sr, lo=40, hi=300) * env_exp(int(0.8 * sr), sr, 0.001, 0.2)
    write("ui_grade", reverb(hit + chord[: len(hit)] * 0.6, sr, 1.5, 0.35), sr, "ui")


# ----------------------------------------------------------------------------- ambience

def ambience():
    sr = 22050
    dur = 30.0
    n = int(dur * sr)
    wind = fft_filter(noise(n), sr, lo=80, hi=700)
    lfo = 0.6 + 0.4 * np.sin(2 * np.pi * t_axis(dur, sr) / 7.5) * np.sin(2 * np.pi * t_axis(dur, sr) / 3.1)
    hum = np.sin(2 * np.pi * 50 * t_axis(dur, sr)) * 0.05 + np.sin(2 * np.pi * 100 * t_axis(dur, sr)) * 0.03
    s = wind * lfo + hum
    s = _loopable(s, sr)
    write("amb_night_wind", s, sr, "ambience")
    hum2 = sum(np.sin(2 * np.pi * f * t_axis(dur, sr)) * a for f, a in [(60, 0.5), (120, 0.25), (180, 0.12), (240, 0.08)])
    hum2 += fft_filter(noise(n), sr, lo=100, hi=2000) * 0.3
    write("amb_industrial_hum", _loopable(hum2, sr), sr, "ambience")
    srv = fft_filter(noise(n), sr, lo=1500, hi=6000) * 0.35 + sum(np.sin(2 * np.pi * f * t_axis(dur, sr)) * 0.1 for f in [440, 660, 997])
    srv += fft_filter(noise(n), sr, lo=60, hi=300) * 0.4
    write("amb_server_room", _loopable(srv, sr), sr, "ambience")


def _loopable(s, sr, xf=1.0):
    k = int(xf * sr)
    head = s[:k].copy()
    s = s[k:]
    s[-k:] = s[-k:] * np.linspace(1, 0, k) + head * np.linspace(0, 1, k)
    return s


# ----------------------------------------------------------------------------- music

NOTE = {"A1": 55.0, "C2": 65.41, "D2": 73.42, "E2": 82.41, "F2": 87.31, "G2": 98.0, "A2": 110.0, "Bb2": 116.54, "C3": 130.81, "D3": 146.83, "E3": 164.81, "F3": 174.61, "G3": 196.0, "A3": 220.0}


def pad_chord(freqs, dur, sr, bright=900):
    t = t_axis(dur, sr)
    s = np.zeros(len(t))
    for f in freqs:
        for d in (-0.004, 0.0, 0.005):
            s += 2 * ((f * (1 + d) * t) % 1.0) - 1
    s = fft_filter(s, sr, hi=bright, order=1.5)
    e = np.minimum(1, t / 1.5) * np.minimum(1, (dur - t) / 1.5)
    return s * e


def music(name, bpm, chords, dur, intensity, sr=22050, bright=800, perc=True, bass=True, arp=False):
    beat = 60.0 / bpm
    total = int(dur * sr)
    out = np.zeros(total)
    bar = beat * 4
    seg = bar * 2
    i = 0
    tpos = 0.0
    while tpos < dur:
        ch = chords[i % len(chords)]
        freqs = [NOTE[c] * 2 for c in ch]
        p = pad_chord(freqs, seg + 1.5, sr, bright)
        a = int(tpos * sr)
        b = min(total, a + len(p))
        out[a:b] += p[: b - a] * 0.25
        if bass:
            root = NOTE[ch[0]]
            for k in range(int(seg / (beat / 2))):
                st = tpos + k * beat / 2
                if st >= dur:
                    break
                if intensity < 0.5 and k % 4 != 0:
                    continue
                nn = int(beat / 2 * sr * 0.9)
                tt = np.arange(nn) / sr
                note = np.sin(2 * np.pi * root * tt) + 0.4 * np.sin(4 * np.pi * root * tt)
                note *= np.exp(-tt * (6 if intensity > 0.5 else 2.5))
                a2 = int(st * sr)
                out[a2:a2 + nn] += note[: max(0, min(nn, total - a2))] * 0.35 * (0.6 + intensity * 0.4)
        if arp:
            for k in range(int(seg / (beat / 4))):
                st = tpos + k * beat / 4
                if st >= dur:
                    break
                f = NOTE[ch[k % len(ch)]] * 4
                nn = int(beat / 4 * sr)
                tt = np.arange(nn) / sr
                note = (2 * ((f * tt) % 1.0) - 1) * np.exp(-tt * 18)
                a2 = int(st * sr)
                out[a2:a2 + nn] += fft_filter(note, sr, hi=2500)[: max(0, min(nn, total - a2))] * 0.08
        tpos += seg
        i += 1
    if perc:
        steps = int(dur / (beat / 2))
        for k in range(steps):
            st = k * beat / 2
            a2 = int(st * sr)
            if k % 8 == 0 or (intensity > 0.7 and k % 8 == 6):
                nn = int(0.4 * sr)
                tt = np.arange(nn) / sr
                kick = np.sin(2 * np.pi * (45 + 80 * np.exp(-tt * 25)) * tt) * np.exp(-tt * 7)
                out[a2:a2 + nn] += kick[: max(0, min(nn, total - a2))] * 0.5 * intensity
            if intensity > 0.4 and k % 2 == 1:
                nn = int(0.06 * sr)
                hat = fft_filter(noise(nn), sr, lo=6000) * np.exp(-np.arange(nn) / sr * 60)
                out[a2:a2 + nn] += hat[: max(0, min(nn, total - a2))] * 0.08 * intensity
            if intensity > 0.6 and k % 8 == 4:
                nn = int(0.3 * sr)
                sn = fft_filter(noise(nn), sr, lo=300, hi=5000) * np.exp(-np.arange(nn) / sr * 14)
                out[a2:a2 + nn] += sn[: max(0, min(nn, total - a2))] * 0.18 * intensity
    out = reverb(out, sr, 2.0, 0.22)[:total]
    write(name, _loopable(out, sr, 1.5), sr, "music")


def all_music():
    dark = [["D2", "F2", "A2"], ["Bb2", "D3", "F3"] and ["A1", "C2", "E2"], ["F2", "A2", "C3"], ["C2", "E2", "G2"]]
    dark = [["D2", "F2", "A2"], ["Bb2", "D3", "F3"], ["F2", "A2", "C3"], ["C2", "E2", "G2"]]
    music("menu", 70, [["D2", "F2", "A2"], ["Bb2", "D3", "F3"], ["G2", "Bb2", "D3"], ["A2", "C3", "E3"]], 64, 0.3, bright=700, perc=False, arp=True)
    music("briefing", 76, [["A1", "C2", "E2"], ["F2", "A2", "C3"], ["D2", "F2", "A2"], ["E2", "G2", "D3"]], 48, 0.35, bright=650)
    music("mission_1", 84, dark, 72, 0.35, bright=600)
    music("mission_2", 92, [["E2", "G2", "D3"], ["C2", "E2", "G2"], ["A1", "C2", "E2"], ["D2", "F2", "A2"]], 72, 0.45, bright=700, arp=True)
    music("mission_3", 98, [["C2", "E2", "G2"], ["Bb2", "D3", "F3"], ["F2", "A2", "C3"], ["G2", "Bb2", "D3"]], 72, 0.5, bright=800, arp=True)
    music("combat", 132, [["D2", "F2", "A2"], ["C2", "E2", "G2"], ["Bb2", "D3", "F3"], ["A1", "C2", "E2"]], 48, 0.95, bright=1400, arp=True)
    music("failure", 60, [["D2", "F2", "A2"], ["A1", "C2", "E2"]], 16, 0.1, bright=500, perc=False)
    music("victory", 80, [["F2", "A2", "C3"], ["C2", "E2", "G2"], ["D2", "F2", "A2"], ["Bb2", "D3", "F3"]], 24, 0.3, bright=900, perc=False, arp=True)
    music("debrief", 72, [["F2", "A2", "C3"], ["D2", "F2", "A2"], ["Bb2", "D3", "F3"], ["C2", "E2", "G2"]], 48, 0.25, bright=750, perc=False)
    music("ending", 66, [["F2", "A2", "C3"], ["C2", "E2", "G2"], ["D2", "F2", "A2"], ["Bb2", "D3", "F3"]], 64, 0.3, bright=900, perc=False, arp=True)


# ----------------------------------------------------------------------------- voice processing

def read_wav(path):
    with wave.open(path, "rb") as w:
        sr = w.getframerate()
        ch = w.getnchannels()
        data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768
    if ch == 2:
        data = data.reshape(-1, 2).mean(axis=1)
    return data, sr


def voices():
    src = os.path.join(ROOT, "tools", "voice_raw")
    spec_path = os.path.join(ROOT, "tools", "voice_lines.json")
    if not os.path.isdir(src) or not os.path.exists(spec_path):
        print("no raw voices; skipping")
        return
    spec = json.load(open(spec_path, encoding="utf8"))
    for key, item in spec.items():
        p = os.path.join(src, key + ".wav")
        if not os.path.exists(p):
            continue
        sig, sr = read_wav(p)
        role = item["role"]
        if role == "oracle":
            sig = fft_filter(sig, sr, lo=320, hi=3400, order=2)
            sig = np.tanh(sig * 2.2) * 0.8
            sig += fft_filter(noise(len(sig)), sr, lo=1000, hi=6000) * 0.008
            k = int(0.06 * sr)
            squelch = fft_filter(noise(k), sr, lo=800, hi=5000) * 0.15
            sig = np.concatenate([squelch, np.zeros(int(0.05 * sr)), sig, np.zeros(int(0.05 * sr)), squelch])
        elif role == "ghost":
            sig = fft_filter(sig, sr, lo=180, hi=4200, order=1.5)
            sig = np.tanh(sig * 1.6) * 0.85
        else:  # guards: shouted / helmet radio
            sig = fft_filter(sig, sr, lo=220 if role == "guard" else 150, hi=3800 if role == "guard" else 2600)
            sig = np.tanh(sig * (2.5 if role == "guard" else 3.2))
        write(key, sig, sr, "voice")


def write_library():
    lines = ["class_name SoundLibrary", "extends RefCounted", "## GENERATED by tools/gen_audio.py — do not edit by hand.", "", "const SOUNDS := {"]
    for k in sorted(LIB):
        files = ", ".join(f'"{f}"' for f in LIB[k])
        lines.append(f'\t"{k}": [{files}],')
    lines.append("}")
    with open(os.path.join(ROOT, "scripts", "core", "sound_library.gd"), "w", encoding="utf8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    only = sys.argv[2] if len(sys.argv) > 2 else "all"
    weapons()
    footsteps()
    misc_sfx()
    ui_sfx()
    ambience()
    if only in ("all", "music"):
        all_music()
    voices()
    write_library()
    print("sounds:", len(LIB), "files:", sum(len(v) for v in LIB.values()))
