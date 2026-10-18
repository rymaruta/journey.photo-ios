import Foundation

/// 投稿したばかりの写真を、自分の一覧に先に並べる（純・2026-10-03）。
///
/// 投稿画面を閉じるとマイページ・ホームは自分の写真を読み直すが、`GET /user/photos` は
/// 利用者の索引（結果整合）を引くので、保存の直後は**上げた写真がまだ返らない**ことがある。
/// 保存の応答で受け取った行（`UploadViewModel.onSaved`）を先に足し、読み直しの結果と合わせる。
///
/// 合わせ方は限定公開の混ぜ方（`RestrictedFeed.merge`）をそのまま使う:
/// - 同じ id は**読み直した行を採る**（サーバーの今の行。保存の応答は画像の URL に署名が付いていない）
/// - 新しい順に並べる（`createdAt`。`GET /user/photos` もこの順・保存の応答にも入っている）
enum PostedPhotos {

    /// 先に足す控えを持つ時間（秒）。
    ///
    /// 2026-10-03 判断: 60秒。索引の遅れはふつう数秒で、控えを長く持つと、その間に消した・
    /// 非公開にした写真が読み直しのたびに戻ってくる。控えは読み直しが1回終われば（成功・失敗・
    /// 取り消しのどれでも）手放すので、これは読み直しが走らなかったときの上限
    static let keepSeconds: TimeInterval = 60

    /// 先に足す控え（保存の応答の行と、受け取った時刻）
    struct Pending {
        let photos: [Photo]
        let receivedAt: Date

        /// `now` の時点でまだ使ってよい行。`keepSeconds` を過ぎていたら空
        func photos(at now: Date) -> [Photo] {
            now.timeIntervalSince(receivedAt) <= PostedPhotos.keepSeconds ? photos : []
        }
    }

    /// `loaded` に、投稿したばかりの `posted` を足す。**持ち主が違う行は足さない**
    /// （投稿のあとに人が替わった）。足すものが無ければ `loaded` をそのまま返す（並びを変えない）
    static func merge(loaded: [Photo], posted: [Photo], owner: String?) -> [Photo] {
        guard let owner else { return loaded }
        let mine = posted.filter { $0.userId == owner }
        guard !mine.isEmpty else { return loaded }
        return RestrictedFeed.merge(publicPhotos: mine, restricted: loaded)
    }

    /// マイページの格子に先に出してよい行。**公開範囲を絞った写真は出さない**——保存の応答の
    /// 画像の URL には署名が付いておらず、`/private/` を指す行は CloudFront に断られて画像が出ない。
    /// 絞った写真は読み直し（署名付き・`/user/photos`）で並ぶ
    static func showable(_ posted: [Photo]) -> [Photo] {
        posted.filter { !RestrictedFeed.isRestricted($0) && !$0.src.contains("/private/") }
    }

    // MARK: - 公開の一覧に重ねる（2026-10-16）

    /// 公開の一覧（探す・地図・ホームのおすすめ）に先に重ねてよい行。
    /// **公開範囲を絞った写真・下書き（非公開で上げた写真）は出さない**——ほかの人にも見える一覧なので、
    /// 公開（`published == true`）と分かっている行だけ。分からない行（nil）も出さない
    static func publicShowable(_ posted: [Photo]) -> [Photo] {
        showable(posted).filter { $0.published == true }
    }

    /// 公開の一覧に、投稿したばかりの公開写真を重ねる。**同じ id は読んだ行を採る**（`merge` と同じ）。
    /// 重ねるものが無ければ `loaded` をそのまま返す（並びを変えない）
    static func overlayPublic(loaded: [Photo], posted: [Photo]) -> [Photo] {
        let shown = publicShowable(posted)
        guard !shown.isEmpty else { return loaded }
        return RestrictedFeed.merge(publicPhotos: shown, restricted: loaded)
    }

    /// 投稿したばかりの写真の控え（画面をまたいで共有する・`PhotoEditLedger` と同じ形）。
    ///
    /// 🔴 **新しい投稿が探す・地図・ホームのおすすめに最大60秒出なかった**（公開の一覧の控え
    /// `PublicGalleryService.cacheLifetime`）。マイページ・ホームの自分の写真は `TabRouter.lastPosted` を
    /// 先に並べていたが、公開の一覧には重ねていなかった。書くのは `TabRouter.postSheetClosed`、
    /// 重ねるのは `PublicGalleryService.merged`（主スレッドと actor の両方から触るので鍵で守る）。
    /// 控えは `keepSeconds` を過ぎたら使わない——その頃には一覧の控えも取り直している
    final class Ledger: @unchecked Sendable {
        static let shared = Ledger()

        private let lock = NSLock()
        private var pending: Pending?

        init() {}

        /// 投稿画面で上がった写真を控える。**空なら前の控えを残す**（何も上げずに閉じた回で消さない）
        func note(_ photos: [Photo], at now: Date = Date()) {
            guard !photos.isEmpty else { return }
            lock.lock(); defer { lock.unlock() }
            pending = Pending(photos: photos, receivedAt: now)
        }

        /// `now` の時点で重ねてよい行（期限を過ぎていたら空）
        func photos(at now: Date = Date()) -> [Photo] {
            lock.lock(); defer { lock.unlock() }
            return pending?.photos(at: now) ?? []
        }

        func clear() {
            lock.lock(); defer { lock.unlock() }
            pending = nil
        }
    }
}
