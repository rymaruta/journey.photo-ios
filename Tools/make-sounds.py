#!/usr/bin/env python3
"""アプリの短い効果音を、自分で合成して作る（2026-11-25 判断）。

他人の音源・ネットの効果音は権利の確認ができないので使わない。ここで正弦波とノイズの包絡だけから作り、
同じ音をいつでも作り直せるようにする（乱数は種を決めた自前の式なので、何度流しても同じバイト列になる）。

    python3 Tools/make-sounds.py                # Sources/JourneyPhoto/Resources/Sounds/ に書く
    python3 Tools/make-sounds.py --out <dir>    # 別の所に書く（聞き比べ用）

形式: CAF・リニア PCM・16 bit・モノラル・32 kHz（`AudioServicesCreateSystemSoundID` が読める形）。
1つ 50KB 未満にするため 32 kHz にした（いちばん高い音は 9 kHz ほどで、32 kHz で足りる）。

- capsule-open.caf: カプセルが開く瞬間。「ポンッ」と軽く弾けて、上へ4つの鈴の音がきらっと続く（約 0.62 秒）
- coin-in.caf: 硬貨が入れ口に入る。小さな「ちゃりん」（約 0.30 秒・カプセルより静か）
"""
import argparse
import math
import os
import struct

RATE = 32000


class Noise:
    """種を決めた白いノイズ（線形合同法）。毎回同じ値の並びになる"""

    def __init__(self, seed):
        self.state = seed

    def next(self):
        self.state = (1103515245 * self.state + 12345) & 0x7FFFFFFF
        return self.state / 0x3FFFFFFF - 1.0


def env(t, attack, tau):
    """立ち上がり attack 秒（直線）、そのあと時定数 tau 秒で減っていく包絡"""
    if t < 0:
        return 0.0
    if t < attack:
        return t / attack
    return math.exp(-(t - attack) / tau)


def bell(buf, start, freq, amp, tau):
    """鈴の音1つ（基音＋少しの金属の倍音 2.76 倍。倍音は早く消える）"""
    n0 = int(start * RATE)
    for i in range(n0, len(buf)):
        t = (i - n0) / RATE
        e = env(t, 0.003, tau)
        if e < 1e-4 and t > 0.01:
            break
        buf[i] += amp * e * (
            math.sin(2 * math.pi * freq * t)
            + 0.22 * math.exp(-t / (tau * 0.35)) * math.sin(2 * math.pi * freq * 2.76 * t)
            + 0.10 * math.exp(-t / (tau * 0.5)) * math.sin(2 * math.pi * freq * 2.0 * t)
        )


def thump(buf, start, f_from, f_to, sweep, amp, tau):
    """低い弾け（高さが f_from から f_to へ sweep 秒で下がる正弦波）"""
    n0 = int(start * RATE)
    phase = 0.0
    k = math.log(f_to / f_from) / sweep
    for i in range(n0, len(buf)):
        t = (i - n0) / RATE
        e = env(t, 0.002, tau)
        if e < 1e-4 and t > 0.01:
            break
        f = f_from * math.exp(k * min(t, sweep))
        phase += 2 * math.pi * f / RATE
        buf[i] += amp * e * math.sin(phase)


def puff(buf, start, amp, tau, seed, low=0.15, high=0.55):
    """空気の抜ける短いノイズ（2つの1次のフィルタで中ほどの高さだけ残す）"""
    n0 = int(start * RATE)
    noise = Noise(seed)
    lp = hp_prev_in = hp_prev_out = 0.0
    for i in range(n0, len(buf)):
        t = (i - n0) / RATE
        e = env(t, 0.001, tau)
        if e < 1e-4 and t > 0.005:
            break
        x = noise.next()
        lp += high * (x - lp)  # 高すぎる音を落とす
        hp = (1 - low) * (hp_prev_out + lp - hp_prev_in)  # 低すぎる音を落とす
        hp_prev_in, hp_prev_out = lp, hp
        buf[i] += amp * e * hp


def finish(buf, peak_db, fade):
    """最後の fade 秒をなめらかに 0 へ、いちばん大きい所を peak_db（dBFS）にそろえる"""
    n = len(buf)
    nf = int(fade * RATE)
    for i in range(n - nf, n):
        x = (n - i) / nf
        buf[i] *= 0.5 - 0.5 * math.cos(math.pi * x)
    peak = max(abs(v) for v in buf) or 1.0
    gain = 10 ** (peak_db / 20) / peak
    return [v * gain for v in buf]


def capsule_open():
    buf = [0.0] * int(0.62 * RATE)
    # ポンッ: 低い弾け（520 → 170 Hz）と、空気の抜ける音
    thump(buf, 0.0, 520, 170, 0.05, 0.75, 0.028)
    puff(buf, 0.0, 0.45, 0.010, seed=20261125)
    # きらっ: 上へ4つ（B5・E6・G#6・B6。ホ長調の和音を上がる）。だんだん小さく
    for k, (at, freq) in enumerate([(0.040, 987.77), (0.090, 1318.51), (0.140, 1661.22), (0.195, 1975.53)]):
        bell(buf, at, freq, 0.30 - 0.025 * k, 0.17)
    return finish(buf, peak_db=-3.0, fade=0.08)


def coin_in():
    buf = [0.0] * int(0.30 * RATE)
    # 入れ口の縁に当たる小さな「こと」と、硬貨の金属の音（倍音が整数倍でない）
    thump(buf, 0.0, 260, 180, 0.02, 0.45, 0.012)
    for at, scale in [(0.0, 1.0), (0.065, 0.55)]:
        for ratio, a, tau in [(1.0, 0.30, 0.070), (1.47, 0.20, 0.055), (2.09, 0.14, 0.040), (2.56, 0.08, 0.030)]:
            bell(buf, at, 2400 * ratio, a * scale, tau)
    return finish(buf, peak_db=-9.0, fade=0.05)


def write_caf(path, samples):
    """CAF（Core Audio Format）を書く: ファイルの頭・desc（形式）・data（音）の3つの塊。数は大きい方から"""
    pcm = b"".join(struct.pack("<h", max(-32768, min(32767, int(round(v * 32767))))) for v in samples)
    head = b"caff" + struct.pack(">HH", 1, 0)
    # 形式: 32 kHz・'lpcm'・小さい方から並ぶ符号付き整数（旗 2）・1枠 2 バイト・1枠 1 標本・1 チャンネル・16 bit
    desc = struct.pack(">d4sIIIII", float(RATE), b"lpcm", 2, 2, 1, 1, 16)
    data = struct.pack(">I", 0) + pcm  # 頭の 4 バイトは編集の回数（0）
    body = b"desc" + struct.pack(">q", len(desc)) + desc + b"data" + struct.pack(">q", len(data)) + data
    with open(path, "wb") as f:
        f.write(head + body)


SOUNDS = {"capsule-open": capsule_open, "coin-in": coin_in}


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    default_out = os.path.join(here, "..", "Sources", "JourneyPhoto", "Resources", "Sounds")
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", default=default_out)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    for name, make in SOUNDS.items():
        samples = make()
        path = os.path.join(args.out, name + ".caf")
        write_caf(path, samples)
        print(f"{os.path.normpath(path)}: {len(samples) / RATE:.3f} 秒, {os.path.getsize(path)} バイト")


if __name__ == "__main__":
    main()
