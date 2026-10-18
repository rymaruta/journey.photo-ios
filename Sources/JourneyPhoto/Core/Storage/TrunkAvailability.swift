import Foundation
import Combine

/// 旅のトランクの口がサーバーに在るか（2026-10-17 の読み直し: **サーバーが出ていない間は入口を出さない**）。
///
/// `GET /user/trunk` が一度でも読めた人にだけマイページの行を出す。口が無い（道の無い 404・本文の無い 403）
/// と分かったら行ごと隠す。圏外・500 などの一時の失敗では前の答えのまま（出していた行を消さない）。
/// 一度読めたことは人ごとに端末へ覚える（次に開いたとき、読み終わる前から行を出す）
@MainActor
final class TrunkAvailability: ObservableObject {

    static let shared = TrunkAvailability()

    @Published private(set) var isAvailable = false

    private let defaults: UserDefaults
    private var userId: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static func key(_ userId: String) -> String { "trunk.available.\(userId)" }
    private static func checkedKey(_ userId: String) -> String { "trunk.availableCheckedAt.\(userId)" }

    /// 入っている人のぶんを出す（要るときだけ読み直す）。見本（画面写真）では読まずに出す
    func refresh(userId: String?, service: TrunkService, force: Bool = false, now: Date = Date(),
                 preview: Bool = PreviewSession.trunkSample != nil) async {
        self.userId = userId
        guard let userId else { isAvailable = false; return }
        if preview { isAvailable = true; return }
        let remembered = defaults.bool(forKey: Self.key(userId))
        isAvailable = remembered
        let checkedAt = defaults.object(forKey: Self.checkedKey(userId)) as? Date
        guard TrunkAvailabilityRule.needsCheck(remembered: remembered, checkedAt: checkedAt, now: now, force: force) else { return }
        var failure: Error?
        do {
            let state = try await service.state()
            // 自分の見せる設定も控える（自分のページを人の画面で開いたときに読み足さない・`TrunkOwnSettings`）
            TrunkOwnSettings.note(showTrunk: state.showTrunk, userId: userId, defaults: defaults)
        } catch is CancellationError { return } catch { failure = error }
        guard self.userId == userId, let decided = TrunkAvailabilityRule.decide(failure) else { return }
        isAvailable = decided
        defaults.set(decided, forKey: Self.key(userId))
        defaults.set(now, forKey: Self.checkedKey(userId))
    }

    /// 退会のとき（`AccountLocalData.remove`）
    nonisolated static func removeData(for userId: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "trunk.available.\(userId)")
        defaults.removeObject(forKey: "trunk.availableCheckedAt.\(userId)")
    }
}

/// 読んだ結果から、行を出すかを決める（nil は「分からない・前のまま」）。道の無い 404・本文の無い 403 は「口が無い」
enum TrunkAvailabilityRule {
    /// 2026-10-17 判断: 一度読めた人は、覚えている値で行を出し、読み直しは **6時間に1回**
    /// （と、アプリが前面に戻ったとき `force`）。マイページを開くたびに `GET /user/trunk` を叩かない。
    /// まだ読めたことの無い人（口が出る前）は、開くたびに確かめる（出たらすぐ行を出すため）
    static let recheckInterval: TimeInterval = 6 * 3600

    /// 読み直すか（覚えている値・前に確かめた時刻・いま）
    static func needsCheck(remembered: Bool, checkedAt: Date?, now: Date, force: Bool) -> Bool {
        if force || !remembered { return true }
        guard let checkedAt else { return true }
        return now.timeIntervalSince(checkedAt) >= recheckInterval
    }

    static func decide(_ error: Error?) -> Bool? {
        guard let error else { return true }
        if case let APIError.server(status, message) = error, (status == 404 || status == 403), message.isEmpty {
            return false
        }
        return nil
    }
}
