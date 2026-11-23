import Foundation

/// **行きたい場所に行けた**（札 #710 の案1・2026-11-23 owner 承認）。
///
/// 「行きたい」に入れた場所で自分が撮った写真があれば、その行は「行った」になる。
///
/// 2026-11-23 判断（案の頁「投稿したくなる案」の1）:
/// - 「行った」は**保存しない**。表示のたびに、自分の写真と行きたい場所の鍵を端末で突き合わせて出す
///   （サーバー・DB は変えない。Web には出さない）
/// - 突き合わせ方は、行きたい場所の一覧（`ProfileSections.wantedPlaces`）と同じ物差しにする:
///   撮影地の鍵は `DerivedSpot.allMergedBySlug` の鍵、観光スポットの鍵（`SPOT-<slug>`）は写真の `spotId` を索引で引いた slug
/// - 進み具合は「1 / 3 行った」とだけ言う。順位や目標は言わない
enum WishVisit {

    /// その場所で撮った自分の写真（鍵 → いちばん新しい1枚）
    static func visits(keys: Set<String>, mine: [Photo], spots: [OfficialSpot]) -> [String: Photo] {
        guard !keys.isEmpty, !mine.isEmpty else { return [:] }
        var out: [String: Photo] = [:]
        // 撮影地の鍵（行きたい場所の一覧と同じ寄せ方・写真は新しい順）
        for place in DerivedSpot.allMergedBySlug(in: mine) where keys.contains(place.slug) {
            if let newest = place.photos.first { out[place.slug] = newest }
        }
        // 観光スポットの鍵。写真の `spotId`（`sp_…`）を索引で slug に直して鍵にする
        let slugById = Dictionary(spots.map { ($0.spotId, $0.slug) }, uniquingKeysWith: { first, _ in first })
        for photo in mine {
            guard let spotId = photo.spotId, let slug = slugById[spotId] else { continue }
            let key = SavedSpotKey.official(slug)
            guard keys.contains(key) else { continue }
            if let kept = out[key], (kept.createdAt ?? "") >= (photo.createdAt ?? "") { continue }
            out[key] = photo
        }
        return out
    }

    /// 見出しの横の「1 / 3 行った」。**1か所も行っていなければ出さない**（0 を数として見せない）
    static func progress(visited: Int, total: Int) -> String? {
        guard visited > 0, total > 0 else { return nil }
        return L("\(min(visited, total)) / \(total) 行った", "\(min(visited, total)) / \(total) visited")
    }

    /// 行の2行目「行った　11月23日、あなたの1枚」。撮影日が無ければ投稿日、それも無ければ日を言わない
    static func rowLine(_ photo: Photo) -> String {
        let raw = photo.date ?? photo.createdAt
        guard let (_, month, day) = TakenDay.ymd(raw) else {
            return L("行った\u{3000}あなたの1枚", "Visited\u{2002}your photo")
        }
        return L("行った\u{3000}\(month)月\(day)日、あなたの1枚", "Visited\u{2002}\(month)/\(day), your photo")
    }

    /// 投稿の知らせの1行目
    static var noticeTitle: String { L("行きたい場所に行けました", "You made it to a place on your list") }

    /// 投稿した写真が当たった行きたい場所（鍵と名前）。**最初の1か所だけ**。
    ///
    /// - Parameters:
    ///   - posted: この投稿で保存が通った写真
    ///   - keys: 行きたい場所の鍵
    ///   - announced: もう知らせた（または前から「行った」だった）鍵。**2枚目からは通常の知らせ**にする
    static func notice(posted: [Photo], keys: Set<String>, spots: [OfficialSpot],
                       announced: Set<String>) -> (key: String, name: String)? {
        let hits = visits(keys: keys, mine: posted, spots: spots)
        guard !hits.isEmpty else { return nil }
        let fresh = hits.keys.filter { !announced.contains($0) }.sorted()
        guard let key = fresh.first, let photo = hits[key] else { return nil }
        return (key, name(of: key, photo: photo, spots: spots))
    }

    /// 鍵の名前（観光スポットは索引の名前、撮影地は写真の撮影地の表示）
    static func name(of key: String, photo: Photo, spots: [OfficialSpot]) -> String {
        if let slug = SavedSpotKey.slug(fromOfficial: key) {
            return spots.first { $0.slug == slug }?.name ?? OfficialWishlist.name(fromSlug: slug)
        }
        let place = DerivedSpot.allMergedBySlug(in: [photo]).first { $0.slug == key }
        return LocationMatch.display(place?.label ?? photo.location)
    }
}

/// 「行きたい場所に行けました」を**もう知らせた鍵**（端末の中だけ・人ごと）。
///
/// 2026-11-23 判断: 「行った」の状態そのものは保存しない（毎回導く）。ここに残すのは、同じ場所で2枚目からは
/// 通常の「投稿しました」に戻すための印だけ。マイページで「行った」と導けた鍵もここに入れる
/// （前から行っていた場所で、案を入れたあとの最初の投稿に「行けました」と言わない）
final class WishVisitMemory {

    /// 覚える鍵の上限（行きたい場所の数より十分に多い）
    static let limit = 500

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ userId: String) -> String { "wishVisit.announced.v1.\(userId)" }

    func announced(for userId: String?) -> Set<String> {
        guard let userId, !userId.isEmpty else { return [] }
        return Set(defaults.stringArray(forKey: key(userId)) ?? [])
    }

    /// 鍵を覚える（変わらなければ書かない）
    func note(_ keys: some Sequence<String>, for userId: String?) {
        guard let userId, !userId.isEmpty else { return }
        let before = defaults.stringArray(forKey: key(userId)) ?? []
        var seen = Set(before)
        var next = before
        for k in keys where !k.isEmpty && seen.insert(k).inserted { next.append(k) }
        guard next.count != before.count else { return }
        defaults.set(Array(next.suffix(Self.limit)), forKey: key(userId))
    }

    func removeAll(for userId: String) {
        defaults.removeObject(forKey: key(userId))
    }
}
