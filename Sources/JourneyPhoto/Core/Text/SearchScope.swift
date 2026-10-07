import Foundation

/// 探すの種類チップ（板 11 の「すべて／写真／人／タグ／撮影地」）。
///
/// **いまの検索の中身を種類で絞る**だけで、新しい検索は増やさない。
/// 写真は手元の一覧から（`PhotoQuery`）、人は `/users/search` から——
/// どちらも前から引いていたもので、チップはどちらを出すかと、
/// 写真を**どの欄で**当てるかを決める。
enum SearchScope: String, CaseIterable, Identifiable {
    case all, photos, people, tags, places

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return L("すべて", "All")
        case .photos: return L("写真", "Photos")
        case .people: return L("人", "People")
        case .tags: return L("タグ", "Tags")
        case .places: return L("撮影地", "Places")
        }
    }

    /// 人の結果を出すか。**名前で探している**ときだけ
    var showsPeople: Bool { self == .all || self == .people }
    /// 写真の結果を出すか
    var showsPhotos: Bool { self != .people }
    /// 撮影スポット（公式ガイド）の節を出すか。**すべて・撮影地のときだけ**
    /// （写真・タグで探しているときに「山」で山形県のスポットが並ぶ、を作らない）
    var showsSpots: Bool { self == .all || self == .places }
    /// タグのチップ（「winter 13」）を出すか。
    /// **撮影地では出さない**——押すとタグの語が撮影地の欄に当たり、
    /// チップの枚数（タグを持つ写真の数）と結果が合わなくなる
    var showsTagChips: Bool { self == .all || self == .photos || self == .tags }
    /// 0件の出口（地図で撮影地を探す）へ持っていく語。**タグで探していた語は渡さない**
    /// ——地図は撮影地とスポット名で当てるので、タグの語で絞ると地図まで0件になる。
    /// 代わりに空の語を渡して、地図に前の語が残らないようにする（`TabRouter.openMap`）。
    /// 欄が空のまま（カテゴリだけで）探していた回も空の語になり、地図の語・範囲・カテゴリは外れる
    /// ——探すのカテゴリは地図へ持っていかない
    func mapQuery(for query: String) -> String {
        self == .tags ? "" : query
    }

    /// 検索欄の案内。人を探しているときは人向けに
    var prompt: String {
        switch self {
        case .people: return L("人を検索（名前）", "Search people")
        default: return L("写真を検索（題・説明・タグなど）", "Search photos")
        }
    }

    /// 写真を種類で絞る。
    ///
    /// - 打っていないとき: タグ／撮影地は**その欄を持つ写真**だけ、写真とすべては全部
    /// - 打っているとき: すべて・写真は `PhotoQuery.match`（題・説明・撮影地・カテゴリ・タグ）、
    ///   タグはタグだけ、撮影地は撮影地だけに当てる（撮影地は `MapSearch.matches`＝名前として・向きを見て）。
    ///   **大文字小文字と全角半角は区別しない**（`PhotoQuery.match` と同じ）
    func photos(_ photos: [Photo], query: String) -> [Photo] {
        guard showsPhotos else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = Self.fold(trimmed)
        // **タグは日英の別名も拾う**（`TagChoices.key`）。チップの枚数は別名を
        // まとめて数える（「冬 13」＝冬1枚＋winter 12枚）のに、押した後は
        // 綴りでしか当てていなかったので、結果が1枚しか出なかった
        let alias = TagChoices.key(trimmed)
        let hasAlias: (Photo) -> Bool = { photo in
            !alias.isEmpty && (photo.tags ?? []).contains { TagChoices.key($0) == alias }
        }
        switch self {
        case .people:
            return []
        case .all, .photos:
            guard !trimmed.isEmpty else { return photos }
            let matched = Set(PhotoQuery.match(photos, query: trimmed).map(\.id))
            return photos.filter { matched.contains($0.id) || hasAlias($0) }
        case .tags:
            return photos.filter { photo in
                let tags = (photo.tags ?? []).map(Self.fold).filter { !$0.isEmpty }
                return needle.isEmpty ? !tags.isEmpty : (tags.contains { $0.contains(needle) } || hasAlias(photo))
            }
        case .places:
            // 撮影地は名前として・向きを見て当てる（地図の `MapSearch.matches` と同じ。
            // 2026-10-07: 字の部分一致だと「福岡」が宮城県の「福岡八宮」に当たっていた）
            return photos.filter { photo in
                let place = Self.fold(photo.location ?? "")
                return needle.isEmpty ? !place.isEmpty : MapSearch.matches(photo, needle: needle)
            }
        }
    }

    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
    }
}

/// 探すの「発見」の段（板 11）。**並びは板どおり**:
/// 注目スポット → おすすめ → 色 → いまの季節 → 機材。
/// 「季節・時間帯から探す」（2026-10-03・板に無い段）は、いまの季節の写真の次に置く
/// （同じ「いつ撮るか」の話をまとめる）。
/// 中身の無い段は出さない（押しても空になる段を置かない）。
enum SearchDiscovery {

    enum Section: String, CaseIterable, Identifiable {
        case spots, featured, colors, seasonal, shootingTime, gear
        var id: String { rawValue }
    }

    /// 段の順。`CaseIterable` の並びに頼らず、ここに書いておく
    static let order: [Section] = [.spots, .featured, .colors, .seasonal, .shootingTime, .gear]

    static func sections(present: Set<Section>) -> [Section] {
        order.filter { present.contains($0) }
    }

    /// 「おすすめ · [カテゴリ名]」に出す塊。**ホームと同じ規則**
    /// （`FeaturedGroups`——owner が選んだ公開写真、多い塊が先）の先頭の1つ。
    /// 探すは段を1つだけ置く（ホームはカテゴリごとに並べている）
    static func featured(in photos: [Photo]) -> FeaturedGroups.Group? {
        FeaturedGroups.groups(from: photos).first
    }

    /// 「いまの季節の写真」の格子に出す枚数。**3列で1段**（板 11）。
    /// 続きは「すべて →」の先
    static let seasonalPreview = 3
}
