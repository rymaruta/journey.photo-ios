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
    /// 🔴 **この端末をサーバーに最後に登録した人**（外せたら消す）。
    ///
    /// 期限切れ（起動時の `restore`・通信中の `expireSession`）は `signingOut` を
    /// 通らず、圏外のログアウトは外せない。**サーバーの `DELETE` はその人の集合から
    /// しか消せない**（`devices.ts`）ので、前の人あての通知が次の人に届き続けていた。
    /// 前の持ち主から外せるのは `POST` だけ（`releasePreviousOwner`）。
    ///
    /// **出来事ではなく状態で見る。** 「外せなかった」の印を出来事ごとに立てると、
    /// 起動時の期限切れのように**前の人を一度も見ないまま**抜ける経路を取りこぼす。
    /// 人ではなく端末に付く
    private static let ownerKey = "photo-gallery-push-owner"
    /// 持ち主を一度でも書いたか。**書く前の版から上げた端末では持ち主が分からない**
    /// ——旧版で通知を受け取っていた人が、更新後に一度も登録しないまま期限切れに
    /// なると、前の人あての宛先が残る。分からない間は、次にログインした人で引き取る
    private static let ownerKnownKey = "photo-gallery-push-owner-known"
    private var owner: String? {
        get { defaults.string(forKey: Self.ownerKey) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Self.ownerKey)
            } else {
                defaults.removeObject(forKey: Self.ownerKey)
            }
            defaults.set(true, forKey: Self.ownerKnownKey)
        }
    }
    /// サーバーに前の持ち主が残っているかもしれない（別の人・または分からない）
    private func mayBelongToSomeoneElse(than userId: String) -> Bool {
        guard defaults.bool(forKey: Self.ownerKnownKey) else { return true }
        return owner.map { $0 != userId } ?? false
    }
    private let defaults: UserDefaults
    private var userId: String?
    private let service: () -> PushService

    init(service: @escaping () -> PushService = { PushService(api: APIClient(tokenProvider: CognitoTokenProvider())) },
         defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Self.legacyEnabledKey)
    }

    /// 起動時とログイン状態が変わるたびに呼ぶ。
    func use(userId: String?) async {
        let previous = self.userId
        self.userId = userId
        if previous != userId { loadIntent(for: userId) }
        await refreshAuthorization()

        if let previous, previous != userId { isRegistered = false }
        // **前の人の宛先が残っていたら、いまの人で外す。** 外さないと
        // 同じ端末に前の人あての通知が届き続ける。
        //
        // ここで前の人のぶんを `DELETE` しても外れない。ログアウト後は前の人の
        // ID トークンが無く、次の人が入ったあとは**次の人の集合**から消すだけ
        if let userId, let token, mayBelongToSomeoneElse(than: userId) {
            await releasePreviousOwner(token: token, as: userId)
        }
        // **外し損ねた宛先を外し直す**（「受け取らない」にした回に圏外だった・
        // 前の人から引き取ったあと外せなかった）
        if let userId, !isEnabled, let token,
           defaults.bool(forKey: Self.pendingUnregisterKey(for: userId)) || owner == userId {
            if (try? await service().unregister(token: token)) != nil {
                defaults.removeObject(forKey: Self.pendingUnregisterKey(for: userId))
                if owner == userId { owner = nil }
                // 外している間に「受け取る」を押された（`enable` の登録を消している）
                if isEnabled, self.userId == userId { await registerIfPossible() }
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
            if owner == userId { owner = nil }
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
    ///
    /// 外せなかったら（圏外など）持ち主（`owner`）が残り、次にログインした人で外す。
    func signingOut() async {
        guard let token, let userId else { return }
        if (try? await service().unregister(token: token)) != nil, owner == userId {
            owner = nil
        }
        isRegistered = false
    }

    /// 前の持ち主からこの端末を外し、いまの人が引き取る（`owner`）。
    ///
    /// 登録（`POST`）がサーバーで前の持ち主の集合からトークンを落とす。
    /// **受け取らない人なら、そのあと外す**のは `use` の「外し損ね」の段
    /// （`owner == userId` かつ `!isEnabled`）——落ちても持ち主が残るので、
    /// 次の `use` でやり直せる。受け取る人は外さない（外すと、このあと APNs
    /// からトークンが返らなかった回に、その人の通知まで止まる）
    private func releasePreviousOwner(token: String, as userId: String) async {
        guard (try? await service().register(token: token)) != nil else { return }
        owner = userId
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
        guard let token, let userId, isEnabled, isAuthorized else { return }
        do {
            try await service().register(token: token)
            // **サーバーの持ち主はこの人になった**（`devices.ts` の逆引き）。
            // 待っている間に人が替わっていても書く（次の `use` が引き取る手がかり）
            owner = userId
            // 画面の「預けてある」は、いまの人のぶんだけ
            guard self.userId == userId else { return }
            isRegistered = true
        } catch {
            // 待っている間に人が替わった: 前の人の失敗を次の人の画面に出さない
            guard self.userId == userId else { return }
            isRegistered = false
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? L("通知を受け取る設定にできませんでした", "Couldn't turn notifications on")
        }
    }
}
