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
