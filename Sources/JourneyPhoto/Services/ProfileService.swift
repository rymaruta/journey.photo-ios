import Foundation

/// プロフィールの読み書き。
struct ProfileService {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// 自分のプロフィール。行が無ければサーバー側が作る
    /// （`createProfileIfMissing`）。
    func myProfile() async throws -> UserProfile {
        try await api.authorized(.get, "/user/profile", as: UserProfile.self)
    }

    /// 他人のプロフィール（認証不要）。
    ///
    /// **退会済みの人は 404 で返る**（`isDeletedProfile` の墓石判定）。
    /// 「取れなかった」と「退会した」を混ぜないよう、呼び出し側は
    /// 404 を専用に扱うこと。
    func publicProfile(userId: String) async throws -> UserProfile {
        let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        return try await api.anonymous(.get, "/profile/\(encoded)", as: UserProfile.self)
    }

    /// 更新。**送った項目だけが変わる**（未指定は「触らない」）。
    func update(_ patch: ProfilePatch) async throws {
        try await api.authorizedVoid(.put, "/user/profile", body: patch)
    }
}

/// プロフィールの部分更新。nil の項目は JSON に載せない
/// （`JSONEncoder` は nil を省くため、「触らない」がそのまま表せる）。
struct ProfilePatch: Encodable {
    var username: String?
    var displayName: String?
    var bio: String?
    var website: String?
    var instagram: String?
    var statusText: String?
    var themeColor: String?
    var pinnedPhotoIds: [String]?
}
