import Foundation

/// 自分の写真の取得・公開切替・削除。
struct PhotoService {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// 自分の写真（下書き＝非公開を含む）。応答は Photo の配列そのもの。
    func myPhotos() async throws -> [Photo] {
        try await api.authorized(.get, "/user/photos", as: [Photo].self)
    }

    /// 公開範囲を絞った写真のうち、**自分に見えるぶん**。`GET /feed/restricted`。
    ///
    /// これらは静的サイトの一覧（`app/data/photos.json`）に載らないので、
    /// ここで取らないとアプリからも見えない。サーバーが
    /// 「フォロワーか」「親しい友達か」を判定して返す——**端末では決めない**。
    func restrictedFeed() async throws -> [Photo] {
        try await api.authorized(.get, "/feed/restricted", as: [Photo].self)
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
            "/photos/\(photoId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? photoId)",
            body: patch
        )
    }

    /// 写真そのものを差し替える。`PUT /photos/{id}` に `key` と `publicUrl` を送る。
    ///
    /// **サーバーは派生（AVIF・256px・寸法）を消す**（`photoReplace.ts` の
    /// `REPLACE_CLEARS`）。残すと端末によって古い写真が出続ける。
    /// 上げ方は投稿と同じ3手（presign → S3 → 保存）で、EXIF は端末で落とす。
    func replace(photoId: String, prepared: ImagePreparer.Prepared,
                 uploads: UploadService) async throws {
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
        let body = Body(replace: Replace(
            key: presigned.key,
            publicUrl: presigned.publicUrl,
            exif: prepared.exif,
            date: prepared.takenOn,
            // 送る前に端末でも丸める（投稿と同じ）
            coords: prepared.coords.map {
                Replace.Coords(lat: ($0.lat * 100).rounded() / 100, lng: ($0.lng * 100).rounded() / 100)
            }
        ))
        do {
            try await api.authorizedVoid(
                .put,
                "/photos/\(photoId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? photoId)",
                body: body
            )
        } catch {
            // 保存できなかったぶんの実体を残さない（投稿と同じ後始末）
            await uploads.discard(key: presigned.key)
            throw error
        }
    }

    /// 削除。**画像の実体と CloudFront の控えもサーバー側で消える**
    /// （`cloudfrontDistributionId` が渡されていれば。渡し忘れると
    /// 消した写真が最大1年 公開URLに残る——CLAUDE.md の LEFT-4）。
    func delete(photoId: String) async throws {
        try await api.authorizedVoid(
            .delete,
            "/photos/\(photoId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? photoId)"
        )
    }
}

/// 写真の部分更新。nil は JSON に載らない＝「触らない」。
///
/// **撮影日は 1990年以降・未来でない日付**でないとサーバーが 400 を返す。
struct PhotoPatch: Encodable {
    var title: String?
    var description: String?
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

    var isEmpty: Bool {
        title == nil && description == nil && location == nil
            && category == nil && tags == nil && date == nil && published == nil
            && song == nil && coords == nil && audience == nil
    }
}
