import Foundation

/// 人ごとに端末に覚える「入・切」1つ（作る画面の切り替えの覚え）。
///
/// 投稿の「撮影地の位置を付ける」（`UploadLocationPreference`・2026-10-18）とストーリーの
/// 「24時間後も自分用に残す」（`StoryArchivePreference`・2026-11-11）が同じ決まりで覚えるので、ここに1つにした:
///
/// - **人ごとに覚える**——同じ端末の次の人に前の人の値を使わない。覚えが無い人は既定の値
/// - ログインしていない（持ち主が分からない）ときは覚えない・読まない（既定の値）
/// - 退会したら消す（`AccountLocalData`）
struct PerUserFlag {

    let baseKey: String
    /// 覚えが無いときの値
    let defaultValue: Bool
    private let defaults: UserDefaults

    init(baseKey: String, defaultValue: Bool, defaults: UserDefaults) {
        self.baseKey = baseKey
        self.defaultValue = defaultValue
        self.defaults = defaults
    }

    /// 人ごとの鍵。持ち主が分からなければ nil（覚えない・読まない）
    static func key(base: String, userId: String?) -> String? {
        guard let userId, !userId.isEmpty else { return nil }
        return "\(base):\(userId)"
    }

    /// その人が選んだ値。覚えが無い・持ち主が分からなければ既定の値
    func value(userId: String?) -> Bool {
        guard let key = Self.key(base: baseKey, userId: userId), defaults.object(forKey: key) != nil else {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }

    /// 選んだ値を覚える。持ち主が分からなければ書かない
    func set(_ value: Bool, userId: String?) {
        guard let key = Self.key(base: baseKey, userId: userId) else { return }
        defaults.set(value, forKey: key)
    }

    /// 退会した人の控えを消す
    func removeData(for userId: String) {
        guard let key = Self.key(base: baseKey, userId: userId) else { return }
        defaults.removeObject(forKey: key)
    }
}
