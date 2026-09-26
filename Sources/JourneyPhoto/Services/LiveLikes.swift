import Foundation

/// いいねの**いまの数**を、公開一覧に重ねる。
///
/// 公開一覧（`app/data/photos.json`）の `likes` は**サイトを建てた時点の数**で、
/// いいねを押してもサイトは建て直らない。だからホームのカードや検索の
/// 格子の数が、詳細画面（`GET /photos/{id}/like` でいまの数を読む）と
/// 食い違っていた。
///
/// 管理 API の `GET /photos` は未認証で読め、DynamoDB の `likes` をそのまま
/// 返す（Web の `usePhotos` が同じ口で一覧を差し替えている）。**一覧の中身は
/// 静的 JSON のまま**にして、数だけをここから写す——こちらが落ちても
/// 一覧は出るし、数が古いだけで済む。
enum LiveLikes {

    /// 応答から `id → likes` を作る。**読めなければ nil**（＝上書きしない）。
    ///
    /// 行ごとに緩く読む。1行が壊れているだけで全部の数を捨てない。
    /// `likes` を持たない行は 0 とみなす——API は DynamoDB の行をそのまま
    /// 返すので、**一度もいいねされていない写真は `likes` を持たない**。
    /// 読み飛ばすと、静的 JSON に残った古い数（取り消されたぶん）が出続ける。
    static func counts(from data: Data) -> [String: Int]? {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return nil }
        var out: [String: Int] = [:]
        for row in rows {
            guard let dict = row as? [String: Any],
                  let id = dict["id"] as? String, !id.isEmpty else { continue }
            let likes = (dict["likes"] as? NSNumber)?.intValue ?? 0
            out[id] = max(0, likes)
        }
        return out
    }

    /// 数を写す。**`counts` に無い写真は触らない**
    /// （公開範囲を絞った写真は `GET /photos` に載らない。そちらは
    ///  `GET /feed/restricted` がいまの数を持ってくる——時刻は
    ///  `PublicGalleryService.restrictedPhotos` が付ける）。
    ///
    /// - Parameter asOf: いまの数を取りに行った時刻。写した写真に付ける
    ///   （`LikeCountStore` の答えとどちらが新しいかを比べるため）
    static func apply(_ counts: [String: Int], asOf: Date, to photos: [Photo]) -> [Photo] {
        guard !counts.isEmpty else { return photos }
        return photos.map { photo in
            guard let live = counts[photo.id] else { return photo }
            var copy = photo
            copy.likes = live
            copy.likesAsOf = asOf
            return copy
        }
    }

    /// 土台にする数。**新しい方**を使う。
    ///
    /// - `stored`: 押した回にサーバーが答えた数（`LikeCountStore`）
    /// - 一覧の数: `photo.likes`（`likesAsOf` がその時刻。nil は静的 JSON）
    ///
    /// 答えの方が新しければ答え。一覧をあとで読み直していま数が取れたら、
    /// そちらが新しいので一覧の数（他の人が押したぶんも入る）。
    /// 以前は答えを無条件に優先していて、一度入ると引き下げ更新でも動かなかった。
    ///
    /// 🔴 **`likesAsOf` は「要求を出した時刻」で、「データの時点」ではない。**
    /// 管理 API の `GET /photos` は Lambda の中に10秒の控えを持つ
    /// （photo-gallery の `api/src/photos.ts` の `LIST_CACHE_TTL_MS`）うえ、
    /// DynamoDB の Scan は書いた直後だと古い値を返しうる。押して数秒で
    /// 引き下げ更新すると、要求は新しくても中身は押す前の数が返ってくる。
    /// だから一覧を勝たせるのは、答えより `serverStaleness` 以上あとに
    /// 取りに行った数だけ。
    static func base(for photo: Photo, stored: LikeCountStore.Entry?) -> Int? {
        guard let stored else { return photo.likes }
        if let asOf = photo.likesAsOf,
           asOf >= stored.at.addingTimeInterval(serverStaleness) {
            return photo.likes
        }
        return stored.count
    }

    /// サーバーの数が遅れうる幅。Lambda の控え（10秒）に、
    /// DynamoDB の「あとで揃う」読み方と端末・サーバーの時計のずれの余裕を足す。
    /// **API 側の控えを延ばしたら、ここも延ばすこと**
    static let serverStaleness: TimeInterval = 30

    /// カードに出す数。
    ///
    /// - `base`: サーバーが答えた数（`LikeCountStore`）、無ければ一覧の数
    ///   （`apply` 済みならいまの数）
    /// - `pendingDelta`: **押して答えを待っている間だけ**の +1 / −1
    ///
    /// 以前は「端末でいいね済みなら一覧の数に +1」だった。一覧の数には
    /// **自分のいいねが既に入っている**ので、押したことのある写真は
    /// 1つ多く出ていた。
    static func displayCount(base: Int?, pendingDelta: Int) -> Int {
        max(0, (base ?? 0) + pendingDelta)
    }
}
