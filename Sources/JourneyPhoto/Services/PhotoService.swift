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

    /// 公開 / 非公開の切り替え。`PUT /photos/{id}`。
    func setPublished(photoId: String, published: Bool) async throws {
        struct Body: Encodable { let published: Bool }
        try await api.authorizedVoid(
            .put,
            "/photos/\(photoId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? photoId)",
            body: Body(published: published)
        )
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
