#!/usr/bin/env node
// 目で見て選んだ候補1枚を、アプリの絵の入れ物へ入れる（2026-10-14）。
//
//   node Tools/composition-examples/install.mjs --kind triangle --pick 2 --note "3本の木の中心が三角の頂点に乗る"
//   node Tools/composition-examples/install.mjs --kind triangle --pick 2 --note "…" --dry-run
//   node Tools/composition-examples/install.mjs --recompress-all      入っている作例を同じ寸法のまま目安まで縮める
//
// やること:
//   1. out/<kind>/<pick>.(png|jpg|webp) を真ん中で縦 3:4 に切り、864×1152 に縮める（**引き伸ばさない**:
//      切った後の短い辺が 864 に届かなければ止める）
//   2. JPEG（基本形・色の情報は 4:2:0・メタデータは捨てる）。画質 82 から下げて、1枚 BUDGET_BYTES 以下に
//   3. Sources/JourneyPhoto/Assets.xcassets/composition-ai-<kind>.imageset/ に jpg と Contents.json
//   4. docs/composition-ai-review.json の accepted に載せ、held から外す（CompositionAIExampleTests が突き合わせる）
//
// 画像を扱う道具は ImageMagick（magick / convert）か、Mac の sips。どちらも無ければ止める。
// 追加の npm パッケージは使わない。

import { readFileSync, writeFileSync, mkdirSync, existsSync, statSync, readdirSync, copyFileSync, rmSync, mkdtempSync } from "node:fs";
import { dirname, join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..");
const ASSETS = join(root, "Sources/JourneyPhoto/Assets.xcassets");
const LEDGER = join(root, "docs/composition-ai-review.json");
export const WIDTH = 864;
export const HEIGHT = 1152;
/// 1枚の目安（37枚で約 9 MB）。届かなければ画質 64 で止めて知らせる
export const BUDGET_BYTES = 250 * 1024;
const QUALITIES = [82, 78, 74, 70, 67, 64];

/// PNG・JPEG の寸法（ヘッダーだけ読む）
export function imageSize(buf) {
  if (buf.length > 24 && buf.readUInt32BE(0) === 0x89504e47) {
    return { width: buf.readUInt32BE(16), height: buf.readUInt32BE(20) };
  }
  if (buf.length > 4 && buf[0] === 0xff && buf[1] === 0xd8) {
    let i = 2;
    while (i + 9 < buf.length) {
      if (buf[i] !== 0xff) { i++; continue; }
      const m = buf[i + 1];
      if (m === 0xc0 || m === 0xc1 || m === 0xc2) {
        return { height: buf.readUInt16BE(i + 5), width: buf.readUInt16BE(i + 7) };
      }
      const len = buf.readUInt16BE(i + 2);
      if (len < 2) return null;
      i += 2 + len;
    }
  }
  return null;
}

/// 真ん中で縦 3:4 に切る範囲
export function centerCrop34(width, height) {
  const target = 3 / 4;
  if (width / height > target) {
    const w = Math.round(height * target);
    return { x: Math.floor((width - w) / 2), y: 0, width: w, height };
  }
  const h = Math.round(width / target);
  return { x: 0, y: Math.floor((height - h) / 2), width, height: h };
}

function which(cmd) {
  try {
    execFileSync("sh", ["-c", `command -v ${cmd}`], { stdio: "pipe" });
    return true;
  } catch {
    return false;
  }
}

function tool() {
  if (which("magick")) return { kind: "im", bin: "magick" };
  if (which("convert")) return { kind: "im", bin: "convert" };
  if (which("sips")) return { kind: "sips", bin: "sips" };
  throw new Error("ImageMagick（magick / convert）か sips が要ります");
}

/// 切って縮めて JPEG にする。crop が null なら寸法そのまま（作り直しだけ）
function encode(t, src, dst, crop, quality, work) {
  if (t.kind === "im") {
    const args = [src];
    if (crop) args.push("-crop", `${crop.width}x${crop.height}+${crop.x}+${crop.y}`, "+repage",
                        "-resize", `${WIDTH}x${HEIGHT}!`);
    args.push("-strip", "-colorspace", "sRGB", "-sampling-factor", "4:2:0", "-interlace", "none",
              "-quality", String(quality), dst);
    execFileSync(t.bin, args, { stdio: "pipe" });
    return;
  }
  // sips: -c は真ん中で切る（高さ 幅の順）
  let from = src;
  if (crop) {
    const cut = join(work, "cut.png");
    execFileSync("sips", ["-c", String(crop.height), String(crop.width), src, "--out", cut], { stdio: "pipe" });
    execFileSync("sips", ["-z", String(HEIGHT), String(WIDTH), cut, "--out", cut], { stdio: "pipe" });
    from = cut;
  }
  execFileSync("sips", ["-s", "format", "jpeg", "-s", "formatOptions", String(quality), from, "--out", dst],
               { stdio: "pipe" });
}

/// 目安に収まるまで画質を下げる。返すのは使った画質と大きさ
function encodeWithinBudget(t, src, dst, crop, work) {
  for (const q of QUALITIES) {
    encode(t, src, dst, crop, q, work);
    const bytes = statSync(dst).size;
    if (bytes <= BUDGET_BYTES) return { quality: q, bytes };
  }
  return { quality: QUALITIES.at(-1), bytes: statSync(dst).size, overBudget: true };
}

function contentsJSON(kind) {
  return JSON.stringify({
    images: [{ filename: `composition-ai-${kind}.jpg`, idiom: "universal" }],
    info: { author: "xcode", version: 1 },
  }, null, 2) + "\n";
}

export function parseArgs(argv) {
  const o = { kind: null, pick: null, note: null, dryRun: false, recompressAll: false, out: join(here, "out") };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = () => {
      const v = argv[++i];
      if (v === undefined) throw new Error(`${a} の後に値が要ります`);
      return v;
    };
    if (a === "--kind") o.kind = next();
    else if (a === "--pick") o.pick = Number(next());
    else if (a === "--note") o.note = next();
    else if (a === "--dry-run") o.dryRun = true;
    else if (a === "--recompress-all") o.recompressAll = true;
    else if (a === "--out") o.out = next();
    else throw new Error(`知らない引数: ${a}`);
  }
  return o;
}

function install(o) {
  const spec = JSON.parse(readFileSync(join(here, "prompts.json"), "utf8"));
  if (!o.kind || !spec.kinds[o.kind]) throw new Error(`--kind に CompositionKind の rawValue を（prompts.json にあるもの）`);
  if (!Number.isInteger(o.pick) || o.pick < 1) throw new Error("--pick に候補の番号（1〜）");
  if (!o.note) throw new Error("--note に、目で見て確かめたこと（線のどこに何が乗るか）を書く");
  const src = ["png", "jpg", "webp"].map((e) => join(o.out, o.kind, `${o.pick}.${e}`)).find(existsSync);
  if (!src) throw new Error(`候補がありません: ${join(o.out, o.kind, `${o.pick}.png`)}`);
  const size = imageSize(readFileSync(src));
  if (!size) throw new Error(`寸法が読めない（PNG か JPEG にしてください）: ${src}`);
  const crop = centerCrop34(size.width, size.height);
  if (crop.width < WIDTH || crop.height < HEIGHT) {
    throw new Error(`切った後が ${crop.width}×${crop.height}。${WIDTH}×${HEIGHT} より小さいので引き伸ばさずに止める（--size 2K で作り直す）`);
  }
  let meta = {};
  const metaFile = join(o.out, o.kind, `${o.pick}.json`);
  if (existsSync(metaFile)) meta = JSON.parse(readFileSync(metaFile, "utf8"));

  const set = join(ASSETS, `composition-ai-${o.kind}.imageset`);
  const dst = join(set, `composition-ai-${o.kind}.jpg`);
  console.log(`${src}（${size.width}×${size.height}）→ 切る ${crop.width}×${crop.height}+${crop.x}+${crop.y} → ${WIDTH}×${HEIGHT} JPEG`);
  console.log(`置き場所: ${dst}`);
  if (o.dryRun) return;

  const t = tool();
  const work = mkdtempSync(join(tmpdir(), "composition-"));
  try {
    const tmp = join(work, "out.jpg");
    const r = encodeWithinBudget(t, src, tmp, crop, work);
    const check = imageSize(readFileSync(tmp));
    if (!check || check.width !== WIDTH || check.height !== HEIGHT) throw new Error(`できた寸法が違う: ${JSON.stringify(check)}`);
    mkdirSync(set, { recursive: true });
    copyFileSync(tmp, dst);
    writeFileSync(join(set, "Contents.json"), contentsJSON(o.kind));
    console.log(`画質 ${r.quality}・${Math.round(r.bytes / 1024)} KB${r.overBudget ? `（目安 ${BUDGET_BYTES / 1024} KB を超えた）` : ""}`);
  } finally {
    rmSync(work, { recursive: true, force: true });
  }

  const ledger = JSON.parse(readFileSync(LEDGER, "utf8"));
  ledger.accepted[o.kind] = {
    source: "individual",
    width: WIDTH,
    height: HEIGHT,
    checked: new Date().toISOString().slice(0, 10),
    note: o.note,
    generator: { model: meta.model ?? "unknown", candidate: o.pick },
  };
  delete ledger.held[o.kind];
  writeFileSync(LEDGER, JSON.stringify(ledger, null, 2) + "\n");
  const count = Object.keys(ledger.accepted).length;
  console.log(`台帳に載せた（${count} 種類）: ${LEDGER}`);
  if (count >= 37) {
    console.log("37種類そろった。CompositionAIExampleTests の「37 未満」の見張りを、全部を目で確かめた上で外す。");
  }
}

function recompressAll() {
  const t = tool();
  const work = mkdtempSync(join(tmpdir(), "composition-"));
  let before = 0, after = 0;
  try {
    for (const name of readdirSync(ASSETS).filter((n) => n.startsWith("composition-ai-") && n.endsWith(".imageset"))) {
      const kind = name.slice("composition-ai-".length, -".imageset".length);
      const file = join(ASSETS, name, `composition-ai-${kind}.jpg`);
      if (!existsSync(file)) continue;
      const bytes = statSync(file).size;
      before += bytes;
      if (bytes <= BUDGET_BYTES) { after += bytes; continue; }
      const tmp = join(work, `${kind}.jpg`);
      const r = encodeWithinBudget(t, file, tmp, null, work);
      if (r.bytes < bytes) { copyFileSync(tmp, file); after += r.bytes; } else { after += bytes; }
      console.log(`${kind}: ${Math.round(bytes / 1024)} → ${Math.round(Math.min(r.bytes, bytes) / 1024)} KB（画質 ${r.quality}）`);
    }
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
  console.log(`合計 ${(before / 1048576).toFixed(1)} MB → ${(after / 1048576).toFixed(1)} MB`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  try {
    const o = parseArgs(process.argv.slice(2));
    if (o.recompressAll) recompressAll();
    else install(o);
  } catch (e) {
    console.error(e.message);
    process.exit(1);
  }
}
