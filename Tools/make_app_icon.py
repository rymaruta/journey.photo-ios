#!/usr/bin/env python3
"""アプリアイコン（1024x1024 PNG）を作る。

外部ライブラリを使わない（この作業環境に Pillow が無い）。標準ライブラリの
zlib だけで PNG を書く。

**アルファを持たせない。** App Store のアイコンは透明部分を許さない。

差し替えたくなったら、この中の色と形を変えて実行する:

    python3 Tools/make_app_icon.py
"""
import struct
import zlib
from pathlib import Path

SIZE = 1024
OUT = Path(__file__).resolve().parent.parent / \
    "Sources/JourneyPhoto/Assets.xcassets/AppIcon.appiconset/icon-1024.png"


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def peak(u, center, width):
    """`center` を頂点にした三角の山。外に出たら 0。"""
    return max(0.0, 1.0 - abs(u - center) / width)


def build_pixels():
    # 上から下へ、夜明けの空。旅の写真というアプリの中身に合わせる。
    # **起動画面の背景（LaunchBackground）と地続きの色にしてある**
    # ——アイコンから本編への繋がりを切らない
    top = (26, 42, 78)        # 濃紺
    bottom = (242, 156, 102)  # 朝焼け
    sun = (255, 226, 168)
    glow = (250, 198, 140)    # 太陽のまわりのにじみ
    ridge_far = (58, 74, 112)
    ridge_near = (24, 32, 56)
    water = (34, 46, 78)      # 手前の水面（山を映す）

    rows = []
    cx, cy, r = SIZE * 0.5, SIZE * 0.40, SIZE * 0.125
    for y in range(SIZE):
        sky = lerp(top, bottom, y / (SIZE - 1))
        row = bytearray()
        for x in range(SIZE):
            color = sky
            # 太陽のまわりのにじみ（外から内へ、少しずつ寄せる）
            d2 = (x - cx) ** 2 + (y - cy) ** 2
            halo = r * 2.1
            if d2 <= halo * halo:
                t = 1.0 - (d2 ** 0.5) / halo
                color = lerp(color, glow, t * t * 0.55)
            # 太陽
            if d2 <= r * r:
                color = sun
            u = x / SIZE
            # 奥の山（なだらか・左寄り）
            far = SIZE * (0.70 - 0.14 * peak(u, 0.32, 0.42))
            if y >= far:
                color = ridge_far
            # 手前の山（とがって右寄り）。奥より下にあるので上書きしてよい
            near = SIZE * (0.84 - 0.22 * peak(u, 0.66, 0.34))
            if y >= near:
                color = ridge_near
            # いちばん手前は水面。山の形をぼんやり映す
            if y >= SIZE * 0.86:
                mirrored = SIZE * 1.72 - y   # 水際で折り返した高さ
                on_ridge = mirrored >= SIZE * (0.84 - 0.22 * peak(u, 0.66, 0.34))
                color = lerp(water, ridge_near, 0.35) if on_ridge else water
            row += bytes(color)
        rows.append(row)
    return rows


def write_png(path, rows):
    raw = b"".join(b"\x00" + bytes(row) for row in rows)

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))  # 8bit truecolor, no alpha
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


if __name__ == "__main__":
    write_png(OUT, build_pixels())
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")
