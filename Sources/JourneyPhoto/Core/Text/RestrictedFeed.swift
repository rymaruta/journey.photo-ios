import Foundation

/// 公開範囲を絞った写真を、公開一覧に足す。
///
/// **なぜ足す必要があるのか。** 公開一覧は静的サイトの
/// `app/data/photos.json` を読んでいるが、絞った写真はそこに**載らない**
/// （載せた時点で「フォロワーだけ」を守れないので、
/// `scripts/sync-photos-from-ddb.js` が落としている）。だから
/// `GET /feed/restricted` で別に取って、ここで1本にする。
enum RestrictedFeed {

    /// 2本を混ぜて新しい順に並べる。
    ///
    /// - 同じ id が両方に居たら**絞りの口の行を採る**（二重には並べない）。
    ///   絞りの口は DynamoDB から直に来る今の行で、公開側は建て直しまで古い静的 JSON。
    ///   🔴 以前は公開側を残していたので、公開→フォロワー限定に変えた写真が
    ///   古い公開の行（建て直しで消える画像の URL・印の無い `audience`）のまま出て、
    ///   画像が出ず、「フォロワーのみ」の札も付かなかった
    /// - `createdAt` は文字列のまま比べる（ISO8601 なので辞書順＝時刻順）。
    ///   **欠けている行を落とさない**——空文字として一番後ろに置く。
    ///   落とすと、古い投稿が一覧から消える
    static func merge(publicPhotos: [Photo], restricted: [Photo]) -> [Photo] {
        // 絞りの口の中で同じ id が2度来ても1行（先の行を採る）
        var restrictedIds = Set<String>()
        var all: [Photo] = []
        for photo in restricted where restrictedIds.insert(photo.id).inserted {
            all.append(photo)
        }
        all.append(contentsOf: publicPhotos.filter { !restrictedIds.contains($0.id) })
        return all.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
    }

    /// **ページで読んだ公開写真**（`GET /feed`）に、絞ったぶんを混ぜる。
    ///
    /// 混ぜるのは**読んだところまでの範囲**（いちばん古い公開写真の `createdAt` 以降）に
    /// 入る行だけ。全部混ぜると、まだ読んでいない古い時期の限定写真が1ページ目の
    /// 末尾に並び、次のページを読むと間に公開写真が割り込んで並びが入れ替わる。
    /// 最後まで読んだ（`reachedEnd`）なら全部混ぜる（`merge` と同じ）
    static func mergeLoaded(publicPhotos: [Photo], restricted: [Photo], reachedEnd: Bool) -> [Photo] {
        if reachedEnd { return merge(publicPhotos: publicPhotos, restricted: restricted) }
        guard let oldest = publicPhotos.compactMap(\.createdAt).filter({ !$0.isEmpty }).min() else {
            // まだ1枚も読めていない（または日付の無い行だけ）——範囲が決まらないので混ぜない
            return merge(publicPhotos: publicPhotos, restricted: [])
        }
        let inRange = restricted.filter { ($0.createdAt ?? "") >= oldest }
        return merge(publicPhotos: publicPhotos, restricted: inRange)
    }

    /// 絞られている写真か（画面に印を出すため）。
    ///
    /// **知らない値は「絞られている」に倒す。** サーバーが選択肢を増やした
    /// ときに、古いアプリが「全体に公開」として見せてしまわないように。
    static func isRestricted(_ photo: Photo) -> Bool {
        guard let audience = photo.audience, !audience.isEmpty else { return false }
        return true
    }

    /// 印の文言。分からない値のときは**広げずに**ぼかす
    static func badge(_ photo: Photo) -> String? {
        guard let raw = photo.audience, !raw.isEmpty else { return nil }
        if let known = Audience(rawValue: raw), known != .everyone { return known.label }
        return L("公開範囲を絞っています", "Limited audience")
    }
}
