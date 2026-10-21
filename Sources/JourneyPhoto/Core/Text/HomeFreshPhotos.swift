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
/// - **同じ投稿の写真は1枚（束の表紙）だけ**——10枚の投稿で段が埋まらないように（`PhotoGroups`）
/// - 下書き（`published == false`）は出さない（`GalleryScope.all` と同じ）
/// - ブロック・通報の絞り込みは**呼ぶ側が先に**掛ける（`ModerationSnapshot.visible`）。
///   ここで数を切ってから落とすと、段が短くなる
/// - **0件なら段ごと出さない**（呼ぶ側）
///
/// 2026-10-21 判断: 人ごとの上限は付けない。いまの利用者は少なく、上限を付けると
/// 段が2〜3枚で終わる
enum HomeFreshPhotos {

    /// 段に並べる最大の枚数（横に流して 3 画面ぶん弱）
    static let limit = 12

    static func photos(_ photos: [Photo], viewerId: String?, followingIds: Set<String>,
                       limit: Int = limit) -> [Photo] {
        guard limit > 0 else { return [] }
        let published = GalleryScope.all.photos(photos, viewerId: viewerId, followingIds: followingIds)
        // 束の表紙（新しい順に並べてから束ねる——束は先頭が出てきた場所に置かれる）
        let covers = PhotoGroups.group(GallerySort.new.apply(published)).map(\.cover)
        func owner(_ photo: Photo) -> String? { photo.userId ?? photo.uploadedBy }
        func rank(_ photo: Photo) -> Int {
            guard let viewerId, let who = owner(photo) else { return 1 }
            if who == viewerId { return 2 }
            return followingIds.contains(who) ? 0 : 1
        }
        // 並べ替えは安定させる（同じ段の中は新しい順のまま）
        let ordered = covers.enumerated()
            .sorted { lhs, rhs in
                let l = rank(lhs.element), r = rank(rhs.element)
                return l != r ? l < r : lhs.offset < rhs.offset
            }
            .map(\.element)
        return Array(ordered.prefix(limit))
    }

    /// 写真の下に添える作者の名前。無ければ撮影地（どちらも無ければ出さない）
    static func byline(_ photo: Photo) -> String? {
        for value in [photo.displayName, photo.location] {
            if let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return text }
        }
        return nil
    }
}
