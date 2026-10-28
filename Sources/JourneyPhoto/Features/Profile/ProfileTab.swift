import Foundation

/// プロフィールの表示切り替え。本人は 投稿 / 旅の記録 / 行きたい場所 / お気に入り
/// （整理案 05c）、他人のページは 投稿 / マップ。
///
/// **年表は外した。** 同じ写真を日付で並べ直すだけの見せ方で、
/// **「旅」の一冊**（`TripBook`——表紙・時間順のページ・足取り）が
/// その役目をより強く果たす。マイページではタブの「旅の記録」から入る。
enum ProfileTab: String, CaseIterable, Identifiable {
    case posts
    /// 旅の一冊の棚（`TripBook`）。**本人のページだけ**——以前は写真の上に
    /// 「旅の記録」の札を別に置いていた（整理案 05c でタブへ移した）
    case trips
    /// 行きたいスポット（`WishlistStore`）。**本人の一覧だけ**（`/user/spots` は本人しか読めない）
    case wishlist
    case map
    case favorites

    var id: String { rawValue }

    var label: String {
        switch self {
        case .posts: return L("投稿", "Posts")
        case .trips: return L("旅の記録", "Trips")
        case .wishlist: return L("行きたい場所", "Want to go")
        case .map: return L("マップ", "Map")
        // 2026-10-16: 「お気に入り」→「保存」。メニューの「保存した写真」・写真の詳細のしおり（保存）と呼び名をそろえた
        case .favorites: return L("保存", "Saved")
        }
    }

    var systemImage: String {
        switch self {
        case .posts: return "square.grid.2x2"  // 板 05c: 2×2 の格子
        case .trips: return "book.closed"
        case .wishlist: return "heart"
        case .map: return "map"
        case .favorites: return "bookmark"
        }
    }

    /// **行きたい場所とお気に入りは、その端末の持ち主にしか無い。**
    ///
    /// どちらも本人の控えで（`WishlistStore` / `FavoritesStore`）、サーバーも
    /// 本人の一覧しか返さない（`/user/spots` は JWT の本人の行だけ）ので、
    /// 他人のぶんは**取りようがない**。以前は他人の
    /// ページにも「お気に入り」の札を出して、押すと「本人だけが見られます」と
    /// 返していた——押しても何も出ない札は、壊れているのと見分けが付かない。
    /// 出さない方が正直。
    ///
    /// **本人のページに「マップ」は出さない**（整理案 05c・2026-09-26）。
    /// 下の札の「マップ」と入口が重なっていた。代わりに「旅の記録」を置く
    /// ——旅の一冊にも足取りの地図がある。他人のページは今まで通り
    static func tabs(isMe: Bool) -> [ProfileTab] {
        isMe ? [.posts, .trips, .wishlist, .favorites] : [.posts, .map]
    }

    // MARK: - 横に払って切り替える（指に付いてくるページ送り）
    //
    // **2026-10-28 判断（owner の実機「投稿からマップにスライドしようとすると、うまくタブの切り替えが
    // できない」・Instagram のように指に付いてくるページ送りにしたい）。** 以前は指を離したときに
    // 「横 50pt 以上・縦の 1.5 倍より横」なら切り替える1回きりの判定で、動いている間は何も動かなかった。
    // 実機で効かなかった本当の原因は判定の厳しさより、払いを SwiftUI の `DragGesture`（`simultaneousGesture`）で
    // 受けていたこと——縦の `ScrollView` の指の操作が先に始まると、払いが途中で取り消されて終わりの判定まで
    // 届かなかった（`ProfileTabSwipe` の注記）。いまは UIKit の指の操作で受け、ここは数の決まりだけを持つ:
    // - 始める: 動き始めの横が**縦の `swipeStartRatio` 倍より大きい**（約 40° より寝ている）で、その向きに隣の札があるとき。
    //   始まったらその指の間は縦に送らない（向きの固定）ので、斜めの縦送りで一覧が突然消えることはない
    // - 動いている間: 中身が指に付いてくる（`followOffset`）。隣が無い向きへは動かさない
    // - 離したとき: 幅の `swipeCommitFraction` 以上動かしたか、同じ向きに `swipeFlingVelocity` 以上の
    //   速さで払ったら隣へ（`settled`）。足りなければ元の札へ戻る

    /// `dx` の向きの隣の札。**指を左へ払う（dx < 0）と右隣、右へ払うと左隣**
    /// （写真アプリ・Instagram と同じ向き）。端では回り込まない
    static func neighbor(of current: ProfileTab, in tabs: [ProfileTab], towards dx: Double) -> ProfileTab? {
        guard dx != 0, let index = tabs.firstIndex(of: current) else { return nil }
        let next = dx < 0 ? index + 1 : index - 1
        return tabs.indices.contains(next) ? tabs[next] : nil
    }

    /// 横の払いを始めるか（動き始めの量で見る）。横が縦の `swipeStartRatio` 倍より大きく、その向きに隣の札があるときだけ。
    /// 隣が無い向き（いちばん左の札で右へ）は始めない——人のページの「戻る」の払いに渡す
    static func startsSwipe(from current: ProfileTab, in tabs: [ProfileTab], dx: Double, dy: Double) -> Bool {
        abs(dx) > abs(dy) * swipeStartRatio && neighbor(of: current, in: tabs, towards: dx) != nil
    }

    /// 動いている間、中身をどれだけ横へずらすか。指の量そのまま（画面の幅まで）。隣が無い向きへは 0
    static func followOffset(from current: ProfileTab, in tabs: [ProfileTab], dx: Double, width: Double) -> Double {
        guard neighbor(of: current, in: tabs, towards: dx) != nil else { return 0 }
        return max(-width, min(width, dx))
    }

    /// 指を離したときの行き先（替えないなら nil）。
    /// - Parameters:
    ///   - dx: 指を置いてからの横の量（左が負）
    ///   - velocity: 離したときの横の速さ（pt/秒・左が負）
    ///   - width: 中身の幅
    static func settled(from current: ProfileTab, in tabs: [ProfileTab],
                        dx: Double, velocity: Double, width: Double) -> ProfileTab? {
        // 勢いのある払い: 動かした向きと同じ向きに速ければ、短くても替える（逆向きに払ったら戻す）
        if abs(velocity) >= swipeFlingVelocity {
            guard dx == 0 || (dx < 0) == (velocity < 0) else { return nil }
            return neighbor(of: current, in: tabs, towards: velocity)
        }
        guard width > 0, abs(dx) >= width * swipeCommitFraction else { return nil }
        return neighbor(of: current, in: tabs, towards: dx)
    }

    /// 離したときにこれだけ動かしていれば替える（中身の幅に対する割合）
    static let swipeCommitFraction: Double = 0.3
    /// 払いを始める横と縦の比（2026-10-28 判断・確かめ役の見直し）。45°（1.0）だと、親指で斜めに流す縦送りの
    /// 出だしが横に寄ったときに札の払いが始まり、縦に送れなくなる（始まったらその指の間は縦に送らない）。
    /// 以前の 1.5 は厳しすぎて普通の払いが効かなかった。その間の 1.2（約 40°）
    static let swipeStartRatio: Double = 1.2
    /// 離したときにこの速さ（pt/秒）以上なら、短くても替える（2026-10-28 判断: 300 → 500）。
    /// 300 では、少し横へ動かして戻しかけた指の揺れでも替わることがあった。ゆっくりでも幅の 3 割動かせば
    /// 替わる（`swipeCommitFraction`）ので、勢いの決まりは「はっきり払った」ときだけでよい
    static let swipeFlingVelocity: Double = 500
}
