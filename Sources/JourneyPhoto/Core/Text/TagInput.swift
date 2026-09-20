import Foundation

/// タグの入力と、写真の絞り込み。
///
/// **`@MainActor` の型に置かない。** 置くと静的メソッドまで MainActor に
/// 縛られ、テスト（`XCTestCase` のメソッドは isolation を持たない）から
/// 呼べなくなる——`Call to main actor-isolated static method in a
/// synchronous nonisolated context` でコンパイルが落ちる。
/// 画面からもテストからも呼ぶ計算は、素の `enum` に置く。
enum TagInput {

    /// 読点・カンマ・空白のどれで区切っても同じに扱う。
    /// **重複は落とす**（同じタグが2つ付くと絞り込みの件数がずれる）。
    static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for piece in text.components(separatedBy: CharacterSet(charactersIn: ",、 　\n")) {
            let tag = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty, !seen.contains(tag.lowercased()) else { continue }
            seen.insert(tag.lowercased())
            result.append(tag)
        }
        return result
    }
}

enum PhotoQuery {

    /// 題・撮影地・タグ・カテゴリのどれかに含まれれば拾う。
    /// 大文字小文字と全角半角は区別しない。
    static func match(_ photos: [Photo], query: String) -> [Photo] {
        let needle = query.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
        guard !needle.isEmpty else { return [] }
        return photos.filter { photo in
            let haystack = [
                photo.displayTitle,
                photo.location ?? "",
                photo.category ?? "",
                (photo.tags ?? []).joined(separator: " "),
            ].joined(separator: " ")
                .folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
            return haystack.contains(needle)
        }
    }

    /// タグ・撮影地・カテゴリでの絞り込み。
    ///
    /// **撮影地はゆるく一致させる。** Web 側の `photosInCollection` が
    /// 「パリ」「パリ, フランス」「オペラ・ガルニエ（パリ）」を寄せているので、
    /// 完全一致で絞ると結果が食い違う。
    enum Collection: Equatable {
        case tag(String)
        case location(String)
        case category(String)

        var title: String {
            switch self {
            case .tag(let value): return "#\(value)"
            case .location(let value): return value
            case .category(let value): return value
            }
        }
    }

    static func photos(_ photos: [Photo], in collection: Collection) -> [Photo] {
        switch collection {
        case .tag(let value):
            let needle = value.lowercased()
            return photos.filter { ($0.tags ?? []).contains { $0.lowercased() == needle } }
        case .category(let value):
            return photos.filter { $0.category == value }
        case .location(let value):
            let needle = value.lowercased()
            return photos.filter {
                guard let location = $0.location?.lowercased() else { return false }
                return location == needle || location.contains(needle) || needle.contains(location)
            }
        }
    }

    /// 「この写真に近いもの」。同じ撮影地を先に、足りなければタグが重なるもので埋める。
    /// **自分自身は入れない。**
    static func related(to photo: Photo, from photos: [Photo], limit: Int = 12) -> [Photo] {
        let others = photos.filter { $0.id != photo.id }
        var picked: [Photo] = []
        var seen = Set<String>()

        if let location = photo.location?.lowercased(), !location.isEmpty {
            for item in others where (item.location?.lowercased() ?? "") == location {
                if seen.insert(item.id).inserted { picked.append(item) }
            }
        }

        let tags = Set((photo.tags ?? []).map { $0.lowercased() })
        if !tags.isEmpty {
            for item in others where !tags.isDisjoint(with: Set((item.tags ?? []).map { $0.lowercased() })) {
                if picked.count >= limit { break }
                if seen.insert(item.id).inserted { picked.append(item) }
            }
        }
        return Array(picked.prefix(limit))
    }

    /// 多い順にタグを数える。**種類が少ないので全部数えてよい**（30枚・59種）。
    static func topTags(in photos: [Photo], limit: Int = 12) -> [String] {
        var counts: [String: Int] = [:]
        for tag in photos.flatMap({ $0.tags ?? [] }) {
            counts[tag, default: 0] += 1
        }
        return counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map(\.key)
    }
}
