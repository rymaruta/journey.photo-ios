import Foundation

/// いいね・コメント・フォロー。api-user の対応する口をそのまま包む。
struct SocialService {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    private func encoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    // MARK: - いいね

    struct LikeCount: Decodable { let likes: Int }
    struct MyLike: Decodable { let liked: Bool }
    /// 押した直後の状態。**件数も一緒に返る**ので、こちらで足し算しない
    /// （二重に押した回や、既に押していた回で数がずれる）。
    struct LikeResult: Decodable { let liked: Bool; let likes: Int? }

    /// いいね数（未認証で読める）。
    func likeCount(photoId: String) async throws -> Int {
        try await api.anonymous(.get, "/photos/\(encoded(photoId))/like", as: LikeCount.self).likes
    }

    /// 自分が押しているか（要ログイン）。
    func myLike(photoId: String) async throws -> Bool {
        try await api.authorized(.get, "/user/likes/\(encoded(photoId))", as: MyLike.self).liked
    }

    func like(photoId: String) async throws -> LikeResult {
        try await api.authorized(.post, "/photos/\(encoded(photoId))/like", as: LikeResult.self)
    }

    func unlike(photoId: String) async throws -> LikeResult {
        try await api.authorized(.delete, "/photos/\(encoded(photoId))/like", as: LikeResult.self)
    }

    // MARK: - コメント

    struct CommentPage: Decodable {
        let items: [PhotoComment]
        let count: Int
    }
    private struct PostedComment: Decodable { let comment: PhotoComment }

    /// コメント一覧（未認証で読める。新しい順）。
    func comments(photoId: String) async throws -> CommentPage {
        try await api.anonymous(.get, "/photos/\(encoded(photoId))/comments", as: CommentPage.self)
    }

    func postComment(photoId: String, text: String) async throws -> PhotoComment {
        struct Body: Encodable { let text: String }
        return try await api.authorized(
            .post, "/photos/\(encoded(photoId))/comments",
            body: Body(text: text), as: PostedComment.self
        ).comment
    }

    func deleteComment(photoId: String, commentId: String) async throws {
        try await api.authorizedVoid(
            .delete, "/photos/\(encoded(photoId))/comments/\(encoded(commentId))"
        )
    }

    // MARK: - フォロー

    struct FollowStats: Decodable {
        let followers: Int
        let following: Int
    }
    struct FollowResult: Decodable {
        let following: Bool
        let followers: Int
    }
    struct FollowList: Decodable {
        let users: [FollowUser]
        /// 数え札（`followstats#`）の値。**一覧の長さとは一致しない**
        /// ——50人で切ったぶん・一覧が追いついていないぶん・ブロックで
        /// 落としたぶんがあるため（`api-user/src/follow.ts` の注記）。
        let total: Int
    }

    /// 誰でも読める（フォロワー数・フォロー数）。
    func followStats(userId: String) async throws -> FollowStats {
        try await api.anonymous(.get, "/users/\(encoded(userId))/follow", as: FollowStats.self)
    }

    func follow(userId: String) async throws -> FollowResult {
        try await api.authorized(.post, "/users/\(encoded(userId))/follow", as: FollowResult.self)
    }

    func unfollow(userId: String) async throws -> FollowResult {
        try await api.authorized(.delete, "/users/\(encoded(userId))/follow", as: FollowResult.self)
    }

    /// 自分がフォローしている人の ID だけ。ボタンの初期状態に使う。
    func myFollowingIds() async throws -> [String] {
        struct Response: Decodable { let userIds: [String] }
        return try await api.authorized(.get, "/user/following", as: Response.self).userIds
    }

    func following(userId: String) async throws -> FollowList {
        try await api.authorized(.get, "/users/\(encoded(userId))/following", as: FollowList.self)
    }

    func followers(userId: String) async throws -> FollowList {
        try await api.authorized(.get, "/users/\(encoded(userId))/followers", as: FollowList.self)
    }
}

/// 1件のコメント。`api-user/src/comments.ts` の `Comment`。
///
/// **`deleted` が立っていたら、その人のプロフィールへの導線を出さない。**
/// 退会した人の名前はサーバー側で伏せ字に差し替わるが、`uid` はそのまま
/// 返る（`/users/<sub>` は公開ルートなので sub は秘密ではない）。
struct PhotoComment: Decodable, Identifiable, Equatable {
    let id: String
    let uid: String
    let name: String
    let text: String
    /// 投稿時刻（ISO8601）
    let t: String?
    let deleted: Bool?

    var isFromDeletedUser: Bool { deleted == true }
}

/// フォロー一覧の1人。名前を出していない人は `name` が無い。
struct FollowUser: Decodable, Identifiable, Equatable {
    let id: String
    let name: String?
    let deleted: Bool?

    var displayName: String {
        if deleted == true { return "退会したユーザー" }
        if let name, !name.isEmpty { return name }
        return String(id.prefix(8))
    }
}
