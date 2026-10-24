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
/// - 中身の高さは**少なくとも画面1枚分**（`minHeight`）。短い札へ替えても位置が詰められず、札の行が跳ばない
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
