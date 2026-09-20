import Foundation

/// ユーザー検索（未認証で叩ける）。
struct UserSearchService {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    private struct Response: Decodable { let users: [UserProfile] }

    /// - Parameter query: 空なら**呼ばない**。サーバーは空で `[]` を返すが、
    ///   行って帰ってくるだけ無駄。
    func search(query: String) async throws -> [UserProfile] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try await api.anonymous(
            .get, "/users/search", query: ["q": trimmed], as: Response.self
        ).users
    }
}
