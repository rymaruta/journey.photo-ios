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
}
