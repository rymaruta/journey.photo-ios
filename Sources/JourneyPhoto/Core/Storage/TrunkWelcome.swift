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
/// - 配ったら `trunkCoinsChanged` を流す。硬貨の数を見せている画面（トランク・カプセルの機械）が読み直す
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
        center.post(name: .trunkCoinsChanged, object: nil, userInfo: ["coins": result.coins])
        // 増えていない（上限に当たっていた）回と、待つ間に人が替わった回は案内を出さない
        guard result.added > 0, owner == userId else { return nil }
        let grant = Grant(added: result.added, coins: result.coins)
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

    /// 出す中身を受け取る（受け取ったら空にする）
    func consume() -> Grant? {
        defer { pending = nil }
        return pending
    }

    /// 入っている人が替わった（ログアウトを含む）。前の人の案内を下ろす
    func noteUser(_ userId: String?) {
        guard userId != owner else { return }
        owner = userId
        pending = nil
    }

    /// 退会のとき（`AccountLocalData.remove`）
    nonisolated static func removeData(for userId: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(userId))
    }
}

/// `POST /user/trunk/welcome` の答え。数は寛容に読む（`LenientInt`）。granted が無い本文は読めない扱い
struct TrunkWelcomeResult: Decodable, Equatable {
    let granted: Bool
    let added: Int
    let coins: Int

    init(granted: Bool, added: Int, coins: Int) {
        self.granted = granted
        self.added = max(0, added)
        self.coins = max(0, coins)
    }

    private enum CodingKeys: String, CodingKey { case granted, added, coins }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // granted が無い本文は答えと見なさない（投げる＝印を残さず、次に開いたときにまた呼ぶ）
        self.init(granted: try c.decode(Bool.self, forKey: .granted),
                  added: LenientInt.read(c, .added) ?? 0, coins: LenientInt.read(c, .coins) ?? 0)
    }
}

extension Notification.Name {
    /// 旅のトランクの硬貨がサーバーで増えた（はじめての硬貨・`TrunkWelcome`）。`userInfo["coins"]` は増えたあとの数。
    /// `TrunkViewModel` が受けて読み直す（トランク・カプセルの機械の数を新しくする）
    static let trunkCoinsChanged = Notification.Name("jp.trunkCoinsChanged")
}
