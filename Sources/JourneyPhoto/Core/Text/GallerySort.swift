import Foundation

/// 一覧の並び替え。**Web の `FilterBar` と同じ3つ**
/// （`lib/hooks/useGallery.ts` の `sort` が `new` / `old` / `popular`）。
///
/// アプリには**並び替えそのものが無く**、常に新着順だった。
///
/// `taken`（撮影日）は**集約の一覧（板 12）だけ**の並び。Web の `FilterBar` には
/// 無いので、ホームのメニューは `feedChoices` の3つを出す
/// （探すの並び替えは板 11 に無いので外した）。
enum GallerySort: String, CaseIterable, Identifiable {
    case new, old, popular, taken

    var id: String { rawValue }

    /// ホームの並び替えメニュー（Web の `FilterBar` と同じ3つ）
    static let feedChoices: [GallerySort] = [.new, .old, .popular]
    /// 集約の一覧のチップ（板 12 の「人気／新着／撮影日」）
    static let collectionChoices: [GallerySort] = [.popular, .new, .taken]

    var label: String {
        switch self {
        case .new: return L("新しい順", "Newest")
        case .old: return L("古い順", "Oldest")
        case .popular: return L("人気順", "Popular")
        case .taken: return L("撮影日順", "Date taken")
        }
    }

    /// チップに載せる短い名前（板 12）
    var chipLabel: String {
        switch self {
        case .new: return L("新着", "New")
        case .old: return L("古い順", "Oldest")
        case .popular: return L("人気", "Popular")
        case .taken: return L("撮影日", "Date taken")
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
        case .taken:
            // **撮った日が新しい順。** 持たない写真は末尾（実データで持つのは少数）。
            // 同じ日・どちらも無いときは投稿の新しい順
            return photos.sorted {
                switch (Self.takenDay($0), Self.takenDay($1)) {
                case let (l?, r?) where l != r: return l > r
                case (_?, nil): return true
                case (nil, _?): return false
                default: return Self.byDate($0, $1, newestFirst: true)
                }
            }
        }
    }

    /// 撮影日を 20260919 のような数に。`date`（YYYY-MM-DD）を先に、
    /// 無ければ EXIF の撮影時刻から。**EXIF の綴りは2通り**——アプリは
    /// `2026:09:19 08:21:05`、Web は `2026-09-19T08:21:05` で送る。
    /// 読めない値は nil（`TakenDay.ymd` が月日の妥当さまで見る）
    static func takenDay(_ photo: Photo) -> Int? {
        let exif = photo.exif?.dateTimeOriginal.map {
            String($0.prefix(10)).replacingOccurrences(of: ":", with: "-")
        }
        guard let day = TakenDay.ymd(photo.date) ?? TakenDay.ymd(exif) else { return nil }
        let (y, m, d) = day
        return y * 10_000 + m * 100 + d
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
