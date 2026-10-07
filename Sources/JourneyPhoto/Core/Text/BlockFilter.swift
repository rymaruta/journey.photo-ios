import Foundation

/// ブロックした人を画面から外す（審査 1.2）。
///
/// **サーバーが絞らない口の分だけ、端末で落とす。** コメントの一覧
/// （`GET /photos/{id}/comments`）と人の検索（`/users/search`）はログイン不要の口で、
/// 誰がブロックしたかを知らない。ストーリーの返信は前から端末で落としていた
/// （`StoryViewerView`）のに、この2つだけ抜けていた。
///
/// **画面の外に置く**（`Shims/` の模型では `View` の中を動かせないので、試験のため）。
enum BlockFilter {
    static func comments(_ comments: [PhotoComment], blocked: Set<String>) -> [PhotoComment] {
        guard !blocked.isEmpty else { return comments }
        return comments.filter { !blocked.contains($0.uid) }
    }

    /// 写真: 通報した1枚と、ブロックした人の写真を落とす。
    /// **公開一覧（`PublicGalleryService.visible`）と画面の両方がこれを通る**
    /// ——基準を2か所に書くと、片方だけ直して黙ってずれる
    ///
    /// - Parameter gone: 自分で消した・非公開にした写真（`ModerationStore.gonePhotoIds`）。
    ///   **公開の写し（`published` が false でない行）だけを落とす。** 公開一覧は
    ///   サイトの建て直し（数分）まで古く、端末にも控え（`PhotoSnapshotStore`）が残るので、
    ///   消した写真がホーム・探す・地図に出続け、開くと いいね・保存・コメントが 404 になった。
    ///   自分の一覧（マイページ）が持つ非公開の写しは `published: false` なので残る——
    ///   非公開にした自分の写真まで自分の画面から消さない
    static func photos(_ photos: [Photo], blocked: Set<String>, reported: Set<String>,
                       gone: Set<String> = []) -> [Photo] {
        guard !blocked.isEmpty || !reported.isEmpty || !gone.isEmpty else { return photos }
        return photos.filter { photo in
            guard !reported.contains(photo.id) else { return false }
            if gone.contains(photo.id), photo.published != false { return false }
            guard let owner = photo.userId ?? photo.uploadedBy else { return true }
            return !blocked.contains(owner)
        }
    }

    static func users(_ users: [UserProfile], blocked: Set<String>) -> [UserProfile] {
        guard !blocked.isEmpty else { return users }
        return users.filter { !blocked.contains($0.userId) }
    }

    /// ストーリーを見た人（`GET /stories/{id}/viewers`）。行からその人のページへ行き、
    /// そこでブロックできる
    static func viewers(_ viewers: [StoryViewer], blocked: Set<String>) -> [StoryViewer] {
        guard !blocked.isEmpty else { return viewers }
        return viewers.filter { !blocked.contains($0.userId) }
    }

    /// ストーリーの返信と反応（`GET /stories/{id}/replies`）。ブロックした人の分を落とす（2026-10-07）。
    /// 落としてから数える——「いいね」「返信」の数がブロックした人を含み、一覧と合わなかった。
    /// 相手の分からない行（`uid` が無い）は落とさない
    static func replies(_ replies: [StoryReply], blocked: Set<String>) -> [StoryReply] {
        guard !blocked.isEmpty else { return replies }
        return replies.filter { reply in reply.uid.map { !blocked.contains($0) } ?? true }
    }

    /// フォロー中・フォロワーの一覧（`FollowListView`）。ブロックした人の行に
    /// 「フォローする」が残り、押すとサーバーが 400 を返していた
    static func follows(_ users: [FollowUser], blocked: Set<String>) -> [FollowUser] {
        guard !blocked.isEmpty else { return users }
        return users.filter { !blocked.contains($0.id) }
    }
}
