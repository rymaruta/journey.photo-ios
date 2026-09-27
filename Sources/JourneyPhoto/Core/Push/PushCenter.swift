import Foundation
import Combine
import UIKit
import UserNotifications

/// プッシュ通知の受け口。許可・トークン・サーバーへの登録をここに集める。
///
/// **「許可を取る」と「宛先を預ける」は別。** 許可だけ取ってもトークンを
/// 送らなければ何も届かないし、ログアウトしたのに外さないと
/// **次にその端末を使う別の人へ通知が飛ぶ**。両方を1か所で持つ。
///
/// **起動時に勝手に聞かない。** 開いた瞬間の許可ダイアログは断られやすく、
/// 一度断られると設定アプリまで行かないと戻せない。設定画面の
/// 「プッシュ通知を受け取る」を押したときにだけ聞く。
@MainActor
final class PushCenter: ObservableObject {

    /// 端末が許可しているか（システム設定の状態）。
    @Published private(set) var isAuthorized = false
    /// サーバーに預けてある状態（＝いま実際に届く状態）。
    @Published private(set) var isRegistered = false
    /// **本人が「受け取る」と言ったか。** これが画面の拠り所。
    ///
    /// 預けられたか（`isRegistered`）で見ると、APNs のトークンは少し遅れて
    /// 届くので**押した直後は必ず false**——画面に入り直すたびにオフへ戻る。
    /// 逆に端末の許可だけで見ると、**自分でオフにしたのに再起動で復活**する
    /// （OS の許可は残るため）。意思は端末に残す。
    ///
    /// 🔴 **人ごとに持つ**（`enabledKey(for:)`）。端末に1つだと、A が
    /// 「受け取る」にした端末で B がログインすると、B は選んでいないのに
    /// B あての宛先がサーバーに預けられていた。未ログインのときは常に false
    @Published private(set) var isEnabled = false
    @Published var errorMessage: String?

    /// APNs から受け取ったトークン。
    ///
    /// **端末に残す。** メモリだけだと、アプリを閉じた時点で消えて
    /// (1) 設定のトグルが毎回オフに見える（サーバーは送り続ける）
    /// (2) **ログアウトで外せない**＝次にこの端末を使う人へ前の人あての
    ///     通知が飛ぶ
    /// (3) トークンが変わった（復元・入れ直し）ことに気づけない
    /// という3つが同時に起きる。秘密ではない（宛先の番号）ので素で持つ。
    private var token: String? {
        get { defaults.string(forKey: Self.tokenKey) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Self.tokenKey)
            } else {
                defaults.removeObject(forKey: Self.tokenKey)
            }
        }
    }
    private static let tokenKey = "photo-gallery-apns-token"
    /// 🔴 **端末全体で1つだった頃の「受け取る」**（移行のためだけに読む）。
    ///
    /// 引き継ぐ先は**アプリを更新したときにログインしていた人だけ**
    /// （更新後の最初の起動でログイン済みと分かった人）——その人は古い作りで
    /// 実際に宛先を預けていた本人なので、画面とサーバーの食い違いを作らない。
    /// 起動の時点で**確かに**ログアウトしていたら誰にも引き継がずに捨てる
    /// （`dropLegacyIntent`・`AuthStore.isKnownSignedOut`）。判定に失敗した回は
    /// 捨てずに残し、次にログイン済みと分かった人が引き継ぐ。
    /// ログアウトのときに宛先は外してあり（外しそびれは `pendingReleaseOwner`）、
    /// あとから来た人は自分で選び直す
    private static let legacyEnabledKey = "photo-gallery-push-enabled"
    private static func enabledKey(for userId: String) -> String {
        "\(legacyEnabledKey):\(userId)"
    }
    private static let pendingReleaseKey = "photo-gallery-push-pending-release"

    /// 🔴 **ログアウトのときに宛先を外しきれなかった人**（外し終えたら nil）。
    ///
    /// 外す口（`DELETE /user/devices`）はその人の鍵が要るので、ログアウトの
    /// 後では叩けない。残るのは2つの出口だけ:
    /// - **同じ人がまたログインした** → その人の鍵で外し直す（`use(userId:)`）
    /// - **この端末で誰かが通知を登録した** → サーバーが登録のたびに
    ///   前の持ち主から外す（api-user `devices.ts` の `releasePreviousOwner`）
    /// どちらも来ない間（誰もログインしない・次の人が通知を受け取らない）は
    /// **前の人あての通知がこの端末に届きうる**——端末からは塞げない
    private(set) var pendingReleaseOwner: String? {
        get { defaults.string(forKey: Self.pendingReleaseKey) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Self.pendingReleaseKey)
            } else {
                defaults.removeObject(forKey: Self.pendingReleaseKey)
            }
        }
    }
    private let defaults: UserDefaults
    private var userId: String?
    private let service: () -> PushService

    init(service: @escaping () -> PushService = { PushService(api: APIClient(tokenProvider: CognitoTokenProvider())) },
         defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
    }

    /// 起動時とログイン状態が変わるたびに呼ぶ。
    func use(userId: String?) async {
        let previous = self.userId
        self.userId = userId
        // **前の人の失敗文を次の人に見せない**（設定画面の赤字）
        if previous != userId { errorMessage = nil }
        // **その人の意思を読む。** 別の人が選んだ「受け取る」で登録まで進めない
        if let userId { adoptLegacyIntent(for: userId) }
        isEnabled = userId.map { defaults.bool(forKey: Self.enabledKey(for: $0)) } ?? false
        await refreshAuthorization()
        await retryPendingRelease(for: userId)

        // **人が入れ替わったら、前の人の宛先を外す。** 外さないと
        // 同じ端末に前の人あての通知が届き続ける
        if let previous, previous != userId, let token {
            try? await service().unregister(token: token)
            isRegistered = false
        }
        // **「受け取る」と言った人にだけ繋ぎ直す。** 端末の許可だけで
        // 判断すると、自分でオフにしたのに再起動で復活する
        guard userId != nil, isEnabled, isAuthorized else { return }
        // トークンは復元や入れ直しで変わる。**預け直すのは APNs が
        // 返してきた新しいトークン**——手元の古い値を送ると、他人の端末の
        // 枠（`DEVICES_MAX`）を食ったまま 410 が出るまで残る
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// システムの許可状態を読み直す。
    func refreshAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        if !isAuthorized { isRegistered = false }
    }

    /// 設定画面の「受け取る」を押したとき。
    ///
    /// - Returns: 許可されたか。**断られたことを黙って飲み込まない**
    ///   （画面が「設定アプリから許可してください」を出せるように）。
    @discardableResult
    func enable() async -> Bool {
        errorMessage = nil
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            isAuthorized = granted
            guard granted else {
                setEnabled(false)
                return false
            }
            setEnabled(true)
        } catch {
            errorMessage = L("通知の許可を確かめられませんでした", "Couldn't check notification permission")
            return false
        }
        // **ここで初めて APNs に繋ぐ。** トークンは AppDelegate に返ってくる
        UIApplication.shared.registerForRemoteNotifications()
        await registerIfPossible()
        return true
    }

    /// 設定画面の「受け取らない」。**端末の許可は取り消せない**ので、
    /// サーバーから宛先を外す（届かなくなる）。
    ///
    /// 🔴 **外せなかったら、外し終えていない印を残す**（`pendingReleaseOwner`）。
    /// 意思（オフ）は先に残すので、次の起動の `use` は「受け取らない人」として
    /// 素通りしていた——圏外で1回落ちただけで、トグルはオフなのに通知が
    /// 届き続けた。印があれば、次の `use`（起動・同じ人のログイン）と
    /// ログアウト（`signingOut`）が外し直す
    func disable() async {
        // **意思を残す。** 残さないと、OS の許可が生きているので
        // 次の起動で勝手に復活する
        setEnabled(false)
        defer { isRegistered = false }
        guard let token, let userId else { return }
        do {
            try await service().unregister(token: token)
            if pendingReleaseOwner == userId { pendingReleaseOwner = nil }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? L("通知を止められませんでした", "Couldn't turn notifications off")
            markUnreleased(userId)
        }
    }

    /// APNs からトークンが届いた（`AppDelegate` が呼ぶ）。
    func accept(deviceToken: Data) {
        let hex = PushToken.hex(from: deviceToken)
        guard PushToken.isValid(hex) else { return }
        token = hex
        // **オフにした直後に遅れて届いた回に、勝手に戻さない**
        guard isEnabled else { return }
        Task { await registerIfPossible() }
    }

    /// APNs に繋げなかった（圏外・シミュレータなど）。**画面は止めない。**
    func acceptFailure(_ error: Error) {
        // 実機以外では必ずここに来る（シミュレータは APNs に繋がらない）
        print("[push] 端末トークンを取れませんでした: \(error.localizedDescription)")
    }

    /// ログアウトの**前**に呼ぶ。認証が要るので、あとだと外せない。
    ///
    /// **外せなくてもログアウトは止めない**（圏外で「ログアウトできない」に
    /// しない）。外せなかったことは端末に残し、次の出口でやり直す
    /// （`pendingReleaseOwner`）。
    ///
    /// **アイコンの数字と通知センターの通知も消す。** 前の人あての
    /// 「○○さんがいいねしました」が次の人の画面に残らないように
    func signingOut() async {
        errorMessage = nil
        await clearDelivered()
        guard let token, let userId else { return }
        do {
            try await service().unregister(token: token)
            if pendingReleaseOwner == userId { pendingReleaseOwner = nil }
        } catch {
            print("[push] ログアウトで宛先を外せませんでした（次の機会にやり直す）: \(error)")
            markUnreleased(userId)
        }
        isRegistered = false
    }

    /// 外せなかった印を残す（`disable` と `signingOut` の共通の決まり）。
    ///
    /// 🔴 **別の人の印は上書きしない。** 印は1人ぶんしか持てない。
    /// 別の人（A）の印が残っている＝その後この端末で登録が1度も通っていない
    /// （通ればサーバーが A から外し、印も消える——`registerIfPossible`）。
    /// サーバーは宛先1つに持ち主1人なので、そのときこの番号は**まだ A のもの**で、
    /// いまの人（B）の外しそびれは実体の無い空振りのことが多い。上書きすると
    /// **本当に残っている A の宛先の手がかり**を、空振りの印で消していた
    /// （以前は `signingOut` だけ無条件に上書きしていた）
    private func markUnreleased(_ userId: String) {
        if pendingReleaseOwner == nil { pendingReleaseOwner = userId }
    }

    /// 外しそびれた宛先を、外せる人が戻ってきたときに外す。
    ///
    /// **同じ人がまた受け取る設定なら外さない**——このあと登録し直すので、
    /// 外すと登録と行き違う。登録が通れば印は消える（`registerIfPossible`）
    private func retryPendingRelease(for userId: String?) async {
        guard let owner = pendingReleaseOwner, owner == userId else { return }
        guard let token else {
            // 宛先の番号が無い＝サーバーに預けたものも無い
            pendingReleaseOwner = nil
            return
        }
        if isEnabled && isAuthorized { return }
        do {
            try await service().unregister(token: token)
            pendingReleaseOwner = nil
        } catch {
            print("[push] 外しそびれた宛先を外せませんでした: \(error)")
        }
    }

    /// アイコンの数字と、通知センターに残っている通知を消す。
    private func clearDelivered() async {
        let center = UNUserNotificationCenter.current()
        try? await center.setBadgeCount(0)
        center.removeAllDeliveredNotifications()
    }

    /// お知らせを読んだので、アイコンの数字を消す。
    ///
    /// **誰も消さないと増える一方。** サーバーは未読数をそのまま載せるが、
    /// 既読にしたことは端末のアイコンに伝わらない。
    func clearBadge() async {
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
    }

    private func setEnabled(_ value: Bool) {
        isEnabled = value
        // 未ログインでは誰の意思でもないので残さない
        guard let userId else { return }
        defaults.set(value, forKey: Self.enabledKey(for: userId))
    }

    /// 端末全体の「受け取る」を、いまログインしている人に引き継ぐ（1回きり）。
    /// **その人がもう自分の値を持っていれば上書きしない**
    private func adoptLegacyIntent(for userId: String) {
        guard defaults.object(forKey: Self.legacyEnabledKey) != nil else { return }
        let key = Self.enabledKey(for: userId)
        if defaults.object(forKey: key) == nil {
            defaults.set(defaults.bool(forKey: Self.legacyEnabledKey), forKey: key)
        }
        defaults.removeObject(forKey: Self.legacyEnabledKey)
    }

    /// 起動時の確認で**確かにログインしていない**と分かったら呼ぶ
    /// （`JourneyPhotoApp`・`AuthStore.isKnownSignedOut`）。判定に失敗した回には呼ばない。
    ///
    /// 端末全体の「受け取る」は、誰にも引き継がずに捨てる——あとからこの端末で
    /// ログインする人は、その値を選んだ本人とは限らない
    func dropLegacyIntent() {
        defaults.removeObject(forKey: Self.legacyEnabledKey)
    }

    private func registerIfPossible() async {
        guard let token, userId != nil, isEnabled, isAuthorized else { return }
        do {
            try await service().register(token: token)
            isRegistered = true
            // **登録が通れば、前の持ち主からはサーバーが外している**
            // （`devices.ts` の `releasePreviousOwner`）
            pendingReleaseOwner = nil
        } catch {
            isRegistered = false
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? L("通知を受け取る設定にできませんでした", "Couldn't turn notifications on")
        }
    }
}
