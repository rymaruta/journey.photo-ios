import Foundation

/// プロフィールの QR（札 #545 の第1段・2026-11-12）。
///
/// **中身は今ある公開プロフィールの URL。** Web の人の頁は `/users/<id>`（ビルドの時点で投稿のある人だけ静的に作る）と
/// `/users?id=<id>`（だれでも開ける・`ROUTES.USER_PROFILE` の後ろの形）の2つ。2026-11-12 判断: QR には**だれでも開ける
/// `/users?id=<id>`** を入れる——登録したばかりで投稿の無い人の `/users/<id>` は、次のビルドまで 404 になる。
/// （指示にあった `/u/…` の形は Web に無い。2026-11-12 に `journey.photo-web` の main の `lib/routes.ts` で確かめた）
///
/// 🔴 **2026-11-12 owner の要望・承認（「DB の変更してもいいけどね」・札 #545）: LINE のように QR を「更新」でき、
/// 古い QR は使えなくなる形にした（悪用を防ぐ）。** 中身は取り替えられる合図（`/qr?t=<合図>`・`ProfileQR.passURL`）で、
/// サーバーの口（`GET /user/qr`・`POST /user/qr/rotate`・`GET /qr/{合図}`。user API とは別のスタック）が持つ:
/// - QR に入れる中身を作るのは `ProfileQRSource` の1か所だけ。アプリは `ServerProfileQRSource`（合図）を使う。
///   前の版の QR（公開プロフィールの URL）は `ProfileQRLink.parse` が読む（2026-11-25 札 #733: 使っていなかった
///   中身の作り手 `PublicProfileQRSource` は消した）
/// - 読み取った文字を見分けるのは `ProfileQRLink.parse` の1か所だけ。合図は `ProfileQRSource.resolve` で人に引き、
///   引けない（更新された・退会した）ときは「この QR コードは使えません」
///
/// 読み取りはアプリの中のカメラ。**journey-photo.com の人の URL だけ**をアプリの人の頁で開く（ほかの QR は開かない）。
/// iPhone のカメラで読んだときにアプリが開く（Associated Domains・第2段）は作らない——Apple の設定が要る
enum ProfileQR {

    /// 公開プロフィールの URL（`https://journey-photo.com/users?id=<id>`）。id が URL に入れられない形なら nil
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

    /// 読み取った文字から、人の id を取り出す（`ProfileQRLink.parse` の `.person` だけ）。合図の QR・ほかの QR は nil
    static func userId(from text: String, base: URL = AppConfig.siteBaseURL) -> String? {
        if case .person(let id) = ProfileQRLink.parse(text, base: base) { return id }
        return nil
    }

    /// 取り替えられる合図を入れた URL（`https://journey-photo.com/qr?t=<合図>`・2026-11-12 札 #545）。
    /// Web の `/qr` の頁が `GET /qr/{合図}` で人を引いて人の頁へ送る。合図が URL に入れられない形なら nil。
    /// 2026-11-12 判断: 設計の案は `/q?t=` だったが、Web の `/q` は今日の一問の頁なので `/qr` に置いた（静的な書き出しなので
    /// パスではなくクエリ・共同アルバムの招待 `/j?t=` と同じ形）
    static func passURL(token: String, base: URL = AppConfig.siteBaseURL) -> URL? {
        guard PathID.isSafe(token),
              var parts = URLComponents(url: base.appendingPathComponent("qr"), resolvingAgainstBaseURL: false)
        else { return nil }
        parts.queryItems = [URLQueryItem(name: "t", value: token)]
        return parts.url
    }

    /// `/users/` の下にある、人ではない頁（Web の `app/users/search`・`app/users/trip`）
    static let notPeople: Set<String> = ["search", "trip"]
}

/// 読み取った QR が指すもの。**見分けるのはここ1か所**（2026-11-12・更新できる QR に備える）
enum ProfileQRLink: Equatable {
    /// 人の頁の URL（`/users?id=<id>`・`/users/<id>`・`/u/<id>`）
    case person(String)
    /// 取り替えられる合図（`/qr?t=<合図>`・更新できる QR・サーバーの `GET /qr/{合図}` で人に引く）
    case pass(String)

    /// 読める形: `/users?id=<id>`・`/users/<id>`（静的な頁）・`/u/<id>`（短い形・第2段のため）・`/qr?t=<合図>`（更新できる QR）。`/qr/<合図>` は読まない（2026-11-12 秘書室の決定）。
    /// `/users/search`・`/users/trip` は人の頁ではないので読まない。id と合図は API のパスに入れられる形だけ（`PathID`）。
    /// **journey-photo.com（と今のサイト）の https/http でなければ nil**——外のサイトへ連れ出さない
    static func parse(_ text: String, base: URL = AppConfig.siteBaseURL) -> ProfileQRLink? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: trimmed),
              let scheme = parts.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = parts.host?.lowercased(), ProfileQR.knownHosts(base: base).contains(host)
        else { return nil }
        let segments = parts.path.split(separator: "/").map(String.init)
        let link: ProfileQRLink?
        switch segments.count {
        case 1 where segments[0] == "users":
            link = parts.queryItems?.first(where: { $0.name == "id" })?.value.map(ProfileQRLink.person)
        case 1 where segments[0] == "qr":
            // 更新できる QR の中身（`ProfileQR.passURL`・2026-11-12）
            link = parts.queryItems?.first(where: { $0.name == "t" })?.value.map(ProfileQRLink.pass)
        case 2 where segments[0] == "users" && !ProfileQR.notPeople.contains(segments[1]):
            link = segments[1].removingPercentEncoding.map(ProfileQRLink.person)
        case 2 where segments[0] == "u":
            link = segments[1].removingPercentEncoding.map(ProfileQRLink.person)
        default:
            link = nil
        }
        guard let link, PathID.isSafe(link.value) else { return nil }
        return link
    }

    private var value: String {
        switch self {
        case .person(let id): return id
        case .pass(let pass): return pass
        }
    }
}

/// 自分の QR の中身を作る所・合図を人に引く所（2026-11-12・**ここ1か所**）。
///
/// 承認のあと（更新できる QR）は、サーバーの口で「今の合図」を取り・更新し・合図を人に引く実装に替える。
/// 画面（`ProfileQRView`）はこの形だけを見るので、替えても画面は変えない
// 画面（メインアクタ）から問い合わせの糸へ渡すので Sendable（2026-11-25 Swift 6）
protocol ProfileQRSource: Sendable {
    /// 自分の QR に入れる URL。作れないときは投げる（画面は「作れませんでした・もう一度」）
    func code(for userId: String) async throws -> URL
    /// 合図（`/qr?t=<合図>`）を人の id に引く。引けない（古い・取り消された）なら nil。通信の失敗は投げる
    /// （圏外で「使えません」と言わない）
    func resolve(pass: String) async throws -> String?
    /// 「QR コードを更新」を出すか。更新すると古い QR は使えなくなる
    var canRenew: Bool { get }
    /// 新しい合図にして、その URL を返す。前の QR とリンクはすぐ使えなくなる（`canRenew` のときだけ呼ぶ）
    func renew(for userId: String) async throws -> URL
}

enum ProfileQRSourceError: Error, Equatable {
    case cannotMake
}

enum ProfileQRSources {
    /// アプリが使う中身の作り手（更新できる合図・2026-11-12 owner 承認）。API の口は画面の環境から渡す
    static func current(api: APIClient) -> any ProfileQRSource { ServerProfileQRSource(api: api) }
}

/// プロフィールのリンクを共有する（札 #545 の段1・2026-11-15）。**リンクだけを渡す**（CLAUDE.md「他人の写真は、その人のもの」:
/// 持ち主の所へ人を連れて行くだけのものは残してよい）。画像は渡さない。
///
/// - 自分のリンク: QR の画面の「リンクをコピー」「共有」。中身は**今の QR と同じ URL**（`ProfileQRSource.code`・取り替えられる合図）。
///   2026-11-15 判断: 公開プロフィールの URL ではなく合図にする——「QR コードを更新」の確かめが「今の QR コードとリンクは
///   使えなくなります」と言っているので、更新すると渡したリンクも一緒に止まる（LINE と同じ）
/// - 他人のリンク: 人の頁の ⋯ の「プロフィールを共有」。中身は公開プロフィールの URL（`ProfileQR.url`・だれでも開ける
///   `/users?id=<id>`）。人の合図はその人だけが持つので、他人は取り替えられる形では渡せない
enum ProfileShareLink {
    /// 人の頁の ⋯ に「プロフィールを共有」を出すときの URL。**自分の頁・ブロックした人・URL に入れられない id は nil**
    /// （自分のリンクは QR の画面から渡す・ブロックした人へは人を連れて行かない）。ログインしていなくても渡せる
    static func url(userId: String, viewerId: String?, blocked: Set<String>,
                    base: URL = AppConfig.siteBaseURL) -> URL? {
        guard userId != viewerId, !blocked.contains(userId) else { return nil }
        return ProfileQR.url(userId: userId, base: base)
    }

    static var copyLabel: String { L("リンクをコピー", "Copy link") }
    static var shareLabel: String { L("共有", "Share") }
    static var copied: String { L("リンクをコピーしました", "Link copied") }
    static var shareProfileLabel: String { L("プロフィールを共有", "Share profile") }
    /// 共有の画面の上に出る題（渡すのはリンクなので「QR」とは書かない）
    static func previewTitle(_ name: String) -> String { L("\(name) のプロフィール", "\(name)'s profile") }
}
