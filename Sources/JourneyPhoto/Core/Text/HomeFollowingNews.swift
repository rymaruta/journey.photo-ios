import Foundation

/// ホームの切り替えの「フォロー中」に付ける真鍮の点（#417 ⑨・2026-10-30 owner 採用）。
///
/// **フォロー中の人に新しい写真がある日は、「フォロー中」の右上に点を出す**（読み上げ「フォロー中・新しい写真あり」）。
/// 外した「NEW（みんなの新しい写真）」の段（`HomeFreshStrip`・#417 ⑦）が持っていた「フォロー中の人の写真を先に」の
/// 役目を引き継ぐ。既定の選びは「おすすめ」のまま。
///
/// 2026-10-30 判断（「新しい」の考えは NEW の段のものを使い回す・通信を増やさない・サーバーは変えない）:
/// - 元は**ホームが既に読んでいる公開一覧**（`GalleryViewModel.allPhotosForTheme`）。NEW の段（`HomeFreshPhotos`）と同じ
/// - 「フォロー中の人の写真」は**「フォロー中」のフィードが出すものと同じ**（`GalleryScope.following`: 下書きを除き、
///   持ち主は `userId ?? uploadedBy`）。自分の写真は数えない。フォロー一覧は今の人のものだけ（呼ぶ側）
/// - ブロック・通報は呼ぶ側が先に落とす（NEW の段と同じ・`ModerationSnapshot.visible`）
/// - 比べるのは投稿日（`createdAt`）の文字のまま（`GallerySort.new` と同じ比べ方）
/// - NEW の段の並べ方（1人2つまで・12件まで）は点には要らないので持ち越さない。段と一緒に `HomeFreshPhotos` は消した
///
/// 既読の扱い（「フォロー中の新しい写真を見た」を覚える仕組みは無かったので、端末に小さく覚える・`FollowingSeenStore`）:
/// - **「フォロー中」を開いたら、その時点までの分は既読**（いちばん新しい投稿日を覚える）。開いている間に届いた分も既読
/// - **初めて（覚えが無い）は、その時点の分を既読として覚えるだけで点を出さない**——前に見たかどうか分からない写真に
///   「新しい」と言わない。次に新しい写真が届いた日から点が出る
enum HomeFollowingNews {

    /// フォロー中の人のいちばん新しい投稿日。フォローしていない・未ログイン・該当が無いなら nil
    static func newest(_ photos: [Photo], viewerId: String?, followingIds: Set<String>) -> String? {
        guard let viewerId, !followingIds.isEmpty else { return nil }
        return GalleryScope.following.photos(photos, viewerId: viewerId, followingIds: followingIds)
            .filter { ($0.userId ?? $0.uploadedBy) != viewerId }
            .compactMap(\.createdAt)
            .max()
    }

    /// 点を出すか。**覚えが無い日は出さない**（初めての日・上の注記）。開いている「フォロー中」には出さない
    static func showsDot(feed: HomeFeed, newest: String?, seen: String?) -> Bool {
        guard feed != .following, let newest, let seen else { return false }
        return newest > seen
    }

    /// 覚え直す値（書かなくてよければ nil）。「フォロー中」を開いている間はいちばん新しい投稿日まで既読、
    /// 覚えが無ければその時点の分を既読として覚える（点は出さない）
    static func seenToStore(feed: HomeFeed, newest: String?, seen: String?) -> String? {
        guard let newest else { return nil }
        guard let seen else { return newest }
        guard feed == .following, newest > seen else { return nil }
        return newest
    }

    /// 「フォロー中」の読み上げ（点を色と形だけにしない）
    static func spokenLabel(_ label: String, hasNew: Bool) -> String {
        hasNew ? L("\(label)・新しい写真あり", "\(label), new photos") : label
    }
}
