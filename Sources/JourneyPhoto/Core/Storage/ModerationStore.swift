import Foundation

/// 「見せない」の控え。
///
/// **審査 1.2 の「不適切な内容を出さない仕組み」の実体。** 通報とブロックが
/// 押せるだけでは足りず、**押したあと実際に消えて**いないと意味がない。
/// 公開の写真一覧はビルド時に焼いた静的 JSON なので、サーバー側では
/// 絞れない——端末で落とす。
///
/// 控えは**アカウントごと**に分ける（`FavoritesStore` と同じ理由）。
@MainActor
final class ModerationStore: ObservableObject {

    @Published private(set) var blockedUserIds: Set<String> = []
    @Published private(set) var reportedPhotoIds: Set<String> = []

    private let defaults: UserDefaults
    private var userId: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ suffix: String) -> String {
        "moderation.\(suffix).\(userId ?? "anonymous")"
    }

    /// ログイン状態が決まったら呼ぶ。端末に残っているぶんを読む。
    func use(userId: String?) {
        self.userId = userId
        blockedUserIds = Set(defaults.stringArray(forKey: key("blocked")) ?? [])
        reportedPhotoIds = Set(defaults.stringArray(forKey: key("reported")) ?? [])
    }

    /// サーバーの一覧で上書きする。
    ///
    /// **端末のぶんを足し合わせない。** 解除したのに端末に残っていると、
    /// 「解除したのに見えない」になり、直す手立てが画面に無い。
    func replaceBlocked(with ids: [String]) {
        blockedUserIds = Set(ids)
        defaults.set(Array(blockedUserIds), forKey: key("blocked"))
    }

    func block(_ id: String) {
        blockedUserIds.insert(id)
        defaults.set(Array(blockedUserIds), forKey: key("blocked"))
    }

    func unblock(_ id: String) {
        blockedUserIds.remove(id)
        defaults.set(Array(blockedUserIds), forKey: key("blocked"))
    }

    /// 通報した写真は、その人の画面からは即座に消す。
    /// **サーバーは消さない**（読むのは人で、すぐには終わらない）。
    func markReported(_ photoId: String) {
        reportedPhotoIds.insert(photoId)
        defaults.set(Array(reportedPhotoIds), forKey: key("reported"))
    }
}
