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
    ///  `GET /feed/restricted` がいまの数を持ってくる）。
    static func apply(_ counts: [String: Int], to photos: [Photo]) -> [Photo] {
        guard !counts.isEmpty else { return photos }
        return photos.map { photo in
            guard let live = counts[photo.id], live != (photo.likes ?? 0) else { return photo }
            var copy = photo
            copy.likes = live
            return copy
        }
    }

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
