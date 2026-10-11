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
        // 2026-10-11 判断: 知らない状態（今後の iOS で増えたもの）は「断られた」と決めつけず、
        // 読めない扱いにする——何も案内しない（設定アプリへの案内も、許可のダイアログも出さない）
        @unknown default: self = .unknown
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
/// **出すのは端末で1回だけ。**「あとで」でも「オンにする」でも、出した時点で覚える
/// （何度も出すと押しつけになる）。あとから受け取りたい人は設定の「プッシュ通知を受け取る」から。
///
/// 2026-10-11 判断: **「あとで」は二度と出さない**（「N 回投稿したらもう一度」はしない）。
/// 代わりに、お知らせの一覧の上に「通知をオンにする」の帯を出す（`ActivityPushBanner`）——
/// 割り込まずに、通知を見に来た所でだけ言う
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

/// お知らせの一覧の上に出す「通知をオンにする」の帯（2026-10-11）。
///
/// 通知の入口は設定の奥（「プッシュ通知を受け取る」）と、初めての投稿のあとの説明（`PushPrimer`・1回だけ）
/// しか無く、「あとで」を押した人や前から使っている人は、届かないまま気づけなかった。
/// お知らせの一覧は「届いたものを見る所」なので、届かない端末ではここで言う。
///
/// 2026-10-11 判断: **端末の許可が無いときだけ**出す（まだ聞いていない・断られた）。許可はあって
/// 設定で「受け取らない」にした人は自分で切ったので出さない（毎回の帯は押しつけになる）。
/// 読めていない間（`.unknown`）も出さない（出てから消えるとちらつく）
enum ActivityPushBanner: Equatable {
    /// まだ聞いていない: 押すと通知を受け取る（OS が尋ねる・設定の行と同じ `PushCenter.enable`）
    case turnOn
    /// 断られた: OS はもう聞かないので、設定アプリの通知の所を開く
    case openSettings

    /// 出す帯。出さないときは nil
    static func state(permission: PushPermission) -> ActivityPushBanner? {
        switch permission {
        case .notDetermined: return .turnOn
        case .denied: return .openSettings
        case .unknown, .allowed: return nil
        }
    }

    /// 帯の1行目
    var title: String { L("通知をオンにする", "Turn on notifications") }

    /// 帯の2行目
    var detail: String {
        switch self {
        case .turnOn:
            return L("いいね・コメントが届いたら、アプリを開いていなくてもお知らせします。",
                     "Get likes and comments even when the app is closed.")
        case .openSettings:
            return L("iPhone の設定で通知が切られています。設定アプリで許可してください。",
                     "Notifications are turned off in iPhone Settings. Allow them in the Settings app.")
        }
    }

    /// 押す所の文字（写真の無い画面の主ボタン＝真鍮の塗りに墨）
    var action: String {
        switch self {
        case .turnOn: return L("オンにする", "Turn on")
        case .openSettings: return L("設定を開く", "Open Settings")
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
