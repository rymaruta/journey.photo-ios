import Foundation

/// 撮影スポットの台帳の1件——Web の `content/spots.json` から
/// アプリ向けに薄く落とした**索引**（`app/data/spots.json`）の形。
///
/// **台帳そのものではない。** 見どころ・季節・アクセスといった本文は
/// 索引に載らない（v1 のアプリは索引しか読まない）。載っているのは
/// 地図に置く・名前で探す・画面の頭を出すのに要るぶんだけ。
///
/// 🔴 **`stage` が `published` でない行は「運営の下書き」。** 2026-09-25 時点で
/// 台帳の全件（1,417件）が `review`——機械が1日で書いた下書きで、人が
/// 1件も確かめていない。画面では**「公式」と呼ばない**（`SpotScreen.eyebrow` /
/// `reviewNotice`）。Swift の型名に `Official` と付いているのは Web の
/// 「公式撮影地ガイド」の入れ物を指す名前で、**利用者に見える語ではない**。
///
/// 写真との紐づけは `Photo.spotId` だけ（`DerivedSpot` の撮影地の集まりとは
/// 別の軸）。知らない項目は読み飛ばし、壊れた行は `LenientOfficialSpotList` が
/// 1件だけ落とす。
struct OfficialSpot: Decodable, Identifiable, Equatable {
    /// 台帳の鍵（`sp_` + 12桁の16進）。名前から作らない
    let spotId: String
    /// URL に出る綴り（`/spots/<slug>`）。「行きたい」の鍵もこれから作る（`SavedSpotKey`）
    let slug: String
    let name: String
    let nameEn: String?
    /// 読み（ひらがな）。名前で探すときに当てる
    let reading: String?
    let region: Region?
    /// 公開してよい座標（写真と同じ約1km精度）。**無い行は地図に置けない**
    let coords: Photo.Coords?
    let category: String?
    /// 概要。**書かれたものだけ**（自動生成しない）
    let summary: String?
    /// `review`（運営未確認の下書き）か `published`（人が確かめた）
    let stage: String
    /// 下書きを書いた日（`YYYY-MM-DD`）。**確認日ではない**
    let draftedAt: String?
    /// 人が確かめた日。`published` の行だけが持つ
    let verifiedAt: String?

    struct Region: Decodable, Equatable {
        let prefecture: String?
        let city: String?
    }

    var id: String { spotId }

    /// **確かめたと言えるのは `published` だけ。** 知らない値も下書きに倒す
    var isDraft: Bool { stage != "published" }

    /// 「[都道府県] · [市区町村]」。どちらも無ければ nil（空の行を置かない）
    var regionLabel: String? {
        let parts = [region?.prefecture, region?.city]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// 1件ずつ復号して、**読めなかった行だけを落とす**入れ物
/// （`LenientPhotoList` と同じ理由・同じ形）。
///
/// 加えて、**鍵になる3つ（`spotId`・`slug`・`name`）が空の行も落とす**。
/// 型は合っていても、空の `slug` は「行きたい」の鍵を `SPOT-` だけにし、
/// 空の名前は札に何も出さない——Web 側の門（`reviewBlockers`）が塞いでいる
/// 形だが、索引を読む側でも受け止める。
struct LenientOfficialSpotList: Decodable {

    let spots: [OfficialSpot]
    /// 落とした行の数。**黙って捨てない**ために数えておく
    let dropped: Int

    init(from decoder: Decoder) throws {
        let rows = try [Row](from: decoder)
        spots = rows.compactMap(\.spot)
        dropped = rows.count - spots.count
    }

    private struct Row: Decodable {
        let spot: OfficialSpot?
        init(from decoder: Decoder) throws {
            guard let decoded = try? OfficialSpot(from: decoder) else {
                spot = nil
                return
            }
            let keys = [decoded.spotId, decoded.slug, decoded.name]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            spot = keys.allSatisfy { !$0.isEmpty } ? decoded : nil
        }
    }
}
