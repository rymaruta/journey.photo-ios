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
    static func photos(_ photos: [Photo], blocked: Set<String>, reported: Set<String>) -> [Photo] {
        guard !blocked.isEmpty || !reported.isEmpty else { return photos }
        return photos.filter { photo in
            guard !reported.contains(photo.id) else { return false }
            guard let owner = photo.userId ?? photo.uploadedBy else { return true }
            return !blocked.contains(owner)
        }
    }

    static func users(_ users: [UserProfile], blocked: Set<String>) -> [UserProfile] {
        guard !blocked.isEmpty else { return users }
        return users.filter { !blocked.contains($0.userId) }
    }
}
