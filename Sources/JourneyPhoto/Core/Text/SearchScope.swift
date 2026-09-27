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
    /// 検索欄の案内。人を探しているときは人向けに
    var prompt: String {
        switch self {
        case .people: return L("人を検索（名前）", "Search people")
        default: return L("写真を検索（題・説明・タグなど）", "Search photos")
        }
    }

    /// 何も打っていないときに出す入口。**どの種類を押しても何かが出る**
    /// （押して何も変わらない札を作らない）
    enum Entry: Equatable {
        /// 発見の段（注目スポット → おすすめ → 色 → 季節 → 機材）
        case discovery
        /// 写真の格子（新しい順の全部）
        case photoGrid
        /// 人の探し方の案内
        case peopleHint
        /// 使われているタグを枚数つきの行で。押すとそのタグで当てる
        case tagRows
        /// 撮影地を枚数つきの行で。押すとスポット（1枚の地点は集約）へ
        case placeRows
    }

    var entry: Entry {
        switch self {
        case .all: return .discovery
        case .photos: return .photoGrid
        case .people: return .peopleHint
        case .tags: return .tagRows
        case .places: return .placeRows
        }
    }

    /// 写真を種類で絞る。
    ///
    /// - 打っていないとき: タグ／撮影地は**その欄を持つ写真**だけ、写真とすべては全部
    /// - 打っているとき: すべて・写真は `PhotoQuery.match`（題・撮影地・カテゴリ・タグ）、
    ///   タグはタグだけ（鍵で完全一致を先に・`tagMatch`）、撮影地は撮影地だけに当てる。
    ///   **大文字小文字と全角半角は区別しない**（`PhotoQuery.match` と同じ）
    func photos(_ photos: [Photo], query: String) -> [Photo] {
        guard showsPhotos else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = Self.fold(trimmed)
        switch self {
        case .people:
            return []
        case .all, .photos:
            return trimmed.isEmpty ? photos : PhotoQuery.match(photos, query: trimmed)
        case .tags:
            guard !needle.isEmpty else {
                return photos.filter { ($0.tags ?? []).contains { !Self.fold($0).isEmpty } }
            }
            return Self.tagMatch(photos, query: trimmed)
        case .places:
            return photos.filter { photo in
                let place = Self.fold(photo.location ?? "")
                return needle.isEmpty ? !place.isEmpty : place.contains(needle)
            }
        }
    }

    /// タグで当てる。**まず鍵で完全一致**（`TagChoices.key`: `#`・大小・日英の別名を
    /// 畳む）——「タグ」の一覧の枚数も鍵で数えているので、行の「冬 13」を押せば
    /// `winter` の写真も含めて出す。「山」で `山中湖` は拾わない。
    /// **鍵で1枚も当たらないときだけ**、打ちかけの語として部分一致で拾う
    /// （「sau」で `sauna`）
    static func tagMatch(_ photos: [Photo], query: String) -> [Photo] {
        // 全角の「＃」も落とす（`TagChoices.key` が落とすのは半角の `#` だけ）
        let keys = Set([TagChoices.key(query), TagChoices.key(fold(query))]).subtracting([""])
        guard !keys.isEmpty else { return [] }
        let exact = photos.filter { ($0.tags ?? []).contains { keys.contains(TagChoices.key($0)) } }
        if !exact.isEmpty { return exact }
        var needle = fold(query)
        while needle.hasPrefix("#") { needle.removeFirst() }
        needle = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return photos.filter { ($0.tags ?? []).contains { fold($0).contains(needle) } }
    }

    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
    }
}

/// 探すの「発見」の段（板 11）。**並びは板どおり**:
/// 注目スポット → おすすめ → 色 → いまの季節 → 機材。
/// 中身の無い段は出さない（押しても空になる段を置かない）。
enum SearchDiscovery {

    enum Section: String, CaseIterable, Identifiable {
        case spots, featured, colors, seasonal, gear
        var id: String { rawValue }
    }

    /// 段の順。`CaseIterable` の並びに頼らず、ここに書いておく
    static let order: [Section] = [.spots, .featured, .colors, .seasonal, .gear]

    static func sections(present: Set<Section>) -> [Section] {
        order.filter { present.contains($0) }
    }

    /// 「おすすめ · [カテゴリ名]」に出す塊。**ホームと同じ規則**
    /// （`FeaturedGroups`——owner が選んだ公開写真、多い塊が先）の先頭の1つ。
    /// 探すは段を1つだけ置く（ホームはカテゴリごとに並べている）
    static func featured(in photos: [Photo]) -> FeaturedGroups.Group? {
        FeaturedGroups.groups(from: photos).first
    }

    /// 「いまの季節の写真」の格子に出す枚数。**3列で1段**（板 11）
    static let seasonalPreview = 3

    /// 「撮影地」の入口に並べる行の数（写真の多い順）
    static let placeRows = 40

    /// 「おすすめ · [カテゴリ名]」に並べる枚数（板 11 の 120×160 が3枚）
    static let featuredPreview = 3
}
