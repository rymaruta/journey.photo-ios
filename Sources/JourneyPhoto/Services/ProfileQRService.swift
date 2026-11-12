import Foundation

/// 更新できる QR（2026-11-12・札 #545）。合図はサーバーが持つ:
/// `GET /user/qr`（今の合図・無ければ作る）／`POST /user/qr/rotate`（新しい合図・前の合図はすぐ消える）／
/// `GET /qr/{合図}`（ログイン不要・使えれば `{ userId }`、使えなければ `{ error }` つきの 404）
struct ServerProfileQRSource: ProfileQRSource {
    let api: APIClient
    var base: URL = AppConfig.siteBaseURL

    private struct Current: Decodable { let token: String }
    private struct Owner: Decodable { let userId: String }

    func code(for userId: String) async throws -> URL {
        // 端末の HTTP の控えを使わない（更新の直後に前の合図を出さない）
        let current = try await api.authorized(.get, "/user/qr", cachePolicy: .reloadIgnoringLocalCacheData, as: Current.self)
        return try url(current.token)
    }

    func renew(for userId: String) async throws -> URL {
        try url(try await api.authorized(.post, "/user/qr/rotate", as: Current.self).token)
    }

    func resolve(pass: String) async throws -> String? {
        // URL に入れられない合図は引かずに「使えない」
        guard PathID.isSafe(pass) else { return nil }
        do {
            return try await api.anonymous(.get, "/qr/\(pass)", as: Owner.self).userId
        } catch let error as APIError {
            if Self.meansUnusable(error) { return nil }
            throw error
        }
    }

    var canRenew: Bool { true }

    /// サーバーが「この合図は使えない」と答えたか。**口の 404（`{ error }` つき）だけ。** 口がまだ配られていない 404
    /// （本文の無い・`isMissingRoute`）や圏外は「使えない」と言わない——使える QR を使えないと言ってしまう
    static func meansUnusable(_ error: APIError) -> Bool {
        if case .server(404, _) = error { return !error.isMissingRoute }
        return false
    }

    private func url(_ token: String) throws -> URL {
        guard let url = ProfileQR.passURL(token: token, base: base) else { throw ProfileQRSourceError.cannotMake }
        return url
    }
}
