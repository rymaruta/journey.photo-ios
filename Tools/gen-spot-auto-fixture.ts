// iOS の試験の答え（journey.photo-ios#425・2026-10-31）。Web の決まり（photo-gallery の
// lib/utils/spotAutoLink.ts）で答えを出し、索引と一緒に JSON に書く。iOS の Swift の写し（`SpotMatcher`）が
// この答えと一致することを `SpotAutoLinkTests` が確かめる。
//
// 使い方（photo-gallery の作業ツリーで。Web の決まり・台帳を直したら作り直す）:
//   cp <journey.photo-ios>/Tools/gen-spot-auto-fixture.ts scripts/
//   npx tsx scripts/gen-spot-auto-fixture.ts <journey.photo-ios>/Tests/Fixtures/spot-auto-link.json
//   rm scripts/gen-spot-auto-fixture.ts
// 作り直して件数が変わったら `SpotAutoLinkTests` の件数も直す（例が消えたことに気づくため）
import { writeFileSync } from "node:fs";
import { execSync } from "node:child_process";
import type { Spot } from "../lib/data/spots";
import { SPOTS } from "../lib/data/spots";
import { SUMMARY_MIN } from "../lib/utils/spotGuide";
import { buildSpotMatchIndex, spotMatcher, type AutoLinkPhoto } from "../lib/utils/spotAutoLink";
import PROD48 from "../lib/utils/__tests__/spotAutoLink.prod48.json";

type Case = { note: string; photo: AutoLinkPhoto };

function texts(v: unknown): string[] {
    if (typeof v === "string") return [v];
    if (Array.isArray(v)) return v.flatMap(texts);
    if (v && typeof v === "object") return Object.values(v as Record<string, unknown>).flatMap(texts);
    return [];
}

function spot(id: number, over: Partial<Spot> = {}): Spot {
    return {
        spotId: `sp_${String(id).padStart(12, "0")}`,
        slug: `spot-${id}`,
        name: `撮影スポット${id}`,
        summary: "あ".repeat(SUMMARY_MIN),
        region: { country: "日本", prefecture: "宮城県", city: "白石市" },
        coords: { lat: 38.02, lng: 140.55 },
        highlights: ["見どころ"],
        officialWebsiteUrl: "https://example.example/",
        status: "published",
        verifiedBy: "運営",
        verifiedAt: "2026-10-31",
        createdAt: "2026-10-31T00:00:00.000Z",
        updatedAt: "2026-10-31T00:00:00.000Z",
        ...over,
    } as Spot;
}

function group(name: string, spots: Spot[], cases: Case[]) {
    const index = buildSpotMatchIndex(spots);
    const matcher = spotMatcher(JSON.parse(JSON.stringify(index)));
    return {
        name,
        index,
        cases: cases.map(({ note, photo }) => ({
            note,
            location: photo.location ?? null,
            texts: [...texts(photo.title), ...texts(photo.description)],
            coords: photo.coords ?? null,
            geoApprox: !!photo.geoApprox,
            // 写真の形のまま（題・説明が言語ごとの形の例も）。iOS は `Photo` に読んでから突き合わせる
            photo: { title: photo.title ?? null, description: photo.description ?? null },
            expect: matcher.match(photo),
        })),
    };
}

const real: Case[] = [
    ...(PROD48 as AutoLinkPhoto[]).map((p) => ({ note: `本番48枚 ${p.id}`, photo: p })),
    { note: "撮影地「リスボン, ポルトガル」→ ポルトに結ばない", photo: { title: "ポルトガルの夕日", location: "リスボン, ポルトガル", coords: { lat: 38.72, lng: -9.14 } } },
    { note: "撮影地「日本」・札幌の位置・題「東京タワー」", photo: { title: "東京タワー", location: "日本", coords: { lat: 43.06, lng: 141.35 } } },
    { note: "撮影地「日本」・東京タワーの近く", photo: { title: "東京タワー", location: "日本", coords: { lat: 35.66, lng: 139.75 } } },
    { note: "スマホカバー", photo: { title: "スマホカバーを新しくした" } },
    { note: "ポルトガル旅行", photo: { title: "ポルトガル旅行" } },
    { note: "ニューヨーク市", photo: { location: "ニューヨーク市, アメリカ合衆国" } },
    { note: "New York", photo: { location: "New York, NY, USA" } },
    { note: "Porto Alegre", photo: { location: "Porto Alegre, Brasil" } },
    { note: "Toledo Ohio", photo: { location: "Toledo, Ohio, USA" } },
    { note: "札幌市・補った位置・東京タワーより高い", photo: { title: "東京タワーより高い", location: "札幌市", coords: { lat: 43.06, lng: 141.35 }, geoApprox: true } },
    { note: "川崎市・補った位置・東京タワーが見えた", photo: { title: "東京タワーが見えた", location: "川崎市", coords: { lat: 35.53, lng: 139.7 }, geoApprox: true } },
    { note: "撮影地 東京タワー・補った位置 50km", photo: { location: "東京タワー", coords: { lat: 35.53, lng: 139.7 }, geoApprox: true } },
    { note: "リヨン・補った位置・ヴァンドーム広場を思い出す", photo: { title: "ヴァンドーム広場を思い出す", location: "リヨン, フランス", coords: { lat: 45.76, lng: 4.84 }, geoApprox: true } },
    { note: "ヨーク, イギリス", photo: { location: "ヨーク, イギリス" } },
    { note: "ポルト, ポルトガル", photo: { location: "ポルト, ポルトガル" } },
    { note: "パリの代表点・ヴァンドーム広場", photo: { title: "ヴァンドーム広場", location: "パリ", coords: { lat: 48.86, lng: 2.32 }, geoApprox: true } },
    { note: "蔵王キツネ村（撮影地）", photo: { location: "蔵王キツネ村, 南蔵王七ヶ宿線, 白石市, 宮城県, 日本", coords: { lat: 38.0, lng: 140.56 } } },
    { note: "蔵王キツネ村（題・位置なし）", photo: { title: "蔵王キツネ村" } },
    { note: "蔵王キツネ村（題・山形県）", photo: { title: "蔵王キツネ村", location: "山形県" } },
    { note: "全角・半角の揺れ（ＴＯＫＹＯ ＴＯＷＥＲ）", photo: { location: "ＴＯＫＹＯ　ＴＯＷＥＲ, 港区" } },
    { note: "絵文字と結合文字", photo: { title: "東京タワー🗼✨", description: "カフェ́で" } },
    { note: "空の写真", photo: {} },
    { note: "題が言語ごと", photo: { title: { ja: "夢の中", en: "In a dream" }, description: { ja: ["蔵王キツネ村での一枚"] } } },
    // 言語ごとの値の境目をまたぐ一致（ja → en の順・Web の写真の行に多い並び）。iOS は ja・en・ほかの順に並べる
    { note: "言語ごとの境目をまたぐ（ja → en）", photo: { title: { ja: "東京", en: "タワー" } } },
    { note: "説明の段落の境目をまたぐ", photo: { description: { ja: ["東京", "タワーの下で"] } } },
];

const FOX = spot(1, { name: "蔵王キツネ村", aliases: ["宮城蔵王キツネ村", "白石市", "リアス海岸"] });
const north = (km: number) => ({ lat: 38.02 + km / 111.195, lng: 140.55 });
const york = spot(12, { name: "ヨーク", region: { country: "イギリス", city: "ヨーク" }, coords: { lat: 53.96, lng: -1.08 } });
const garnier = spot(2, { name: "オペラ・ガルニエ（パレ・ガルニエ）", region: { country: "フランス", city: "パリ" }, coords: { lat: 48.87, lng: 2.33 } });
const short = spot(3, { name: "大山" });
const vendome = spot(4, { name: "ヴァンドーム広場", region: { country: "フランス", city: "パリ" }, coords: { lat: 48.87, lng: 2.33 } });
const vendome13 = spot(13, { name: "ヴァンドーム広場", aliases: ["Place Vendome"], region: { country: "フランス", city: "パリ" }, coords: { lat: 48.87, lng: 2.33 } });
const bikan = spot(14, { name: "倉敷美観地区", aliases: ["Bikan"], region: { country: "日本", prefecture: "岡山県", city: "倉敷市" }, coords: { lat: 34.6, lng: 133.77 } });
const cover = spot(9, { name: "カバー", region: { country: "日本", prefecture: "東京都" }, coords: { lat: 35.68, lng: 139.76 } });
const porto = spot(10, { name: "ポルト", region: { country: "ポルトガル", city: "ポルト" }, coords: { lat: 41.15, lng: -8.61 } });
const ginza = spot(11, { name: "銀座の通り", aliases: ["ギンザ"], region: { country: "日本", prefecture: "東京都" }, coords: { lat: 35.67, lng: 139.77 } });
const other = spot(5, { name: "白石城" });
const hachimanA = spot(6, { name: "八幡神社" });
const hachimanB = spot(7, { name: "八幡神社", region: { country: "日本", prefecture: "京都府" }, coords: { lat: 35.0, lng: 135.7 } });
const aliasThief = spot(8, { name: "別の神社", aliases: ["蔵王キツネ村"] });

const out = {
    from: `photo-gallery ${execSync("git rev-parse --short HEAD").toString().trim()} lib/utils/spotAutoLink.ts（scripts/gen-spot-auto-fixture.ts で生成）`,
    groups: [
        group("本物の台帳（content/spots.json）", SPOTS, real),
        group("ヨーク", [york], [
            { note: "ニューヨーク・NY の位置", photo: { title: "ニューヨークの夜", location: "ニューヨーク", coords: { lat: 40.71, lng: -74.01 } } },
        ]),
        group("蔵王キツネ村", [FOX], [
            { note: "撮影地に正式名", photo: { location: "蔵王キツネ村, 白石市" } },
            { note: "題に正式名", photo: { title: "蔵王キツネ村で" } },
            { note: "説明に正式名", photo: { title: { ja: "夢の中" }, description: { ja: ["蔵王キツネ村での一枚"] } } },
            { note: "別名を撮影地に", photo: { location: "宮城蔵王キツネ村" } },
            { note: "別名を題に（当てない）", photo: { title: "リアス海岸" } },
            { note: "別名リアス海岸を撮影地に", photo: { location: "リアス海岸" } },
            { note: "地名だけの別名", photo: { location: "白石市, 宮城県" } },
            { note: "4.9km", photo: { title: "蔵王キツネ村", coords: north(4.9) } },
            { note: "5.5km", photo: { title: "蔵王キツネ村", coords: north(5.5) } },
            { note: "補った位置・山形県", photo: { title: "蔵王キツネ村", location: "山形県", coords: { lat: 38.02, lng: 140.55 }, geoApprox: true } },
            { note: "宮城県", photo: { title: "蔵王キツネ村", location: "宮城県" } },
            { note: "山形県", photo: { title: "蔵王キツネ村", location: "山形県" } },
            { note: "位置も撮影地も無い", photo: { title: "蔵王キツネ村" } },
        ]),
        group("括弧と短い名前", [garnier, short], [
            { note: "括弧の中を除く", photo: { location: "オペラ・ガルニエ（パリ）" } },
            { note: "3字未満", photo: { title: "大山の夕景" } },
        ]),
        group("ヴァンドーム広場", [vendome], [
            { note: "代表点 1km", photo: { title: "ヴァンドーム広場", location: "パリ", coords: { lat: 48.86, lng: 2.32 }, geoApprox: true } },
            { note: "代表点 20km・題だけ", photo: { title: "ヴァンドーム広場", location: "パリ", coords: { lat: 49.05, lng: 2.33 }, geoApprox: true } },
            { note: "代表点 20km・撮影地に名前", photo: { location: "ヴァンドーム広場, パリ", coords: { lat: 49.05, lng: 2.33 }, geoApprox: true } },
            { note: "本物の位置 20km", photo: { title: "ヴァンドーム広場", location: "パリ", coords: { lat: 49.05, lng: 2.33 } } },
            { note: "本物の位置 20km・ホテル前", photo: { title: "ヴァンドーム広場", location: "ホテル前", coords: { lat: 49.05, lng: 2.33 } } },
        ]),
        group("語の切れ目", [vendome13], [
            { note: "中黒の後ろ", photo: { title: "パリ・ヴァンドーム広場にて" } },
            { note: "ô は別の字", photo: { location: "Place Vendôme, Paris" } },
            { note: "英字の別名", photo: { location: "Place Vendome, Paris" } },
            { note: "英字の続き", photo: { location: "Place Vendomex, Paris" } },
            { note: "カタカナの続き", photo: { title: "ニューヴァンドーム広場" } },
            { note: "大文字・小文字", photo: { location: "PLACE VENDOME" } },
        ]),
        group("英字の短い別名", [bikan], [
            { note: "語の切れ目だけでは当てない", photo: { location: "Bikan Street Cafe, Tokyo" } },
            { note: "撮影地の1項目そのもの", photo: { location: "Bikan, Kurashiki" } },
        ]),
        group("短いカタカナ", [cover, porto, ginza], [
            { note: "スマホカバー", photo: { title: "スマホカバーを新しくした" } },
            { note: "ポルトガル旅行", photo: { title: "ポルトガル旅行" } },
            { note: "撮影地 ポルトガル", photo: { location: "ポルトガル" } },
            { note: "ポルトの朝（題）", photo: { title: "ポルトの朝" } },
            { note: "ポルト, ポルトガル", photo: { location: "ポルト, ポルトガル" } },
            { note: "ギンザ、東京", photo: { location: "ギンザ、東京" } },
            { note: "ギンザ通り", photo: { location: "ギンザ通り" } },
        ]),
        group("2つ以上", [FOX, other], [
            { note: "蔵王キツネ村から白石城へ", photo: { title: "蔵王キツネ村から白石城へ" } },
        ]),
        group("同名異所", [hachimanA, hachimanB], [
            { note: "八幡神社", photo: { title: "八幡神社" } },
        ]),
        group("別名の取り合い", [FOX, aliasThief], [
            { note: "蔵王キツネ村", photo: { location: "蔵王キツネ村" } },
        ]),
        group("下書き", [{ ...FOX, status: "review" } as Spot], [
            { note: "下書きには結ばない", photo: { title: "蔵王キツネ村" } },
        ]),
    ],
};

writeFileSync(process.argv[2], JSON.stringify(out) + "\n");
const counts = out.groups.map((g) => `${g.name}: ${g.cases.length}件（結ぶ ${g.cases.filter((c) => c.expect).length}）`);
console.log(counts.join("\n"));
