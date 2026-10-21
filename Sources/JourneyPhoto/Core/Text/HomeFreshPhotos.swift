import Foundation

/// ホームの最初の画面に出す「みんなの新しい写真」の1段（2026-10-21・全画面の点検）。
///
/// 点検で、ホームの最初の画面が**出典付きのスポットの作例だけ**で、利用者が投稿した写真が
/// 1枚も無いと分かった（ストーリーの列も「あなた」だけ）。写真の SNS に見えないので、
/// ストーリーの列のすぐ下に、**利用者の新しい写真を横に流す1段**を置く。
///
/// - 元は**ホームが既に読んでいる公開一覧**（`GalleryViewModel.allPhotosForTheme`）。
///   新しいサーバーの口は作らない。ログインしていない人にも公開の写真が見える
/// - **フォロー中の人の写真を先に**、残りを新しい順で埋める（ログインしている人だけ）
/// - 自分の写真は最後（自分の写真はマイページが持ち場。ほかに無いときだけ埋める）
/// - **投稿（束）ごとに1つ**。段には表紙を出し、開いた詳細では同じ投稿の残りへ送れる
///   （ホームの一覧 `HomeMosaic` と同じく束を返す）
/// - 下書き（`published == false`）は出さない（`GalleryScope.all` と同じ）
/// - ブロック・通報の絞り込みは**呼ぶ側が先に**掛ける（`ModerationSnapshot.visible`）。
///   ここで数を切ってから落とすと、段が短くなる
/// - **0件なら段ごと出さない**（呼ぶ側）
enum HomeFreshPhotos {

    /// 段に並べる最大の数（横に流して 3 画面ぶん弱）
    static let limit = 12

    /// 1巡目で1人から出す数。
    ///
    /// 2026-10-21 判断（確かめ役の見直し）: **1巡目は順を保って1人2つまで**、溢れた分を同じ順で
    /// 後ろに足して上限まで埋める。1人が続けて投稿すると段がその人で埋まり「みんなの」に見えない。
    /// 一方、いまは利用者が少ないので、溢れた分を捨てると段が2〜3枚で終わる——**枚数は減らさない**
    static let perPersonFirstPass = 2

    static func groups(_ photos: [Photo], viewerId: String?, followingIds: Set<String>,
                       limit: Int = limit) -> [PhotoGroups.Group] {
        guard limit > 0 else { return [] }
        let published = GalleryScope.all.photos(photos, viewerId: viewerId, followingIds: followingIds)
        // 新しい順に並べてから束ねる——束は先頭が出てきた場所に置かれる
        let groups = PhotoGroups.group(GallerySort.new.apply(published))
        func owner(_ group: PhotoGroups.Group) -> String? { group.cover.userId ?? group.cover.uploadedBy }
        func rank(_ group: PhotoGroups.Group) -> Int {
            guard let viewerId, let who = owner(group) else { return 1 }
            if who == viewerId { return 2 }
            return followingIds.contains(who) ? 0 : 1
        }
        // 並べ替えは安定させる（同じ段の中は新しい順のまま）
        let ordered = groups.enumerated()
            .sorted { lhs, rhs in
                let l = rank(lhs.element), r = rank(rhs.element)
                return l != r ? l < r : lhs.offset < rhs.offset
            }
            .map(\.element)
        // 1巡目は1人2つまで（持ち主の分からない写真は1人に数えない）。溢れた分は同じ順で後ろへ
        var counts: [String: Int] = [:]
        var first: [PhotoGroups.Group] = []
        var overflow: [PhotoGroups.Group] = []
        for group in ordered {
            guard let who = owner(group) else { first.append(group); continue }
            let seen = counts[who, default: 0]
            counts[who] = seen + 1
            if seen < perPersonFirstPass { first.append(group) } else { overflow.append(group) }
        }
        return Array((first + overflow).prefix(limit))
    }

    /// 写真の下に添える作者の名前。無ければ撮影地（どちらも無ければ出さない）
    static func byline(_ photo: Photo) -> String? {
        for value in [photo.displayName, photo.location] {
            if let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return text }
        }
        return nil
    }
}
