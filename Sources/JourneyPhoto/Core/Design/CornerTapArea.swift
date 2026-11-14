import SwiftUI

/// **画面の角に置く「閉じる」「×」「戻る」の当たり**（2026-11-14 判断・人間工学の点検「追加の点検 5」）。
///
/// 押す正確さは画面の真ん中で約 7mm、角で約 12mm（約 72pt）と角ほど落ちる（Hoober、UXmatters 2017）。
/// 44pt（約 7.3mm）は真ん中向けの大きさで、とくに左上は右手の親指から最も遠い。そこで角の物は
/// **見た目はそのまま、当たりの形（`contentShape`）だけを角の側へ広げて 60pt 四方以上**にする。
///
/// - 広げるのは角の側（上と、左右の外側）だけ。内側（隣の物がある側）へは広げないので、隣の物と重ならない
/// - 板の「押せる範囲は形だけ広げる（contentShape）。負の余白で張り出さない」の作り方。並び（レイアウト）は変えない
/// - 当たりは形だけなので、読み上げの枠（UI テストの `frame`）は見た目の大きさのまま。広さは UI テストが
///   角の側の点を指で押して確かめる（`ScreenshotTests.testCornerTapArea…`）
/// - 上のバーの中（`SheetCloseButton` の既定・標準の戻る）は UIKit が当たりを決めるので、ここでは広げない
enum CornerTapArea {

    /// 角の物の当たりの一辺（pt）。見た目が小さくてもこの四方は押せる
    nonisolated static let side: CGFloat = 60

    /// どの角に置いた物か
    enum Corner: Sendable { case topLeading, topTrailing }

    /// 見た目の枠 `rect`（物の中の座標）を、角の側へ広げた当たりの枠。
    /// 角と反対の辺（内側・下）は動かさず、一辺が `side` に届くまで角の側へ伸ばす（もとが大きければそのまま）
    nonisolated static func hitRect(_ rect: CGRect, corner: Corner, side: CGFloat = side) -> CGRect {
        let width = max(rect.width, side)
        let height = max(rect.height, side)
        let y = rect.maxY - height
        switch corner {
        case .topLeading:
            return CGRect(x: rect.maxX - width, y: y, width: width, height: height)
        case .topTrailing:
            return CGRect(x: rect.minX, y: y, width: width, height: height)
        }
    }
}

/// `CornerTapArea.hitRect` の形（当たり判定だけに使う）
struct CornerHitShape: Shape {
    let corner: CornerTapArea.Corner

    func path(in rect: CGRect) -> Path {
        Path { $0.addRect(CornerTapArea.hitRect(rect, corner: corner)) }
    }
}

extension View {
    /// 画面の角に置いた物の当たりを、角の側へ 60pt 四方まで広げる（見た目は変えない・`CornerTapArea`）。
    /// ボタンの中身（`label`）の最後に付ける（前の `.contentShape(Circle())` などの代わり）
    func cornerTapArea(_ corner: CornerTapArea.Corner) -> some View {
        contentShape(CornerHitShape(corner: corner))
    }
}
