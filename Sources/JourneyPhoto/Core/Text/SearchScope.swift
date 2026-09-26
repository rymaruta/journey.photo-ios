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

    /// 写真を種類で絞る。
    ///
    /// - 打っていないとき: タグ／撮影地は**その欄を持つ写真**だけ、写真とすべては全部
    /// - 打っているとき: すべて・写真は `PhotoQuery.match`（題・撮影地・カテゴリ・タグ）、
    ///   タグはタグだけ、撮影地は撮影地だけに当てる。
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
            return photos.filter { photo in
                let tags = (photo.tags ?? []).map(Self.fold).filter { !$0.isEmpty }
                return needle.isEmpty ? !tags.isEmpty : tags.contains { $0.contains(needle) }
            }
        case .places:
            return photos.filter { photo in
                let place = Self.fold(photo.location ?? "")
                return needle.isEmpty ? !place.isEmpty : place.contains(needle)
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

    /// 「いまの季節の写真」の格子に出す枚数。**3列で2段**（板 11 は3列）
    static let seasonalPreview = 6
}
