import SwiftUI

/// 探すの欄を画面の下に置く入れ物（2026-11-25 判断・人間工学の案 4）。
///
/// iOS 26 の Apple のアプリ（ミュージック・写真など）と同じく、探す欄を親指の届く下（下のタブのすぐ上）に置く。
/// 打ち始めると、欄はキーボードのすぐ上に乗る（`safeAreaInset(edge: .bottom)` の中に置くので、キーボードの分だけ上がる）。
///
/// - 曲が鳴っていて、下の再生器（`MiniPlayerBar`）が欄と重なる所にあるときは、欄を再生器の上に積む
///   （`MiniPlayerPlacement.clearance`）。再生器を指で上へ動かしたら、欄は元の所へ戻る
/// - 知らせ（`ToastOverlay`）は欄の上に出す（`ToastCenter.keepClearAbove`・地図の札と同じ仕組み）
/// - **探すの画面の `body` を描き直さない**: 再生器の置き場所と欄の位置を見張るのは、この小さな入れ物だけ
///   （探すの `body` は重い・札 #590 / #594）
struct SearchBottomField<Content: View>: View {
    let content: Content

    @ObservedObject private var placement = MiniPlayerPlacementStore.shared
    @EnvironmentObject private var toasts: ToastCenter
    /// 持ち上げる前の欄の所（画面全体の座標）
    @State private var resting: CGRect = .zero
    /// この入れ物が知らせの「覆わない所」に置いた上端（ほかの画面の値を消さないため）
    @State private var keptTop: CGFloat?
    @State private var visible = false

    var body: some View {
        let lift = MiniPlayerPlacement.clearance(field: resting, player: placement.restingFrame)
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                // 測った所は持ち上げた後なので、持ち上げた分を戻して控える
                let unlifted = frame.offsetBy(dx: 0, dy: lift)
                if resting != unlifted { resting = unlifted }
                keepToastsAbove(frame.minY)
            }
            .padding(.top, JPSpace.xs)
            .padding(.bottom, JPSpace.xs + lift)
            .background(alignment: .bottom) {
                // 結果の上に重なる帯の地。上の端は透けて、結果が下へ流れていくのが見える
                LinearGradient(stops: [.init(color: WebTheme.background.opacity(0), location: 0),
                                       .init(color: WebTheme.background.opacity(0.94), location: 0.35)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
            }
            .animation(.easeOut(duration: 0.2), value: lift)
            .onAppear {
                visible = true
                if resting != .zero { keepToastsAbove(resting.minY - lift) }
            }
            .onDisappear {
                visible = false
                // 自分が置いた値のときだけ外す（地図の札など、ほかの画面が置いた値は残す）
                if let keptTop, toasts.keepClearAbove == keptTop { toasts.keepClearAbove = nil }
                keptTop = nil
            }
            // ほかの画面（地図）が離れるときに外した値を、出ている間は置き直す
            .onChange(of: toasts.keepClearAbove) { _, now in
                if visible, now == nil, let keptTop { toasts.keepClearAbove = keptTop }
            }
    }

    private func keepToastsAbove(_ top: CGFloat) {
        guard visible, top.isFinite, top > 0 else { return }
        keptTop = top
        if toasts.keepClearAbove != top { toasts.keepClearAbove = top }
    }
}
