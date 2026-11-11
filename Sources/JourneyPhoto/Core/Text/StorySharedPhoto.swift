import Foundation

/// **ストーリーで紹介された写真を開く**（2026-11-11・札 #541 の ①）。見る画面の「写真を見る」が使う。
///
/// 紹介できるのは全体に公開した写真だけ（`api-user/src/storyPhotoShare.ts`）なので、**公開の一覧から引き当てる**
/// （「この写真を見て撮影」の元の写真と同じ引き当て方・`InspiredBy.photoToOpen`）。一覧に無い——持ち主が
/// 非公開にした直後・消した・一覧の控えが古い——ときは開かずに知らせる（空の詳細を開かない）。
/// 写真がもう見られないストーリーは、サーバーが本人以外にはそもそも返さない
enum StorySharedPhoto {

    static func find(_ id: String, in feed: [Photo]?) -> Photo? {
        guard PathID.isSafe(id) else { return nil }
        return feed?.first { $0.id == id }
    }

    static let unavailableMessage = L("この写真は今は開けません", "This photo can't be opened right now")
}
