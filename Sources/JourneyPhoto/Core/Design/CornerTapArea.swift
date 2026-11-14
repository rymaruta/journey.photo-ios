import SwiftUI
import UIKit

/// **画面の角に置く「閉じる」「×」「戻る」の当たり**（2026-11-14 判断・人間工学の点検「追加の点検 5」）。
///
/// 押す正確さは画面の真ん中で約 7mm、角で約 12mm（約 72pt）と角ほど落ちる（Hoober、UXmatters 2017）。
/// 44pt（約 7.3mm）は真ん中向けの大きさで、とくに左上は右手の親指から最も遠い。そこで角の物は
/// **見た目はそのまま、当たりの形（`contentShape`）だけを角の側へ広げて 60pt 四方以上**にする。
///
/// - 広げるのは角の側（上と、左右の外側）だけ。内側（隣の物がある側）へは広げないので、隣の物と重ならない
/// - 板の「押せる範囲は形だけ広げる（contentShape）。負の余白で張り出さない」の作り方。並び（レイアウト）は変えない
/// - **読み上げの枠（UI テストの `frame`）は当たりの形の大きさになる**（Mac run 1278 で測った: 写真を大きく見るの ×
///   は見た目 44 のところ (-4, 52, 60, 60)）。見た目の枠と比べる試験は、見た目を別に出して比べる（現像の `develop.close.visual`）
/// - **上へは安全な範囲の上端（状態バーの下）までしか広げない**（2026-11-14）。run 1278 では、60pt 四方の左上の隅
///   （状態バーの帯の中・画面の端）を押しても閉じなかった。上の幅は窓の安全な範囲の上（`UIWindow.safeAreaInsets.top`）と
///   物の画面の上での位置から決める（`CornerTapAreaView`）。測るまでは上へ広げない
/// - 上のバーの中（`SheetCloseButton` の既定・標準の戻る）は UIKit が当たりを決めるので、ここでは広げない
enum CornerTapArea {

    /// 角の物の当たりの一辺（pt）。見た目が小さくてもこの四方は押せる（上は安全な範囲の中まで）
    nonisolated static let side: CGFloat = 60

    /// どの角に置いた物か
    enum Corner: Sendable { case topLeading, topTrailing }

    /// 見た目の枠 `rect`（物の中の座標）を、角の側へ広げた当たりの枠。
    /// 角と反対の辺（内側・下）は動かさず、一辺が `side` に届くまで角の側へ伸ばす（もとが大きければそのまま）。
    /// 上へ伸ばすのは `maxUp` まで（物の上端から安全な範囲の上端までの幅）
    nonisolated static func hitRect(_ rect: CGRect, corner: Corner, side: CGFloat = side,
                                    maxUp: CGFloat = .infinity) -> CGRect {
        let width = max(rect.width, side)
        let height = min(max(rect.height, side), rect.height + max(0, maxUp))
        let y = rect.maxY - height
        switch corner {
        case .topLeading:
            return CGRect(x: rect.maxX - width, y: y, width: width, height: height)
        case .topTrailing:
            return CGRect(x: rect.minX, y: y, width: width, height: height)
        }
    }

    /// 上へ広げてよい幅: 物の上端（画面の座標）から安全な範囲の上端までの幅（安全な範囲の外にいれば 0）
    nonisolated static func allowedUp(viewMinY: CGFloat, safeTop: CGFloat) -> CGFloat {
        max(0, viewMinY - safeTop)
    }

    /// 窓の安全な範囲の上の幅（状態バー・島の下端・画面の座標）。読めなければ nil
    @MainActor
    static func windowSafeTop() -> CGFloat? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first {
                return window.safeAreaInsets.top
            }
        }
        return nil
    }
}

/// `CornerTapArea.hitRect` の形（当たり判定だけに使う）
struct CornerHitShape: Shape {
    let corner: CornerTapArea.Corner
    var maxUp: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        Path { $0.addRect(CornerTapArea.hitRect(rect, corner: corner, maxUp: maxUp)) }
    }
}

/// 物の画面の上での位置を測り、上へ広げてよい幅を決めて当たりの形を付ける
struct CornerTapAreaView<Content: View>: View {
    let content: Content
    let corner: CornerTapArea.Corner

    /// 上へ広げてよい幅。測るまでは 0（状態バーの帯へ広げない）
    @State private var maxUp: CGFloat = 0
    @State private var safeTop: CGFloat = -1

    var body: some View {
        let shaped = content
            .contentShape(CornerHitShape(corner: corner, maxUp: maxUp))
            .background {
                GeometryReader { g in
                    let minY = g.frame(in: .global).minY
                    Color.clear
                        .onAppear { update(minY: minY) }
                        .onChange(of: minY) { _, value in update(minY: value) }
                }
            }
        if PreviewSession.layoutProbe {
            // UI テストの事実取りだけ: 当たりを決めた数を値に出す（画面の木からは取れない）
            shaped.accessibilityValue(String(format: "safeTop=%.1f maxUp=%.1f", safeTop, maxUp.isFinite ? maxUp : 999))
        } else {
            shaped
        }
    }

    private func update(minY: CGFloat) {
        guard let top = CornerTapArea.windowSafeTop() else { return }
        safeTop = top
        maxUp = Self.noClamp ? .infinity : CornerTapArea.allowedUp(viewMinY: minY, safeTop: top)
    }

    /// UI テストの事実取りだけ: 上へ止めずに 60pt 四方まで広げる（状態バーの帯で触れが取れるかを測る・
    /// `-JPPreviewCornerNoClamp YES`・`ScreenshotTests.testCornerTapAreaStatusBand`）。Release では必ず false
    private static var noClamp: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "JPPreviewCornerNoClamp")
        #else
        return false
        #endif
    }
}

extension View {
    /// 画面の角に置いた物の当たりを、角の側へ 60pt 四方まで広げる（見た目は変えない・上は安全な範囲の中まで・`CornerTapArea`）。
    /// ボタンの中身（`label`）の最後に付ける（前の `.contentShape(Circle())` などの代わり）
    func cornerTapArea(_ corner: CornerTapArea.Corner) -> some View {
        CornerTapAreaView(content: self, corner: corner)
    }
}
