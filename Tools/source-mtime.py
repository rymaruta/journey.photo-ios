#!/usr/bin/env python3
"""ソースの時刻を中身から決める（2026-11-11・毎回のを速くする (b)）。

    python3 Tools/source-mtime.py            # git が持つファイルとフォルダの時刻を、中身の印（blob・tree の id）から決める

Xcode（swift-driver・組む仕組み）は、前に組んだときのファイルの時刻と今の時刻が**同じ**なら組み直さない。
チェックアウトしたばかりのファイルは全部「今」の時刻になるので、控え（DerivedData）に前の組みが残っていても
アプリとテストの 1,000 ファイルあまりを毎回組み直していた（run 42955376909: 組む 11.2 分）。

時刻を「中身の印から決まる値」にすれば、中身が同じファイルは控えを書いた回と同じ時刻になり、組み直さない。
中身を変えたファイルは別の時刻になり、組み直す（同じ時刻になるのは印が 2^30 で割った余りまで一致したときだけ）。
控えを書く回（xcode-cache-warm.yml）と読む回（毎回の・ガチガチの）の両方で、組む前に流す。
"""
import os
import subprocess
import sys

BASE = 631152000  # 1990-01-01。ここから 2^30 秒（約 34 年）の幅に散らす
SPAN = 1 << 30


def stamp(object_id):
    return BASE + int(object_id[:16], 16) % SPAN


def main():
    root = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True,
                          check=True).stdout.strip()
    os.chdir(root)
    files = dirs = 0
    # 🔴 **印は作業の木の中身から取る。** `ls-files -s` の印は index（コミットした中身）のもので、手で書き換えた
    # ファイル（まだ add していない）に古い印の時刻を付けると、Xcode が「変わっていない」と読んで組み直さない
    # （2026-11-11 の測る回 run 42989273825 で、書き換えたファイルを 0 件しか組まなかった）。
    # CI のチェックアウト直後は index と同じだが、違うファイルは `git hash-object` で今の中身から取り直す
    dirty = {p for p in subprocess.run(["git", "diff", "--name-only", "-z"], capture_output=True,
                                        check=True).stdout.split(b"\0") if p}
    listed = subprocess.run(["git", "ls-files", "-s", "-z"], capture_output=True, check=True).stdout
    for entry in listed.split(b"\0"):
        if not entry:
            continue
        meta, path = entry.split(b"\t", 1)
        mode, object_id, _ = meta.decode().split(" ")
        if mode == "120000" or mode == "160000":  # シンボリックリンク・サブモジュールは触らない
            continue
        if path in dirty and os.path.isfile(path):
            object_id = subprocess.run(["git", "hash-object", "--", path], capture_output=True, text=True,
                                       check=True).stdout.strip()
        t = stamp(object_id)
        try:
            os.utime(path, ns=(t * 10**9, t * 10**9))
            files += 1
        except FileNotFoundError:
            pass
    trees = subprocess.run(["git", "ls-tree", "-d", "-r", "-z", "HEAD"], capture_output=True, check=True).stdout
    for entry in trees.split(b"\0"):
        if not entry:
            continue
        meta, path = entry.split(b"\t", 1)
        t = stamp(meta.decode().split(" ")[2])
        if os.path.isdir(path):
            os.utime(path, ns=(t * 10**9, t * 10**9))
            dirs += 1
    print(f"ソースの時刻を中身から決めました: ファイル {files}（index と違う {len(dirty)}）・フォルダ {dirs}"
          "（フォルダは HEAD の木の印。手で足した・消したファイルがあるフォルダは CI では起きない）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
