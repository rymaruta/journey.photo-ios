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
    /// 自分で消した・非公開にした写真と、控えた時刻。**公開一覧の写しから落とす**
    /// （`BlockFilter.photos` の `gone`）。
    ///
    /// 公開一覧は静的な `photos.json` で、消しても非公開にしてもサイトの建て直し
    /// （通常は数分）まで載ったまま。端末の控え（60秒の記憶と `PhotoSnapshotStore`）も
    /// 残るので、消した写真がホーム・探す・地図・保存・近くの写真に出続け、押すと
    /// もう無い写真が開いて いいね・保存・コメントが 404 になっていた。
    /// 通報（`reportedPhotoIds`）と同じ道——`revision` を進め、`setHidden` で
    /// 公開一覧へ渡す——に乗せるので、画面ごとの配線は増やしていない。
    ///
    /// **端末に残す（`goneLifetime` まで）。** 起動し直しても圏外なら円盤の控えが出るし、
    /// 建て直しの合図（`repository_dispatch`）が落ちると、週1の定期ビルドまで
    /// 最大7日 載ったままになる。id は使い回されないので、消した写真を長めに
    /// 覚えていても害は無い。公開に戻したら `unmarkGone` で外す
    @Published private(set) var goneMarks: [String: Date] = [:]
    var gonePhotoIds: Set<String> { Set(goneMarks.keys) }
    /// 覚えておく長さ。**週1の定期ビルド（最大7日）に合わせる**
    static let goneLifetime: TimeInterval = 7 * 24 * 60 * 60
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
    /// いまの時刻（試験が期限切れを作るため）
    private let now: () -> Date
    private var userId: String?
    /// 手元でブロック・解除した分（同期の入れ替えで消さないため・`LocalEdits`）
    private var blockEdits = LocalEdits()

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    /// **本当に変わったときだけ数を進める。**
    ///
    /// 何も変わっていないのに進めると、画面が全件取得をやり直す。
    /// 「ブロックした人」の画面は開くたびにサーバーの一覧で上書きする
    /// （`replaceBlocked`）ので、そこを無条件に数えると**開くたびに
    /// 公開一覧を丸ごと取り直す**ことになる。
    private func bumpIfChanged(since before: ModerationSnapshot) {
        guard before != snapshot else { return }
        revision += 1
    }

    private func key(_ suffix: String) -> String {
        "moderation.\(suffix).\(userId ?? "anonymous")"
    }

    /// ログイン状態が決まったら呼ぶ。端末に残っているぶんを読む。
    func use(userId: String?) {
        let before = snapshot
        let changedUser = userId != self.userId
        self.userId = userId
        blockedUserIds = Set(defaults.stringArray(forKey: key("blocked")) ?? [])
        reportedPhotoIds = Set(defaults.stringArray(forKey: key("reported")) ?? [])
        // **人ごとに読む。** 前の人が消した写真の印を次の人に持ち越さない
        goneMarks = loadGoneMarks()
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
            bumpIfChanged(since: before)
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
        let before = snapshot
        blockedUserIds = next
        defaults.set(Array(blockedUserIds), forKey: key("blocked"))
        bumpIfChanged(since: before)
    }

    /// 手元に持っている写真の一覧から、いま「見せない」ものを落とす。
    /// **読み込み済みの画面が、ブロック／通報の直後に消すため**
    /// （公開一覧の側は次に読んだときに落ちるが、画面はもう持っている）
    func visible(_ photos: [Photo]) -> [Photo] {
        BlockFilter.photos(photos, blocked: blockedUserIds, reported: reportedPhotoIds, gone: gonePhotoIds)
    }

    /// いまの「見せない」の写し。**画面が絞る時点を自分で選ぶため**
    /// （描画のたびに `visible` を呼ぶと、見ている最中に一覧が縮む）
    var snapshot: ModerationSnapshot {
        ModerationSnapshot(blocked: blockedUserIds, reported: reportedPhotoIds, gone: gonePhotoIds)
    }

    /// ブロック一覧を取りに行く**前に**取る。`replaceBlocked(with:for:since:)` に渡す
    var blockSyncMark: LocalEdits.Mark { blockEdits.mark }

    /// ブロック一覧の取得1回ぶんの札。**取りに行く前に**取り、`replaceBlocked(with:for:fetch:)` に渡す。
    ///
    /// 印（`mark`）だけでは、2つの取得（起動時の同期と「ブロックした人」の画面）の
    /// **どちらが後に始まったか**が分からない（その間に押していなければ印は同じ）。
    /// 先に始まった取得が後から返ると、新しい一覧を古い一覧で上書きしていた
    struct BlockFetch {
        let mark: LocalEdits.Mark
        fileprivate let seq: Int
    }
    private var blockFetchSeq = 0
    private var appliedBlockFetchSeq = 0

    func beginBlockFetch() -> BlockFetch {
        blockFetchSeq += 1
        return BlockFetch(mark: blockEdits.mark, seq: blockFetchSeq)
    }

    /// サーバーの一覧で入れ替える。**後に始まった取得の答えが既に入っていたら書かない**。
    /// 印の後に手元で押した分は重ねる（`LocalEdits`）
    func replaceBlocked(with ids: [String], for owner: String?, fetch: BlockFetch) {
        guard owner == userId, fetch.seq > appliedBlockFetchSeq else { return }
        guard blockEdits.merged(Set(ids), since: fetch.mark) != nil else { return }
        appliedBlockFetchSeq = fetch.seq
        replaceBlocked(with: ids, for: owner, since: fetch.mark)
    }

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
        let before = snapshot
        blockedUserIds.insert(id)
        blockEdits.note(id, on: true)
        defaults.set(Array(blockedUserIds), forKey: key("blocked"))
        bumpIfChanged(since: before)
    }

    func unblock(_ id: String) {
        let before = snapshot
        blockedUserIds.remove(id)
        blockEdits.note(id, on: false)
        defaults.set(Array(blockedUserIds), forKey: key("blocked"))
        bumpIfChanged(since: before)
    }

    /// 退会した人の控えを消す（`AccountLocalData`）
    func removeData(for userId: String) {
        defaults.removeObject(forKey: "moderation.blocked.\(userId)")
        defaults.removeObject(forKey: "moderation.reported.\(userId)")
        defaults.removeObject(forKey: "moderation.gone.\(userId)")
    }

    /// 通報した写真は、その人の画面からは即座に消す。
    /// **サーバーは消さない**（読むのは人で、すぐには終わらない）。
    /// 通報の答えを待った後に控える。**待っている間に人が替わっていたら書かない**
    /// （`block(_:for:)` と同じ）——書くと、未ログインの控えに入り、以後だれの
    /// 画面からもその写真が消えていた
    func markReported(_ photoId: String, for owner: String?) {
        guard owner == userId else { return }
        markReported(photoId)
    }

    func markReported(_ photoId: String) {
        let before = snapshot
        reportedPhotoIds.insert(photoId)
        defaults.set(Array(reportedPhotoIds), forKey: key("reported"))
        bumpIfChanged(since: before)
    }

    /// 自分で消した・非公開にした写真を、公開一覧の写しから落とす（`goneMarks`）。
    /// **サーバーの答えを待った後に呼ぶ。** 待っている間に人が替わっていたら書かない
    /// （`markReported(_:for:)` と同じ）——書くと次の人の画面からその写真が消える
    func markGone(_ photoId: String, for owner: String?) {
        guard owner == userId else { return }
        let before = snapshot
        goneMarks[photoId] = now()
        saveGoneMarks(goneMarks)
        bumpIfChanged(since: before)
    }

    /// 公開に戻した写真の印を外す。**外さないと、建て直しで一覧に戻っても
    /// この端末でだけ `goneLifetime` の間 出てこない**
    func unmarkGone(_ photoId: String, for owner: String?) {
        guard owner == userId, goneMarks[photoId] != nil else { return }
        let before = snapshot
        goneMarks[photoId] = nil
        saveGoneMarks(goneMarks)
        bumpIfChanged(since: before)
    }

    /// 端末の印を読む。**期限を過ぎた印はここで捨てる**（書き戻して溜めない）
    /// サーバーが「公開中」と答えた自分の写真の印を外す（Web や別の端末で公開に
    /// 戻した写真が、この端末でだけ最大7日出なかった）。
    ///
    /// **付けたばかりの印は外さない**（`graceSeconds`）。自分の一覧（`/user/photos`）は
    /// 索引の写しを読むので、非公開にした直後は古い「公開中」を返しうる——それで
    /// 外すと、非公開にした写真がすぐ一覧に戻る
    func confirmPublished(_ photoIds: [String], for owner: String?, graceSeconds: TimeInterval = 120) {
        guard owner == userId else { return }
        let cutoff = now().addingTimeInterval(-graceSeconds)
        let stale = photoIds.filter { id in goneMarks[id].map { $0 < cutoff } ?? false }
        guard !stale.isEmpty else { return }
        let before = snapshot
        for id in stale { goneMarks[id] = nil }
        saveGoneMarks(goneMarks)
        bumpIfChanged(since: before)
    }

    private func loadGoneMarks() -> [String: Date] {
        let raw = defaults.dictionary(forKey: key("gone")) ?? [:]
        let cutoff = now().addingTimeInterval(-Self.goneLifetime)
        var marks: [String: Date] = [:]
        for (id, value) in raw {
            guard let seconds = (value as? Double) ?? (value as? NSNumber)?.doubleValue else { continue }
            // 先の時刻は今に抑える（時計を進めて付けた印が長く残らない）
            let at = min(Date(timeIntervalSince1970: seconds), now())
            if at > cutoff { marks[id] = at }
        }
        if marks.count != raw.count { saveGoneMarks(marks) }
        return marks
    }

    private func saveGoneMarks(_ marks: [String: Date]) {
        if marks.isEmpty {
            defaults.removeObject(forKey: key("gone"))
        } else {
            defaults.set(marks.mapValues { $0.timeIntervalSince1970 }, forKey: key("gone"))
        }
    }
}

/// `ModerationStore.snapshot` の中身。値なので `@State` に置ける
struct ModerationSnapshot: Equatable {
    var blocked: Set<String> = []
    var reported: Set<String> = []
    /// 自分で消した・非公開にした写真（`ModerationStore.goneMarks`）
    var gone: Set<String> = []

    func visible(_ photos: [Photo]) -> [Photo] {
        BlockFilter.photos(photos, blocked: blocked, reported: reported, gone: gone)
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
