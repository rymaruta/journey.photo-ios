import Foundation

/// 複数枚のストーリー（モック4-5 のメディアストリップ）の並びの計算。
///
/// **画面から出しておく。** `Shims/` の模型では `View` の中を動かせないので、
/// ここに置いたぶんだけが Linux の `swift test` で確かめられる。
enum StoryQueue {

    /// 一度に出せる枚数。**サーバーの1日の上限（20本・`STORY_DAILY_LIMIT`）を
    /// 1回で使い切らせない。**
    static let maxShots = 10

    /// 1枚外したあと、どれを編集するか。
    ///
    /// 🔴 **ずらさないと、外した瞬間に別の写真の文字を触ることになる。**
    /// 3枚のうち1番目（添字0）を外すと、それまで2番目だったものが
    /// 添字0に降りてくる——`current` が1のままだと、画面に出ている絵と
    /// 触っている文字が1つずれる。
    ///
    /// - Parameters:
    ///   - removed: 外した位置
    ///   - current: いま編集していた位置
    ///   - count: **外したあとの**枚数
    static func currentAfterRemoving(_ removed: Int, current: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        if removed < current { return current - 1 }
        if current >= count { return count - 1 }
        return current
    }

    /// あと何枚足せるか。**上限に達していたら 0**
    static func remaining(_ count: Int) -> Int { max(0, maxShots - count) }

    /// 途中で失敗したときの知らせ。
    ///
    /// **「何枚出て、何枚残ったか」を言う。** 「投稿できませんでした」だけだと、
    /// 出たぶんが在ることが伝わらず、押し直して二重に出すことになる。
    static func partialFailure(posted: Int, total: Int, reason: String) -> String {
        if posted == 0 { return reason }
        return L("\(posted)枚は出せましたが、残り\(total - posted)枚は出せませんでした（\(reason)）",
                 "Posted \(posted), but \(total - posted) failed (\(reason))")
    }
}
