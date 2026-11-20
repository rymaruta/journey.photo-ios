import Foundation

/// 投稿の題・説明・タグの候補（端末の AI・札 #622）の回数の上限（札 #658・2026-11-20 owner 承認）。
///
/// - 無料も Pro も **1日20回かつ月300回**。日と月の境目は日本時間
/// - 2026-11-20 判断: **数えるのは端末の中だけ。** 候補は端末の AI だけで作り（0円・外へ何も送らない）、サーバーの AI は
///   使わないので、サーバーでは数えない（CLAUDE.md「費用がかかる道はサーバーで数える」の外）
/// - 数えるのは**候補を画面に出した回だけ**（AI が答えなかった回は数えない）
/// - 上限に達したら候補を出さないだけ。投稿は止めない、ダイアログは出さない（候補の場所に小さく1行）
/// - 端末ごとの数。ログアウト・退会では消さない（消すと入り直しで回り込める）
struct PostSuggestQuota {

    static let dayLimit = 20
    static let monthLimit = 300

    static let dayKey = "journey-photo-post-suggest-day"
    static let monthKey = "journey-photo-post-suggest-month"

    enum Block: Equatable { case day, month }

    private let defaults: UserDefaults
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    /// 今日と今月に使った数（日付が替わっていれば 0）
    var usedToday: Int { used(key: Self.dayKey, period: Self.day(now())) }
    var usedThisMonth: Int { used(key: Self.monthKey, period: Self.month(now())) }

    /// 上限に達しているか（月を先に見る）
    var blocked: Block? {
        if usedThisMonth >= Self.monthLimit { return .month }
        if usedToday >= Self.dayLimit { return .day }
        return nil
    }

    /// 候補を画面に出した回を1つ数える
    func count() {
        let date = now()
        save(key: Self.dayKey, period: Self.day(date), value: usedToday + 1)
        save(key: Self.monthKey, period: Self.month(date), value: usedThisMonth + 1)
    }

    /// 候補の場所に出す1行
    static func line(_ block: Block) -> String {
        switch block {
        case .day: return L("今日の候補は使い切りました", "You've used today's suggestions")
        case .month: return L("今月の候補は使い切りました", "You've used this month's suggestions")
        }
    }

    private func used(key: String, period: String) -> Int {
        guard let stored = defaults.dictionary(forKey: key), stored["period"] as? String == period else { return 0 }
        return stored["count"] as? Int ?? 0
    }

    private func save(key: String, period: String, value: Int) {
        defaults.set(["period": period, "count": value], forKey: key)
    }

    private static var tokyo: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        return c
    }

    static func day(_ date: Date) -> String {
        let c = tokyo.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func month(_ date: Date) -> String {
        let c = tokyo.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }
}
