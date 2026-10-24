import SwiftUI

/// プロフィールの下の札（投稿 / 旅の記録 / 行きたい場所 / 保存・人のページは 投稿 / マップ）の中身を
/// **横に並べて持つ**入れ物。マイページと人のページで同じ部品。
///
/// **2026-10-24 判断（owner「切り替えスムーズにできるようにしたい」）。** 以前の引っかかり（コードで確かめた原因）:
/// 1. 中身が `if tab == … else if …` の枝だったので、札を替えるたびに前の中身を捨てて作り直していた。
///    格子の写真（`RemoteImage` ＝ `AsyncImage`・手元に絵の控えを持たない）は戻るたびに読み込み中の輪から
///    出直してちらつき、人のページの地図は作り直しで位置が戻っていた（通信の読み直しは無い——中身は画面の
///    持つ一覧から作る）
/// 2. 中身の高さが札ごとに違い、長い格子を下まで送ってから短い札へ替えると、スクロールの位置が
///    詰められて札の行ごと跳んだ
/// 3. 下線は札ごとに「選んでいれば真鍮・でなければ透明」で描き、切り替えにアニメーションが無かった
/// 4. 横の払いはマイページにだけあり（人のページには無い）、切り替えは動き無しで入れ替わるだけだった
///
/// 直し方:
/// - 一度開いた札の中身は**捨てずに持つ**（`ProfileTabPages`）。開いていない札は作らない（最初の読み込みを増やさない）
/// - 札を横に並べ（`ProfileTabPagerLayout`）、選んだ札の高さだけを使い、ほかは外に置いて切り抜く。
///   選んでいない札は押せず、読み上げにも出さない
/// - 中身の高さは**少なくとも「見えている高さ − 札の行と間」**（`minHeight`・`ProfileTabScroll.minPageHeight`）。
///   短い札へ替えても位置が詰められず、札の行が跳ばない。いちばん下まで送っても札の行が上端に残る
/// - 深く送ってから替えたときは、札の行を上端へ送って新しい札を頭から見せる（`ProfileTabScroll.scrollsToRow`・呼ぶ側）
/// - 保持した札の中身の計算は控えから（`MyPageTabMemo`）。見えていない札の分まで描き直しのたびに計算しない
/// - 切り替えは `ProfileTabMotion.animation` で滑らせる（「視差効果を減らす」のときは動かさない）
struct ProfileTabPager<Page: View>: View {

    let tabs: [ProfileTab]
    @Binding var selection: ProfileTab
    /// 中身の最低の高さ（画面に見えている高さ）。0 なら付けない
    var minHeight: CGFloat = 0
    /// 横の払いを受けない札（人のページの地図——地図の横の操作とぶつかる）。札の行の払いは受ける
    var swipeBlocked: Set<ProfileTab> = []
    @ViewBuilder let page: (ProfileTab) -> Page

    @State private var pages = ProfileTabPages(initial: .posts)

    var body: some View {
        ProfileTabPagerLayout(index: tabs.firstIndex(of: selection) ?? 0) {
            ForEach(tabs) { option in
                let shown = option == selection
                Group {
                    if pages.isBuilt(option) || shown {
                        page(option)
                    } else {
                        Color.clear.frame(height: 0)
                    }
                }
                .allowsHitTesting(shown)
                .accessibilityHidden(!shown)
            }
        }
        .frame(minHeight: minHeight, alignment: .top)
        .clipped()
        .modifier(ProfileTabSwipe(tabs: tabs, selection: $selection,
                                  enabled: !swipeBlocked.contains(selection)))
        .onAppear { pages.select(selection) }
        .onChange(of: selection) { _, next in pages.select(next) }
    }
}

/// どの札の中身を作ってあるか（画面を持たない計算）。**一度作った札は持ち続ける**
struct ProfileTabPages: Equatable {

    private(set) var built: [ProfileTab]

    init(initial: ProfileTab) { built = [initial] }

    /// 選んだ札を「作ってある」に足す（二度足さない）
    mutating func select(_ tab: ProfileTab) {
        if !built.contains(tab) { built.append(tab) }
    }

    func isBuilt(_ tab: ProfileTab) -> Bool { built.contains(tab) }

    /// 選んだ札から見た、その札の置き場（画面幅いくつ分右か。左は負）
    static func offset(of tab: ProfileTab, selected: ProfileTab, in tabs: [ProfileTab]) -> Int {
        guard let i = tabs.firstIndex(of: tab), let s = tabs.firstIndex(of: selected) else { return 0 }
        return i - s
    }
}

/// 札の中身を横に並べる。**高さは選んだ札のぶんだけ**（ほかの札の高さで行が伸び縮みしない）
struct ProfileTabPagerLayout: Layout {

    /// 選んでいる札の位置
    let index: Int

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.indices.contains(index) else { return CGSize(width: proposal.width ?? 0, height: 0) }
        let selected = subviews[index].sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? selected.width, height: selected.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for i in subviews.indices {
            subviews[i].place(at: CGPoint(x: bounds.minX + Self.x(of: i, selected: index, width: bounds.width),
                                          y: bounds.minY),
                              proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }

    /// 札 `i` の左端（選んだ札が 0・右隣が画面幅）
    static func x(of i: Int, selected: Int, width: CGFloat) -> CGFloat {
        CGFloat(i - selected) * width
    }
}

/// 札の切り替えの動き。**「視差効果を減らす」のときは動かさない**
enum ProfileTabMotion {
    static let duration: Double = 0.25

    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: duration)
    }
}

/// 横の払いで隣の札へ（札の行と中身の両方に付ける）。**`simultaneousGesture` で付ける**——`gesture` に
/// すると縦のスクロールと写真を押す操作を奪う。判定は `ProfileTab.swiped`（はっきり横に動いたときだけ・端で回り込まない）
struct ProfileTabSwipe: ViewModifier {

    let tabs: [ProfileTab]
    @Binding var selection: ProfileTab
    /// false のときは中の操作（地図など）にだけ渡す
    var enabled: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        guard let next = ProfileTab.swiped(from: selection, in: tabs,
                                                           dx: Double(value.translation.width),
                                                           dy: Double(value.translation.height))
                        else { return }
                        withAnimation(ProfileTabMotion.animation(reduceMotion: reduceMotion)) {
                            selection = next
                        }
                    },
                including: enabled ? .all : .subviews)
    }
}

/// 札の行の位置の計算（画面を持たない計算・2026-10-24 確かめ役の見直し）
enum ProfileTabScroll {

    /// 札の行の目印（`ScrollViewReader.scrollTo`）
    static let rowID = "profile.tabs.row"

    /// 札を替えたとき、札の行を画面の上端へ送るか。**札の行が見えている上端より上へ出ているときだけ**
    /// （深く送ってから替えた回）。まだ送っていない回はそのまま（見出しを見ていた人を動かさない）
    /// - Parameters:
    ///   - rowMinY: 札の行の上端（スクロールの見えている枠から測る）
    ///   - visibleTop: 見えている上端（カバーを時計の裏まで伸ばしたマイページは時計の下＝安全域の高さ。ほかは 0）
    static func scrollsToRow(rowMinY: CGFloat, visibleTop: CGFloat) -> Bool {
        rowMinY < visibleTop - 0.5
    }

    /// `scrollTo` の目印の縦の割合。札の行の上端を `visibleTop` に合わせる
    /// （`scrollTo` は札の行の中の同じ割合の点を、見えている枠の同じ割合の点にそろえる）
    static func anchorY(visibleTop: CGFloat, viewport: CGFloat, rowHeight: CGFloat) -> CGFloat {
        let room = viewport - rowHeight
        guard room > 0 else { return 0 }
        return min(1, max(0, visibleTop / room))
    }

    /// 札の中身の最低の高さ。**見えている高さ − 札の行と間**——いちばん下まで送っても札の行が
    /// 上端に残る（短い札へ替えても位置が詰められず、札の行が跳ばない）。余計な空きは作らない
    static func minPageHeight(viewport: CGFloat, visibleTop: CGFloat, rowHeight: CGFloat, spacing: CGFloat) -> CGFloat {
        max(0, viewport - visibleTop - rowHeight - spacing)
    }
}

/// 同じ入力なら前の答えを返す控え。**保持した札の中身の計算を、描き直しのたびに走らせない**
/// （見えていない札の分まで毎回計算していた・2026-10-24 確かめ役の見直し）。
/// 入力の比べは `==`（配列は同じ入れ物なら中身を見ずに一致する）
final class DerivedMemo<Key: Equatable, Value> {
    private var last: (key: Key, value: Value)?
    /// 計算した回数（テスト用）
    private(set) var computeCount = 0

    init() {}

    func value(for key: Key, _ make: () -> Value) -> Value {
        if let last, last.key == key { return last.value }
        let value = make()
        last = (key, value)
        computeCount += 1
        return value
    }
}

/// マイページの札の中身の計算の控え（写真・公開一覧・見せない人・行きたい場所の鍵が変わったときだけ計算し直す）
final class MyPageTabMemo {

    struct PoolKey: Equatable {
        let feed: [Photo]
        let mine: [Photo]
        let hidden: ModerationSnapshot?
    }

    struct WantedKey: Equatable {
        let keys: Set<String>
        let pool: [Photo]
    }

    struct SavedKey: Equatable {
        let ids: Set<String>
        let publicPool: [Photo]
        let mine: [Photo]
    }

    let shelf = DerivedMemo<[Photo], [TripBook.Trip]>()
    let posted = DerivedMemo<[Photo], [LibraryTrips.PostedShot]>()
    let publicPool = DerivedMemo<PoolKey, [Photo]>()
    let unfilteredPool = DerivedMemo<PoolKey, [Photo]>()
    let pool = DerivedMemo<PoolKey, [Photo]>()
    let wanted = DerivedMemo<WantedKey, [DerivedSpot.Place]>()
    let unfilteredWanted = DerivedMemo<WantedKey, [DerivedSpot.Place]>()
    let saved = DerivedMemo<SavedKey, [Photo]>()

    init() {}

    func shelfTrips(_ photos: [Photo]) -> [TripBook.Trip] {
        shelf.value(for: photos) { TripBook.shelfTrips(from: photos) }
    }

    func postedShots(_ photos: [Photo]) -> [LibraryTrips.PostedShot] {
        posted.value(for: photos) { LibraryTrips.postedShots(of: photos) }
    }

    /// 見せない人を落とした公開一覧
    func visibleFeed(_ feed: [Photo], hidden: ModerationSnapshot) -> [Photo] {
        publicPool.value(for: PoolKey(feed: feed, mine: [], hidden: hidden)) { hidden.visible(feed) }
    }

    func wishlistPool(own: [Photo], feed: [Photo], hidden: ModerationSnapshot) -> [Photo] {
        pool.value(for: PoolKey(feed: feed, mine: own, hidden: hidden)) {
            MyPageView.wishlistPool(own: own, feed: feed, hidden: hidden)
        }
    }

    func unfilteredWishlistPool(own: [Photo], feed: [Photo]) -> [Photo] {
        unfilteredPool.value(for: PoolKey(feed: feed, mine: own, hidden: nil)) {
            ProfileSections.wishlistPool(feed: feed, mine: own)
        }
    }

    func wantedPlaces(keys: Set<String>, pool: [Photo]) -> [DerivedSpot.Place] {
        wanted.value(for: WantedKey(keys: keys, pool: pool)) {
            ProfileSections.wantedPlaces(keys: keys, pool: pool)
        }
    }

    func unfilteredWantedPlaces(keys: Set<String>, pool: [Photo]) -> [DerivedSpot.Place] {
        unfilteredWanted.value(for: WantedKey(keys: keys, pool: pool)) {
            ProfileSections.wantedPlaces(keys: keys, pool: pool)
        }
    }

    func savedPhotos(ids: Set<String>, publicPool: [Photo], mine: [Photo]) -> [Photo] {
        saved.value(for: SavedKey(ids: ids, publicPool: publicPool, mine: mine)) {
            LikedPhotos.resolve(ids, in: [publicPool, mine])
        }
    }
}
