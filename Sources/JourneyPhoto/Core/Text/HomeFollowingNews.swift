import Foundation

/// フォロー中の人の新しい写真を、どこまで上に出したか（ホームの1本の並びの 1.・`HomeFeed.followingFresh`・札 #595）。
///
/// 2026-11-13 判断（#595 で切り替えをやめた）: 前は「フォロー中」の札の右上の真鍮の点（#417 ⑨）に使っていた。
/// 札が無くなったので点もやめ、**上に出した写真のいちばん新しい投稿日を覚え**（`FollowingSeenStore`）、
/// 次に並べ直すときはそれより新しい写真だけを上に出す（同じ写真をいつまでも上に置かない）。
///
/// - 元は**ホームが既に読んでいる全件**（`GalleryViewModel.allPhotosForTheme`）。通信を増やさない・サーバーは変えない
/// - 「フォロー中の人の写真」は `GalleryScope.following`（下書きを除き、持ち主は `userId ?? uploadedBy`）。自分の写真は数えない
/// - ブロック・通報は呼ぶ側が先に落とす（`ModerationSnapshot.visible`）
/// - 比べるのは投稿日（`createdAt`）の文字のまま（`GallerySort.new` と同じ比べ方）
/// - 覚えが無い（まだ1度も上に出していない）ときは、全部を新しいとして上に出す（`followingMax` まで）。
///   出したらその時点のいちばん新しい投稿日を覚える。上限で出しきれなかった古い分も既に見せたことになるが、
///   それらも 3. の新着から並びに混ざる
enum HomeFollowingNews {

    /// フォロー中の人のいちばん新しい投稿日。フォローしていない・未ログイン・該当が無いなら nil
    static func newest(_ photos: [Photo], viewerId: String?, followingIds: Set<String>) -> String? {
        guard let viewerId, !followingIds.isEmpty else { return nil }
        return GalleryScope.following.photos(photos, viewerId: viewerId, followingIds: followingIds)
            .filter { ($0.userId ?? $0.uploadedBy) != viewerId }
            .compactMap(\.createdAt)
            .max()
    }
}
