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
///
/// **2026-10-31 判断（#426）: 区分の型（`PagedTab`）で受ける。** ホームのフィード（おすすめ / フォロー中 / 新着）・
/// フォロー一覧・ストーリーの分析・すれちがい帳・着想の棚も、この入れ物で横にめくる（写しを作らない）
struct ProfileTabPager<Tab: PagedTab, Page: View>: View {

    let tabs: [Tab]
    @Binding var selection: Tab
    /// 中身の最低の高さ（画面に見えている高さ）。0 なら付けない
    var minHeight: CGFloat = 0
    /// 横の払いを受けない札（人のページの地図——地図の横の操作とぶつかる）。札の行の払いは受ける。
    /// **その札へ入る払いは受ける**（投稿の中身を左へ払えば地図へ移る）——止めるのは、その札を
    /// 選んでいる間の中身の上だけ（`ProfileTabSwipe.enabled`・2026-10-28 判断）
    var swipeBlocked: Set<Tab> = []
    /// 札の行が見えている上端からどれだけ上へ出ているか（深く送った回だけ正・`ProfileTabScroll.rowOverflow`）。
    /// **値ではなく読み方で受ける**（2026-10-28）——値で受けると、呼ぶ側は送るたびに変わる上端を
    /// 見張る値に置くことになり、1フレームごとに画面全体が作り直される（`ProfileTabRowSpot`）。読むのは払い始めだけ
    var rowOverflow: () -> CGFloat = { 0 }
    /// 画面を開いて手が空いたら先に作っておく札（人のページの地図——払いの途中に初めて作ると引っかかる）
    var prebuilt: [Tab] = []
    /// 選んでいる札から2つ以上離れた札の中身を捨てるか（2026-10-31 #426 確かめ役の見直し・ホームの重さ）。
    /// 既定は持ち続ける（マイページ・人のページ）。ホームは写真の一覧が長いので、選んでいる札と左右の隣だけを持つ
    /// ——隣へは払っている間に作り（`willShow`）、戻りは隣なので作り直さない（`ProfileTabPages.trim`）。
    /// **直前に選んでいた札は捨てない**（2026-10-31 #426 2回目の確かめ）: 選び替えた直後に捨てると、滑っている
    /// 最中に出ていく札が空になり、すぐ戻ると作り直して #423 で消した「ちらつき」が戻る。ばねが落ち着く時間を
    /// 待って捨てる案は採らない——待ち時間の間に続けて替えると、どの札を捨てるかが時間でずれ、
    /// 「視差効果を減らす」で滑らない回とも決まりが割れる。直前の札を残す方が、いつも同じ札が残って手ざわりが揃う
    var keepsDistantPages: Bool = true
    /// 払いを受ける枠を上へ広げる量（ホーム・2026-10-31 #426 確かめ役の見直し）。ホームは札の行が節の見出しで、
    /// 札の行と中身にそれぞれ払いを付けると、留まった札の行（中身の上に重なる）の上で2つが指を取り合い、
    /// 札の行の上の払いでは中身が指に付いてこなかった。中身の払い1つの枠を札の行まで広げ、どちらで払っても同じにする
    var swipeExtendsUp: CGFloat = 0
    @ViewBuilder let page: (Tab) -> Page

    /// 作ってある札。**最初は空**で、出たとき（`onAppear`）に選んでいる札を入れる——以前は `.posts` 決め打ちで、
    /// 区分の型を広げたので初めの札を決められない（選んでいる札は `shown` で作るので、空でも中身は出る）
    @State private var pages = ProfileTabPages<Tab>()
    /// 指に付いてきている横の量。**入れ物の `body` はこれに依存しない**（2026-10-28 確かめ役の見直し）——
    /// `@State` に箱（参照）を置くだけで中を見張らないので、払っている間に毎フレーム全部の札の `page()` を
    /// 作り直さない。読むのは中身をずらす小さな子（`ProfileTabDragOffset`）だけ
    @State private var drag = ProfileTabDrag()
    /// 選んでいない札を下へずらす量（払い始めに `rowOverflow` を写す）
    @State private var lift: CGFloat = 0

    var body: some View {
        ProfileTabDragOffset(drag: drag, content:
            ProfileTabPagerLayout(index: tabs.firstIndex(of: selection) ?? 0) {
                ForEach(tabs, id: \.self) { option in
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
                                  extendsUp: swipeExtendsUp,
                                  willShow: { next in
                                      // 払っている間は毎フレーム呼ばれる。状態を書くのは変わるときだけ
                                      let overflow = rowOverflow()
                                      if lift != overflow { lift = overflow }
                                      // 隣の札は、まだ作っていなければ作る（指の後ろから空の札が出てこない）
                                      if !pages.isBuilt(next) { pages.select(next) }
                                  }))
        .onAppear { pages.select(selection) }
        .onChange(of: selection) { previous, next in
            pages.select(next)
            if !keepsDistantPages { pages.trim(around: next, keeping: previous, in: tabs) }
        }
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

/// 縦の送りの中を流れる「札の行＋横にめくる中身」（2026-10-31 判断・#426）。
///
/// 人のページ（`UserProfileView`）で組んだ形——札の行の位置の控え（`ProfileTabRowSpot`）・深く送ってから替えたら
/// 札の行を上端へ（`ProfileTabScroll.scrollsToRow`）・払っている間に隣の札を下げる（`rowOverflow`）・最低の高さ
/// （`minPageHeight`）——を1つにまとめた。フォロー一覧・ストーリーの分析・すれちがい帳・着想の棚がこれを使う
/// （画面ごとに同じ手順を写さない）。**置くのは縦の `ScrollView` の中**（見えている上端が 0 の画面）。
/// 札の行は上に留めない（マイページ・ホームのように留める画面は、それぞれの留め方で `ProfileTabBar` と
/// `ProfileTabPager` を直に使う）
struct ProfileTabSection<Tab: PagedTab, Page: View>: View {

    let tabs: [Tab]
    @Binding var selection: Tab
    /// 縦の送りの見えている高さ（呼ぶ側が `onGeometryChange` で測る）。0 なら最低の高さを付けない
    var viewport: CGFloat = 0
    /// 札の行と中身の間
    var spacing: CGFloat = JPSpace.m
    /// 札の字の左右の余白（`ProfileTabBar.gutter`）
    var gutter: CGFloat = ProfileTabStyle.gutter
    /// 札の名前の右の数（`ProfileTabBar.detail`）
    var detail: (Tab) -> String? = { _ in nil }
    @ViewBuilder let page: (Tab) -> Page

    @State private var row = ProfileTabRowSpot()
    @State private var rowHeight: CGFloat = ProfileTabStyle.height
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 札の行の目印（替えたら頭から）。1つの画面に1つだけ置く
    static var rowID: String { "tabs.section.row" }

    var body: some View {
        ScrollViewReader { reader in
            VStack(alignment: .leading, spacing: spacing) {
                ProfileTabBar(tabs: tabs, selection: $selection, gutter: gutter, detail: detail)
                    .modifier(ProfileTabSwipe(tabs: tabs, selection: $selection))
                    .id(Self.rowID)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .scrollView)
                    } action: { frame in
                        if let height = row.record(frame, height: rowHeight) { rowHeight = height }
                    }
                ProfileTabPager(tabs: tabs, selection: $selection,
                                minHeight: viewport > 0
                                    ? ProfileTabScroll.minPageHeight(viewport: viewport, visibleTop: 0,
                                                                     rowHeight: rowHeight, spacing: spacing)
                                    : 0,
                                rowOverflow: { ProfileTabScroll.rowOverflow(rowMinY: row.minY, visibleTop: 0) }) { tab in
                    page(tab)
                }
            }
            // 深く送ってから札を替えたら、新しい札は頭から（札の行を上端へ）。まだ送っていなければそのまま
            .onChange(of: selection) { _, _ in
                guard ProfileTabScroll.scrollsToRow(rowMinY: row.minY, visibleTop: 0) else { return }
                withAnimation(ProfileTabMotion.animation(reduceMotion: reduceMotion)) {
                    reader.scrollTo(Self.rowID, anchor: .top)
                }
            }
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
struct ProfileTabPages<Tab: Hashable>: Equatable {

    private(set) var built: [Tab]

    init() { built = [] }

    init(initial: Tab) { built = [initial] }

    /// 選んだ札を「作ってある」に足す（二度足さない）
    mutating func select(_ tab: Tab) {
        if !built.contains(tab) { built.append(tab) }
    }

    func isBuilt(_ tab: Tab) -> Bool { built.contains(tab) }

    /// 選んでいる札から2つ以上離れた札を捨てる。左右の隣と、**直前に選んでいた札**（`keeping`）は残す——
    /// 払って戻るときに作り直さない・滑っている最中に出ていく札を空にしない
    mutating func trim(around selected: Tab, keeping previous: Tab? = nil, in tabs: [Tab]) {
        guard let center = tabs.firstIndex(of: selected) else { return }
        built.removeAll { tab in
            if tab == previous { return false }
            guard let index = tabs.firstIndex(of: tab) else { return true }
            return abs(index - center) > 1
        }
    }

    /// 選んだ札から見た、その札の置き場（画面幅いくつ分右か。左は負）
    static func offset(of tab: Tab, selected: Tab, in tabs: [Tab]) -> Int {
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
struct ProfileTabSwipe<Tab: PagedTab>: ViewModifier {

    let tabs: [Tab]
    @Binding var selection: Tab
    /// false のときは中の操作（地図など）にだけ渡す
    var enabled: Bool = true
    /// 指に付いてくる横の量の書き込み先（中身を動かす `ProfileTabPager` だけが渡す）
    var follow: ProfileTabDrag? = nil
    /// 指を受ける枠を上へ広げる量（`ProfileTabPager.swipeExtendsUp`）
    var extendsUp: CGFloat = 0
    /// 動いている間、入ってくる隣の札を知らせる（作っておく・縦の位置をそろえる）
    var willShow: ((Tab) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background {
                ProfileSwipeCatcher(
                    isEnabled: enabled,
                    shouldBegin: { dx, dy in
                        Tab.startsSwipe(from: selection, in: tabs, dx: dx, dy: dy)
                    },
                    onChange: { dx, width in
                        if let next = Tab.neighbor(of: selection, in: tabs, towards: dx) { willShow?(next) }
                        follow?.offset = CGFloat(Tab.followOffset(from: selection, in: tabs,
                                                                  dx: dx, width: width))
                    },
                    onEnd: { dx, velocity, width in
                        let next = Tab.settled(from: selection, in: tabs,
                                               dx: dx, velocity: velocity, width: width)
                        withAnimation(ProfileTabMotion.animation(reduceMotion: reduceMotion)) {
                            if let next { selection = next }
                            follow?.offset = 0
                        }
                    })
                    // 枠を上へ広げる（札の行が中身の上の見出しの画面）。広げた分も同じ1つの払いが受ける
                    .padding(.top, -extendsUp)
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
            guard probe.bounds.contains(touch.location(in: probe)) else { return false }
            // 2026-10-31 判断（#426・ホームの「おすすめ」には横に流れる列がある——PICKS・季節の撮影スポット）:
            // 横に流れる列の上で始まった指は、その列に渡す（列を流したいのか札を替えたいのか指だけでは分けられない）。
            // 札を替えるのは列の外の払いか札を押す
            return !Self.startsInHorizontalScroller(touch.view, host: host)
        }

        /// 指の下（`view`）から縦の送り（`host`）までの間に、横に流れる `UIScrollView` があるか
        static func startsInHorizontalScroller(_ view: UIView?, host: UIScrollView?) -> Bool {
            var current = view
            while let candidate = current, candidate !== host {
                if let scroll = candidate as? UIScrollView,
                   scroll.isScrollEnabled, scroll.contentSize.width > scroll.bounds.width + 1 {
                    return true
                }
                current = candidate.superview
            }
            return false
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

/// 節の見出し（`LazyVStack(pinnedViews: [.sectionHeaders])`）で上に留める札の行の位置の控え（ホーム・#426）。
///
/// **2026-10-31 判断: ホームはマイページの「重ねて描く札」（`pinnedTabRow`）にしない。** ホームの並びは
/// `LazyVStack` で、流れている札の行は深く送ると作り直されて位置を測れなくなる（測れないと、払っている間に
/// 隣の札を下げる量 `rowOverflow` が古いまま残り、入ってくる札が空に見える——マイページの 2026-10-28 の件）。
/// 節の見出しは留まっている間も生きているので、#417 ⑧ の留め方はそのまま使い、位置は次の2つから出す:
/// - 札の行の下端（見出し）と、札の中身の上端（`ProfileTabPager`）。留まっていない間は2つの間（`restGap`）は
///   変わらず、留まると中身だけが上へ流れて間が詰まる。**詰まった量がはみ出し**（`ProfileTabScroll.pinnedOverflow`）
/// - 間の決まった値は測って覚える（見出しと中身の間に `LazyVStack` の間が入るかを決め打ちしない）。
///   **覚え直すのは「留まっていない」と分かる回だけ**: 開いた最初の回（札の行は画面の中ほど）と、前の計算から
///   札の行と中身が同じだけ動いた回（留まっていれば札の行は動かない）。2026-10-31 確かめ役の見直し: 以前は
///   「いちばん広かった間」を覚えて戻らなかったので、一度広すぎる間を測ると「留まった」と思い込み続けた
///
/// 2つの位置は別々の `onGeometryChange` で届く。片方だけ新しい値で計算すると、送っている最中は1フレームぶん
/// ずれた間を覚えてしまう——**両方が届いた後（次の回り）にまとめて計算する**（`schedule`）。
/// 送るたびに変わる値なので `@State` に置かない（`ProfileTabRowSpot` と同じ）。描き直すのは留まった・外れたときだけ
final class PinnedTabRowSpot {
    private(set) var headerMaxY: CGFloat?
    private(set) var contentMinY: CGFloat?
    /// 留まっていないときの札の行と中身の間（留まっていないと分かった回に覚え直す）
    private(set) var restGap: CGFloat?
    /// 前の計算のときの2つの位置（同じだけ動いたか＝留まっていないかを見る）
    private var settledHeader: CGFloat?
    private var settledContent: CGFloat?
    private var scheduled = false

    /// 札の行（見出し）の下端を控える。計算は次の回りで（`settled` に留まっているかを渡す）
    func recordHeader(maxY: CGFloat, settled: @escaping (Bool) -> Void) {
        headerMaxY = maxY
        schedule(settled)
    }

    /// 札の中身の上端を控える
    func recordContent(minY: CGFloat, settled: @escaping (Bool) -> Void) {
        contentMinY = minY
        schedule(settled)
    }

    /// 2つの位置がそろった今の値で、元の間を覚え直して、留まっているかを返す
    @discardableResult
    func settle() -> Bool {
        if let headerMaxY, let contentMinY {
            if Self.isFlowing(header: headerMaxY, content: contentMinY,
                              previousHeader: settledHeader, previousContent: settledContent) {
                restGap = contentMinY - headerMaxY
            }
            settledHeader = headerMaxY
            settledContent = contentMinY
        }
        return isPinned
    }

    /// 札の行が留まっていない（流れている）と分かるか。最初の回（前が無い）か、札の行が動き、中身も同じだけ動いた回。
    /// 留まっている間は札の行が動かないので、中身だけ動いた回は覚え直さない
    static func isFlowing(header: CGFloat, content: CGFloat, previousHeader: CGFloat?, previousContent: CGFloat?) -> Bool {
        guard let previousHeader, let previousContent else { return true }
        let moved = header - previousHeader
        return abs(moved) > 0.5 && abs(moved - (content - previousContent)) < 0.5
    }

    /// 札の中身の頭が、留まった札の行の下からどれだけ上へ流れているか（留まっていなければ 0）
    var overflow: CGFloat {
        guard let headerMaxY, let contentMinY, let restGap else { return 0 }
        return ProfileTabScroll.pinnedOverflow(gap: contentMinY - headerMaxY, restGap: restGap)
    }

    /// 札の行が上に留まっているか（`ProfileTabScroll.scrollsToRow` と同じ 0.5 の遊び）
    var isPinned: Bool { overflow > 0.5 }

    private func schedule(_ settled: @escaping (Bool) -> Void) {
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [self] in
            scheduled = false
            settled(settle())
        }
    }
}

/// 縦の送り（`UIScrollView`）を直に送る取っ手（ホーム・2026-10-31 #426 Mac の確かめ）。
///
/// **ホームで「留まったまま替えたら頭へ」を `ScrollViewReader.scrollTo` でやめた理由**（run 41187923424・
/// `testSwipesHomeFeedTabs`）: 留まった札の行（`LazyVStack` の節の見出し）を目印に送ると、札の行が留まりの位置
/// （y=116）から送る前の頭（y=558・いちばん上）まで戻った。遅れて作る並びは、深く送ると上の段（すれちがい・
/// ストーリー・上の札）を捨てて高さを見積もりに置き換えるので、目印の位置がその見積もりで決まり、いちばん上へ
/// 送ってしまう。いまは測った実物の量（`PinnedTabRowSpot.overflow`＝中身の頭が札の行の下からどれだけ上へ
/// 流れているか）だけ、送りの位置を戻す——見積もりを通らないので、札の行は留まりの位置から動かない
final class ScrollHostHandle {
    #if os(iOS)
    weak var scrollView: UIScrollView?
    #endif

    /// 最後に戻したときの数（UI テストの見えない要素に出す・`PreviewSession.feedProbe`）
    private(set) var lastScrollBack = "none"

    init() {}

    /// いまの送りの数（UI テストの見えない要素に出す）。送りが無ければ空
    var probe: String {
        #if os(iOS)
        guard let scroll = scrollView else { return "scroll=nil" }
        return "offset=\(Self.n(scroll.contentOffset.y)) insetTop=\(Self.n(scroll.adjustedContentInset.top))"
            + " contentH=\(Self.n(scroll.contentSize.height)) boundsH=\(Self.n(scroll.bounds.height))"
        #else
        return "scroll=nil"
        #endif
    }

    static func n(_ value: CGFloat) -> String { String(format: "%.2f", Double(value)) }

    /// 留まった札の行の下へ、新しい札の頭を出す（`overflow` は測ったはみ出し）。
    ///
    /// 2026-10-31（#426 Mac の2回目・run の `:4126`・`:4128` で札の行が 116 → 118.33）: はみ出しをちょうど戻すと、
    /// 札の行は留まりの境目ちょうどに来る。境目では、測りの小さなずれ（1/3pt の丸め・新しい札で高さが変わったときの
    /// 並びの付け直し）や、戻す動きの行き過ぎ（減衰 0.85 のばねは約 0.6% 行き過ぎる——1100pt 戻すと 7pt）で、
    /// 札の行が留まりから外れて数 pt 下へ動いた。いまは:
    /// - 戻す量は **はみ出しから `ProfileTabScroll.pinnedSlack`（4）を引いた分**（`scrollBackDistance`）。札の行は
    ///   留まりの側に 4pt 残り、境目を越えない。新しい札の頭が札の行の下に 4pt 隠れるが、写真の頭の 4pt は目に入らない
    ///   （札の行が 2pt 跳ねる方が見える）。次に替えたときは残りが 4 なので戻さない（同じ位置のまま）
    /// - 戻す動きは**行き過ぎないばね**（減衰 1）。行き過ぎると、留まった札の行が一度外れて下がり、戻る
    /// 「視差効果を減らす」では動かさずに置く
    func scrollBack(_ overflow: CGFloat, reduceMotion: Bool) {
        #if os(iOS)
        let distance = ProfileTabScroll.scrollBackDistance(overflow: overflow)
        guard distance > 0.5, let scroll = scrollView else {
            lastScrollBack = "skip overflow=\(Self.n(overflow)) distance=\(Self.n(distance))"
            return
        }
        let target = ProfileTabScroll.offsetBack(current: scroll.contentOffset.y, distance: distance,
                                                 top: -scroll.adjustedContentInset.top)
        lastScrollBack = "overflow=\(Self.n(overflow)) distance=\(Self.n(distance))"
            + " from=\(Self.n(scroll.contentOffset.y)) to=\(Self.n(target))"
        let point = CGPoint(x: scroll.contentOffset.x, y: target)
        if reduceMotion {
            scroll.setContentOffset(point, animated: false)
        } else {
            UIView.animate(withDuration: ProfileTabScroll.scrollBackDuration, delay: 0,
                           usingSpringWithDamping: ProfileTabScroll.scrollBackDamping, initialSpringVelocity: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState],
                           animations: { scroll.contentOffset = point }, completion: nil)
        }
        #endif
    }
}

/// `ScrollHostHandle` に、いちばん近い祖先の `UIScrollView`（縦の送り）を渡す見えない部品。指は受けない
struct ScrollHostProbe: View {
    let handle: ScrollHostHandle

    var body: some View {
        #if os(iOS)
        ScrollHostProbeView(handle: handle)
        #else
        Color.clear
        #endif
    }
}

#if os(iOS)
/// `ScrollHostProbe` の UIKit の部分
struct ScrollHostProbeView: UIViewRepresentable {
    let handle: ScrollHostHandle

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.backgroundColor = .clear
        probe.isUserInteractionEnabled = false
        probe.handle = handle
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        probe.handle = handle
        probe.attach()
    }

    final class Probe: UIView {
        var handle: ScrollHostHandle?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attach()
        }

        func attach() {
            guard window != nil else { return }
            var view = superview
            while let current = view, !(current is UIScrollView) { view = current.superview }
            if let scroll = view as? UIScrollView { handle?.scrollView = scroll }
        }
    }
}
#endif

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

    /// 区分の札を上に留めるか（マイページ・#418）。札の行が見えている上端を越えた（`scrollsToRow` と同じ境）とき。
    /// ちょうど上端に居るとき（替えて頭へ送った直後）は元の行がそのまま見えている
    static func pinsRow(rowMinY: CGFloat, visibleTop: CGFloat) -> Bool {
        scrollsToRow(rowMinY: rowMinY, visibleTop: visibleTop)
    }

    /// 札の行が見えている上端からどれだけ上へ出ているか（出ていなければ 0）。払っている間、選んでいない札を
    /// これだけ下げると、札の行を上端へ送ったときの位置に頭が来る（`ProfileTabPager.lift`・2026-10-28）
    static func rowOverflow(rowMinY: CGFloat, visibleTop: CGFloat) -> CGFloat {
        scrollsToRow(rowMinY: rowMinY, visibleTop: visibleTop) ? visibleTop - rowMinY : 0
    }

    /// 節の見出しで留めた札の行（ホーム・`PinnedTabRowSpot`）のはみ出し。札の行と中身の間（`gap`）が、
    /// 留まっていないときの間（`restGap`）よりどれだけ詰まったか
    static func pinnedOverflow(gap: CGFloat, restGap: CGFloat) -> CGFloat {
        max(0, restGap - gap)
    }

    /// 送りの位置を `distance` だけ戻した先（いちばん上 `top` より上へは行かない）
    static func offsetBack(current: CGFloat, distance: CGFloat, top: CGFloat) -> CGFloat {
        max(top, current - max(0, distance))
    }

    /// 送りを戻す動きの秒。札の切り替えのばね（0.28 秒）と並んで終わる長さ
    static let scrollBackDuration: Double = 0.35
    /// 送りを戻す動きの減衰。**1（行き過ぎない）**——行き過ぎると留まった札の行が一度外れて下がる
    static let scrollBackDamping: CGFloat = 1

    /// 留まりの側に残す量（札の行が留まりの境目を越えないための遊び・`ScrollHostHandle.scrollBack`）
    static let pinnedSlack: CGFloat = 4

    /// はみ出し `overflow` のうち、送りを戻す量（遊びを残す。遊び以下なら戻さない）
    static func scrollBackDistance(overflow: CGFloat) -> CGFloat {
        max(0, overflow - pinnedSlack)
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
