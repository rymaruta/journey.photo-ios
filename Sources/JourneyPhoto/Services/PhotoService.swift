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

        struct Body: Encodable {
            let key: String
            let publicUrl: String
            let exif: ExifFields?
            let date: String?
            let coords: Coords?
            struct Coords: Encodable { let lat: Double; let lng: Double }
        }
        let body = Body(
            key: presigned.key,
            publicUrl: presigned.publicUrl,
            exif: prepared.exif,
            date: prepared.takenOn,
            // 送る前に端末でも丸める（投稿と同じ）
            coords: prepared.coords.map {
                Body.Coords(lat: ($0.lat * 100).rounded() / 100, lng: ($0.lng * 100).rounded() / 100)
            }
        )
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
    /// 写真に付ける曲。**`POST /upload/save` は受け取らない**ので、
    /// 投稿のあとに `PUT /photos/{id}` で付ける（`api-user/src/upload.ts` の
    /// 本文には song が無く、`photoUpdate.ts` にはある）
    var song: Photo.Song?

    var isEmpty: Bool {
        title == nil && description == nil && location == nil
            && category == nil && tags == nil && date == nil && published == nil && song == nil
    }
}
