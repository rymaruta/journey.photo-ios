import Foundation
// `ObservableObject` と `@Published` は Combine のもの（`MusicPreviewPlayer` と同じく明示する）
import Combine

/// 全体の再生器（`MiniPlayerBar`）の置き場所。**指で動かせる**
/// （2026-10-28 owner「再生中の音楽自由に動かせるといいね」）。
///
/// 2026-10-28 判断:
/// - 動かしたら、離した所から**左右どちらか近い端へ寄せて止める**。速く払ったら払った向きの端
///   （勢いを足した行き着く先 `predictedEndTranslation` で決める）
/// - 縦は**離した所**。ただし上の見出し・下のタブバーに重ならない範囲に収める
/// - **下へ素早く払って、行き着く先が範囲の下より再生器1つ分以上外なら、止めて消す**（停止ボタンと同じ結果）
/// - 置き場所は端（左・右）と縦の割合（0 = いちばん下・1 = いちばん上）で覚える。割合にするのは、
///   画面を回したり大きさが変わったりしても範囲の中に残るように
///
/// 計算は画面を持たない（単体テスト用）。座標は再生器を置く枠（安全領域の内側）の中のもの
enum MiniPlayerPlacement {

    enum Side: Equatable { case leading, trailing }

    /// 覚える置き場所
    struct Spot: Equatable {
        var side: Side
        /// 0 = 範囲のいちばん下・1 = いちばん上
        var height: CGFloat

        /// 初めは右下（前の全幅のバーと同じ、タブバーのすぐ上）
        static let initial = Spot(side: .trailing, height: 0)
    }

    /// 離したときの結果
    enum Outcome: Equatable {
        case place(Spot)
        /// 下へ払って外へ出した。止めて消す
        case dismiss
    }

    /// 画面の左右の端からの間
    static let margin: CGFloat = 12
    /// 再生器の幅の上限。**全幅だと左右へ寄せられない**ので細くする（曲名がおよそ9字入る幅）
    static let maxWidth: CGFloat = 280
    /// 上の見出し（ロゴ・探す・お知らせ・メニューの帯）と、その下の1段（探すの入力欄など）の高さ。ここには重ねない。
    /// 2026-10-28 判断: 見出しだけ（52）では、いちばん上に置くと探すの入力欄にかぶる（確かめ役の指摘）。
    /// 見出し 52 ＋ 入力欄の段 60 にした。画面写真 `10m-探す（再生器・いちばん上）` で確かめる
    static let topReserved: CGFloat = 112
    /// 下のタブバーの高さ（前の `padding(.bottom, 56)` と同じ）。ここには重ねない
    static let bottomReserved: CGFloat = 56
    /// 「速く払った」とみなす、勢いで先へ進む量（pt）。これより小さい動きでは消さない。
    /// 2026-10-28 判断: 60 では下へ引き下ろしただけで止まった（確かめ役の指摘）。はっきり払ったときだけにする
    static let flingDistance: CGFloat = 160
    /// 読み上げの「上へ移す／下へ移す」の1回の量（範囲の割合）
    static let accessibilityStep: CGFloat = 1.0 / 3.0

    /// 再生器の幅
    static func barWidth(container: CGSize) -> CGFloat {
        max(0, min(maxWidth, container.width - margin * 2))
    }

    /// 中心の y が動ける範囲（上の見出しの下〜タブバーの上）。狭すぎる枠ではいちばん下に揃える
    static func verticalRange(container: CGSize, barHeight: CGFloat) -> ClosedRange<CGFloat> {
        let bottom = container.height - bottomReserved - barHeight / 2
        let top = topReserved + barHeight / 2
        return min(top, bottom)...bottom
    }

    /// 端に寄せたときの中心の x
    static func centerX(side: Side, container: CGSize, barWidth: CGFloat) -> CGFloat {
        switch side {
        case .leading: return margin + barWidth / 2
        case .trailing: return container.width - margin - barWidth / 2
        }
    }

    /// 置き場所の中心
    static func center(of spot: Spot, container: CGSize, barSize: CGSize) -> CGPoint {
        let range = verticalRange(container: container, barHeight: barSize.height)
        let height = min(1, max(0, spot.height))
        let y = range.upperBound - height * (range.upperBound - range.lowerBound)
        return CGPoint(x: centerX(side: spot.side, container: container, barWidth: barSize.width), y: y)
    }

    /// 中心の y を範囲に収めて、割合にする
    static func height(forCenterY y: CGFloat, container: CGSize, barHeight: CGFloat) -> CGFloat {
        let range = verticalRange(container: container, barHeight: barHeight)
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        let clamped = min(range.upperBound, max(range.lowerBound, y))
        return (range.upperBound - clamped) / span
    }

    /// 指を離したときの行き先。`translation` は動かした量、`predicted` は勢いを足した行き着く先までの量
    static func settle(from spot: Spot, translation: CGSize, predicted: CGSize,
                       container: CGSize, barSize: CGSize) -> Outcome {
        let start = center(of: spot, container: container, barSize: barSize)
        let range = verticalRange(container: container, barHeight: barSize.height)
        // 下へ払って外へ出した: 指を離した所そのものが範囲の下端より再生器半分以上タブバー側に出ていて、
        // 勢いで下へ進む量が十分・縦の動きが主・行き着く先が範囲の下より再生器1つ分外。
        // **範囲の中で離したら、勢いがあっても止めない**（引き下ろしただけで止まらないように）
        let releasedOut = start.y + translation.height > range.upperBound + barSize.height / 2
        let flungDown = predicted.height - translation.height >= flingDistance
        let mostlyDown = predicted.height > abs(predicted.width)
        let projectedY = start.y + predicted.height
        if releasedOut && flungDown && mostlyDown && projectedY > range.upperBound + barSize.height {
            return .dismiss
        }
        // 左右は勢いを足した行き着く先で（速く払った向きの端へ）
        let projectedX = start.x + predicted.width
        let side: Side = projectedX < container.width / 2 ? .leading : .trailing
        // 縦は離した所
        let releasedY = start.y + translation.height
        return .place(Spot(side: side,
                           height: height(forCenterY: releasedY, container: container, barHeight: barSize.height)))
    }

    /// 読み上げの「上へ移す」「下へ移す」
    static func moved(_ spot: Spot, up: Bool) -> Spot {
        var next = spot
        next.height = min(1, max(0, spot.height + (up ? accessibilityStep : -accessibilityStep)))
        return next
    }

    /// 読み上げの「左の端へ」「右の端へ」。高さは変えない
    static func moved(_ spot: Spot, to side: Side) -> Spot {
        var next = spot
        next.side = side
        return next
    }
}

/// 置き場所を**再生の間（アプリを閉じるまで）**覚える。保存はしない（2026-10-28 判断: 次に開いたら右下から）。
/// `MusicPreviewPlayer` と同じく `@MainActor` を付けない（View のプロパティ初期化子から読むため）
final class MiniPlayerPlacementStore: ObservableObject {
    static let shared = MiniPlayerPlacementStore()
    @Published var spot = MiniPlayerPlacement.Spot.initial
    private init() {}
}
