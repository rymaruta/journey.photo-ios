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
    // 🔴 **ログアウトの前に宛先を外せなかった回**（ログインの期限切れ・圏外・
    // 退会の途中）の後始末は、2つの印で持つ。外す口（`DELETE /user/devices`）は
    // **その人の認証で、その人の集合からしか消せない**（`devices.ts`）ので、
    // あとからは前の人の認証で外せない。放っておくと、前の人あての通知
    // （行動した人の名前）が、ログアウトした端末や次の人に届き続ける。
    //
    // | 場面                               | `registeredOwner`（端末）  | `owner`（サーバー）              |
    // |------------------------------------|----------------------------|----------------------------------|
    // | 誰もログインしない                 | 端末ごと APNs から外す     | 残す（次の人が引き取る）         |
    // | 次の人がログイン（受け取らない）   | 端末ごと APNs から外す     | 次の人で POST → DELETE           |
    // | 次の人がログイン（受け取る）       | 預け直しが落ちたら外す     | 次の人で POST（引き取る）        |
    // | 持ち主を書く前の版から上げた端末   | —                          | 次にログインした人で一度引き取る |
    // | 次の人が預けられない（登録・APNs の失敗・受け取らない） | 端末ごと外す（`owner` が別の人でも） | 残す |
    // | 登録の通信中に人が替わった         | いまの人が預け直す・預けないなら端末ごと外す | 同左 |

    /// 🔴 **この端末の宛先を、いま届く形で預けてある人。** 端末に残す。
    ///
    /// 前の人の認証が無くても、**端末ごと APNs から外せば**すぐ届かなくなる
    /// （サーバーは次に送ったときに 410 を受けて宛先を捨てる）。端末ごと外したら
    /// 消す——起動のたびに外して付け直さない
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
    /// 🔴 **この端末をサーバーに最後に登録した人**（サーバーから外せたら消す）。
    ///
    /// 端末ごと外しても、サーバーの前の人の集合にはトークンが 410 まで残る。
    /// 前の持ち主から外せるのは `POST` だけ（`releasePreviousOwner`）なので、
    /// 次にログインした人で引き取る。
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
    /// サーバーに預けられた（登録・引き取り）。**2つの印をこの人にする**
    private func noteRegistered(by userId: String) {
        owner = userId
        registeredOwner = userId
    }
    /// この人の認証でサーバーから外せた。**この人の印だけ消す**——前の人の印
    /// （預け直しが落ちて残ったもの）は、この人の認証では外れていない
    private func noteUnregistered(by userId: String) {
        if owner == userId { owner = nil }
        if registeredOwner == userId { registeredOwner = nil }
    }
    private let defaults: UserDefaults
    private var userId: String?
    private let service: () -> PushService
    /// 端末ごと APNs から外す（`unregisterForRemoteNotifications`）。試験で差し替える
    private let releaseDevice: @MainActor () -> Void
    /// システムの許可を読む。試験で差し替える（模型では許可が取れない）
    private let readAuthorization: () async -> Bool

    init(service: @escaping () -> PushService = { PushService(api: APIClient(tokenProvider: CognitoTokenProvider())) },
         defaults: UserDefaults = .standard,
         releaseDevice: @escaping @MainActor () -> Void = { UIApplication.shared.unregisterForRemoteNotifications() },
         readAuthorization: @escaping () async -> Bool = {
             let settings = await UNUserNotificationCenter.current().notificationSettings()
             return settings.authorizationStatus == .authorized
                 || settings.authorizationStatus == .provisional
         }) {
        self.service = service
        self.defaults = defaults
        self.releaseDevice = releaseDevice
        self.readAuthorization = readAuthorization
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

        if let previous, previous != userId { isRegistered = false }
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
        if let leftover = registeredOwner, leftover != userId {
            let registersNow = userId != nil && isEnabled && isAuthorized
            if registersNow {
                // 印は残す。預け直せたら次の人の印に替わる（`registerIfPossible`）。
                // 落ちたら印が残り、次の `use` でもう一度見る
            } else {
                releaseForeignRegistration(except: userId)
            }
            isRegistered = false
        }
        // **サーバーに前の人の宛先が残っていたら、いまの人で引き取る。** 端末ごと
        // 外しても、前の人の集合には 410 までトークンが残る（誰もログインしない
        // 間は上の段が端末ごと外し、ここは次にログインした人を待つ）。
        //
        // ここで前の人のぶんを `DELETE` しても外れない。ログアウト後は前の人の
        // ID トークンが無く、次の人が入ったあとは**次の人の集合**から消すだけ
        if let userId, let token, mayBelongToSomeoneElse(than: userId) {
            await releasePreviousOwner(token: token, as: userId)
            guard self.userId == userId else { return }
        }
        // **外し損ねた宛先を外し直す**（「受け取らない」にした回に圏外だった・
        // 前の人から引き取ったあと外せなかった）
        if let userId, !isEnabled, let token,
           defaults.bool(forKey: Self.pendingUnregisterKey(for: userId)) || owner == userId {
            if (try? await service().unregister(token: token)) != nil {
                defaults.removeObject(forKey: Self.pendingUnregisterKey(for: userId))
                noteUnregistered(by: userId)
                // 外している間に「受け取る」を押された（`enable` の登録を消している）
                if isEnabled, self.userId == userId { await registerIfPossible() }
            }
            guard self.userId == userId else { return }
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
        isAuthorized = await readAuthorization()
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
        // 前の人の宛先が残っていたら（預け直しで上書きできないまま）端末ごと外す
        // （この人の DELETE はこの人の集合からしか消せない）
        releaseLeftovers(except: userId)
        guard let token, let userId else { return }
        do {
            try await service().unregister(token: token)
            defaults.removeObject(forKey: Self.pendingUnregisterKey(for: userId))
            noteUnregistered(by: userId)
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
        // **預け直せなかったのと同じ。** 前の人の宛先を、次の `use` まで残さない
        guard userId != nil, isEnabled else { return }
        releaseLeftovers(except: userId)
    }

    /// ログアウトの**前**に呼ぶ。認証が要るので、あとだと外せない。
    ///
    /// 外せなかったら（圏外など）印が残り、ログアウトのあとの `use` が端末ごと
    /// 外し（`registeredOwner`）、次にログインした人がサーバーから引き取る（`owner`）
    func signingOut() async {
        guard let token, let userId else { return }
        // **外せた回だけ、自分の印だけ消す。** 前の人の印（預け直しが落ちて
        // 残ったもの）は、この人の認証では外れていないので残す
        if (try? await service().unregister(token: token)) != nil {
            noteUnregistered(by: userId)
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
        noteRegistered(by: userId)
        if self.userId != userId { await settleLateRegistration() }
    }

    /// 預け終えたときには、呼んだ人がもういまの人でなかった（通信中のログアウト・
    /// 期限切れ・入れ替わり）。**その間に走った `use` はまだ印を見ていない**ので、
    /// ここで片づける——残すと、誰もログインしていない端末や次の人に、呼んだ人あての
    /// 通知が届く。いまの人が預けるなら預け直し（サーバーが呼んだ人から外す）、
    /// 預けないなら端末ごと外す
    private func settleLateRegistration() async {
        if userId != nil, isEnabled, isAuthorized {
            await registerIfPossible()
        } else {
            releaseForeignRegistration(except: userId)
        }
    }

    /// **この人で預けられなかった**（登録の失敗・APNs に繋げない・受け取らない）ときの
    /// 後始末。前の人の宛先が端末に届く形で残っていたら、端末ごと APNs から外す。
    ///
    /// 端末の印（`registeredOwner`）だけでなく、**サーバーの持ち主（`owner`）が分かっていて
    /// 別の人**のときも外す。端末の印は、誰もログインしない間に一度外した時点で消えるが、
    /// そのあと APNs に繋ぎ直すと、サーバーの前の人の集合に残ったトークンへまた届く。
    /// `owner` は消さない（次の引き取りの手がかり）。持ち主が分からない端末では外さない
    /// ——旧版で受け取っていた本人の通知まで止める。`use` の中では使わない（ログアウト中の
    /// 起動のたびに外し直すことになる）
    private func releaseLeftovers(except userId: String?) {
        let onDevice = registeredOwner.map { $0 != userId } ?? false
        let onServer = defaults.bool(forKey: Self.ownerKnownKey) && owner != nil && owner != userId
        guard onDevice || onServer else { return }
        if token != nil { releaseDevice() }
        if onDevice { registeredOwner = nil }
    }

    /// 前の人の宛先が残っていたら、端末ごと APNs から外して印を消す
    private func releaseForeignRegistration(except userId: String?) {
        guard let owner = registeredOwner, owner != userId else { return }
        if token != nil { releaseDevice() }
        registeredOwner = nil
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

    /// 試験から失敗の経路を通すため internal（画面からは呼ばない）
    func registerIfPossible() async {
        guard let token, let owner = userId, isEnabled, isAuthorized else { return }
        do {
            try await service().register(token: token)
            // **呼んだ時点の人を控える**（返ってくる間に替わっていても、
            // サーバーに預けたのはこの人の宛先・次の `use` が引き取る手がかり）
            noteRegistered(by: owner)
            // 画面の「預けてある」は、いまの人のぶんだけ
            guard userId == owner else {
                await settleLateRegistration()
                return
            }
            isRegistered = true
        } catch {
            // **呼んでいる間に人が替わっていたら触らない**（遅れて返った前の人の
            // 失敗で、次の人の宛先を外さない・次の人の画面に出さない）
            guard userId == owner else { return }
            isRegistered = false
            // **預け直せなかったら前の人の宛先を残さない。** 前の人の印を残したまま
            // 落ち続けると、この人がログインしている間ずっと前の人あてに届く
            releaseLeftovers(except: owner)
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? L("通知を受け取る設定にできませんでした", "Couldn't turn notifications on")
        }
    }
}
