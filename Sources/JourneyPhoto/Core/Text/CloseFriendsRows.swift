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
/// その人は「親しい友達」限定のストーリーを見続けられる（2026-09-26 のバグ探し）。
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
}
