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

    /// `loaded` に、投稿したばかりの `posted` を足す。**持ち主が違う行は足さない**
    /// （投稿のあとに人が替わった）。足すものが無ければ `loaded` をそのまま返す（並びを変えない）
    static func merge(loaded: [Photo], posted: [Photo], owner: String?) -> [Photo] {
        guard let owner else { return loaded }
        let mine = posted.filter { $0.userId == owner }
        guard !mine.isEmpty else { return loaded }
        return RestrictedFeed.merge(publicPhotos: mine, restricted: loaded)
    }
}
