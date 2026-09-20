import Foundation

/// 招待リンクからトークンを取り出す。
///
/// **`@MainActor` の型に置かない**（`TagInput` と同じ理由）。テストから
/// 呼べなくなる。
enum InviteLink {

    /// `https://…/j?t=<トークン>` からトークンを取り出す。
    /// URL でなければ、打たれた文字列そのものをトークンとみなす。
    ///
    /// **リンクをそのまま貼れるようにする。** 受け取った人に `?t=` の後ろだけを
    /// 取り出す作業をさせない（URL を貼って弾かれるのがいちばん多い失敗）。
    /// トークンを持たない URL は空を返す——URL 全体を送ると、サーバーに
    /// 無意味な問い合わせが飛ぶ。
    static func token(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed) else { return trimmed }
        if let value = components.queryItems?.first(where: { $0.name == "t" })?.value {
            return value
        }
        return components.scheme == nil ? trimmed : ""
    }
}
