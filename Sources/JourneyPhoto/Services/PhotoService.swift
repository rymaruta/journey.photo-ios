import Foundation

/// 自分の写真の取得・公開切替・削除。
struct PhotoService {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// パスに入れる ID。**英数字・`-`・`_` 以外は要求を出さずに失敗にする**（`PathID`）
    private func encoded(_ value: String) throws -> String {
        try PathID.segment(value)
    }

    /// 自分の写真（下書き＝非公開を含む）。応答は Photo の配列そのもの。
    ///
    /// **1行ずつ緩く読む**（公開一覧と同じ `LenientPhotoList`）。`[Photo]` で
    /// 読むと、1行でも形が違えば一覧ごと落ち、マイページが丸ごとエラーになる
    func myPhotos() async throws -> [Photo] {
        try Self.kept(try await api.authorized(.get, "/user/photos", as: LenientPhotoList.self), from: "/user/photos")
    }

    /// 公開範囲を絞った写真のうち、**自分に見えるぶん**。`GET /feed/restricted`。
    ///
    /// これらは静的サイトの一覧（`app/data/photos.json`）に載らないので、
    /// ここで取らないとアプリからも見えない。サーバーが
    /// 「フォロワーか」「親しい友達か」を判定して返す——**端末では決めない**。
    ///
    /// **1行ずつ緩く読む。** 公開一覧の側（`PublicGalleryService`）はここの失敗を
    /// 黙って空にするので、1行の崩れで限定写真が全部消えていた
    func restrictedFeed() async throws -> [Photo] {
        try Self.kept(try await api.authorized(.get, "/feed/restricted", as: LenientPhotoList.self), from: "/feed/restricted")
    }

    /// 読めた行を返す。**落とした行は黙って捨てない**（記録に残す）
    ///
    /// 🔴 **1行も読めなかったら失敗にする。** 空の一覧で成功にすると、
    /// マイページが「まだ写真がありません」を出し、限定写真は前回の控えを
    /// 空で上書きする（公開一覧の `fetchStaticList` と同じ守り）
    private static func kept(_ list: LenientPhotoList, from path: String) throws -> [Photo] {
        if list.dropped > 0 {
            print("[photos] \(path): 読めなかった写真の行を \(list.dropped) 件落としました")
        }
        if list.photos.isEmpty && list.dropped > 0 {
            throw APIError.decoding("\(path): 写真の行を1件も読めませんでした")
        }
        return list.photos
    }

    /// 自分の写真を1枚だけ引き直す。
    ///
    /// **編集したあとに画面を作り直すため。** 個別に引く口はサーバーに
    /// 無いので、自分の一覧から拾う（編集できるのは本人だけなので足りる）。
    /// **見つからなくても投げない**——消した直後などに 1件も無いのは
    /// 異常ではなく、呼ぶ側は「変えない」で済ませたい。
    func myPhoto(id: String) async throws -> Photo? {
        try await myPhotos().first { $0.id == id }
    }

    /// 写真の中身を書き換える。`PUT /photos/{id}`。
    ///
    /// **送った項目だけが変わる。** 何も送らないと 400「更新項目がありません」。
    func update(photoId: String, patch: PhotoPatch) async throws {
        try await api.authorizedVoid(
            .put,
            "/photos/\(encoded(photoId))",
            body: patch
        )
    }

    /// 写真そのものを差し替える。`PUT /photos/{id}` に `key` と `publicUrl` を送る。
    ///
    /// **サーバーは派生（AVIF・256px・寸法）を消す**（`photoReplace.ts` の
    /// `REPLACE_CLEARS`）。残すと端末によって古い写真が出続ける。
    /// 上げ方は投稿と同じ3手（presign → S3 → 保存）で、EXIF は端末で落とす。
    /// - Parameter keepCoords: 新しい写真の座標を書くか（`EditPlaceRules.keepsCoordsOnReplace`）。
    ///   ピンの無い写真・撮影地を消した写真では false——外した位置が戻らないように
    /// - Returns: **撮影日を載せずに差し替えたか**（`replaceDate` が落とした）。
    ///   true なら保存済みの撮影日は前のまま残る——画面で知らせる（黙って古い日付が残らないように）
    @discardableResult
    func replace(photoId: String, prepared: ImagePreparer.Prepared,
                 uploads: UploadService, keepCoords: Bool = true) async throws -> Bool {
        // ID の形は**上げる前に**確かめる（上げ切ってから弾くと、実体が無駄に残る）
        _ = try encoded(photoId)
        // **投稿と同じ関所を通す。** 50MB と対応形式はサーバーも見るが、
        // 手前で弾かないと、上げ切ってから 400 を食う（投稿側と同じ理由）
        try UploadService.checkAcceptable(size: prepared.data.count, type: prepared.contentType)
        let presigned = try await uploads.presign(
            fileName: prepared.fileName,
            fileType: prepared.contentType,
            fileSize: prepared.data.count
        )
        do {
            try await uploads.put(data: prepared.data, to: presigned)
        } catch {
            await uploads.discard(key: presigned.key)
            throw error
        }

        // **`replace` で包む。** サーバーは `body.replace` しか見ない
        // （`photoUpdate.ts` の `hasReplace`）。包まないと、包まれていない
        // 項目だけが「中身の更新」として通り、**画像は古いまま
        // 撮影日と座標だけ黙って上書き**される（Web は包んでいる）。
        struct Body: Encodable { let replace: Replace }
        struct Replace: Encodable {
            let key: String
            let publicUrl: String
            let exif: ExifFields?
            let date: String?
            let coords: Coords?
            struct Coords: Encodable { let lat: Double; let lng: Double }
        }
        // サーバーが弾く撮影日は載せない（載せると差し替えごと 400）
        let date = Self.replaceDate(prepared.takenOn)
        let body = Body(replace: Replace(
            key: presigned.key,
            publicUrl: presigned.publicUrl,
            exif: prepared.exif,
            date: date,
            // 送る前に端末でも丸める（投稿と同じ）
            coords: (keepCoords ? prepared.coords : nil).map {
                Replace.Coords(lat: ($0.lat * 100).rounded() / 100, lng: ($0.lng * 100).rounded() / 100)
            }
        ))
        do {
            try await api.authorizedVoid(
                .put,
                "/photos/\(encoded(photoId))",
                body: body
            )
        } catch {
            // 保存できなかったぶんの実体を残さない（投稿と同じ後始末）
            await uploads.discard(key: presigned.key)
            throw error
        }
        return prepared.takenOn != nil && date == nil
    }

    /// 差し替えに載せる撮影日。**サーバーが弾く日付なら nil（送らない）。**
    ///
    /// `photoUpdate.ts` は `replace.date` が読めない（1990年より前・未来）と
    /// `dateWasRejected` で**差し替えごと 400** にする。カメラの日付未設定
    /// （1970・1980）の EXIF を持つ写真で、写真そのものが差し替えられなかった。
    /// 境界は `sanitize.ts` の `sanitizeDate` と同じ（UTC の年が 1990 未満・今より24時間先を超える）
    static func replaceDate(_ takenOn: String?, now: Date = Date()) -> String? {
        guard let takenOn else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: takenOn) else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard utc.component(.year, from: date) >= 1990,
              date <= now.addingTimeInterval(24 * 60 * 60) else { return nil }
        return takenOn
    }

    /// 削除。**画像の実体と CloudFront の控えもサーバー側で消える**
    /// （`cloudfrontDistributionId` が渡されていれば。渡し忘れると
    /// 消した写真が最大1年 公開URLに残る——CLAUDE.md の LEFT-4）。
    /// 写真を消す。**404（もう無い）は消せたのと同じ**（別の端末で先に消した回。
    /// `photoUpdate.ts` の `deleteMyPhoto` は行が無ければ 404）。失敗と読むと、
    /// もう無い写真の画面に留まり、削除を押すたびにエラーになる
    func delete(photoId: String) async throws {
        do {
            try await api.authorizedVoid(
                .delete,
                "/photos/\(encoded(photoId))"
            )
        } catch where SocialService.isNotFound(error) {
            return
        }
    }
}

/// 写真の部分更新。nil は JSON に載らない＝「触らない」。
///
/// **撮影日は 1990年以降・未来でない日付**でないとサーバーが 400 を返す。
struct PhotoPatch: Encodable {
    /// 題・説明。**`{ja, en}` の写真で英語を消さない形**を `LocalizedEdit` が作る
    var title: LocalizedPatchValue?
    var description: LocalizedPatchValue?
    var location: String?
    var category: String?
    var tags: [String]?
    var date: String?
    var published: Bool?
    /// 撮影地の座標。**候補から選んだときだけ送る。**
    ///
    /// 送らずに `location` だけ変えると、サーバーは
    /// 「地名から起こした座標（`geoApprox`）」を**消す**
    /// （`photoUpdate.ts`。新しい地名に古い近似座標は合わないため）。
    /// ＝**撮影地を直した写真が地図から消える**。候補から選んだ回は
    /// 座標も一緒に送って、地図に残す。
    var coords: Photo.Coords?
    /// 写真に付ける曲。**`POST /upload/save` は受け取らない**ので、
    /// 投稿のあとに `PUT /photos/{id}` で付ける（`api-user/src/upload.ts` の
    /// 本文には song が無く、`photoUpdate.ts` にはある）
    var song: Photo.Song?

    /// 公開範囲。**`nil` は「触らない」**。外すときは空文字を送る
    /// ——キーが本文に無いと、サーバーは既にある印をそのまま残す
    /// （`photoUpdate.ts` の `hasAudience`）。`Audience.patchValue` が作る。
    var audience: String?

    /// 座標を**消す**（本文に `"coords": null` を載せる）。
    ///
    /// `coords` の `nil` は「触らない」なので、それだけでは消せない——撮影地を
    /// 空にして保存しても座標が残り、地図とページに約1kmのピンが立ち続けていた。
    /// サーバーは `"coords" in body` で見て、使えない値（null）なら消す
    /// （`photoUpdate.ts` の `applyMeta("coords", …)`）
    var clearCoords = false

    var isEmpty: Bool {
        title == nil && description == nil && location == nil
            && category == nil && tags == nil && date == nil && published == nil
            && song == nil && coords == nil && audience == nil && !clearCoords
    }

    private enum CodingKeys: String, CodingKey {
        case title, description, location, category, tags, date, published, coords, song, audience
    }

    /// 自動生成と同じく **nil のキーは載せない**。`clearCoords` のときだけ
    /// `coords: null` を明示する
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(location, forKey: .location)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(tags, forKey: .tags)
        try c.encodeIfPresent(date, forKey: .date)
        try c.encodeIfPresent(published, forKey: .published)
        if let coords {
            try c.encode(coords, forKey: .coords)
        } else if clearCoords {
            try c.encodeNil(forKey: .coords)
        }
        try c.encodeIfPresent(song, forKey: .song)
        try c.encodeIfPresent(audience, forKey: .audience)
    }
}
