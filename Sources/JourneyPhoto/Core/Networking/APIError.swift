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
            return Labels.Common.signInRequired
        case .unreachable:
            return Labels.Common.unreachable
        case .server(let status, let message):
            // **認証切れは「サーバーエラー」と言わない。** 直し方が違う
            // ——押し直しても直らず、ログインし直すしかない
            if status == 401 {
                return L("ログインの有効期限が切れました。ログインし直してください",
                         "Your session expired. Please sign in again.")
            }
            // **403 を「ログインし直して」と言わない。** 401 と混ぜていたが、
            // 403 は**ログインできているのに権限が無い**状態で、
            // ログインし直しても直らない（登録直後に権限を配る処理が
            // 落ちたときに起きる。Cognito 側に無いので本人には直せない）。
            // Web は同じ取り違えで**ログイン画面と元の画面を無限に往復**
            // させていた（`lib/hooks/useMemberGate.ts` の経緯）。
            if status == 403 {
                return L("この操作をする権限がありません。登録直後にこの状態になった場合は、お手数ですがお問い合わせください（ログインし直しても直りません）",
                         "You don't have permission for this. If this started right after signing up, please contact us — signing in again won't fix it.")
            }
            return message.isEmpty ? L("サーバーエラー（\(status)）", "Server error (\(status))") : message
        case .decoding:
            return L("応答を読み取れませんでした", "Couldn't read the response")
        }
    }

    /// 認証が切れている（再ログインを促すべき）応答か。
    ///
    /// **403 は含めない。** あちらはログインできているのに権限が無い状態で、
    /// ログインし直しても直らない（上の注記）。
    var isAuthExpired: Bool {
        if case .server(let status, _) = self { return status == 401 }
        return false
    }

    /// ログイン済みなのに権限が無い（Web の `MemberOnlyNotice` が出る状態）
    var isForbidden: Bool {
        if case .server(let status, _) = self { return status == 403 }
        return false
    }
}
