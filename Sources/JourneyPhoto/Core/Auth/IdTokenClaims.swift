import Foundation

/// ID トークン（JWT）の中身から、画面の出し分けに要るものだけを読む。
///
/// **署名は確かめない。** ここで読むのは「メニューに『管理』の行を出すか」だけで、
/// 権限の判断はサーバーがする（管理の口は API 側が `admin` の群を見る）。
/// Web も同じく ID トークンの `cognito:groups` で出し分けている（`app/auth/context.tsx`）。
enum IdTokenClaims {

    /// `cognito:groups`。読めなければ空（管理を出さない側へ倒す）
    static func groups(fromJWT token: String) -> [String] {
        (payload(of: token)?["cognito:groups"] as? [String]) ?? []
    }

    /// `sub`（その人の ID）。読めなければ nil。**401 の送り直しで「同じ人か」を見る**
    /// （`APIClient.send`）——署名は確かめない（送り直すかどうかの判断だけに使う）
    static func subject(fromJWT token: String) -> String? {
        guard let sub = payload(of: token)?["sub"] as? String, !sub.isEmpty else { return nil }
        return sub
    }

    private static func payload(of token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        // base64url → base64（- と _ を戻し、= で4の倍数に埋める）
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func isAdmin(jwt token: String) -> Bool {
        groups(fromJWT: token).contains("admin")
    }
}
