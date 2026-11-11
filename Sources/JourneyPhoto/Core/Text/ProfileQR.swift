import Foundation

/// プロフィールの QR（札 #545 の第1段・2026-11-12）。
///
/// **中身は今ある公開プロフィールの URL。** Web の人の頁は `/users/<id>`（ビルドの時点で投稿のある人だけ静的に作る）と
/// `/users?id=<id>`（だれでも開ける・`ROUTES.USER_PROFILE` の後ろの形）の2つ。2026-11-12 判断: QR には**だれでも開ける
/// `/users?id=<id>`** を入れる——登録したばかりで投稿の無い人の `/users/<id>` は、次のビルドまで 404 になる。
/// （指示にあった `/u/…` の形は Web に無い。2026-11-12 に `journey.photo-web` の main の `lib/routes.ts` で確かめた）
///
/// 読み取りはアプリの中のカメラ。**journey-photo.com の人の URL だけ**をアプリの人の頁で開く（ほかの QR は開かない）。
/// iPhone のカメラで読んだときにアプリが開く（Associated Domains・第2段）は作らない——Apple の設定が要る
enum ProfileQR {

    /// 自分の QR に入れる URL（`https://journey-photo.com/users?id=<id>`）。id が URL に入れられない形なら nil
    static func url(userId: String, base: URL = AppConfig.siteBaseURL) -> URL? {
        guard PathID.isSafe(userId),
              var parts = URLComponents(url: base.appendingPathComponent("users"), resolvingAgainstBaseURL: false)
        else { return nil }
        parts.queryItems = [URLQueryItem(name: "id", value: userId)]
        return parts.url
    }

    /// 人の頁と読める家（本番の2つと、いま繋いでいるサイト。staging の版でも本番の QR を読める）
    static func knownHosts(base: URL = AppConfig.siteBaseURL) -> Set<String> {
        var hosts: Set<String> = ["journey-photo.com", "www.journey-photo.com"]
        if let host = base.host?.lowercased() { hosts.insert(host) }
        return hosts
    }

    /// 読み取った文字から、人の id を取り出す。**journey-photo.com の人の頁の URL でなければ nil**。
    ///
    /// 読める形: `/users?id=<id>`・`/users/<id>`（静的な頁）・`/u/<id>`（第2段で短い形を作ったときのため）。
    /// `/users/search`・`/users/trip` は人の頁ではないので読まない。id は API のパスに入れられる形だけ（`PathID`）
    static func userId(from text: String, base: URL = AppConfig.siteBaseURL) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: trimmed),
              let scheme = parts.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = parts.host?.lowercased(), knownHosts(base: base).contains(host)
        else { return nil }
        let segments = parts.path.split(separator: "/").map(String.init)
        let id: String?
        switch segments.count {
        case 1 where segments[0] == "users":
            id = parts.queryItems?.first(where: { $0.name == "id" })?.value
        case 2 where segments[0] == "users" && !notPeople.contains(segments[1]):
            id = segments[1].removingPercentEncoding
        case 2 where segments[0] == "u":
            id = segments[1].removingPercentEncoding
        default:
            id = nil
        }
        guard let id, PathID.isSafe(id) else { return nil }
        return id
    }

    /// `/users/` の下にある、人ではない頁（Web の `app/users/search`・`app/users/trip`）
    static let notPeople: Set<String> = ["search", "trip"]
}
