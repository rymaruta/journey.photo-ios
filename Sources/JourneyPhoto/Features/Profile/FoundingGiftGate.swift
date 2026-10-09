import Foundation

/// 初期ユーザー章を贈る全画面（`FoundingGiftView`）を出すかどうか（2026-10-09）。
///
/// - 出すのは**初期ユーザー章を持っていて、名前の横にまだ飾っていない人**だけ
/// - 「受け取って、プロフィールに飾る」で飾ったら二度と出さない
/// - 「あとで」は閉じるだけ。**次の起動でもう一度出す（同じ人に出すのは合わせて3回まで）**。
///   しつこくしない。飾りたくなったら、プロフィールの編集の「名前の横のバッジ」から選べる
/// - 覚えるのは人ごと（同じ端末で別の人が入っても、その人の分は数え直す）
struct FoundingGiftGate {

    /// 初期ユーザー章の鍵（サーバーの `earlyUser`）
    static let badgeKey = "earlyUser"
    /// 同じ人に出す回数の上限
    static let maxShows = 3
    static func shownKey(_ userId: String) -> String { "foundingGift.shown.\(userId)" }
    static func doneKey(_ userId: String) -> String { "foundingGift.done.\(userId)" }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// このプロフィールの人に出すか（出すと決めたら `noteShown` を呼ぶ）
    func shouldPresent(userId: String, profile: UserProfile) -> Bool {
        guard !userId.isEmpty, profile.earnedBadges[Self.badgeKey] != nil else { return false }
        // もう飾っている人（ほかの画面で選んだ人も）には出さず、覚えて終わり
        if profile.shownBadge?.key == Self.badgeKey {
            defaults.set(true, forKey: Self.doneKey(userId))
            return false
        }
        if defaults.bool(forKey: Self.doneKey(userId)) { return false }
        return defaults.integer(forKey: Self.shownKey(userId)) < Self.maxShows
    }

    /// 出した（「あとで」でも数える）
    func noteShown(userId: String) {
        defaults.set(defaults.integer(forKey: Self.shownKey(userId)) + 1, forKey: Self.shownKey(userId))
    }

    /// 飾った。二度と出さない
    func noteAccepted(userId: String) {
        defaults.set(true, forKey: Self.doneKey(userId))
    }

    /// 贈る相手の名前（表示名、無ければ @ユーザー名、どちらも無ければ空）
    static func name(_ profile: UserProfile) -> String {
        let display = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !display.isEmpty { return display }
        let username = profile.username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return username.isEmpty ? "" : "@\(username)"
    }
}
