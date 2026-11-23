import Foundation

/// 「サインインの方法」のサーバーの口（札 #601・2026-11-23 owner「設定に『サインインの方法』を足し、Apple と Google を解除できるようにする」）。
///
/// - `GET /user/signin-methods`: メールアドレスとパスワード、Apple、Google の、連携しているか・解除できるか
/// - `DELETE /user/signin-methods/{provider}`: Apple か Google の連携を解除する（Apple はサーバーが取り消してから）
///
/// 🔴 最後に残る入り方はサーバーが断る（409・`last_signin_method`）。アプリは答えの `blockedReason` をそのまま出す。
/// 口がまだ無いサーバー（Apple のスタックを配っていない本番）は道の無い 404 になる。その時は設定の行を出さない（`list` が nil）
///
/// サーバーの作りは photo-gallery の `api-user/src/signinMethods.ts`（別スタック `serverless.apple-signin.yml`）。
struct SigninMethodsService {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    private struct Answer: Decodable {
        let methods: [SigninMethod]
    }

    /// 今の連携。口が無いサーバーなら nil（行を出さない）。ほかの失敗は投げる。
    /// 2026-11-23 判断: 404 は本文があっても nil（道が無い 404 と、サーバーが本人の行を見つけられない 404 のどちらも、
    /// 出せる中身が無いので行を出さない）
    func list() async throws -> [SigninMethod]? {
        do {
            return try await api.authorized(.get, "/user/signin-methods", as: Answer.self).methods
        } catch APIError.server(status: 404, message: _) {
            return nil
        }
    }

    /// 連携を解除する。答えは解除したあとの一覧
    func remove(_ provider: SigninMethod.Provider) async throws -> [SigninMethod] {
        try await api.authorized(.delete, "/user/signin-methods/\(provider.rawValue)", as: Answer.self).methods
    }
}

/// サインインの方法の1行（サーバーの `SigninMethod` と同じ形）
struct SigninMethod: Decodable, Equatable, Sendable, Identifiable {

    enum Provider: String, Sendable, CaseIterable {
        case apple, google
    }

    /// `email`・`apple`・`google`
    let id: String
    /// 連携しているか（メールは「メールアドレスとパスワードで入れるか」）
    let linked: Bool
    /// 「解除」を出してよいか（メールは解除しない）
    let removable: Bool
    /// 解除できない理由（連携しているのに解除できないときだけ）
    let blockedReason: String?
    /// メールアドレス（本人の答えだけ・`email` の行だけ）
    let email: String?

    init(id: String, linked: Bool, removable: Bool, blockedReason: String? = nil, email: String? = nil) {
        self.id = id
        self.linked = linked
        self.removable = removable
        self.blockedReason = blockedReason
        self.email = email
    }

    var provider: Provider? { Provider(rawValue: id) }
}

/// 画面の文（`SigninMethodsView`）。2026-11-23 owner「外す」ではなく「解除」
enum SigninMethodsText {

    static var title: String { L("サインインの方法", "Sign-in methods") }

    /// 行の名前
    static func name(_ id: String) -> String {
        switch id {
        case "email": return L("メールアドレスとパスワード", "Email and password")
        case "apple": return "Apple"
        case "google": return "Google"
        default: return id
        }
    }

    /// 行の2行目（状態は色だけでなく文字で言う）
    static func detail(_ method: SigninMethod) -> String {
        if method.id == "email" {
            if method.linked, let email = method.email { return email }
            return method.email.map { L("\($0)（パスワードは未設定）", "\($0) (no password set)") }
                ?? L("設定されていません", "Not set up")
        }
        return method.linked ? L("連携しています", "Connected") : L("連携していません", "Not connected")
    }

    static var removeButton: String { L("解除", "Disconnect") }
    static var removing: String { L("解除しています…", "Disconnecting…") }

    /// 確かめのダイアログの題（取り消せない操作なので確かめる）
    static func confirmTitle(_ provider: SigninMethod.Provider) -> String {
        let name = Self.name(provider.rawValue)
        return L("\(name) の連携を解除しますか", "Disconnect \(name)?")
    }

    static func confirmMessage(_ provider: SigninMethod.Provider) -> String {
        let name = Self.name(provider.rawValue)
        return L("解除すると、\(name) ではこのアカウントに入れなくなります。",
                 "You won't be able to sign in to this account with \(name).")
    }

    static var confirmButton: String { L("解除する", "Disconnect") }

    /// 一覧が読めなかった
    static var loadFailed: String { L("読み込めませんでした", "Couldn't load") }
}
