// 本物の SwiftUI で大きさを測るので iOS（Mac の模擬機）だけ。Linux の模型（Shims）には UIHostingController が無い
#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import JourneyPhoto

/// **DM の観光スポットの札の枠は、中身によらず同じ大きさ**（2026-11-12・DM の会話が固まる件・1.1.85）。
///
/// 会話の `LazyVStack` の中で札の高さが読み込み中（250）から読み終えた札の高さに替わると、払った直後から
/// 主スレッドが戻らなくなった（Mac run 1186・1190: 直す前は払い1回 60.8〜61.2 秒。札の高さを固定した版は 3.1 秒）。
/// 直しは、読み込み中・読めた・読めないを同じ枠（`DMSpotCardBox`）に入れること。ここでは枠の大きさが
/// 中身で替わらないことと、いちばん大きい札（写真 130・名前2行・ボタン・出典）が入る高さであることを確かめる。
@MainActor
final class DMSpotCardBoxTests: XCTestCase {

    private func size<V: View>(_ view: V) -> CGSize {
        let host = UIHostingController(rootView: view)
        return host.sizeThatFits(in: CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude))
    }

    /// 中身が低くても高くても、枠の大きさは同じ（読み込み中 → 読めた札で高さが替わらない）
    func testBoxSizeDoesNotDependOnContent() {
        let short = size(DMSpotCardBox { Color.red.frame(height: 10) })
        let tall = size(DMSpotCardBox { Color.red.frame(height: 900) })
        let loading = size(DMSpotCardBox {
            RoundedRectangle(cornerRadius: JPRadius.l).fill(WebTheme.surface3)
        })
        let oneLineCard = size(DMSpotCardBox {
            VStack(alignment: .leading, spacing: 0) {
                DMSpotCardPhotoPlaceholder()
                DMSpotCardText(name: "兼六園", region: "石川")
                Spacer(minLength: 0)
                DMSpotCardWishLabel(wanted: false)
            }
        })
        XCTAssertEqual(short, tall)
        XCTAssertEqual(short, loading)
        XCTAssertEqual(short, oneLineCard)
        XCTAssertEqual(short.width, DMSpotCard.width)
    }

    /// 枠は、いちばん大きい札（見本）の高さそのもの。写真 130 とボタン 44 より大きい
    func testBoxIsAsTallAsTheLargestCard() {
        let box = size(DMSpotCardBox { Color.clear })
        let skeleton = size(DMSpotCardSkeleton())
        XCTAssertEqual(box, skeleton)
        let twoLines = size(VStack(alignment: .leading, spacing: 0) {
            DMSpotCardPhotoPlaceholder()
            DMSpotCardText(name: "大雪山 旭岳 姿見の池と\nその周りの遊歩道", region: "北海道")
            DMSpotCardWishLabel(wanted: false)
            DMSpotCardCredit(text: "写真: 撮った人 / CC BY-SA 4.0")
        }.frame(width: DMSpotCard.width))
        XCTAssertEqual(box.height, twoLines.height, accuracy: 0.5,
                       "名前2行・出典ありの札が、枠にちょうど入ること")
        XCTAssertGreaterThan(box.height, DMSpotCard.photoHeight + 44)
    }

    /// **名前が1行・出典なしの札は、余りを写真に回して枠いっぱいに詰まる**（2026-11-13 デザインの点検:
    /// 余りをボタンの上の `Spacer` に置いていたので、名前とボタンの間が約1行分空いた）。
    /// 伸びる写真の札は、枠の大きさを渡すとその高さまで伸び（＝空きが写真の中に入る）、枠の大きさは替わらない
    func testOneLineCardStretchesThePhotoNotTheGap() {
        let box = size(DMSpotCardBox { Color.clear })
        let oneLine = VStack(alignment: .leading, spacing: 0) {
            DMSpotCardPhotoPlaceholder(grows: true)
            DMSpotCardText(name: "兼六園", region: "石川")
            DMSpotCardWishLabel(wanted: false)
        }.frame(width: DMSpotCard.width)
        let host = UIHostingController(rootView: oneLine)
        let fitted = host.sizeThatFits(in: box)
        XCTAssertEqual(fitted.height, box.height, accuracy: 0.5, "1行の札が枠の高さまで伸びない（どこかに空きが残る）")
        // 伸びない写真（枠の見本）は 130 のまま
        XCTAssertEqual(size(DMSpotCardPhotoPlaceholder()).height, DMSpotCard.photoHeight, accuracy: 0.5)
        XCTAssertEqual(size(DMSpotCardBox { oneLine }), box, "伸びる写真で枠の大きさが替わった")
        print("dmSpotCard.box height=\(box.height) oneLineFitted=\(fitted.height)")
    }
}
#endif
