import Foundation

/// 「親しい友達」の画面に並べる人。
///
/// 🔴 **選んでいる人は、フォロー中の一覧に居なくても必ず並べる。**
/// 以前はフォロー中の一覧（サーバーが**50人で切る**・`api-user/src/follow.ts`
/// の `FOLLOWING_PAGE`）だけを並べていたので、
/// - フォローを外した相手
/// - フォローが50人を超えて一覧から押し出された相手
///
/// が親しい友達に残ったまま**画面に出ず、外す手段が無かった**。
/// その人は公開範囲を「親しい友達」にした**写真**を見続けられる
/// （`api-user/src/restrictedFeed.ts`・2026-09-26 のバグ探し）。
/// ストーリーには効かない——ストーリーは常にフォロワーだけに出る。
/// サーバーは誰でも入れられる作り（`closeFriends.ts`）なので、これは画面側の穴。
enum CloseFriendsRows {

    /// - Returns: `others` は選んでいるがフォロー中の一覧に居ない人の id
    ///   （選んだ順＝サーバーの並び）。`following` はフォロー中の一覧そのまま
    static func split(following: [FollowUser], chosen: [String]) -> (others: [String], following: [FollowUser]) {
        let shown = Set(following.map(\.id))
        var seen = Set<String>()
        let others = chosen.filter { !shown.contains($0) && seen.insert($0).inserted }
        return (others, following)
    }

    // MARK: - 「保存」（板 39）

    /// 選べる上限。サーバーの `CLOSE_FRIENDS_MAX`（`api-user/src/closeFriends.ts`）と同じ値。
    ///
    /// サーバーは上限を超えて足されると**断らずに古い人を黙って押し出す**
    /// （`api-user/src/userList.ts` の `slice(0, max)`）＝応答は成功のまま。
    /// だから**画面で止める**: 選んだ数が上限を超えている間は「保存」を押せない
    static let limit = 200

    static func overLimit(_ picked: Set<String>) -> Bool {
        picked.count > limit
    }

    /// 戻ろうとしたときの扱い。
    enum Leave: Equatable {
        /// そのまま戻る（送っていない変更が無い）
        case now
        /// 「保存して戻る／変更を捨てる／キャンセル」を確かめる
        case confirm
        /// 送っている最中は戻らせない（途中の失敗が消えた画面に出る）
        case wait
    }

    static func leave(hasChanges: Bool, isSaving: Bool) -> Leave {
        if isSaving { return .wait }
        return hasChanges ? .confirm : .now
    }

    /// 保存で送るもの。**外す方を先に送る**。
    ///
    /// 押し出しを防いでいるのは**2つの組み合わせ**: 選んだ結果が上限以内
    /// （`overLimit` で画面が止める）かつ外す方が先。外し終えてから足すので、
    /// 途中の人数は最後の人数を超えない＝上限にも届かない。足す方を先に送ると、
    /// 満杯のときに途中で上限を超え、外すつもりの無い人が落ちる。
    /// ⚠️ 読んだあとに**別の端末で足した**ぶんは見えていないので、その場合は
    /// まだ押し出しうる（画面を開き直せば見える）
    ///
    /// 並びは画面の並び（`order`）に従う。`order` に居ない id は後ろに id 順で足す
    /// （呼び出しごとに順番が揺れない）。
    struct Change: Equatable {
        let userId: String
        let wanted: Bool
    }

    static func changes(saved: Set<String>, picked: Set<String>, order: [String]) -> [Change] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        func sorted(_ ids: Set<String>) -> [String] {
            ids.sorted { a, b in
                switch (rank[a], rank[b]) {
                case let (x?, y?): return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return a < b
                }
            }
        }
        return sorted(saved.subtracting(picked)).map { Change(userId: $0, wanted: false) }
            + sorted(picked.subtracting(saved)).map { Change(userId: $0, wanted: true) }
    }

    /// 送った結果。
    struct SaveOutcome: Equatable {
        /// **サーバーが返した状態を積んだ**「保存済み」の集合
        let saved: Set<String>
        /// 送れた数 / 送るはずだった数
        let done: Int
        let total: Int
        var finished: Bool { done == total }
    }

    /// 差分を**1件ずつ順に**送る。
    ///
    /// まとめて書く口がサーバーに無い（`PUT` / `DELETE /user/close-friends/{id}`
    /// の1人ずつだけ・`api-user/src/closeFriends.ts`）。並べて投げると、
    /// アカウント全体で10本の Lambda の枠を1人で埋める。
    ///
    /// **最初に失敗したところで止める。** その先は送らない——どこまで
    /// 保存できたかが「送れた数」だけで言える。送れたぶんは `saved` に入っており、
    /// 残りは画面の選択に残る（もう一度「保存」を押すと残りだけが送られる）。
    ///
    /// 状態は**返ってきた値を使う**（自分で決めない）
    static func save(saved: Set<String>, changes: [Change],
                     send: (Change) async throws -> Bool) async -> SaveOutcome {
        var now = saved
        var done = 0
        for change in changes {
            guard let isFriend = try? await send(change) else { break }
            if isFriend { now.insert(change.userId) } else { now.remove(change.userId) }
            done += 1
        }
        return SaveOutcome(saved: now, done: done, total: changes.count)
    }

    /// 途中で止まったときの知らせ。**何件保存できたかを言う**
    static func partialMessage(_ outcome: SaveOutcome) -> String? {
        guard !outcome.finished else { return nil }
        if outcome.done == 0 {
            return L("保存できませんでした。もう一度「保存」を押してください。",
                     "Couldn't save. Tap Save to try again.")
        }
        let rest = outcome.total - outcome.done
        return L("変更 \(outcome.total) 件のうち \(outcome.done) 件を保存しました。残りの \(rest) 件は保存できていません。もう一度「保存」を押してください。",
                 "Saved \(outcome.done) of \(outcome.total) changes. \(rest) not saved yet. Tap Save to try again.")
    }
}
