import Foundation
// `ObservableObject` と `@Published` は Combine のもの。SwiftUI を読む
// ファイルは再輸出で使えるが、ここは読んでいないので明示する
import Combine

/// お気に入り（端末に残るハート）。
///
/// **鍵はアカウントごとに分ける。** Web 版は共有キー1本だった頃、
/// A のハート一覧が同じ端末の B にそのまま見え、いいね判定の
/// フォールバックを通じて B の初回押下が取り消しに化けていた
/// （`lib/hooks/useFavorites.ts` の経緯）。同じ轍を踏まない。
///
/// サーバーのいいねが本体で、これはその写し。**圏外でも一覧が出る**ように
/// 端末にも持つ。
@MainActor
final class FavoritesStore: ObservableObject {

    @Published private(set) var ids: Set<String> = []

    /// **この起動中に、この端末で外した** ID（人が替わると捨てる）。
    ///
    /// 「いいねした写真」の画面はサーバーの一覧と控えの和を出すが、サーバーの
    /// 一覧の読み取りは強い整合でなく（`userList.ts` の `readUserRows`）、
    /// 外した直後に開くと**外したいいねが古い一覧で戻ってくる**。その画面は
    /// ここに載っているものを引く（`listedIds(server:)`）。控えそのものは
    /// 書き換えない——書き換えるのは起動時の `syncLikes` だけ
    private(set) var removedHere: Set<String> = []

    private let defaults: UserDefaults
    private var userId: String?
    /// 手元で押した分（同期の入れ替えで消さないため・`LocalEdits`）
    private var edits = LocalEdits()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static let sharedKey = "photo-gallery-favorites"

    private func key(for userId: String?) -> String {
        guard let userId, !userId.isEmpty else { return Self.sharedKey }
        return "\(Self.sharedKey):\(userId)"
    }

    /// ログイン状態が変わったら呼ぶ。**持ち越さない**
    /// （別の人のハートを吸い込む事故は Web で実際に起きた）。
    func use(userId: String?) {
        self.userId = userId
        ids = Set(defaults.stringArray(forKey: key(for: userId)) ?? [])
        removedHere = []
        edits.reset(owner: userId)
    }

    /// 同期で一覧を取りに行く**前に**取る。`replace(with:for:since:)` に渡す
    var syncMark: LocalEdits.Mark { edits.mark }

    /// 「いいねした写真」に並べる ID。**サーバーの一覧 ∪ 端末の控え − この起動中に
    /// この端末で外したもの**。
    ///
    /// - サーバーの一覧は**別の端末で押したぶん**を足す
    /// - 控えは、サーバーの一覧の書き込みが落ちた回（`likes.ts` の `noteLiked` は
    ///   失敗しても成功を返す）の救済。**ここで入れ替えない**——入れ替えると
    ///   その救済を画面を開くたびに消し、古い一覧で外したいいねを控えに戻す
    /// - Parameter server: 取れなければ nil（控えだけ）
    func listedIds(server: [String]?) -> Set<String> {
        ids.union(server ?? []).subtracting(removedHere)
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    /// 押すたびに入れ替える（ホームのフィードから1タップで）
    func toggle(_ id: String) { set(id, favorite: !contains(id)) }

    /// サーバーのいいね一覧に合わせる。**取れた回だけ呼ぶこと**
    /// ——取れなかった回に空で上書きすると、控えごと消える。
    ///
    /// 🔴 **入れ替える（足すのではない）理由。** 保存といいねが同じ入れ物を
    /// 使っていた頃の端末には、**保存しただけの写真の id がここに残っている**。
    /// 足すだけだと、その古い混ざりものが「いいねした写真」に出続ける。
    ///
    /// - Parameters:
    ///   - owner: 取りに行ったときの人。**返ってくる間に人が替わって
    ///     いたら書かない**（前の人のいいねを次の人の控えに書かない）
    ///   - mark: 取りに行く前の `syncMark`。**その後に押した分は残す**
    ///     （起動直後に押したいいねを、押す前の一覧で消さない）。別の人の印なら書かない
    func replace(with photoIds: [String], for owner: String?, since mark: LocalEdits.Mark? = nil) {
        guard owner == userId else { return }
        var next = Set(photoIds)
        if let mark {
            guard let merged = edits.merged(next, since: mark) else { return }
            next = merged
        }
        ids = next
        defaults.set(Array(ids), forKey: key(for: userId))
    }

    /// 退会した人の控えを消す（`AccountLocalData`）
    func removeData(for userId: String) {
        defaults.removeObject(forKey: key(for: userId))
    }

    /// いまの控えの持ち主。**答えを待つ前に取り、`set(_:favorite:for:)` に渡す**
    var owner: String? { userId }

    /// 答えを待った後に書く。**待っている間に人が替わっていたら書かない**。
    ///
    /// 🔴 書くと前の人のいいねが次の人の控えに入り、しかも「同期の間に押した分」
    /// （`LocalEdits`）として次の人の同期の入れ替えでも消えずに残る
    func set(_ id: String, favorite: Bool, for owner: String?) {
        guard owner == userId else { return }
        set(id, favorite: favorite)
    }

    func set(_ id: String, favorite: Bool) {
        if favorite {
            ids.insert(id)
            removedHere.remove(id)
        } else {
            ids.remove(id)
            removedHere.insert(id)
        }
        edits.note(id, on: favorite)
        defaults.set(Array(ids), forKey: key(for: userId))
    }
}
