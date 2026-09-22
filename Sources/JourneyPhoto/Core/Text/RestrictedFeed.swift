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
    /// - 同じ id が両方に居たら**公開側を残す**。絞りの口は本人にも返すので、
    ///   自分の写真が二重に並ぶのを防ぐ（id が同じなら中身も同じ行）
    /// - `createdAt` は文字列のまま比べる（ISO8601 なので辞書順＝時刻順）。
    ///   **欠けている行を落とさない**——空文字として一番後ろに置く。
    ///   落とすと、古い投稿が一覧から消える
    static func merge(publicPhotos: [Photo], restricted: [Photo]) -> [Photo] {
        var seen = Set(publicPhotos.map(\.id))
        var all = publicPhotos
        for photo in restricted where !seen.contains(photo.id) {
            seen.insert(photo.id)
            all.append(photo)
        }
        return all.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
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
