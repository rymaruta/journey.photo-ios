import Foundation

/// 撮影スポット（モック5）。
///
/// 🔴 **台帳を持たない。** 2026-09-22 に本番がそう決めた
/// （`photo-gallery/docs/spot-master.md`）——モック10の9項目のうち
/// 7項目は**いまある写真から導出できる**ので、新しい入れ物も
/// 第二の ID も作らない。
///
/// アプリは一度「`spot#` 行の台帳」で作ったが、それは
/// **本番と逆の設計**だった。台帳は空のままで、画面は誰にも出なかった。
/// ここでは同じ結論に合わせて、**撮影地の集まり**をスポットとして扱う。
///
/// 鍵は `/location/<スラッグ>` のスラッグ（`LocationSlug`）——
/// サーバーの「行きたい場所」が持っているのと同じ文字列。
enum DerivedSpot {

    struct Place: Identifiable, Equatable {
        /// 見出しに出す名前（＝撮影地の文字列そのもの）
        let label: String
        /// 鍵。`/location/<slug>` と `spots#<uid>` に入る値
        let slug: String
        /// この撮影地の写真（**新しい順**）
        let photos: [Photo]
        /// **より広い撮影地。** 「パリ, フランス」に対する「パリ」「フランス」。
        /// **推測しない**——同じ一覧に実際に在って、含む関係にあるものだけ
        let broader: [String]
        /// 写真が持っている分類（チップ）
        let categories: [String]
        /// 代表の座標。**写真が持っているときだけ**
        let coords: Photo.Coords?

        var id: String { slug.isEmpty ? label : slug }
        var count: Int { photos.count }
        /// 代表の1枚。**いちばん多く押された写真**（数えた値）
        var cover: Photo? { GallerySort.popular.apply(photos).first }
    }

    /// その撮影地のスポット。**1枚も無ければ nil**（空の地点を作らない）
    static func place(_ label: String, in photos: [Photo]) -> Place? {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let matched = PhotoQuery.photos(photos, in: .location(trimmed))
        guard !matched.isEmpty else { return nil }
        return Place(
            label: trimmed,
            slug: LocationSlug.make(trimmed),
            photos: matched.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") },
            broader: broader(of: trimmed, in: photos),
            categories: categories(of: matched),
            coords: matched.compactMap(\.coords).first
        )
    }

    /// **スポットの画面を開いてよい地点か。**
    ///
    /// 3か所（写真の詳細・地図のピン・「注目スポット」の札）が同じ判断を
    /// していた。同じものを三度書くと、線を動かしたとき1か所だけ残る。
    ///
    /// 線は **2枚**。1枚だけの地点にスポットの画面を出すと、その写真の
    /// 個別ページと中身が同じになる（Web の `MIN_INDEXABLE_LOCATION` と
    /// 同じ考え）。
    static func openable(_ label: String, in photos: [Photo]) -> Place? {
        guard let place = place(label, in: photos) else { return nil }
        return place.count >= minPhotosForSpotPage ? place : nil
    }

    /// スポットの画面を出す最低の枚数（Web の `MIN_INDEXABLE_LOCATION` と同じ）
    static let minPhotosForSpotPage = 2

    /// 一覧にある撮影地すべて。**枚数の多い順**
    static func all(in photos: [Photo]) -> [Place] {
        var seen = Set<String>()
        var labels: [String] = []
        for photo in photos {
            let label = (photo.location ?? "").trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty else { continue }
            let key = label.lowercased()
            if seen.insert(key).inserted { labels.append(label) }
        }
        return labels.compactMap { place($0, in: photos) }
            .sorted { $0.count > $1.count }
    }

    /// **より広い撮影地。** 同じ一覧に在って、この名前を含んでいるもの。
    ///
    /// **広い順には並べない。** 「パリ, フランス」の広い方は「パリ」と
    /// 「フランス」で、**短い方が狭い**——長さでは決まらない
    /// （Web の `broaderSpots` が同じことを書いている）。
    static func broader(of label: String, in photos: [Photo]) -> [String] {
        let needle = label.lowercased()
        var seen = Set<String>()
        var out: [String] = []
        for photo in photos {
            let other = (photo.location ?? "").trimmingCharacters(in: .whitespaces)
            let key = other.lowercased()
            guard !other.isEmpty, key != needle, seen.insert(key).inserted else { continue }
            // 「この撮影地の写真は、そちらのページにも載るか」
            if needle.contains(key) { out.append(other) }
        }
        return out
    }

    /// 近くの撮影地。**座標を持っているものだけ**（距離を測れないものは出さない）。
    /// 近い順に返す。
    ///
    /// 🔴 **含む関係にある撮影地は「近く」に出さない。** run 55 の実機の絵で
    /// 2つ出ていた:
    ///
    ///  - 「フランス ヴェルサイユ」の近くに **「フランス」が 1km 以内**
    ///    ——広い方は見出しの下に既に出ている（`broader`）し、その写真は
    ///    この画面の一覧にも入っている。**同じものを2度出していた**
    ///  - 「パリ」と「パリ, フランス」が**別々の札**で並んでいた
    ///    ——綴り違いで、写真は片方がもう片方に丸ごと入っている
    ///
    /// だから2つ落とす。**文字で決めるのは自分との関係だけ**で、
    /// 候補どうしは**実際の写真の集合**で見る（綴りの当てものにしない）。
    static func nearby(_ place: Place, in photos: [Photo], limit: Int = 6) -> [(place: Place, km: Double)] {
        guard let here = place.coords else { return [] }
        let needle = place.label.lowercased()
        let candidates = all(in: photos)
            .filter { $0.slug != place.slug }
            // **自分を含む／自分に含まれる撮影地は出さない。**
            // 広い方は `broader`、狭い方の写真はこの画面の一覧に入っている
            .filter { other in
                let key = other.label.lowercased()
                return !needle.contains(key) && !key.contains(needle)
            }
            .compactMap { other -> (Place, Double)? in
                guard let there = other.coords else { return nil }
                return (other, TravelDistance.kilometers(from: here, to: there))
            }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.label.count < $1.0.label.count }

        // **写真が丸ごと他方に入っている札は落とす**（「パリ, フランス」→「パリ」）。
        // 残すのは広い方（枚数が多い方）。同じ集合なら短い名前
        var kept: [(Place, Double)] = []
        for candidate in candidates {
            let mine = Set(candidate.0.photos.map(\.id))
            let swallowed = candidates.contains { other in
                guard other.0.slug != candidate.0.slug else { return false }
                let theirs = Set(other.0.photos.map(\.id))
                guard mine.isSubset(of: theirs) else { return false }
                // 同じ集合なら短い名前を残す（どちらも落とさない／どちらも残さない、を避ける）
                return mine.count < theirs.count || other.0.label.count < candidate.0.label.count
            }
            if !swallowed { kept.append(candidate) }
        }
        return kept.prefix(limit).map { (place: $0.0, km: $0.1) }
    }

    /// 写真が持っている分類（多い順）。**空は入れない**
    static func categories(of photos: [Photo]) -> [String] {
        var counts: [String: (name: String, n: Int)] = [:]
        for photo in photos {
            let raw = (photo.category ?? "").trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { continue }
            let key = CategoryChoices.key(raw)
            counts[key] = (counts[key]?.name ?? raw, (counts[key]?.n ?? 0) + 1)
        }
        return counts.values.sorted { $0.n > $1.n }.map(\.name)
    }
}
