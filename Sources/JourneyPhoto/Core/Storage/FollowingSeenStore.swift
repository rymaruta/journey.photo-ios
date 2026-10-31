import Foundation

/// 「フォロー中」をどこまで見たか（いちばん新しい投稿日の `createdAt`・#417 ⑨・`HomeFollowingNews`）。
///
/// 鍵は人ごと（同じ端末で人が替わったとき、前の人の既読で点を消さない）。未ログインでは使わない。
/// 値は1つだけなので増え続けない。退会で消す（`AccountLocalData`）
struct FollowingSeenStore {

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static let key = "journey-photo-following-seen"

    private func key(for userId: String) -> String { "\(Self.key):\(userId)" }

    func seen(for userId: String?) -> String? {
        guard let userId, !userId.isEmpty else { return nil }
        return defaults.string(forKey: key(for: userId))
    }

    /// 覚える（**戻さない**——今より古い値は書かない）
    func mark(_ createdAt: String, for userId: String?) {
        guard let userId, !userId.isEmpty, !createdAt.isEmpty else { return }
        if let current = seen(for: userId), current >= createdAt { return }
        defaults.set(createdAt, forKey: key(for: userId))
    }

    /// 退会した人の印を消す（`AccountLocalData`）
    func removeData(for userId: String) {
        defaults.removeObject(forKey: key(for: userId))
    }
}
