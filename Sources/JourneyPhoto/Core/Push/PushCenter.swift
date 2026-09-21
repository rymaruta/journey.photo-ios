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
    private static let enabledKey = "photo-gallery-push-enabled"
    private let defaults: UserDefaults
    private var userId: String?
    private let service: () -> PushService

    init(service: @escaping () -> PushService = { PushService(api: APIClient(tokenProvider: CognitoTokenProvider())) },
         defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    /// 起動時とログイン状態が変わるたびに呼ぶ。
    func use(userId: String?) async {
        let previous = self.userId
        self.userId = userId
        await refreshAuthorization()

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
    func disable() async {
        // **意思を残す。** 残さないと、OS の許可が生きているので
        // 次の起動で勝手に復活する
        setEnabled(false)
        defer { isRegistered = false }
        guard let token, userId != nil else { return }
        do {
            try await service().unregister(token: token)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? L("通知を止められませんでした", "Couldn't turn notifications off")
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
    func signingOut() async {
        guard let token, userId != nil else { return }
        try? await service().unregister(token: token)
        isRegistered = false
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
        defaults.set(value, forKey: Self.enabledKey)
    }

    private func registerIfPossible() async {
        guard let token, userId != nil, isEnabled, isAuthorized else { return }
        do {
            try await service().register(token: token)
            isRegistered = true
        } catch {
            isRegistered = false
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? L("通知を受け取る設定にできませんでした", "Couldn't turn notifications on")
        }
    }
}
