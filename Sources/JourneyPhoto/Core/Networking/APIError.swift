import Foundation

/// api-user / 静的サイトへの通信で起きうる失敗。
///
/// **「通信できなかった」と「ログインしていない」を混ぜない。** Web 側は
/// 一度これを混ぜていて、圏外なだけの利用者に「ログインしてください」と
/// 出していた（`lib/utils/api.ts` の `NETWORK_UNREACHABLE_MESSAGE`）。
enum APIError: LocalizedError, Equatable {
    /// 認証が必要なのにトークンが無い（＝ログインしていない）
    case notAuthenticated
    /// 通信そのものが届かなかった（圏外・タイムアウト）
    case unreachable
    /// サーバーが 4xx / 5xx を返した。message は api-user の `{ error }`
    case server(status: Int, message: String)
    /// 応答の形が想定と違う
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "ログインが必要です"
        case .unreachable:
            return "通信できませんでした。電波の良いところでもう一度お試しください"
        case .server(let status, let message):
            return message.isEmpty ? "サーバーエラー（\(status)）" : message
        case .decoding:
            return "応答を読み取れませんでした"
        }
    }

    /// 認証が切れている（再ログインを促すべき）応答か
    var isAuthExpired: Bool {
        if case .server(let status, _) = self { return status == 401 || status == 403 }
        return false
    }
}
