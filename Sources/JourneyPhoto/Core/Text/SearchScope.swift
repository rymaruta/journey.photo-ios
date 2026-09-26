import Foundation

/// 探す画面の絞り（板 11: すべて / 写真 / 人 / タグ / 撮影地）。
///
/// 以前はカテゴリの丸い札と並び替えを持っていたが、板どおりに外した
/// （owner の判断・2026-09-26）。カテゴリはホームの札と各集約ページに残る。
enum SearchScope: String, CaseIterable, Identifiable {
    case all
    case photos
    case people
    case tags
    case places

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

    /// 人の結果を出すか。**「写真」「タグ」「撮影地」では出さない**
    var showsPeople: Bool { self == .all || self == .people }

    /// 写真の結果を出すか
    var showsPhotos: Bool { self != .people }

    /// 打った語で写真を拾う。**どの欄で当てるかを絞りで変える**
    /// ——「タグ」は写真のタグだけ、「撮影地」は撮影地の文字だけ。
    /// 「すべて」「写真」は今まで通り題・撮影地・カテゴリ・タグのどれか
    /// （`PhotoQuery.match`）。大文字小文字と全角半角は区別しない
    func match(_ photos: [Photo], query: String) -> [Photo] {
        switch self {
        case .people:
            return []
        case .all, .photos:
            return PhotoQuery.match(photos, query: query)
        case .tags:
            return Self.tagMatch(photos, query: query)
        case .places:
            return Self.filter(photos, query: query) { $0.location ?? "" }
        }
    }

    /// タグで当てる。**まず鍵で一致させる**（`TagChoices.key`: `#`・大小・日英の別名を
    /// 畳む）——「タグ」の一覧の枚数も鍵で数えているので、行を押して「冬 13」と
    /// 書いてあれば `winter` の写真も含めて13枚出す。鍵で1枚も当たらないときだけ、
    /// 打ちかけの語として部分一致で拾う（「sau」で `sauna`）
    private static func tagMatch(_ photos: [Photo], query: String) -> [Photo] {
        let key = TagChoices.key(query)
        guard !key.isEmpty else { return [] }
        let exact = photos.filter { ($0.tags ?? []).contains { TagChoices.key($0) == key } }
        if !exact.isEmpty { return exact }
        let stripped = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#＃"))
        return filter(photos, query: stripped) { ($0.tags ?? []).joined(separator: " ") }
    }

    private static func filter(_ photos: [Photo], query: String,
                               field: (Photo) -> String) -> [Photo] {
        let needle = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return [] }
        return photos.filter { fold(field($0)).contains(needle) }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
    }
}
