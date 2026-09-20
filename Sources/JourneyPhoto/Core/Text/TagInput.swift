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
