import Foundation

/// 端末の控え（いいね・保存・ブロック）を**サーバーの一覧で入れ替えるとき**に、
/// 読み始めた後に手元で押した分を残すための記録。
///
/// 🔴 起動・ログイン直後の同期は、一覧を取りに行ってから控えを丸ごと入れ替える。
/// 取りに行っている間にホームでいいね・保存・ブロックすると、押す前の一覧で
/// 上書きされ、ハートが消える・ブロックした人の写真がまた出ていた（審査 1.2）。
///
/// 使い方: 取りに行く前に `mark` を取り、返ってきた一覧を `merged(_:since:)` に通す。
/// **印より前に押した分は重ねない**——同期の「入れ替える」（保存しただけの古い id を
/// 落とす）はそのまま効く。
struct LocalEdits {

    /// 読み始めた時点。**誰の控えか**も持つ（別の人の同期の答えを書かないため）
    struct Mark: Equatable {
        fileprivate let owner: String?
        fileprivate let count: Int
    }

    private struct Edit {
        let at: Int
        let on: Bool
    }

    /// 押した回数。**人が替わっても戻さない**（前の人の印が新しい人の記録に当たらない）
    private var count = 0
    private var owner: String?
    /// id ごとの最後の操作
    private var last: [String: Edit] = [:]

    var mark: Mark { Mark(owner: owner, count: count) }

    /// 人が替わった（`use(userId:)`）。前の人の記録は捨てる
    mutating func reset(owner: String?) {
        self.owner = owner
        last = [:]
    }

    /// 手元で入れた（`on`）・外した
    mutating func note(_ id: String, on: Bool) {
        count += 1
        last[id] = Edit(at: count, on: on)
    }

    /// サーバーの一覧に、印の後に押した分を重ねる。**印が別の人のものなら nil**（書かない）
    func merged(_ ids: Set<String>, since mark: Mark) -> Set<String>? {
        guard mark.owner == owner else { return nil }
        var result = ids
        for (id, edit) in last where edit.at > mark.count {
            if edit.on { result.insert(id) } else { result.remove(id) }
        }
        return result
    }
}
