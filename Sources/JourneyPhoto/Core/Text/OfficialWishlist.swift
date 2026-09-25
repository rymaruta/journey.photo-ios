import Foundation

/// マイページの「行きたい」に並べる、**台帳の撮影スポット**の行。
///
/// 「行きたい」の入れ物（`WishlistStore`）には撮影地の鍵（スラッグそのまま）と
/// スポットの鍵（`SPOT-<slug>`・`SavedSpotKey`）が同居する。撮影地の側は
/// `DerivedSpot.all` と突き合わせて行にするので、こちらはスポットの鍵だけを
/// 索引（`OfficialSpot`）と突き合わせる。
///
/// 🔴 **索引が無くても行は出す。** 索引は本番が 404 の間（Web の変更が main に
/// 入るまで）取れないが、押した覚えのあるものを「まだありません」と言うと
/// 消えたように見える。名前は slug から起こして、行だけ出す（押しても開けない）。
enum OfficialWishlist {

    struct Row: Identifiable, Equatable {
        /// 入れ物に入っている鍵そのもの（外すときに使う）
        let key: String
        let slug: String
        /// 索引にあればその名前、無ければ slug から起こした名前
        let name: String
        let regionLabel: String?
        /// 索引の行。**無ければ nil**（画面は開けない・行だけ）
        let spot: OfficialSpot?

        var id: String { key }
    }

    /// 並びは**索引にあるものが先**、そのあと名前順（毎回同じ並びにする）
    static func rows(keys: Set<String>, index: [OfficialSpot]) -> [Row] {
        let bySlug = Dictionary(index.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        return keys
            .compactMap { key -> Row? in
                guard let slug = SavedSpotKey.slug(fromOfficial: key) else { return nil }
                let spot = bySlug[slug]
                return Row(key: key,
                           slug: slug,
                           name: spot?.name ?? name(fromSlug: slug),
                           regionLabel: spot?.regionLabel,
                           spot: spot)
            }
            .sorted { a, b in
                if (a.spot != nil) != (b.spot != nil) { return a.spot != nil }
                if a.name != b.name { return a.name < b.name }
                return a.key < b.key
            }
    }

    /// 索引に無い鍵の見出し。`takaya-jinja` → `takaya jinja`。空なら「名前のないスポット」
    /// （**壊れた鍵 `SPOT-` も落とさない**——落とすと本人が外せない）
    static func name(fromSlug slug: String) -> String {
        let words = slug.split(separator: "-").map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return L("名前のないスポット", "Unnamed spot") }
        return words.joined(separator: " ")
    }
}
