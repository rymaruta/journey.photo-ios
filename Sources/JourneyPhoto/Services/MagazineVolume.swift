import Foundation

/// 雑誌の「Vol.」の番号を読む（2026-11-18・`MagazineCard.volume` が数える）。
///
/// **サーバーを変えずに数える。** `GET /user/photos`（`PhotoService.completeMyPhotos`）はサーバーが利用者の索引を
/// 最後まで読んで全件を返す（`api-user/src/ddb-photos.ts` の `listMyPhotos`・ページに分けない）。マイページの格子が
/// 少しずつ出るのは画面の出し方だけで、手元に来る一覧は全件。
/// - 読めない（圏外・鍵が無い・1行でも読めない行がある）・`wait` 秒を過ぎた → nil（「Vol.」を出さない）
/// - 投稿したばかりでまだ一覧に無い写真は `justPosted` で足す（`PostedPhotos` と同じ考え）
enum MagazineVolume {
    /// 一覧を待つ上限（秒）。雑誌の絵はこれを待ってから描く
    static let wait: Double = 6

    static func load(photoId: String?, justPosted: Photo?, photos: PhotoService) async -> Int? {
        guard let photoId, !photoId.isEmpty else { return nil }
        let list: [Photo]? = await withTaskGroup(of: [Photo]?.self) { group in
            group.addTask { try? await photos.completeMyPhotos() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        return MagazineCard.volume(of: photoId, among: list, justPosted: justPosted)
    }
}
