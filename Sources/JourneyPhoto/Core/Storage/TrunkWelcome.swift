import Foundation
import Combine

/// 旅のトランクの「はじめての硬貨」（2026-10-18 owner 承認）。硬貨が始まる前から居る利用者に、一度だけ硬貨 10 枚。
///
///     POST /user/trunk/welcome（認証つき・本文なし）→ { granted, added, coins }
///
/// - `granted` は**この呼び出しで新しく配った**ときだけ true。既に配った・対象外は false（200）
/// - 200 の答え（granted が true でも false でも）を受けたら、その人（uid ごと）では**以後呼ばない印**を端末に残す
/// - 失敗（古いサーバーで口が無い 404・圏外・500・読めない本文）は**印を残さない**——次に開いたときにまた呼ぶ。
///   ただし**同じ起動中に同じ人で二度は呼ばない**（`triedThisLaunch`）
/// - 配った回だけ、`RootView` がほかの画面と重ならない頃合いに案内を1回出す（`PostModalGate.welcomeMayShow`）
/// - **出す案内も uid ごとに端末へ控える**（`trunk.welcome.pending.<uid>`・2026-10-18 の見直し）。呼ぶ印は応答のときに
///   残るので、案内をメモリにだけ持つと、出す前に待ちが切れた・アプリが終わった・落ちた回に**二度と出ない**。
///   控えは出したら消し、次の起動では控えがあればサーバーを呼ばずに戻す（`restore`）
/// - 配ったら `trunkCoinsChanged` を流す（`userInfo` に uid）。硬貨の数を見せている画面（トランク・カプセルの機械）が
///   **自分の人の知らせだけ**を受けて読み直す
@MainActor
final class TrunkWelcome: ObservableObject {

    static let shared = TrunkWelcome()

    /// 案内に出す中身
    struct Grant: Identifiable, Equatable {
        /// この回に増えた枚数（上限 99 に当たると 10 より少ない）
        let added: Int
        /// 配ったあとの手持ちの硬貨
        let coins: Int
        var id: String { "\(added)-\(coins)" }
    }

    /// 増えるたびに `RootView` が出す頃合いを見る
    @Published private(set) var requests = 0
    private(set) var pending: Grant?

    private let defaults: UserDefaults
    private let center: NotificationCenter
    /// この起動で呼んだ人（失敗しても同じ起動中は呼び直さない）
    private var triedThisLaunch: Set<String> = []
    /// 案内を出す相手（人が替わったら前の人の案内を下ろす）
    private var owner: String?

    init(defaults: UserDefaults = .standard, center: NotificationCenter = .default) {
        self.defaults = defaults
        self.center = center
    }

    nonisolated static func key(_ userId: String) -> String { "trunk.welcome.done.\(userId)" }
    /// まだ出していない案内の控え（`added`・`coins`）
    nonisolated static func pendingKey(_ userId: String) -> String { "trunk.welcome.pending.\(userId)" }

    /// 端末に控えた、まだ出していない案内（無ければ nil）
    func storedGrant(_ userId: String) -> Grant? {
        guard let raw = defaults.dictionary(forKey: Self.pendingKey(userId)),
              let added = raw["added"] as? Int, added > 0 else { return nil }
        return Grant(added: added, coins: max(0, raw["coins"] as? Int ?? 0))
    }

    /// 起動のとき（人が替わったときも）: 控えた案内があれば、サーバーを呼ばずに出す待ちへ戻す。戻したら true
    @discardableResult
    func restore(userId: String?) -> Bool {
        noteUser(userId)
        guard let userId, pending == nil, let grant = storedGrant(userId) else { return false }
        pending = grant
        requests += 1
        return true
    }

    /// その人について、もう答えをもらったか（以後呼ばない印）
    func isDone(_ userId: String) -> Bool { defaults.bool(forKey: Self.key(userId)) }

    /// 呼んでよいか（入っている・トランクが使える・印が無い・この起動でまだ呼んでいない）
    func shouldClaim(userId: String?, available: Bool) -> Bool {
        guard let userId, !userId.isEmpty, available else { return false }
        return !isDone(userId) && !triedThisLaunch.contains(userId)
    }

    /// 呼ぶ。配った回だけ案内の中身を返す（`pending` にも入る）。呼ばなかった・失敗・配らなかった回は nil
    @discardableResult
    func claim(userId: String?, available: Bool,
               call: () async throws -> TrunkWelcomeResult) async -> Grant? {
        guard shouldClaim(userId: userId, available: available), let userId else { return nil }
        noteUser(userId)
        triedThisLaunch.insert(userId)
        let result: TrunkWelcomeResult
        do {
            result = try await call()
        } catch is CancellationError {
            // 取り消し（人が替わった・画面が消えた）は呼んだうちに数えない
            triedThisLaunch.remove(userId)
            return nil
        } catch {
            // 古いサーバー（404）・圏外・500: 印を残さず、次に開いたときにまた呼ぶ
            return nil
        }
        // 答えをもらった: 配った・既に配った・対象外のどれでも、この人では以後呼ばない
        defaults.set(true, forKey: Self.key(userId))
        guard result.granted else { return nil }
        let grant = Grant(added: result.added, coins: result.coins)
        // 増えた回は案内を端末に控える（待つ間に人が替わっても、その人が次に開いたときに出す）
        if result.added > 0 {
            defaults.set(["added": grant.added, "coins": grant.coins], forKey: Self.pendingKey(userId))
        }
        // 待つ間に人が替わった回は、いまの人の画面に知らせも案内も出さない
        guard owner == userId else { return nil }
        center.post(name: .trunkCoinsChanged, object: nil, userInfo: ["coins": result.coins, "userId": userId])
        // 増えていない（上限に当たっていた）回は案内を出さない（「+0 枚」を見せない）
        guard result.added > 0 else { return nil }
        pending = grant
        requests += 1
        return grant
    }

    /// 画面写真の見本（`-JPPreviewTrunkWelcome`）。サーバーには何も送らない
    func deliverPreview(_ grant: Grant) {
        pending = grant
        requests += 1
    }

    var hasPending: Bool { pending != nil }

    /// 出す中身を受け取る（受け取ったら空にする）。**端末の控えは消さない**——全画面が実際に出たときに
    /// `noteShown` で消す（2026-10-18 の見直し: 同じ瞬間に別のシートが出始めて全画面が出なかった回に、案内が二度と出なくなる）
    func consume() -> Grant? {
        defer { pending = nil }
        return pending
    }

    /// 案内の全画面が実際に出た（`TrunkWelcomeView` の `onAppear`）。端末の控えを消す＝次の起動ではもう出さない
    func noteShown(userId: String?) {
        guard let userId else { return }
        defaults.removeObject(forKey: Self.pendingKey(userId))
    }

    /// 出そうとした全画面が出なかった（ほかのシートと重なった）。出す待ちへ戻す（同じ人のときだけ）
    func requeue(_ grant: Grant, userId: String?) {
        guard userId == owner, pending == nil else { return }
        pending = grant
    }

    /// 入っている人が替わった（ログアウトを含む）。前の人の案内を下ろす（端末の控えは残す＝その人が次に開いたときに出す）
    func noteUser(_ userId: String?) {
        guard userId != owner else { return }
        owner = userId
        pending = nil
    }

    /// 退会のとき（`AccountLocalData.remove`）
    nonisolated static func removeData(for userId: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(userId))
        defaults.removeObject(forKey: pendingKey(userId))
    }
}

/// `POST /user/trunk/welcome` の答え。数は寛容に読む（`LenientInt`）。granted が無い本文は読めない扱い
///
/// アイコン・カバーのお礼（`POST /user/trunk/reward`・#304）も同じ形で、`rewarded`（その種類のお礼の印が立っているか）が
/// 足される。はじめての硬貨は返さない（nil）
struct TrunkWelcomeResult: Decodable, Equatable {
    let granted: Bool
    let added: Int
    let coins: Int
    let rewarded: Bool?

    init(granted: Bool, added: Int, coins: Int, rewarded: Bool? = nil) {
        self.granted = granted
        self.added = max(0, added)
        self.coins = max(0, coins)
        self.rewarded = rewarded
    }

    private enum CodingKeys: String, CodingKey { case granted, added, coins, rewarded }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // granted が無い本文は答えと見なさない（投げる＝印を残さず、次に開いたときにまた呼ぶ）
        self.init(granted: try c.decode(Bool.self, forKey: .granted),
                  added: LenientInt.read(c, .added) ?? 0, coins: LenientInt.read(c, .coins) ?? 0,
                  rewarded: try? c.decodeIfPresent(Bool.self, forKey: .rewarded))
    }
}

extension Notification.Name {
    /// 旅のトランクの硬貨がサーバーで増えた（はじめての硬貨・`TrunkWelcome`）。`userInfo["coins"]` は増えたあとの数、
    /// `userInfo["userId"]` は配った人。`TrunkViewModel` が**自分の人の知らせだけ**受けて読み直す（トランク・カプセルの機械の数）
    static let trunkCoinsChanged = Notification.Name("jp.trunkCoinsChanged")
}
