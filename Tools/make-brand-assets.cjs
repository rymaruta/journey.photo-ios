#!/usr/bin/env node
/**
 * **アプリのブランド素材を、サイトと同じ1枚の元絵から作る。**
 *
 *   NODE_PATH=../photo-gallery/node_modules \
 *     node Tools/make-brand-assets.cjs [元絵のPNG]
 *   （既定: ../photo-gallery/scripts/icon-source/aperture.png）
 *
 * 出す先（すべて上書き）:
 *   Assets.xcassets/AppIcon.appiconset/icon-1024.png   ホーム画面・App Store のアイコン
 *   Assets.xcassets/BrandMark.imageset/brand-mark*.png  見出しのマーク（32/64/96px・テンプレート）
 *
 * **サイトと同じ計算にしてある**（`photo-gallery/scripts/generate-icons.mjs`）:
 *   - アイコン: 黒地に白いアパーチャ・**枠なし**（owner の判断 2026-09-20）。
 *     サイトは 512 に絵 340px（66.4%）。ここは 1024 に 680px
 *   - マーク: **明るさをそのまま透明度にする**（形は1画素も変えない。しきい値で
 *     切ると縁がギザギザになる——`photo-gallery/app/layout.tsx` の記録）。
 *     構図は元絵を丸ごと縮める（サイトの `logo-aperture.png` と同じ余白 17%）
 *
 * **絵は描き直さない。** 元絵は owner の PNG。ここは切り出しと縮小だけ。
 *
 * `sharp` はこのリポジトリの依存に無い（Swift のリポジトリなので package.json を
 * 持たない）。photo-gallery が既に持っているものを `NODE_PATH` で借りる。
 *
 * 以前は `Tools/make_app_icon.py` が夕日と山のアイコンを**描いて**いた。
 * サイトがアパーチャに揃えたので置き換えた——残すと、走らせた瞬間に
 * 古い絵へ戻る。
 */
const path = require("node:path");
const fs = require("node:fs");
let sharp;
try { sharp = require("sharp"); } catch {
    console.error("sharp が見つかりません。photo-gallery で npm ci してから、NODE_PATH=<photo-gallery>/node_modules を付けて実行してください");
    process.exit(1);
}

const root = path.resolve(__dirname, "..");
const assets = path.join(root, "Sources/JourneyPhoto/Assets.xcassets");
const src = path.resolve(process.argv[2] ?? path.join(root, "../photo-gallery/scripts/icon-source/aperture.png"));
if (!fs.existsSync(src)) {
    console.error(`元絵がありません: ${src}`);
    process.exit(1);
}

/** 元絵の白い部分の外接矩形（generate-icons.mjs の whiteBBox と同じ） */
async function whiteBBox(file) {
    const { data, info } = await sharp(file).raw().toBuffer({ resolveWithObject: true });
    let minx = info.width, miny = info.height, maxx = -1, maxy = -1;
    for (let y = 0; y < info.height; y++) {
        for (let x = 0; x < info.width; x++) {
            if (data[(y * info.width + x) * info.channels] > 128) {
                if (x < minx) minx = x; if (x > maxx) maxx = x;
                if (y < miny) miny = y; if (y > maxy) maxy = y;
            }
        }
    }
    if (maxx < 0) throw new Error("元絵に白い部分が無い");
    return { left: minx, top: miny, width: maxx - minx + 1, height: maxy - miny + 1 };
}

/** 絵を正方形に切り出して size px に（generate-icons.mjs の artwork と同じ） */
async function artwork(size) {
    const b = await whiteBBox(src);
    const side = Math.max(b.width, b.height);
    const meta = await sharp(src).metadata();
    const left = Math.max(0, Math.min(meta.width - side, b.left - Math.floor((side - b.width) / 2)));
    const top = Math.max(0, Math.min(meta.height - side, b.top - Math.floor((side - b.height) / 2)));
    return sharp(src).extract({ left, top, width: side, height: side })
        .resize(size, size, { fit: "contain", background: "#000" }).png().toBuffer();
}

(async () => {
    // ── アプリアイコン（1024・透明なし）──
    const art = await artwork(680);
    const iconPath = path.join(assets, "AppIcon.appiconset/icon-1024.png");
    await sharp({ create: { width: 1024, height: 1024, channels: 3, background: "#000" } })
        .composite([{ input: art, gravity: "centre" }])
        .removeAlpha()                 // App Store のアイコンは透明を持てない（ITMS で弾かれる）
        .png({ compressionLevel: 9 }).toFile(iconPath);

    // ── 見出しのマーク（白＋明るさ＝透明度）──
    const { data, info } = await sharp(src).greyscale().raw().toBuffer({ resolveWithObject: true });
    const rgba = Buffer.alloc(info.width * info.height * 4);
    for (let i = 0; i < info.width * info.height; i++) {
        rgba[i * 4] = 255; rgba[i * 4 + 1] = 255; rgba[i * 4 + 2] = 255; rgba[i * 4 + 3] = data[i];
    }
    const base = sharp(rgba, { raw: { width: info.width, height: info.height, channels: 4 } });
    const markDir = path.join(assets, "BrandMark.imageset");
    for (const [suffix, px] of [["", 32], ["@2x", 64], ["@3x", 96]]) {
        await base.clone().resize(px, px, { kernel: "lanczos3" }).png({ compressionLevel: 9 })
            .toFile(path.join(markDir, `brand-mark${suffix}.png`));
    }
    console.log("[brand] wrote AppIcon/icon-1024.png, BrandMark 32/64/96 from", path.relative(root, src));
})().catch((e) => { console.error(e); process.exit(1); });
