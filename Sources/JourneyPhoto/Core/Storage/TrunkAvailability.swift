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

    private func key(_ userId: String) -> String { "trunk.available.\(userId)" }

    /// 入っている人のぶんを読み直す。見本（画面写真）では読まずに出す
    func refresh(userId: String?, service: TrunkService, preview: Bool = PreviewSession.trunkSample != nil) async {
        self.userId = userId
        guard let userId else { isAvailable = false; return }
        if preview { isAvailable = true; return }
        isAvailable = defaults.bool(forKey: key(userId))
        var failure: Error?
        do { _ = try await service.state() } catch is CancellationError { return } catch { failure = error }
        guard self.userId == userId, let decided = TrunkAvailabilityRule.decide(failure) else { return }
        isAvailable = decided
        defaults.set(decided, forKey: key(userId))
    }
}

/// 読んだ結果から、行を出すかを決める（nil は「分からない・前のまま」）。道の無い 404・本文の無い 403 は「口が無い」
enum TrunkAvailabilityRule {
    static func decide(_ error: Error?) -> Bool? {
        guard let error else { return true }
        if case let APIError.server(status, message) = error, (status == 404 || status == 403), message.isEmpty {
            return false
        }
        return nil
    }
}
