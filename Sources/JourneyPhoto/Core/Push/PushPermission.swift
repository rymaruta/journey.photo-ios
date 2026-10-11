import Foundation
import UserNotifications

/// 端末の通知の許可（システム設定の状態）を、画面が使う4つに縮めたもの（2026-10-11）。
///
/// `PushCenter.isAuthorized`（真偽）だけでは「まだ聞いていない」と「断られた」を分けられない。
/// 分けないと、断られた人に許可のダイアログを出そうとして何も起きない（OS は二度と聞かない）
/// ——その人には設定アプリへの案内が要る
enum PushPermission: Equatable {
    /// まだ読んでいない（起動直後）。**この間は何も案内しない**
    case unknown
    /// まだ聞いていない。聞けば OS のダイアログが出る
    case notDetermined
    /// 断られた（または制限）。OS は二度と聞かない。設定アプリでしか戻せない
    case denied
    /// 許可されている（仮の許可・一時的な許可も含む）
    case allowed

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .authorized, .provisional, .ephemeral: self = .allowed
        @unknown default: self = .denied
        }
    }

    /// システムの許可を読む（`PushCenter` の既定）
    static func system() async -> PushPermission {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return PushPermission(settings.authorizationStatus)
    }
}

/// 通知の許可を**こちらから**尋ねる頃合い（画面を持たない決まり・2026-10-11）。
///
/// Apple のガイドライン（Human Interface Guidelines「Managing notifications」）に合わせる:
/// - **起動した直後には聞かない**（何の通知か分からないうちに聞くと断られ、
///   一度断られると設定アプリまで行かないと戻せない）
/// - 通知が役に立つ場面で、**先にアプリの中で短く理由を言ってから**システムのダイアログへ
///
/// 2026-10-11 判断: 場面は**初めての投稿が上がったとき**の1か所（いいね・コメントが届くのは
/// 投稿してから）。Pro の「前の晩に知らせる」は、行の中に「通知がオフのため届きません」を出して
/// 押せばその場で許可へ進める（`LightAlertPushNotice`）ので、こちらから割り込む場面には数えない。
/// フォローした時は、届く通知（相手の投稿）が今は無いので場面にしない
///
/// **出すのは端末で1回だけ。**「あとで」でも「通知を受け取る」でも、出した時点で覚える
/// （何度も出すと押しつけになる）。あとから受け取りたい人は設定の「プッシュ通知を受け取る」から
enum PushPrimer {

    /// 説明を出してよいか
    /// - Parameters:
    ///   - signedIn: ログインしているか（宛先を預ける人が決まっていないと届かない）
    ///   - permission: 端末の許可。**まだ聞いていないときだけ**出す
    ///     （許可済みでアプリ内でオフにした人は自分で切った・断られた人には OS がもう聞かない）
    ///   - alreadyOffered: この端末で前に出したか
    static func shouldOffer(signedIn: Bool, permission: PushPermission, alreadyOffered: Bool) -> Bool {
        signedIn && !alreadyOffered && permission == .notDetermined
    }
}

/// Pro の「前の晩に知らせる」の行に出す、通知が届かないことの知らせ（2026-10-11）。
///
/// 「前の晩に知らせる」は既定でオン（`wantsLightAlert ?? true`）だが、プッシュが届かない端末では
/// オンに見えて何も来なかった。行の下に「通知がオフのため届きません」を出し、押すと直せる所へ進む
enum LightAlertPushNotice: Equatable {
    /// まだ聞いていない・アプリの中でオフにした: 押すと通知を受け取る（必要なら OS が尋ねる）
    case turnOn
    /// 断られた: OS はもう聞かないので、設定アプリを開く
    case openSettings

    /// 出す知らせ。出さないときは nil
    /// - Parameters:
    ///   - wants: 「前の晩に知らせる」がオンか（オフなら届かなくて当然なので言わない）
    ///   - knownNotPro: Pro でないと分かっている（Pro でなければそもそも届かない。押すと Pro の案内）
    ///   - permission: 端末の許可（読めていない間は言わない）
    ///   - enabled: 設定の「プッシュ通知を受け取る」（本人の意思・`PushCenter.isEnabled`）
    static func state(wants: Bool, knownNotPro: Bool,
                      permission: PushPermission, enabled: Bool) -> LightAlertPushNotice? {
        guard wants, !knownNotPro else { return nil }
        switch permission {
        case .unknown: return nil
        case .denied: return .openSettings
        case .notDetermined: return .turnOn
        case .allowed: return enabled ? nil : .turnOn
        }
    }

    /// 行の1行目（板 Settings の「通知が切られています」の行と同じ形）
    var title: String { L("通知がオフのため届きません", "Notifications are off, so this won\u{2019}t arrive") }

    /// 行の2行目
    var detail: String {
        switch self {
        case .turnOn:
            return L("押すと通知を受け取れるようにします。", "Tap to turn on notifications.")
        case .openSettings:
            return L("iPhone の設定で通知が切られています。設定アプリで許可してください。",
                     "Notifications are turned off in iPhone Settings. Allow them in the Settings app.")
        }
    }

    /// 読み上げの補足（押すと何が起きるか）
    var hint: String {
        switch self {
        case .turnOn: return L("通知の許可を求めます", "Asks for notification permission")
        case .openSettings: return L("設定アプリを開きます", "Opens the Settings app")
        }
    }
}
