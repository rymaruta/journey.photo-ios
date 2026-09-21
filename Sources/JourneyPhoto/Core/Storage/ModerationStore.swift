import Foundation
// `ObservableObject` と `@Published` は Combine のもの。SwiftUI を読む
// ファイルは再輸出で使えるが、ここは読んでいないので明示する
import Combine

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
    /// 中身が変わるたびに増える。**画面が「読み直せ」を1回で受け取るため。**
    ///
    /// 2つの集合を別々に見ると、通報とブロックを続けて行う回
    /// （`ReportSheet` の「通報してブロックもする」）に全件取得が2回走る。
    @Published private(set) var revision = 0

    private let defaults: UserDefaults
    private var userId: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// **本当に変わったときだけ数を進める。**
    ///
    /// 何も変わっていないのに進めると、画面が全件取得をやり直す。
    /// 「ブロックした人」の画面は開くたびにサーバーの一覧で上書きする
    /// （`replaceBlocked`）ので、そこを無条件に数えると**開くたびに
    /// 公開一覧を丸ごと取り直す**ことになる。
    private func bumpIfChanged(blocked: Set<String>, reported: Set<String>) {
        guard blocked != blockedUserIds || reported != reportedPhotoIds else { return }
        revision += 1
    }

    private func key(_ suffix: String) -> String {
        "moderation.\(suffix).\(userId ?? "anonymous")"
    }

    /// ログイン状態が決まったら呼ぶ。端末に残っているぶんを読む。
    func use(userId: String?) {
        let before = (blockedUserIds, reportedPhotoIds)
        self.userId = userId
        blockedUserIds = Set(defaults.stringArray(forKey: key("blocked")) ?? [])
        reportedPhotoIds = Set(defaults.stringArray(forKey: key("reported")) ?? [])
        // **人が変わったときも数を進める。** 進めないと、画面は
        // `.onChange(of: revision)` を見ているので読み直さず、
        // **前の人の絞り込みで読んだ一覧**が新しい人に見えたままになる
        // （前の人がブロックした相手の写真が、新しい人には出てこない）
        bumpIfChanged(blocked: before.0, reported: before.1)
    }

    /// サーバーの一覧で上書きする。
    ///
    /// **端末のぶんを足し合わせない。** 解除したのに端末に残っていると、
    /// 「解除したのに見えない」になり、直す手立てが画面に無い。
    func replaceBlocked(with ids: [String]) {
        let before = (blockedUserIds, reportedPhotoIds)
        blockedUserIds = Set(ids)
        defaults.set(Array(blockedUserIds), forKey: key("blocked"))
        bumpIfChanged(blocked: before.0, reported: before.1)
    }

    func block(_ id: String) {
        let before = (blockedUserIds, reportedPhotoIds)
        blockedUserIds.insert(id)
        defaults.set(Array(blockedUserIds), forKey: key("blocked"))
        bumpIfChanged(blocked: before.0, reported: before.1)
    }

    func unblock(_ id: String) {
        let before = (blockedUserIds, reportedPhotoIds)
        blockedUserIds.remove(id)
        defaults.set(Array(blockedUserIds), forKey: key("blocked"))
        bumpIfChanged(blocked: before.0, reported: before.1)
    }

    /// 通報した写真は、その人の画面からは即座に消す。
    /// **サーバーは消さない**（読むのは人で、すぐには終わらない）。
    func markReported(_ photoId: String) {
        let before = (blockedUserIds, reportedPhotoIds)
        reportedPhotoIds.insert(photoId)
        defaults.set(Array(reportedPhotoIds), forKey: key("reported"))
        bumpIfChanged(blocked: before.0, reported: before.1)
    }
}
