import Foundation

/// 投稿の「撮影地の位置を付ける」（写真の位置情報を使うか）を端末に覚える。
///
/// 2026-10-18 判断（プライバシーポリシーの見直しから）: iOS には切り替えが無く、写真に位置情報があって
/// 自動で入った撮影地のまま投稿すると、**聞かずに**座標（約1kmに丸めた値）を送っていた。Web には
/// 「写真のGPSから撮影地を自動入力」のチェックボックスがあり、最初はオン・選んだ値を端末に覚える
/// （`photo-gallery` の `app/user/upload/page.tsx` の `jp_gps_autofill`）。iOS もそろえる:
///
/// - **最初の値はオン**（Web と同じ。今までの動きを変えない）
/// - **人ごとに覚える**——同じ端末の次の人に前の人の「オフ」「オン」を使わない。覚えが無い人はオン
/// - ログインしていない（持ち主が分からない）ときは覚えない（画面の中だけの値）
/// - 退会したら消す（`AccountLocalData`）
///
/// 画面が開くたびに読み、切り替えたときに書くだけなので `ObservableObject` にしない（`RecentSongsStore` と同じ）
struct UploadLocationPreference {

    /// 覚えが無いときの値（Web と同じオン）
    static let defaultValue = true

    private static let baseKey = "journey-photo-upload-attach-location"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 人ごとの鍵。持ち主が分からなければ nil（覚えない・読まない）
    static func key(for userId: String?) -> String? {
        guard let userId, !userId.isEmpty else { return nil }
        return "\(baseKey):\(userId)"
    }

    /// その人が選んだ値。覚えが無い・持ち主が分からなければ既定（オン）
    func attachesLocation(userId: String?) -> Bool {
        guard let key = Self.key(for: userId), defaults.object(forKey: key) != nil else { return Self.defaultValue }
        return defaults.bool(forKey: key)
    }

    /// 選んだ値を覚える。持ち主が分からなければ書かない
    func set(_ attaches: Bool, userId: String?) {
        guard let key = Self.key(for: userId) else { return }
        defaults.set(attaches, forKey: key)
    }

    /// 退会した人の控えを消す（`AccountLocalData`）
    func removeData(for userId: String) {
        guard let key = Self.key(for: userId) else { return }
        defaults.removeObject(forKey: key)
    }
}
