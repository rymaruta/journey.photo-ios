import Foundation

/// いいねの**いまの数**を、公開一覧に重ねる。
///
/// 公開一覧（`app/data/photos.json`）の `likes` は**サイトを建てた時点の数**で、
/// いいねを押してもサイトは建て直らない。だからホームのカードや検索の
/// 格子の数が、詳細画面（`GET /photos/{id}/like` でいまの数を読む）と
/// 食い違っていた。
///
/// 管理 API の `GET /photos` は未認証で読め、DynamoDB の `likes` をそのまま
/// 返す（Web の `usePhotos` が同じ口で一覧を差し替えている）。
///
/// 2026-10-16 判断: **一覧の中身もこの答えで置き換える**（`read`・`list`）。以前は数だけを
/// 写し、`photos.json` に無い id を捨てていた。サイトの作り直しが見送られて定期ビルドも
/// 止まり、`photos.json` は 2026-09-28 の 44 件で止まっている——Web では見える写真（題「焚き火🔥」）
/// が iOS のホームのおすすめ・探す・地図などに出なかった。Web の `usePhotos` と同じ決まりにそろえる:
/// - 答えが**空でない配列**なら、その並びで置き換える（同じ id は生の行が正）
/// - 失敗・空・配列でない答えなら、今までどおり `photos.json`
/// こちらが落ちても一覧は出る（静的 JSON に戻るだけ）
enum LiveLikes {

    /// `GET /photos` の答えを読んだもの。**1回の要求から、数と行の両方を作る**（二重に叩かない）
    struct Snapshot {
        /// `id → likes`（`counts(from:)`）
        let counts: [String: Int]
        /// 答えの行の id。**答えの並び**（サーバーが `createdAt` の新しい順に並べている）
        let ids: [String]
        /// 写真として読めた行（`LenientPhotoList`）
        let photos: [String: Photo]
    }

    /// 答えを読む。**読めなければ nil**（＝置き換えない・数も写さない）。
    ///
    /// 行は `LenientPhotoList`（`photos.json` と同じ緩い読み方）で読む。
    /// 写真として読めない行（`src` が無いなど）でも id と数は残す——`list` がその id を
    /// `photos.json` の行で埋める（1行の型違いで、在る写真を一覧から消さない）
    static func read(_ data: Data) -> Snapshot? {
        guard let counts = counts(from: data),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return nil }
        var ids: [String] = []
        var seen = Set<String>()
        for row in rows {
            guard let dict = row as? [String: Any],
                  let id = dict["id"] as? String, !id.isEmpty, seen.insert(id).inserted else { continue }
            // 公開範囲を絞った行は**id ごと**一覧に入れない（`isRestrictedRow`）
            if isRestrictedRow(dict["audience"]) { continue }
            ids.append(id)
        }
        let decoded = (try? JSONDecoder.api.decode(LenientPhotoList.self, from: data))?.photos ?? []
        let photos = Dictionary(decoded.filter { !isRestrictedRow($0.audience) }.map { ($0.id, $0) },
                                uniquingKeysWith: { first, _ in first })
        return Snapshot(counts: counts, ids: ids, photos: photos)
    }

    /// 公開範囲を絞った行か。**サーバーの `isRestricted`（`api/src/photos.ts`）と同じ線**——空でない
    /// 文字列、または null 以外の値なら絞った行とみなす（知らない値も隠す側に倒す）。
    ///
    /// 2026-10-16 判断: `GET /photos` は絞った行を返さない（Scan の `attribute_not_exists(audience)`）が、
    /// 念のため端末でも落とす。限定公開は `GET /feed/restricted` から `RestrictedFeed.merge` が別に重ねる
    /// ——生の行で混ざると、見てよい人の判定（サーバーの `isVisiblePhoto`）を通らずに出てしまう
    static func isRestrictedRow(_ audience: Any?) -> Bool {
        switch audience {
        case nil, is NSNull: return false
        case let text as String: return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return true
        }
    }

    /// 一覧の元。**Web の `usePhotos` と同じ決まり**（2026-10-16 判断）。
    ///
    /// - `live` が無い・行が0件 → `photos.json`（数も写さない＝今までどおり）
    /// - それ以外 → **答えの並びで置き換える。** 同じ id は生の行が正。生の行が写真として
    ///   読めなかった id だけ `photos.json` の行で埋める。答えに無い `photos.json` の行は
    ///   出さない（サーバーで消した・非公開にした写真。Web も置き換えで消えている）
    /// - 数といまの時刻（`asOf`）は、置き換えた一覧の全部に写す（`apply`）
    ///
    /// 絞り込み（公開範囲・ブロック・通報・消した写真・`published`）はここでは掛けない。
    /// 呼ぶ側（`PublicGalleryService.merged`）が、合わせた後に必ず通す
    static func list(live: Snapshot?, asOf: Date, static staticPhotos: [Photo]) -> [Photo] {
        guard let live, !live.ids.isEmpty else { return staticPhotos }
        let staticById = Dictionary(staticPhotos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let replaced = live.ids.compactMap { live.photos[$0] ?? staticById[$0] }
            .filter { !isRestrictedRow($0.audience) }
        // 1行も写真にできなかった答え（形の変わった答えなど）で一覧を空にしない。数だけ写す
        guard !replaced.isEmpty else { return apply(live.counts, asOf: asOf, to: staticPhotos) }
        return apply(live.counts, asOf: asOf, to: replaced)
    }

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
        if readSupersedes(readAt: photo.likesAsOf, answeredAt: stored.at) {
            return photo.likes
        }
        return stored.count
    }

    /// 読んだ数（と自分のいいね）が、押した回の答えより新しいとみなせるか。
    ///
    /// **読んだのが答えから `serverStaleness` 以上あとのときだけ真。** 読み取りは
    /// 結果整合で控えも挟む（上の説明）ので、押した直後に読むと押す前の数・印が返る。
    /// 一覧の数（`base`）と詳細画面の読み込み（`PhotoDetailViewModel.load`）で
    /// 同じ判断を使う
    ///
    /// - Parameters:
    ///   - readAt: 読みに行った時刻。nil（静的 JSON など時刻が分からない）は負け
    ///   - answeredAt: 押した回の答えの時刻。nil（押していない）なら読んだ方が勝つ
    static func readSupersedes(readAt: Date?, answeredAt: Date?) -> Bool {
        guard let answeredAt else { return true }
        guard let readAt else { return false }
        return readAt >= answeredAt.addingTimeInterval(serverStaleness)
    }

    /// 端末の控え（`FavoritesStore` のハート）で、画面のハートを書き換えてよいか。
    ///
    /// **サーバーで確かめたハートは、それより新しい押した答え（`LikeCountStore.Entry.at`）の
    /// ときだけ控えで書き換える。** 確かめていなければ控えを出す（圏外で開いた回の白を避ける）。
    /// 2026-10-03: 大きく見る画面を閉じた後の `.task` が、確かめた♥を控えの白で上書きしていた
    ///
    /// - Parameters:
    ///   - confirmedAt: 今の1枚のハートをサーバーで確かめた時刻。nil なら確かめていない
    ///   - answeredAt: 控えに入った押した答えの時刻。nil なら答えは無い
    static func storedLikedWins(confirmedAt: Date?, answeredAt: Date?) -> Bool {
        guard let confirmedAt else { return true }
        guard let answeredAt else { return false }
        return answeredAt > confirmedAt
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

    /// ダブルタップ（付けるだけ）が届かなかったときの状態＝**押す前の値**。
    ///
    /// 以前は無条件に「外した」にしていたので、元からいいね済みの写真で
    /// 送りに失敗すると、端末の控えでは外れた扱いになった
    /// （ハートのほうは前から押す前の値に戻している）
    static func likedAfterFailedDoubleTap(wasLiked: Bool) -> Bool {
        wasLiked
    }
}
