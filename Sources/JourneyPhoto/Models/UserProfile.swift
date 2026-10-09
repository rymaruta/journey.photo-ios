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
    /// 居住地（モック2-1 の「📍Tokyo, Japan」）。**自由入力の1行**。
    ///
    /// **写真の撮影地とは別物。** あちらは `/location/*` と地図に効くが、
    /// こちらは自己紹介の一部で、集約にも地図にも使わない
    /// （使うと、住んでいる場所が地図にピンとして出る）。
    let homeLocation: String?
    /// 認証済みの印（名前の横のバッジ）。
    ///
    /// **立てられるのは運営だけ**（`api-user` の更新の経路は受け取らない）。
    /// 誰も立てていなければ誰にも出ない——それは正しい状態であって
    /// 「機能が無い」のではない。
    let verified: Bool?
    let themeColor: String?
    let pinnedPhotoIds: [String]?
    /// プロフィールのBGM（モック2-4）。**最大5曲**でサーバーが持っている
    /// （`api-user/src/userProfile.ts` の `songs`・`PROFILE_SONGS_MAX`）。
    ///
    /// 以前ここに「プロフィールに曲の項目が無い」と書いて ⛔ にしていたのは
    /// **誤り**——`toPublicProfile` は前から返していた。アプリが復号して
    /// いなかっただけ。
    let songs: [Photo.Song]?

    // MARK: バッジと Pro（第1段階・2026-10-09）
    //
    // **どれも包みで持ち、壊れていても投げない**（`Badge.swift`）。古いサーバーは
    // 返さない——そのときは「バッジ無し・Pro でない」で出る。画面は下の計算プロパティを読む

    /// 持っているバッジ（`{key: {tier, at}}`）
    private let badges: BadgeSet?
    /// 名前の横に出すと本人が選んだバッジの鍵
    private let displayBadge: LenientText?
    /// Pro 会員か（**まだ誰も Pro ではない**が、立てば印が出る）
    private let pro: LenientFlag?
    /// Pro マークの形（`iris` / `plate`）
    private let proMarkStyle: LenientText?

    /// 持っているバッジ。返さないサーバーでは空
    var earnedBadges: BadgeSet { badges ?? BadgeSet() }

    /// 名前の横に出すバッジ。**選んだ鍵を持っているときだけ**——持っていない鍵
    /// （取り消された・古い値）を指していたら何も出さない
    var shownBadge: EarnedBadge? {
        guard let key = displayBadge?.value else { return nil }
        return earnedBadges[key]
    }

    /// 選んでいる鍵（持っているかは問わない。名前の横の画面の初期値に使う）
    var chosenBadgeKey: String? { displayBadge?.value }

    var isPro: Bool { pro?.value ?? false }

    /// サポーターの印（番号・申し込んだ日・続けた月の数・第2段階）。公開。
    /// **やめても残る**——Pro かどうかは `isPro` で見る
    private let supporter: LenientSupporter?

    /// サポーター証の中身。申し込んだことのない人・古いサーバーでは nil
    var supporterInfo: SupporterInfo? { supporter?.value }

    /// 光と天気の知らせ（Pro・2026-10-09）を受け取るか。**本人の応答だけに載る**（公開プロフィールには無い）。
    /// サーバーは行に無ければ「受け取る」を返す（`userProfile.ts` の `withBadgeFields`）
    private let lightAlert: LenientFlag?

    /// 前の晩の知らせを受け取るか。**無い（古いサーバー）ときは受け取る**（サーバーの既定と同じ）
    var wantsLightAlert: Bool { lightAlert?.value ?? true }

    /// Pro マークの形。知らない値・無い値は既定の絞り羽根
    var markStyle: ProMarkStyle {
        proMarkStyle?.value.flatMap(ProMarkStyle.init(rawValue:)) ?? .iris
    }

    /// 画面に出す1曲。**先頭だけ**（モックのカードは1枚）
    var bgm: Photo.Song? {
        guard let songs else { return nil }
        return songs.first { !$0.title.isEmpty && $0.previewURL != nil }
    }

    var id: String { userId }

    /// 画面に出す名前。username も無ければ ID の頭で代用する。
    var name: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let username, !username.isEmpty { return username }
        return Labels.Common.unnamedUser
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

/// アイコン・カバーの `?v=`（`UserProfile.profileAssetURL` の `cacheBust`）を**いつ替えるか**。
///
/// **読み直すたびに替えない（2026-10-02）。** マイページと人のページは、読み込みのたび
/// （タブに戻る・画面に戻る）に今の時刻を `?v=` にしていた。URL が毎回変わるので、
/// 出ていた絵まで捨てて取り直し、見出しが一瞬空になっていた。
///
/// 替えるのは:
/// - **アプリを開き直したとき**（`launch`）——Web や別の端末で変えた分は、ここで拾う
/// - **この端末で本人がアイコン・カバーを変えたとき**（`bump`）——その人のぶんだけ
///
/// サーバーはアイコンの版を返さない（`profiles/<uid>` は固定キーで、上げても
/// プロフィールの行は書き換わらない）ので、他の人の変更はアプリを開き直すまで待つ
struct ProfileImageVersions: Equatable {
    /// この起動の印
    let launch: String
    /// この端末で変えた人ごとの印
    private(set) var bumped: [String: String] = [:]

    init(launch: String) { self.launch = launch }

    /// その人のアイコン・カバーに付ける `?v=`
    func token(for userId: String) -> String { bumped[userId] ?? launch }

    /// 本人がアイコンかカバーを変えた。**その人の印だけ**替える
    mutating func bump(_ userId: String, token: String = UUID().uuidString) {
        bumped[userId] = token
    }

    /// アプリ全体で1つ（画面をまたいで同じ印を使う）
    @MainActor static var shared = ProfileImageVersions(launch: String(Int(Date().timeIntervalSince1970)))
}
