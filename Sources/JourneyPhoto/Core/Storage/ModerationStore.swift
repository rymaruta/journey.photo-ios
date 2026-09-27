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
    /// 人が替わるたびに増える（`revision` も同時に進む）。
    /// **ブロックでは絞るだけの画面が、人の入れ替わりでは読み直すため**
    /// （地図はブロックのたびに読み直さない——`PhotoMapView.needsDrop`）
    private(set) var userRevision = 0

    private let defaults: UserDefaults
    private var userId: String?
    /// 手元でブロック・解除した分（同期の入れ替えで消さないため・`LocalEdits`）
    private var blockEdits = LocalEdits()

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
        let changedUser = userId != self.userId
        self.userId = userId
        blockedUserIds = Set(defaults.stringArray(forKey: key("blocked")) ?? [])
        reportedPhotoIds = Set(defaults.stringArray(forKey: key("reported")) ?? [])
        blockEdits.reset(owner: userId)
        // **人が変わったときも数を進める。** 進めないと、画面は
        // `.onChange(of: revision)` を見ているので読み直さず、
        // **前の人の絞り込みで読んだ一覧**が新しい人に見えたままになる
        // （前の人がブロックした相手の写真が、新しい人には出てこない）。
        //
        // 🔴 **集合が同じでも進める。** 公開一覧には前の人あての
        // 「フォロワーのみ／親しい友達」が混ざっている（`setRestrictedLoader`）。
        // 前の人も次の人もブロック・通報が0件だと数が進まず、検索・ホームに
        // 前の人あての写真が残っていた
        if changedUser {
            userRevision += 1
            revision += 1
        } else {
            bumpIfChanged(blocked: before.0, reported: before.1)
        }
    }


    /// サーバーの一覧で上書きする。
    ///
    /// **端末のぶんを足し合わせない。** 解除したのに端末に残っていると、
    /// 「解除したのに見えない」になり、直す手立てが画面に無い。
    ///
    /// - Parameters:
    ///   - owner: 取りに行ったときの人。**返ってくる間に人が替わって
    ///     いたら書かない**（前の人のブロックを次の人の控えに書かない）
    ///   - mark: 取りに行く前の `blockSyncMark`。**その後にブロック・解除した分は
    ///     残す**（起動直後にブロックした人の写真が、押す前の一覧でまた出ていた）。
    ///     別の人の印なら書かない
    func replaceBlocked(with ids: [String], for owner: String?, since mark: LocalEdits.Mark? = nil) {
        guard owner == userId else { return }
        var next = Set(ids)
        if let mark {
            guard let merged = blockEdits.merged(next, since: mark) else { return }
            next = merged
        }
        let before = (blockedUserIds, reportedPhotoIds)
        blockedUserIds = next
        defaults.set(Array(blockedUserIds), forKey: key("blocked"))
        bumpIfChanged(blocked: before.0, reported: before.1)
    }

    /// 手元に持っている写真の一覧から、いま「見せない」ものを落とす。
    /// **読み込み済みの画面が、ブロック／通報の直後に消すため**
    /// （公開一覧の側は次に読んだときに落ちるが、画面はもう持っている）
    func visible(_ photos: [Photo]) -> [Photo] {
        BlockFilter.photos(photos, blocked: blockedUserIds, reported: reportedPhotoIds)
    }

    /// いまの「見せない」の写し。**画面が絞る時点を自分で選ぶため**
    /// （描画のたびに `visible` を呼ぶと、見ている最中に一覧が縮む）
    var snapshot: ModerationSnapshot {
        ModerationSnapshot(blocked: blockedUserIds, reported: reportedPhotoIds)
    }

    /// ブロック一覧を取りに行く**前に**取る。`replaceBlocked(with:for:since:)` に渡す
    var blockSyncMark: LocalEdits.Mark { blockEdits.mark }

    /// いまの控えの持ち主。**サーバーの答えを待つ前に取り、`block(_:for:)` に渡す**
    var owner: String? { userId }

    /// サーバーの答えを待った後にブロックを控える。**待っている間に人が替わって
    /// いたら書かない**——書くと前の人のブロックで次の人の画面から人が消え、
    /// 「同期の間に押した分」（`LocalEdits`）として次の人の同期でも消えない
    func block(_ id: String, for owner: String?) {
        guard owner == userId else { return }
        block(id)
    }

    /// `block(_:for:)` の解除
    func unblock(_ id: String, for owner: String?) {
        guard owner == userId else { return }
        unblock(id)
    }

    func block(_ id: String) {
        let before = (blockedUserIds, reportedPhotoIds)
        blockedUserIds.insert(id)
        blockEdits.note(id, on: true)
        defaults.set(Array(blockedUserIds), forKey: key("blocked"))
        bumpIfChanged(blocked: before.0, reported: before.1)
    }

    func unblock(_ id: String) {
        let before = (blockedUserIds, reportedPhotoIds)
        blockedUserIds.remove(id)
        blockEdits.note(id, on: false)
        defaults.set(Array(blockedUserIds), forKey: key("blocked"))
        bumpIfChanged(blocked: before.0, reported: before.1)
    }

    /// 退会した人の控えを消す（`AccountLocalData`）
    func removeData(for userId: String) {
        defaults.removeObject(forKey: "moderation.blocked.\(userId)")
        defaults.removeObject(forKey: "moderation.reported.\(userId)")
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

/// `ModerationStore.snapshot` の中身。値なので `@State` に置ける
struct ModerationSnapshot: Equatable {
    var blocked: Set<String> = []
    var reported: Set<String> = []

    func visible(_ photos: [Photo]) -> [Photo] {
        BlockFilter.photos(photos, blocked: blocked, reported: reported)
    }

    /// 人・コメント・見た人も同じ写しで落とす。**描くたびに `hidden.blockedUserIds` で
    /// 絞らない**——行から開いた先でブロックすると、元の行が消えて開いている画面が閉じる
    func users(_ users: [UserProfile]) -> [UserProfile] {
        BlockFilter.users(users, blocked: blocked)
    }

    func comments(_ comments: [PhotoComment]) -> [PhotoComment] {
        BlockFilter.comments(comments, blocked: blocked)
    }

    func viewers(_ viewers: [StoryViewer]) -> [StoryViewer] {
        BlockFilter.viewers(viewers, blocked: blocked)
    }
}
