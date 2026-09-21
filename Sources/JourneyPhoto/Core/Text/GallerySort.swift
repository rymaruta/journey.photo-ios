import Foundation

/// 一覧の並び替え。**Web の `FilterBar` と同じ3つ**
/// （`lib/hooks/useGallery.ts` の `sort` が `new` / `old` / `popular`）。
///
/// アプリには**並び替えそのものが無く**、常に新着順だった。
enum GallerySort: String, CaseIterable, Identifiable {
    case new, old, popular

    var id: String { rawValue }

    var label: String {
        switch self {
        case .new: return L("新しい順", "Newest")
        case .old: return L("古い順", "Oldest")
        case .popular: return L("人気順", "Popular")
        }
    }

    /// 並べ替える。**元の並びを壊さない**（新着の規則は1か所に置く）。
    ///
    /// - `new` / `old`: `createdAt` で。**無い行は末尾へ**送る
    ///   （実データに欠けている写真がある。Web の `photoOrder.ts` と同じ）
    /// - `popular`: `likes` の多い順。**持たない写真は 0**
    ///   （Web も `(b.likes ?? 0) - (a.likes ?? 0)`）
    func apply(_ photos: [Photo]) -> [Photo] {
        switch self {
        case .new:
            return photos.sorted { Self.byDate($0, $1, newestFirst: true) }
        case .old:
            return photos.sorted { Self.byDate($0, $1, newestFirst: false) }
        case .popular:
            // **同点は新しい順。** そうしないと押すたびに並びが変わって見える
            return photos.sorted {
                let left = $0.likes ?? 0
                let right = $1.likes ?? 0
                if left != right { return left > right }
                return Self.byDate($0, $1, newestFirst: true)
            }
        }
    }

    private static func byDate(_ lhs: Photo, _ rhs: Photo, newestFirst: Bool) -> Bool {
        switch (lhs.createdAt, rhs.createdAt) {
        case let (l?, r?): return newestFirst ? l > r : l < r
        // **日付の無い写真は、どちらの向きでも末尾。** 古い順のときに
        // 先頭へ来ると、「いちばん古い写真」として日付不明のものが並ぶ
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return lhs.id < rhs.id
        }
    }
}
