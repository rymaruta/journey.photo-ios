import Foundation
import Combine

/// アイコン・カバーを初めて設定したお礼（#304・2026-10-18 owner「3枚ずつ」）。それぞれ一度だけ、旅のトランクの硬貨3枚。
///
///     POST /user/trunk/reward { kind: avatar | cover } → { granted, added, coins }
///
/// 配るか・何枚かは**サーバーが決める**（実体を確かめて印を立てる・`api-user/src/trunk.ts` の `rewardCoins`）。ここは呼んで知らせるだけ:
/// - プロフィールの編集で保存が通ったあと（`claim`）。知らせは編集を閉じてから（`editorOpen` が下りてから）
/// - **すでに設定済みの人にも、次に開いたときに1回**（はじめての硬貨と同じ呼び方・`claimExisting`）。
///   2つとも呼び、足せた分を1枚の知らせにまとめる（両方で +6）。**2つとも `rewarded` が true になったら**
///   以後起動のときに呼ばない（まだ設定していない種類がある間は、起動のたびに確かめ直す・2026-10-18 見直し）
/// - **置いた直後は「まだ無い」と答えることがある**（サーバーは公開の CDN に HEAD で聞き、CDN は無いキーの 404 を約10秒覚える）。
///   保存のあとに頼んで足せず印も無ければ、`retryDelay`（約12秒）おいて1回だけ頼み直す
/// - **知らせは `added > 0` のときだけ**（もらい済み・上限に当たった回は出さない）。足せたら `trunkCoinsChanged` を流す
/// - 出す知らせは uid ごとに端末へ控え、出たら消す（`TrunkWelcome` と同じ・待ちが切れた回に二度と出なくならない）
/// - 起動のときにまとめて渡す分は、はじめての硬貨の案内を出した起動では出さない（同じ全画面を続けて出さない・板 53 の付箋）。
///   控えてあるので次の起動で出る
@MainActor
final class ProfileReward: ObservableObject {

    static let shared = ProfileReward()

    enum Kind: String, CaseIterable, Equatable {
        case avatar
        case cover
    }

    /// 知らせに出す中身
    struct Grant: Identifiable, Equatable {
        /// 足せた種類（両方なら [.avatar, .cover]）
        let kinds: [Kind]
        /// 足せた枚数の合計
        let added: Int
        /// 足したあとの手持ち
        let coins: Int
        /// 起動のときに、前から設定していた分をまとめて渡した回か
        var existing = false
        var id: String { "\(kinds.map(\.rawValue).joined(separator: "+"))-\(added)-\(coins)" }
    }

    /// 増えるたびに `RootView` が出す頃合いを見る
    @Published private(set) var requests = 0
    /// プロフィールの編集が開いている（知らせは閉じてから出す・板 53）
    @Published var editorOpen = false
    private(set) var pending: Grant?

    private let defaults: UserDefaults
    private let center: NotificationCenter
    private var owner: String?
    /// この起動で、起動のときの呼び出しをした人
    private var triedThisLaunch: Set<String> = []
    /// 頼み直すまでの待ち（試験は差し替える）
    private let retryWait: () async -> Void

    /// CDN が 404 を覚える約10秒より少し長く
    nonisolated static let retryDelay: TimeInterval = 12

    init(defaults: UserDefaults = .standard, center: NotificationCenter = .default,
         retryWait: @escaping () async -> Void = { try? await Task.sleep(nanoseconds: UInt64(ProfileReward.retryDelay * 1_000_000_000)) }) {
        self.defaults = defaults
        self.center = center
        self.retryWait = retryWait
    }

    nonisolated static func existingKey(_ userId: String) -> String { "profile.reward.existing.\(userId)" }
    nonisolated static func pendingKey(_ userId: String) -> String { "profile.reward.pending.\(userId)" }

    var hasPending: Bool { pending != nil }

    /// 保存が通ったあとに呼ぶ。足せた回だけ知らせの中身を返す（`pending` にも入る）
    @discardableResult
    func claim(_ kinds: [Kind], userId: String?, available: Bool,
               call: (Kind) async throws -> TrunkWelcomeResult) async -> Grant? {
        guard let userId, !userId.isEmpty, available, !kinds.isEmpty else { return nil }
        noteUser(userId)
        var got: [Kind] = []
        var added = 0
        var coins: Int?
        for kind in kinds {
            // 失敗（古いサーバーの 404・圏外）は黙って飛ばす。サーバーに印が立っていないので、
            // 起動のときの呼び出し（まだならそこで）か、次に設定し直したときに渡せる
            guard var result = try? await call(kind) else { continue }
            // 置いた直後で CDN がまだ「無い」と答えた: 少しおいて1回だけ頼み直す
            if result.added == 0, result.rewarded == false {
                await retryWait()
                let again = try? await call(kind)
                if let again { result = again }
            }
            coins = result.coins
            if result.added > 0 {
                got.append(kind)
                added += result.added
            }
        }
        return deliver(kinds: got, added: added, coins: coins, userId: userId, existing: false)
    }

    /// 起動のときに呼んでよいか（入っている・トランクが使える・その人でまだ答えをもらっていない・この起動でまだ）
    func shouldClaimExisting(userId: String?, available: Bool) -> Bool {
        guard let userId, !userId.isEmpty, available else { return false }
        return !defaults.bool(forKey: Self.existingKey(userId)) && !triedThisLaunch.contains(userId)
    }

    /// 起動のとき（すでに設定済みの人に1回）。**2つとも答えをもらえたら**以後呼ばない印を残す
    @discardableResult
    func claimExisting(userId: String?, available: Bool,
                       call: (Kind) async throws -> TrunkWelcomeResult) async -> Grant? {
        guard shouldClaimExisting(userId: userId, available: available), let userId else { return nil }
        noteUser(userId)
        triedThisLaunch.insert(userId)
        var got: [Kind] = []
        var added = 0
        var coins: Int?
        var settled = 0
        for kind in Kind.allCases {
            let result: TrunkWelcomeResult
            do {
                result = try await call(kind)
            } catch is CancellationError {
                triedThisLaunch.remove(userId)
                return nil
            } catch {
                continue
            }
            if result.rewarded == true { settled += 1 }
            coins = result.coins
            if result.added > 0 {
                got.append(kind)
                added += result.added
            }
        }
        // 2つともお礼の印が立った（rewarded）ときだけ以後呼ばない。まだ設定していない・読めなかった種類があれば、
        // 次に開いたときに確かめ直す（もらった方はサーバーに印があるので二度は来ない）
        if settled == Kind.allCases.count { defaults.set(true, forKey: Self.existingKey(userId)) }
        return deliver(kinds: got, added: added, coins: coins, userId: userId, existing: true)
    }

    private func deliver(kinds: [Kind], added: Int, coins: Int?, userId: String, existing: Bool) -> Grant? {
        guard added > 0, let coins else { return nil }
        // 同じ人のまだ出していない知らせがあれば足す（保存を2回続けた・起動のときと重なった）
        let before = pending.flatMap { owner == userId ? $0 : nil } ?? storedGrant(userId)
        let merged = Grant(kinds: Kind.allCases.filter { kinds.contains($0) || (before?.kinds.contains($0) ?? false) },
                           added: added + (before?.added ?? 0), coins: coins,
                           existing: existing && (before?.existing ?? true))
        defaults.set(["kinds": merged.kinds.map(\.rawValue), "added": merged.added, "coins": merged.coins,
                      "existing": merged.existing], forKey: Self.pendingKey(userId))
        // 待つ間に人が替わった回は、いまの人の画面に出さない（控えは残る）
        guard owner == userId else { return nil }
        center.post(name: .trunkCoinsChanged, object: nil, userInfo: ["coins": coins, "userId": userId])
        pending = merged
        requests += 1
        return merged
    }

    /// 端末に控えた、まだ出していない知らせ
    func storedGrant(_ userId: String) -> Grant? {
        guard let raw = defaults.dictionary(forKey: Self.pendingKey(userId)),
              let added = raw["added"] as? Int, added > 0 else { return nil }
        let kinds = (raw["kinds"] as? [String] ?? []).compactMap(Kind.init(rawValue:))
        return Grant(kinds: kinds.isEmpty ? [.avatar] : kinds, added: added,
                     coins: max(0, raw["coins"] as? Int ?? 0), existing: raw["existing"] as? Bool ?? false)
    }

    /// 起動のとき（人が替わったときも）: 控えがあれば出す待ちへ戻す
    @discardableResult
    func restore(userId: String?) -> Bool {
        noteUser(userId)
        guard let userId, pending == nil, let grant = storedGrant(userId) else { return false }
        pending = grant
        requests += 1
        return true
    }

    /// 出してよいか（`PostModalGate.rewardMayShow` が見る）。起動のときにまとめた分は、はじめての硬貨の案内を
    /// 出した起動では出さない
    func mayShowNow(welcomeShownThisLaunch: Bool) -> Bool {
        guard let pending, !editorOpen else { return false }
        return !(pending.existing && welcomeShownThisLaunch)
    }

    /// 出す中身を受け取る（受け取ったら空にする。端末の控えは出たときに消す）
    func consume() -> Grant? {
        defer { pending = nil }
        return pending
    }

    /// 出せなかった（ほかのシートと重なった）。待ちへ戻す
    func requeue(_ grant: Grant, userId: String?) {
        guard userId == owner, pending == nil else { return }
        pending = grant
    }

    /// 知らせが実際に出た。控えを消す
    func noteShown(userId: String?) {
        guard let userId else { return }
        defaults.removeObject(forKey: Self.pendingKey(userId))
    }

    /// 画面写真の見本（`-JPPreviewCoinReward`）。サーバーには何も送らない
    func deliverPreview(_ grant: Grant) {
        pending = grant
        requests += 1
    }

    func noteUser(_ userId: String?) {
        guard userId != owner else { return }
        owner = userId
        pending = nil
    }

    /// 退会のとき（`AccountLocalData.remove`）
    nonisolated static func removeData(for userId: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: existingKey(userId))
        defaults.removeObject(forKey: pendingKey(userId))
    }
}
