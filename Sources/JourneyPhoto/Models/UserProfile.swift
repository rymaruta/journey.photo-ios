import Foundation

/// プロフィール。`GET /user/profile`（自分）と `GET /profile/{userId}`（他人）
/// が同じ形を返す。
///
/// **すべて optional にしてある。** Web 側は `as UserProfile` の素通しで
/// 型の合わない値を画面まで通し、`bio` にオブジェクトが入っていた回は
/// ページ全体がエラーカードで覆われた（`lib/utils/profileShape.ts`）。
/// Swift の Decodable は型が違えば弾くので同じ壊れ方はしないが、
/// **1項目の型違いで全体の復号が失敗する**のは同じくらい困る。
/// 落としても構わない項目は optional にして、欠けても読めるようにする。
struct UserProfile: Decodable, Equatable, Identifiable {
    let userId: String
    let username: String?
    let displayName: String?
    let bio: String?
    let website: String?
    let instagram: String?
    let statusText: String?
    /// 認証済みの印（名前の横のバッジ）。
    ///
    /// **立てられるのは運営だけ**（`api-user` の更新の経路は受け取らない）。
    /// 誰も立てていなければ誰にも出ない——それは正しい状態であって
    /// 「機能が無い」のではない。
    let verified: Bool?
    let themeColor: String?
    let pinnedPhotoIds: [String]?

    var id: String { userId }

    /// 画面に出す名前。username も無ければ ID の頭で代用する。
    var name: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let username, !username.isEmpty { return username }
        return String(userId.prefix(8))
    }

    /// アイコン。`profiles/<uid>` は**固定キーで中身が差し替わる**ので、
    /// サーバーもアップロードも `no-store` を付けている
    /// （`public/sw.js` がこれを控えないのと同じ理由）。
    /// URLSession のキャッシュに残らないよう、変更を知りたい場面では
    /// `cacheBust` を渡す。
    func avatarURL(cacheBust: String? = nil) -> URL? {
        Self.profileAssetURL(userId: userId, suffix: nil, cacheBust: cacheBust)
    }

    /// カバー画像。`profiles/<uid>/cover`。
    func coverURL(cacheBust: String? = nil) -> URL? {
        Self.profileAssetURL(userId: userId, suffix: "cover", cacheBust: cacheBust)
    }

    /// **サイトのドメインで組み立てる。** CloudFront の既定ドメインを直接
    /// 指すと別オリジンになり、Web 側が 2026-09-13 に揃えた
    /// （`lib/utils/seo.ts` の `publicImageUrl`）状態から逆戻りする。
    static func profileAssetURL(userId: String, suffix: String?, cacheBust: String?) -> URL? {
        guard let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        var path = "profiles/\(encoded)"
        if let suffix { path += "/\(suffix)" }
        var components = URLComponents(
            url: AppConfig.siteBaseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if let cacheBust {
            components?.queryItems = [URLQueryItem(name: "v", value: cacheBust)]
        }
        return components?.url
    }
}
