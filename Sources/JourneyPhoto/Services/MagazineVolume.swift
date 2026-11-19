import Foundation

/// 雑誌の「Vol.」の番号を読む（2026-11-18・`MagazineCard.volume` が数える）。
///
/// **サーバーを変えずに数える。** `GET /user/photos`（`PhotoService.completeMyPhotos`）はサーバーが利用者の索引を
/// 最後まで読んで全件を返す（`api-user/src/ddb-photos.ts` の `listMyPhotos`・ページに分けない）。マイページの格子が
/// 少しずつ出るのは画面の出し方だけで、手元に来る一覧は全件。
/// - 読めない（圏外・鍵が無い・1行でも読めない行がある）・`wait` 秒を過ぎた → nil（「Vol.」を出さない）
/// - 投稿したばかりでまだ一覧に無い写真は `justPosted` で足す（`PostedPhotos` と同じ考え）
/// - **読むのは雑誌を描くときだけ**（2026-11-19 まとめ役の判断。共有画面を開くたびに全件を読まない）
/// - 読んだ一覧は**アプリを使っている間だけ、利用者ごとに**覚える（`Memo`・端末には残さない）。
///   投稿した（`UploadService.save`）・消した（`PhotoService.delete`）・公開を替えた（`PhotoService.update`）・
///   ログアウトした（`AuthStore.signOut`）ら忘れる。覚えた人と違う人には使わない
enum MagazineVolume {
    /// 一覧を待つ上限（秒）。雑誌の絵はこれを待ってから描く
    static let wait: Double = 6

    /// 読んだ自分の写真の一覧（メモリだけ・利用者1人ぶん）
    final class Memo: @unchecked Sendable {
        static let shared = Memo()

        private let lock = NSLock()
        private var owner: String?
        private var photos: [Photo]?

        init() {}

        /// その人の覚えた一覧。別の人の一覧なら手放して nil
        func list(for owner: String) -> [Photo]? {
            lock.lock(); defer { lock.unlock() }
            guard self.owner == owner else {
                self.owner = nil
                photos = nil
                return nil
            }
            return photos
        }

        func keep(_ list: [Photo], for owner: String) {
            lock.lock(); defer { lock.unlock() }
            self.owner = owner
            photos = list
        }

        func forget() {
            lock.lock(); defer { lock.unlock() }
            owner = nil
            photos = nil
        }
    }

    /// 投稿・削除・公開の切り替え・ログアウトのあとに呼ぶ（覚えた数え方を捨てる）
    static func forget() { Memo.shared.forget() }

    static func load(photoId: String?, justPosted: Photo?, owner: String?, photos: PhotoService,
                     memo: Memo = .shared) async -> Int? {
        guard let photoId, !photoId.isEmpty, let owner, !owner.isEmpty else { return nil }
        if let known = memo.list(for: owner) {
            return MagazineCard.volume(of: photoId, among: known, justPosted: justPosted)
        }
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
        if let list { memo.keep(list, for: owner) }
        return MagazineCard.volume(of: photoId, among: list, justPosted: justPosted)
    }
}
