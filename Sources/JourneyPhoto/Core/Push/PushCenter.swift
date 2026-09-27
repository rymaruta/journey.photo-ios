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
    /// 「受け取る」の意思。**人ごとに分ける**——端末に1つだと、前の人がオンに
    /// したまま次の人がログインしたとき、本人は何もしていないのに宛先が登録され、
    /// 設定のトグルもオンに見えていた。ログイン前（人が決まる前）は昔からの鍵を読む
    private static let legacyEnabledKey = "photo-gallery-push-enabled"
    private static func enabledKey(for userId: String?) -> String {
        userId.map { "\(legacyEnabledKey).\($0)" } ?? legacyEnabledKey
    }
    /// 「受け取らない」にしたのに、サーバーから宛先を外せなかった（圏外など）。
    /// 次にその人で開いたときに外し直す
    private static func pendingUnregisterKey(for userId: String) -> String {
        "photo-gallery-push-unregister-pending.\(userId)"
    }
    /// 🔴 **この端末の宛先をサーバーに預けてある人。** 端末に残す。
    ///
    /// ログアウトの前に外せなかった回（ログインの期限切れ・圏外）は、外す口
    /// （`DELETE /user/devices`）が前の人の認証を要るので、あとからは外せない。
    /// 放っておくと、ログアウトした端末に前の人あての通知（行動した人の名前）が
    /// 届き続ける。起動をまたいでも気づけるように、預けた人を覚えておく
    private static let registeredOwnerKey = "photo-gallery-push-registered-owner"
    private var registeredOwner: String? {
        get { defaults.string(forKey: Self.registeredOwnerKey) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Self.registeredOwnerKey)
            } else {
                defaults.removeObject(forKey: Self.registeredOwnerKey)
            }
        }
    }
    private let defaults: UserDefaults
    private var userId: String?
    private let service: () -> PushService
    /// 端末ごと APNs から外す（`unregisterForRemoteNotifications`）。試験で差し替える
    private let releaseDevice: @MainActor () -> Void

    init(service: @escaping () -> PushService = { PushService(api: APIClient(tokenProvider: CognitoTokenProvider())) },
         defaults: UserDefaults = .standard,
         releaseDevice: @escaping @MainActor () -> Void = { UIApplication.shared.unregisterForRemoteNotifications() }) {
        self.service = service
        self.defaults = defaults
        self.releaseDevice = releaseDevice
        self.isEnabled = defaults.bool(forKey: Self.legacyEnabledKey)
    }

    /// 退会した人の控えを消す（`AccountLocalData`）。「受け取る」の意思と、
    /// 外し損ねの印。**預けた人の印はここでは消さない**——退会の直後の
    /// `use(userId: nil)` がそれを見て、外し損ねていれば端末ごと外す
    static func removeLocalData(for userId: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: enabledKey(for: userId))
        defaults.removeObject(forKey: pendingUnregisterKey(for: userId))
    }

    /// 起動時とログイン状態が変わるたびに呼ぶ。
    func use(userId: String?) async {
        let previous = self.userId
        self.userId = userId
        if previous != userId { loadIntent(for: userId) }
        await refreshAuthorization()
        // 待っている間に次の `use` が始まっていたら、そちらに任せる
        guard self.userId == userId else { return }

        // 🔴 **前の人の宛先が残っている**（ログアウトの前に外せなかった:
        // ログインの期限切れ・圏外・退会の途中）。前の人の認証はもう無いので
        // サーバーからは外せない。**端末ごと APNs から外す**——サーバーは
        // 次に送ったときに 410 を受けて宛先を捨てる（`notify.ts` の
        // `forgetTokens`）。次の人がすぐ預け直すなら要らない（サーバーの登録が
        // 前の持ち主から外す・`devices.ts` の `releasePreviousOwner`）
        //
        // **印だけで決める。** ふつうのログアウトは先に外せている（`signingOut`
        // が印を消す）ので、ここで端末ごと外さない。更新前から預けていた人は、
        // 次にその人で開いたときの登録で印が付く
        if let owner = registeredOwner, owner != userId {
            let registersNow = userId != nil && isEnabled && isAuthorized
            if registersNow {
                // 印は残す。預け直せたら次の人の印に替わる（`registerIfPossible`）。
                // 落ちたら印が残り、次の `use` でもう一度見る
            } else {
                if token != nil { releaseDevice() }
                registeredOwner = nil
            }
            isRegistered = false
        }
        // **外し損ねた宛先を外し直す**（「受け取らない」にした回に圏外だった）
        if let userId, !isEnabled, let token,
           defaults.bool(forKey: Self.pendingUnregisterKey(for: userId)) {
            if (try? await service().unregister(token: token)) != nil {
                defaults.removeObject(forKey: Self.pendingUnregisterKey(for: userId))
                if registeredOwner == userId { registeredOwner = nil }
            }
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
        // **押した人を控える。** 許可のダイアログを出している間にログインが切れる
        // （`expireSession`）と、答えが次の人（や端末共通の鍵）に書かれていた
        let owner = userId
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            isAuthorized = granted
            guard let owner, owner == userId else {
                // 人が替わった／ログインしていない: 押した人の鍵にだけ残す
                if let owner { defaults.set(granted, forKey: Self.enabledKey(for: owner)) }
                return granted
            }
            guard granted else {
                setEnabled(false)
                return false
            }
            setEnabled(true)
            // オンにし直したので、外し損ねの印はもう要らない
            defaults.removeObject(forKey: Self.pendingUnregisterKey(for: owner))
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
        guard let token, let userId else { return }
        do {
            try await service().unregister(token: token)
            defaults.removeObject(forKey: Self.pendingUnregisterKey(for: userId))
            if registeredOwner == userId { registeredOwner = nil }
        } catch {
            // 外せなかったことを覚え、次に開いたときに外し直す（`use`）
            defaults.set(true, forKey: Self.pendingUnregisterKey(for: userId))
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
        // **外せた回だけ印を消す。** 外せなかったら、ログアウトのあとの
        // `use` が印を見て端末ごと外す
        if (try? await service().unregister(token: token)) != nil {
            registeredOwner = nil
        }
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
        defaults.set(value, forKey: Self.enabledKey(for: userId))
    }

    /// その人の「受け取る」を読む。**人ごとの鍵がまだ無く、昔の端末共通の鍵が
    /// オンなら、最初にログインした人のものとして一度だけ移す**（更新前にオンにした
    /// 人が、更新でオフに戻らないように）
    private func loadIntent(for userId: String?) {
        if let userId, defaults.object(forKey: Self.enabledKey(for: userId)) == nil,
           defaults.bool(forKey: Self.legacyEnabledKey) {
            defaults.set(true, forKey: Self.enabledKey(for: userId))
            defaults.removeObject(forKey: Self.legacyEnabledKey)
        }
        isEnabled = defaults.bool(forKey: Self.enabledKey(for: userId))
        errorMessage = nil
    }

    private func registerIfPossible() async {
        guard let token, let owner = userId, isEnabled, isAuthorized else { return }
        do {
            try await service().register(token: token)
            isRegistered = true
            // **呼んだ時点の人を控える**（返ってくる間に替わっていても、
            // サーバーに預けたのはこの人の宛先）
            registeredOwner = owner
        } catch {
            isRegistered = false
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? L("通知を受け取る設定にできませんでした", "Couldn't turn notifications on")
        }
    }
}
