import Foundation

/// ID トークン（JWT）の中身から、画面の出し分けに要るものだけを読む。
///
/// **署名は確かめない。** ここで読むのは「メニューに『管理』の行を出すか」だけで、
/// 権限の判断はサーバーがする（管理の口は API 側が `admin` の群を見る）。
/// Web も同じく ID トークンの `cognito:groups` で出し分けている（`app/auth/context.tsx`）。
enum IdTokenClaims {

    /// `cognito:groups`。読めなければ空（管理を出さない側へ倒す）
    static func groups(fromJWT token: String) -> [String] {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return [] }
        // base64url → base64（- と _ を戻し、= で4の倍数に埋める）
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let groups = object["cognito:groups"] as? [String] else { return [] }
        return groups
    }

    static func isAdmin(jwt token: String) -> Bool {
        groups(fromJWT: token).contains("admin")
    }
}
