import Foundation

/// プロフィールの QR（札 #545 の第1段・2026-11-12）。
///
/// **中身は今ある公開プロフィールの URL。** Web の人の頁は `/users/<id>`（ビルドの時点で投稿のある人だけ静的に作る）と
/// `/users?id=<id>`（だれでも開ける・`ROUTES.USER_PROFILE` の後ろの形）の2つ。2026-11-12 判断: QR には**だれでも開ける
/// `/users?id=<id>`** を入れる——登録したばかりで投稿の無い人の `/users/<id>` は、次のビルドまで 404 になる。
/// （指示にあった `/u/…` の形は Web に無い。2026-11-12 に `journey.photo-web` の main の `lib/routes.ts` で確かめた）
///
/// 🔴 **2026-11-12 owner の要望: LINE のように QR を「更新」でき、古い QR は使えなくなる形にする（悪用を防ぐ）。**
/// そのときの中身は取り替えられる合図（`/qr?t=<合図>`・2026-11-12 秘書室が決定。`/q` は Web の今日の一問とぶつかるので
/// 人の頁と同じく静的な頁 1 枚＋クエリの形）で、サーバーの口と DB の行が要る（owner の承認待ち）。だから:
/// - QR に入れる中身を作るのは `ProfileQRSource` の1か所だけ。今は公開プロフィールの URL を返す仮の実装
///   （`PublicProfileQRSource`）。承認のあとは合図を返す実装に替えるだけで、画面は変えない
/// - 読み取った文字を見分けるのは `ProfileQRLink.parse` の1か所だけ。`/qr?t=<合図>` も今から見分ける
///   （引くのは `ProfileQRSource.resolve`。今は引けないので「使えなくなった QR」と言う）
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

    /// `/users/` の下にある、人ではない頁（Web の `app/users/search`・`app/users/trip`）
    static let notPeople: Set<String> = ["search", "trip"]
}

/// 読み取った QR が指すもの。**見分けるのはここ1か所**（2026-11-12・更新できる QR に備える）
enum ProfileQRLink: Equatable {
    /// 人の頁の URL（`/users?id=<id>`・`/users/<id>`・`/u/<id>`）
    case person(String)
    /// 取り替えられる合図（`/qr?t=<合図>`・更新できる QR・承認のあとサーバーで人に引く）
    case pass(String)

    /// 読める形: `/users?id=<id>`・`/users/<id>`（静的な頁）・`/u/<id>`（短い形・第2段のため）・`/qr?t=<合図>`。
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
protocol ProfileQRSource {
    /// 自分の QR に入れる URL。作れないときは投げる（画面は「作れませんでした・もう一度」）
    func code(for userId: String) async throws -> URL
    /// 合図（`/qr?t=<合図>`）を人の id に引く。引けない（古い・取り消された）なら nil
    func resolve(pass: String) async throws -> String?
    /// 「QR コードを更新」を出すか。更新すると古い QR は使えなくなる（承認のあと true の実装に替える）
    var canRenew: Bool { get }
}

enum ProfileQRSourceError: Error, Equatable {
    case cannotMake
}

/// 今の中身（仮の実装）: 公開プロフィールの URL。合図は引けない・更新は出さない
struct PublicProfileQRSource: ProfileQRSource {
    var base: URL = AppConfig.siteBaseURL

    func code(for userId: String) async throws -> URL {
        guard let url = ProfileQR.url(userId: userId, base: base) else { throw ProfileQRSourceError.cannotMake }
        return url
    }

    func resolve(pass: String) async throws -> String? { nil }

    var canRenew: Bool { false }
}

enum ProfileQRSources {
    /// アプリが使う中身の作り手。承認のあとはここを合図の実装に替える
    static let current: any ProfileQRSource = PublicProfileQRSource()
}
