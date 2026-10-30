import SwiftUI
#if os(iOS)
import UIKit
#endif

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
/// - **横の払いでは中身が指に付いてくる**（2026-10-28 判断・`ProfileTab.settled`・`ProfileTabSwipe`）。
///   動かし始めたら、その向きの隣の札を作って（まだなら）右か左から見せる
struct ProfileTabPager<Page: View>: View {

    let tabs: [ProfileTab]
    @Binding var selection: ProfileTab
    /// 中身の最低の高さ（画面に見えている高さ）。0 なら付けない
    var minHeight: CGFloat = 0
    /// 横の払いを受けない札（人のページの地図——地図の横の操作とぶつかる）。札の行の払いは受ける。
    /// **その札へ入る払いは受ける**（投稿の中身を左へ払えば地図へ移る）——止めるのは、その札を
    /// 選んでいる間の中身の上だけ（`ProfileTabSwipe.enabled`・2026-10-28 判断）
    var swipeBlocked: Set<ProfileTab> = []
    /// 札の行が見えている上端からどれだけ上へ出ているか（深く送った回だけ正・`ProfileTabScroll.rowOverflow`）。
    /// **値ではなく読み方で受ける**（2026-10-28）——値で受けると、呼ぶ側は送るたびに変わる上端を
    /// 見張る値に置くことになり、1フレームごとに画面全体が作り直される（`ProfileTabRowSpot`）。読むのは払い始めだけ
    var rowOverflow: () -> CGFloat = { 0 }
    /// 画面を開いて手が空いたら先に作っておく札（人のページの地図——払いの途中に初めて作ると引っかかる）
    var prebuilt: [ProfileTab] = []
    @ViewBuilder let page: (ProfileTab) -> Page

    @State private var pages = ProfileTabPages(initial: .posts)
    /// 指に付いてきている横の量。**入れ物の `body` はこれに依存しない**（2026-10-28 確かめ役の見直し）——
    /// `@State` に箱（参照）を置くだけで中を見張らないので、払っている間に毎フレーム全部の札の `page()` を
    /// 作り直さない。読むのは中身をずらす小さな子（`ProfileTabDragOffset`）だけ
    @State private var drag = ProfileTabDrag()
    /// 選んでいない札を下へずらす量（払い始めに `rowOverflow` を写す）
    @State private var lift: CGFloat = 0

    var body: some View {
        ProfileTabDragOffset(drag: drag, content:
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
                    // **2026-10-28 判断（確かめ役: 深く送ってから払うと、入ってくる札が空に見えた）。**
                    // 隣の札は札の行の真下から並ぶので、深く送った回はいま見えている高さより上に頭があった。
                    // 払い始めに、選んでいない札を「札の行を上端へ送ったときの位置」まで下げて見せる
                    // （Instagram と同じく、隣の札は頭から）。替えたら呼ぶ側が札の行を上端へ送り
                    // （`ProfileTabScroll.scrollsToRow`）、同じ動きでこのずらしが 0 に戻るので、新しい札は跳ばない。
                    // 払い始めに札の行を先に上端へ送る案は採らない——指の下の一覧が縦に飛ぶ
                    .offset(y: shown ? 0 : lift)
                    .allowsHitTesting(shown)
                    .accessibilityHidden(!shown)
                }
            }
        )
        .frame(minHeight: minHeight, alignment: .top)
        .clipped()
        .modifier(ProfileTabSwipe(tabs: tabs, selection: $selection,
                                  enabled: !swipeBlocked.contains(selection), follow: drag,
                                  willShow: { next in
                                      // 払っている間は毎フレーム呼ばれる。状態を書くのは変わるときだけ
                                      let overflow = rowOverflow()
                                      if lift != overflow { lift = overflow }
                                      // 隣の札は、まだ作っていなければ作る（指の後ろから空の札が出てこない）
                                      if !pages.isBuilt(next) { pages.select(next) }
                                  }))
        .onAppear { pages.select(selection) }
        .onChange(of: selection) { _, next in pages.select(next) }
        // 払いの途中で画面を離れたら、ずらしを残さない
        .onDisappear { drag.offset = 0 }
        .task {
            // 開いてすぐは見えている札の読み込みを優先し、少し待ってから作る
            guard !prebuilt.isEmpty else { return }
            try? await Task.sleep(nanoseconds: ProfileTabPrebuild.delayNanoseconds)
            guard !Task.isCancelled else { return }
            for tab in prebuilt where tabs.contains(tab) && !pages.isBuilt(tab) { pages.select(tab) }
        }
    }
}

/// 画面を開いてから先に札を作るまでの待ち
enum ProfileTabPrebuild {
    static let delayNanoseconds: UInt64 = 1_200_000_000
}

/// 指に付いてくる横の量の箱。**見張るのは `ProfileTabDragOffset` だけ**（入れ物は持つだけ）
final class ProfileTabDrag: ObservableObject {
    @Published var offset: CGFloat = 0
}

/// 中身を横にずらす小さな子。払っている間に描き直すのはここだけ。**中身は親が作った値で受け取る**
/// （作り方の関数で受けると、ここが描き直すたびに全部の札の `page()` を呼び直す）
struct ProfileTabDragOffset<Content: View>: View {
    @ObservedObject var drag: ProfileTabDrag
    let content: Content

    var body: some View {
        content.offset(x: drag.offset)
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

/// 札の切り替えの動き。**「視差効果を減らす」のときは動かさない**（下線も中身も置くだけ）。
///
/// 2026-10-30 owner 採用（#418・案A）: 0.25 秒の easeOut から **0.28 秒のばね（減衰 0.85）** に替えた。
/// 下線が次の札の幅に伸び縮みしながら滑る動きと、中身の横の送り・札の行へ戻す送りを同じ手ざわりにする
/// （値は `ProfileTabStyle.springResponse`・`springDamping`）
enum ProfileTabMotion {
    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: ProfileTabStyle.springResponse,
                                     dampingFraction: ProfileTabStyle.springDamping)
    }
}

/// 横の払いで隣の札へ（札の行と中身の両方に付ける）。判定の数は `ProfileTab`（`startsSwipe`・`followOffset`・`settled`）。
///
/// **2026-10-28 判断（owner の実機で投稿から隣の札へ払っても替わらなかった）。** 以前は SwiftUI の
/// `DragGesture` を `simultaneousGesture` で付け、指を離したときに1回だけ判定していた。実機では
/// 縦の `ScrollView` の指の操作（UIKit のパン）が先に始まると SwiftUI の払いが取り消され、`onEnded` が
/// 呼ばれずに終わった——札の行の上の、勢いを付けない送り（UI テストの道）では通るのに、格子の上を普通の
/// 速さで払うと効かなかった。`gesture` に替えると今度は縦のスクロールと写真を押す操作を奪う。
///
/// いまは**縦の送りを持つ `UIScrollView` に、UIKit のパンを1本足す**（`ProfileSwipeCatcher`）:
/// - この部品の枠の中で始まった指だけを見る。動き始めが縦より横で、その向きに隣の札があれば始める
/// - 縦の送りは**こちらが「始めない」と決まってから動く**（`shouldBeRequiredToFailBy`）——横に払っている指で
///   一覧が縦に揺れない／縦に送っている指で札が替わらない（向きの固定）
/// - 始まったら写真を押す操作は取り消される（払って離した指で写真の詳細が開かない）。長押しのメニューは
///   指を止めたときだけなので、払いとはぶつからない
/// - `follow` を渡すと、動いている間の横の量をそこへ書く（中身が指に付いてくる・`ProfileTabPager`）。
///   札の行は渡さない（離したときに替わる）
///
/// `enabled` が false の札（人のページの地図）では、この部品の枠の中の指を受けない——地図を横に
/// 動かす操作を優先する（2026-10-28 判断: 地図の中で払って札を替えると、地図を動かしたいのか札を替え
/// たいのか指だけでは分けられない。地図から出るのは札の行の払いか札を押す。地図へ入る払いは投稿の中身で効く）
struct ProfileTabSwipe: ViewModifier {

    let tabs: [ProfileTab]
    @Binding var selection: ProfileTab
    /// false のときは中の操作（地図など）にだけ渡す
    var enabled: Bool = true
    /// 指に付いてくる横の量の書き込み先（中身を動かす `ProfileTabPager` だけが渡す）
    var follow: ProfileTabDrag? = nil
    /// 動いている間、入ってくる隣の札を知らせる（作っておく・縦の位置をそろえる）
    var willShow: ((ProfileTab) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background {
                ProfileSwipeCatcher(
                    isEnabled: enabled,
                    shouldBegin: { dx, dy in
                        ProfileTab.startsSwipe(from: selection, in: tabs, dx: dx, dy: dy)
                    },
                    onChange: { dx, width in
                        if let next = ProfileTab.neighbor(of: selection, in: tabs, towards: dx) { willShow?(next) }
                        follow?.offset = CGFloat(ProfileTab.followOffset(from: selection, in: tabs,
                                                                         dx: dx, width: width))
                    },
                    onEnd: { dx, velocity, width in
                        let next = ProfileTab.settled(from: selection, in: tabs,
                                                      dx: dx, velocity: velocity, width: width)
                        withAnimation(ProfileTabMotion.animation(reduceMotion: reduceMotion)) {
                            if let next { selection = next }
                            follow?.offset = 0
                        }
                    })
            }
    }
}

/// 縦の送りの `UIScrollView` に横のパンを足す見えない部品（`ProfileTabSwipe`）。指は受けない——枠の大きさと
/// 位置を測るためだけに置く。UIKit の部分は iOS だけ（`ProfileSwipePanHost`）。Linux の型検査では何も置かない
struct ProfileSwipeCatcher: View {

    var isEnabled: Bool
    /// 動き始めの横・縦の量で、始めるか
    var shouldBegin: (Double, Double) -> Bool
    /// 動いている間（横の量・枠の幅）
    var onChange: (Double, Double) -> Void
    /// 離した・取り消された（横の量・横の速さ・枠の幅）。取り消しは量も速さも 0
    var onEnd: (Double, Double, Double) -> Void

    var body: some View {
        #if os(iOS)
        ProfileSwipePanHost(handlers: self)
        #else
        Color.clear
        #endif
    }
}

#if os(iOS)
/// `ProfileSwipeCatcher` の UIKit の部分（`isUserInteractionEnabled = false` の見えない UIView）
struct ProfileSwipePanHost: UIViewRepresentable {

    let handlers: ProfileSwipeCatcher

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.backgroundColor = .clear
        probe.isUserInteractionEnabled = false
        probe.coordinator = context.coordinator
        context.coordinator.handlers = handlers
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        context.coordinator.handlers = handlers
        context.coordinator.attach(to: probe)
    }

    static func dismantleUIView(_ probe: Probe, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// 窓に載った・外れたときに、パンを付け替える
    final class Probe: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attach(to: self)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        var handlers: ProfileSwipeCatcher?
        private weak var probe: UIView?
        private weak var host: UIScrollView?
        private lazy var pan: UIPanGestureRecognizer = {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            return pan
        }()

        /// いちばん近い祖先の `UIScrollView`（縦の送り）にパンを付ける
        func attach(to probe: UIView) {
            self.probe = probe
            guard probe.window != nil else { detach(); return }
            var view = probe.superview
            while let current = view, !(current is UIScrollView) { view = current.superview }
            guard let scroll = view as? UIScrollView else { detach(); return }
            guard scroll !== host || pan.view !== scroll else { return }
            detach()
            scroll.addGestureRecognizer(pan)
            host = scroll
        }

        /// 外す。**払いの途中なら「取り消し」として終える**（画面を離れたときにずらしを残さない）
        func detach() {
            if pan.state == .began || pan.state == .changed {
                handlers?.onEnd(0, 0, Double(probe?.bounds.width ?? 0))
            }
            pan.view?.removeGestureRecognizer(pan)
            host = nil
        }

        @objc private func handle(_ pan: UIPanGestureRecognizer) {
            guard let probe, let handlers else { return }
            let width = Double(probe.bounds.width)
            switch pan.state {
            case .began, .changed:
                handlers.onChange(Double(pan.translation(in: probe).x), width)
            case .ended:
                handlers.onEnd(Double(pan.translation(in: probe).x), Double(pan.velocity(in: probe).x), width)
            case .cancelled, .failed:
                handlers.onEnd(0, 0, width)
            default:
                break
            }
        }

        /// この部品の枠の中で始まった指だけ（枠の外の縦の送り・ハイライトの横の列には関わらない）
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard gestureRecognizer === pan, let probe, probe.window != nil, handlers?.isEnabled == true else {
                return false
            }
            return probe.bounds.contains(touch.location(in: probe))
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === pan, let probe, let handlers else { return true }
            var move = pan.translation(in: probe)
            if move == .zero { move = pan.velocity(in: probe) }
            return handlers.shouldBegin(Double(move.x), Double(move.y))
        }

        /// 縦の送りは、こちらが「始めない」と決まってから（向きの固定）
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer === pan && otherGestureRecognizer === host?.panGestureRecognizer
        }
    }
}
#endif

/// 札の行の位置の控え（マイページ・人のページ）。
///
/// **2026-10-28 判断（owner「スクロールするとなんか重い」）: 送るたびに変わる上端を `@State` に置かない。**
/// 札の行の上端は送るたびに（1フレームごとに）変わる。`@State` の値に書くと、そのたびに画面の
/// `body` ぜんぶ（見出し・保持した全部の札の `page()`）が作り直されていた。上端を読むのは
/// 札を替えたとき（`scrollsToRow`）と払い始め（`rowOverflow`）だけなので、見張らない箱に控える
/// （`@State` に置くのは箱の参照だけ。中を書き換えても描き直さない・`ProfileTabDrag` と同じ形）。
/// 高さは最低の高さの計算（描く値）に使い、文字の大きさでしか変わらないので、変わったときだけ返す
final class ProfileTabRowSpot {
    /// 札の行の上端（スクロールの見えている枠から）
    private(set) var minY: CGFloat = 0

    /// 測った枠を控える。戻り値は**描き直しが要るときだけ**新しい高さ（上端だけ動いた回は nil）
    func record(_ frame: CGRect, height current: CGFloat) -> CGFloat? {
        minY = frame.minY
        return frame.height == current ? nil : frame.height
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

    /// 札の行が見えている上端からどれだけ上へ出ているか（出ていなければ 0）。払っている間、選んでいない札を
    /// これだけ下げると、札の行を上端へ送ったときの位置に頭が来る（`ProfileTabPager.lift`・2026-10-28）
    static func rowOverflow(rowMinY: CGFloat, visibleTop: CGFloat) -> CGFloat {
        scrollsToRow(rowMinY: rowMinY, visibleTop: visibleTop) ? visibleTop - rowMinY : 0
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
    /// 旅の記録の数（見出しの下の節）。2026-10-28 判断: 描き直しのたびに数え直していた（古い順の並べ替え3回・
    /// 国の名前の当てはめ）ので、写真が変わったときだけ数える
    let travel = DerivedMemo<[Photo], ProfileTravelRecord.Summary>()
    /// 投稿の格子の「複数枚」の印の写真（同じく写真が変わったときだけ）
    let multiple = DerivedMemo<[Photo], Set<String>>()

    init() {}

    func travelSummary(_ photos: [Photo]) -> ProfileTravelRecord.Summary {
        travel.value(for: photos) { ProfileTravelRecord.Summary(photos: photos) }
    }

    func multiPhotoIds(_ photos: [Photo]) -> Set<String> {
        multiple.value(for: photos) { PhotoGroups.multiPhotoIds(photos) }
    }

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

/// 人のページの旅の記録・旅の棚の計算の控え（2026-10-28 判断・マイページの `MyPageTabMemo.travelSummary` と同じ理由）。
/// 写真かブロックの関係が変わったときだけ数える
final class OthersTravelMemo {

    struct Key: Equatable {
        let photos: [Photo]
        let blocked: Bool
    }

    let summary = DerivedMemo<Key, ProfileTravelRecord.Summary>()
    let shelf = DerivedMemo<Key, ProfileTravelRecord.OthersShelf>()

    init() {}

    func othersSummary(_ photos: [Photo], blocked: Bool) -> ProfileTravelRecord.Summary {
        summary.value(for: Key(photos: photos, blocked: blocked)) {
            ProfileTravelRecord.othersSummary(photos, blocked: blocked)
        }
    }

    func othersShelf(_ photos: [Photo], blocked: Bool) -> ProfileTravelRecord.OthersShelf {
        shelf.value(for: Key(photos: photos, blocked: blocked)) {
            ProfileTravelRecord.othersShelf(photos, blocked: blocked)
        }
    }
}
