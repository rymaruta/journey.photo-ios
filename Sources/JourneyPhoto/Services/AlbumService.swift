import Foundation

/// アルバム（招待リンクで人を呼べる、写真のまとまり）。
struct AlbumService {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    private func encoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private struct AlbumList: Decodable { let albums: [Album] }
    private struct CreatedAlbum: Decodable { let album: Album }

    func list() async throws -> [Album] {
        try await api.authorized(.get, "/albums", as: AlbumList.self).albums
    }

    func create(title: String) async throws -> Album {
        struct Body: Encodable { let title: String }
        return try await api.authorized(
            .post, "/albums", body: Body(title: title), as: CreatedAlbum.self
        ).album
    }

    func rename(id: String, title: String) async throws {
        struct Body: Encodable { let title: String }
        try await api.authorizedVoid(.patch, "/albums/\(encoded(id))", body: Body(title: title))
    }

    func delete(id: String) async throws {
        try await api.authorizedVoid(.delete, "/albums/\(encoded(id))")
    }

    struct Invite: Decodable {
        let token: String
        let expiresAt: String?
    }

    /// 招待リンクを作る（すでにあれば作り直す）。
    func createInvite(albumId: String) async throws -> Invite {
        try await api.authorized(.post, "/albums/\(encoded(albumId))/invite", as: Invite.self)
    }

    /// 招待リンクを取り消す。**押した瞬間に効く**（サーバーは no-store で返す）。
    func revokeInvite(albumId: String) async throws {
        try await api.authorizedVoid(.delete, "/albums/\(encoded(albumId))/invite")
    }

    struct InvitePreview: Decodable {
        let album: Album
        let photos: [Photo]
    }

    /// 招待の中身を見る（未認証で読める）。
    func invite(token: String) async throws -> InvitePreview {
        try await api.anonymous(.get, "/invites/\(encoded(token))", as: InvitePreview.self)
    }

    struct JoinResult: Decodable {
        let albumId: String
        let joined: Bool
        let already: Bool?
    }

    func join(token: String) async throws -> JoinResult {
        try await api.authorized(.post, "/invites/\(encoded(token))/join", as: JoinResult.self)
    }
}

struct Album: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let createdAt: String?
    let memberCount: Int?
    let inviteToken: String?
    let inviteExpiresAt: String?

    /// **枚数は持たない。** サーバーが返さないため（`photoIds` は消された
    /// 写真の ID を持ち続けるので、数えると嘘になる）。
    var members: Int { memberCount ?? 1 }
}
