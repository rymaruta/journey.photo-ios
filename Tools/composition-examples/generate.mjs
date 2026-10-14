#!/usr/bin/env node
// 構図の作例写真の候補を Gemini API で作る（2026-10-14）。
//
//   GEMINI_API_KEY=… node Tools/composition-examples/generate.mjs            全37種類 × 3枚
//   node Tools/composition-examples/generate.mjs --dry-run                     送る中身だけ表示（キー不要）
//   node Tools/composition-examples/generate.mjs --kind thirds                 1種類だけ
//   node Tools/composition-examples/generate.mjs --kind thirds --only 2        その種類の2枚目だけ
//   … --model gemini-3-pro-image --size 2K --retake 1 --force
//
// **Imagen は使えない。** ai.google.dev の Imagen のページ（2026-10-14 に読んだ）は
// 「Imagen models are shut down. Use Nano Banana for image generation.」。
// だから Nano Banana（Gemini の画像モデル）の Interactions API に送る:
//   POST https://generativelanguage.googleapis.com/v1beta/interactions
//   見出し x-goog-api-key・body { model, input, response_format: { type: "image", mime_type, aspect_ratio, image_size } }
//   返事 steps[] の type "model_output" の content[] の type "image" の data（base64）
// 出典: https://ai.google.dev/gemini-api/docs/image-generation （curl と JavaScript の例）。
// 返事の生の JSON の形は文書に無く、SDK の例（steps → content → data）からの**推測**。
// output_image（SDK の近道）も見るようにしてある。
//
// **キーの値は出さない。** 環境変数から読み、見出しに載せるだけ。表示・ログ・ファイルに書かない。
// 失敗の本文も、キーの文字列が混ざっていたら伏せてから出す。
//
// 追加の npm パッケージは使わない（Node 18 以上の fetch）。

import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/interactions";
const DEFAULT_MODEL = "gemini-nano-banana-2.1";
const MIN_INTERVAL_MS = 6000; // 1件ごとに空ける時間（無料枠・低い段の毎分の上限を見込んで。確かめていない）
const MAX_RETRIES = 5;

export function parseArgs(argv) {
  const opts = { dryRun: false, kind: null, only: null, model: DEFAULT_MODEL, size: null, retake: 0,
                 force: false, out: join(here, "out") };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = () => {
      const v = argv[++i];
      if (v === undefined) throw new Error(`${a} の後に値が要ります`);
      return v;
    };
    if (a === "--dry-run") opts.dryRun = true;
    else if (a === "--kind") opts.kind = next();
    else if (a === "--only") opts.only = Number(next());
    else if (a === "--model") opts.model = next();
    else if (a === "--size") opts.size = next();
    else if (a === "--retake") opts.retake = Number(next());
    else if (a === "--force") opts.force = true;
    else if (a === "--out") opts.out = next();
    else if (a === "-h" || a === "--help") opts.help = true;
    else throw new Error(`知らない引数: ${a}`);
  }
  return opts;
}

export function loadPrompts() {
  return JSON.parse(readFileSync(join(here, "prompts.json"), "utf8"));
}

/// 1枚ぶんの指示文。common → 構図の線と置き場所 → 場面 → 決まり
export function buildPrompt(spec, kind, index, retake = 0) {
  const k = spec.kinds[kind];
  if (!k) throw new Error(`prompts.json に ${kind} が無い`);
  const scene = k.scenes[index % k.scenes.length];
  const parts = [
    spec.common.lead,
    `Scene: ${scene.subject}, in ${scene.where}.`,
    `Composition (exact): ${k.placement}`,
    `For reference, the guide that will be overlaid is: ${k.lines} (x from the left edge, y from the top edge, 0 to 1).`,
    `Light: ${scene.light}. Lens: ${scene.lens}.`,
    ...spec.common.rules,
  ];
  if (retake > 0) {
    const phrases = spec.common.retakePhrases;
    parts.push(phrases[(retake - 1) % phrases.length]);
  }
  return parts.join(" ");
}

export function buildRequest(spec, kind, index, opts) {
  return {
    model: opts.model,
    input: buildPrompt(spec, kind, index, opts.retake),
    response_format: {
      type: "image",
      mime_type: "image/png",
      aspect_ratio: spec.aspectRatio,
      image_size: opts.size ?? spec.imageSize,
    },
  };
}

/// 返事から最初の画像（base64 と種類）。見つからなければ null
export function extractImage(body) {
  if (body?.output_image?.data) return { data: body.output_image.data, mime: body.output_image.mime_type };
  for (const step of body?.steps ?? []) {
    if (step?.type !== "model_output") continue;
    for (const block of step.content ?? []) {
      if (block?.type === "image" && block.data) return { data: block.data, mime: block.mime_type };
    }
  }
  return null;
}

/// キーの文字列を伏せる（失敗の本文に混ざっても出さない）
export function redact(text, key) {
  let t = String(text);
  if (key) t = t.split(key).join("[REDACTED]");
  return t.replace(/AIza[0-9A-Za-z_-]{20,}/g, "[REDACTED]");
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function extFor(mime) {
  if (mime === "image/jpeg") return "jpg";
  if (mime === "image/webp") return "webp";
  return "png";
}

async function send(request, key) {
  let wait = 10000;
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: { "x-goog-api-key": key, "Content-Type": "application/json" },
      body: JSON.stringify(request),
    });
    if (res.ok) return res.json();
    const text = redact(await res.text(), key).slice(0, 600);
    const retryable = res.status === 429 || res.status === 500 || res.status === 503;
    if (!retryable || attempt >= MAX_RETRIES) throw new Error(`HTTP ${res.status}: ${text}`);
    const after = Number(res.headers.get("retry-after"));
    const ms = Number.isFinite(after) && after > 0 ? after * 1000 : wait;
    console.log(`   ${res.status} — ${Math.round(ms / 1000)} 秒待ってやり直す（${attempt + 1}/${MAX_RETRIES}）`);
    await sleep(ms);
    wait = Math.min(wait * 2, 120000);
  }
}

function usage() {
  console.log(`使い方: node Tools/composition-examples/generate.mjs [--dry-run] [--kind <rawValue>] [--only <1..3>]
        [--model ${DEFAULT_MODEL}] [--size 1K|2K|4K] [--retake <n>] [--force] [--out <dir>]
  鍵は環境変数 GEMINI_API_KEY から読む（値は表示しない）。保存先は out/<kind>/<n>.png`);
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) return usage();
  const spec = loadPrompts();
  const kinds = opts.kind ? [opts.kind] : Object.keys(spec.kinds);
  for (const k of kinds) if (!spec.kinds[k]) throw new Error(`prompts.json に ${k} が無い`);
  const count = spec.candidates;
  const jobs = [];
  for (const kind of kinds) {
    for (let n = 1; n <= count; n++) {
      if (opts.only && opts.only !== n) continue;
      jobs.push({ kind, n, request: buildRequest(spec, kind, n - 1, opts) });
    }
  }

  if (opts.dryRun) {
    console.log(`POST ${ENDPOINT}`);
    console.log(`見出し: x-goog-api-key: <GEMINI_API_KEY・表示しない>, Content-Type: application/json`);
    console.log(`件数: ${jobs.length}（${kinds.length} 種類 × 最大 ${count} 枚）`);
    for (const j of jobs) {
      console.log(`\n--- ${j.kind} / ${j.n} → ${join(opts.out, j.kind, `${j.n}.png`)}`);
      console.log(JSON.stringify(j.request, null, 2));
    }
    return;
  }

  const key = process.env.GEMINI_API_KEY;
  if (!key) {
    console.error("GEMINI_API_KEY がありません。環境変数に入れてから流してください（--dry-run なら不要）。");
    process.exit(2);
  }

  let made = 0, skipped = 0, failed = 0;
  for (const [i, j] of jobs.entries()) {
    const dir = join(opts.out, j.kind);
    const existing = ["png", "jpg", "webp"].map((e) => join(dir, `${j.n}.${e}`)).find(existsSync);
    if (existing && !opts.force) {
      skipped++;
      continue;
    }
    console.log(`[${i + 1}/${jobs.length}] ${j.kind} / ${j.n}`);
    const started = Date.now();
    try {
      const body = await send(j.request, key);
      const image = extractImage(body);
      if (!image) throw new Error("返事に画像が無い（安全のため止められた可能性。言い回しを変えるか --retake）");
      mkdirSync(dir, { recursive: true });
      const file = join(dir, `${j.n}.${extFor(image.mime)}`);
      writeFileSync(file, Buffer.from(image.data, "base64"));
      // 作り方の控え（キーは入れない）
      writeFileSync(join(dir, `${j.n}.json`), JSON.stringify({ ...j.request, createdAt: new Date().toISOString() }, null, 2));
      console.log(`   保存: ${file}`);
      made++;
    } catch (e) {
      failed++;
      console.error(`   失敗: ${redact(e.message, key)}`);
    }
    const rest = MIN_INTERVAL_MS - (Date.now() - started);
    if (rest > 0 && i < jobs.length - 1) await sleep(rest);
  }
  console.log(`\n作った ${made}・既にあって飛ばした ${skipped}・失敗 ${failed}`);
  if (failed > 0) process.exitCode = 1;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main().catch((e) => {
    console.error(redact(e.message, process.env.GEMINI_API_KEY));
    process.exit(1);
  });
}
