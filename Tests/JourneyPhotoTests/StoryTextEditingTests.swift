import XCTest
@testable import JourneyPhoto

/// 文字を写真の上で直接打つときの決まり（`StoryTextEditing`）
final class StoryTextEditingTests: XCTestCase {

    /// 新しい文字は空・明朝・真ん中より少し上。**上限に達していれば置かない**
    func testNewTextStartsEmptyAndRespectsLimit() {
        let fresh = StoryTextEditing.newText(in: [])
        XCTAssertEqual(fresh?.text, "")
        XCTAssertEqual(fresh?.kind, .text)
        XCTAssertEqual(fresh?.face, .mincho)
        XCTAssertEqual(fresh?.y ?? 0, StoryTextEditing.newTextY, accuracy: 0.0001)

        let full = (0..<TextOverlay.maxCount).map { TextOverlay(text: "\($0)") }
        XCTAssertNil(StoryTextEditing.newText(in: full))
        XCTAssertNotNil(StoryTextEditing.newText(in: Array(full.dropLast())))
    }

    /// 打ち終えて空（空白・改行だけ）なら取り除く。**他の札と、中身のある札は残す**
    func testFinishDropsOnlyTheEmptyEditedOverlay() {
        let kept = TextOverlay(text: "残す")
        let blank = TextOverlay(text: "  \n ")
        let otherBlank = TextOverlay(text: " ")
        let list = [kept, blank, otherBlank]

        let result = StoryTextEditing.finish(list, id: blank.id)
        XCTAssertEqual(result.map(\.id), [kept.id, otherBlank.id])
        // 中身があれば何も消さない
        XCTAssertEqual(StoryTextEditing.finish(list, id: kept.id).map(\.id), list.map(\.id))
        // もう無い札の id（消した後に届いた）でも他を消さない
        XCTAssertEqual(StoryTextEditing.finish(list, id: UUID()).map(\.id), list.map(\.id))
    }

    /// 打ち直せるのは自由な文字・撮影地・タグ・曲。時刻・日付・スタンプは開かない
    func testWhichOverlaysOpenTyping() {
        let opens = TextOverlay.Kind.allCases.filter {
            StoryTextEditing.opensTyping(TextOverlay(text: "x", kind: $0))
        }
        XCTAssertEqual(Set(opens), [.text, .place, .song, .hashtag])
    }

    /// 見た目は白 → 黒 → 帯 → 縁取り → 白と回る。**色は `withStyle` の寄せ方に従う**
    func testNextStyleCyclesThroughAllStyles() {
        var overlay = TextOverlay(text: "文字")
        XCTAssertEqual(overlay.style, .light)
        var seen: [TextOverlay.Style] = []
        for _ in 0..<4 {
            overlay = StoryTextEditing.nextStyle(overlay)
            seen.append(overlay.style)
        }
        XCTAssertEqual(seen, [.dark, .banner, .outline, .light])
        // 白の文字で黒の見た目に入ると墨に寄る（白い縁に白は読めない）
        XCTAssertEqual(StoryTextEditing.nextStyle(TextOverlay(text: "a")).ink, .ink)
    }

    /// 帯で固定の札（撮影地など）とスタンプは見た目を変えない
    func testNextStyleLeavesForcedKindsAlone() {
        for kind in [TextOverlay.Kind.place, .song, .time, .date, .hashtag, .stamp] {
            let overlay = TextOverlay(text: "x", kind: kind)
            XCTAssertEqual(StoryTextEditing.nextStyle(overlay), overlay, "\(kind)")
        }
    }

    /// 揃えは中央 → 左 → 右 → 中央。**改行できない札は変えない**
    func testNextAlignCyclesOnlyForFreeText() {
        var overlay = TextOverlay(text: "文字")
        XCTAssertEqual(overlay.align, .center)
        overlay = StoryTextEditing.nextAlign(overlay)
        XCTAssertEqual(overlay.align, .leading)
        overlay = StoryTextEditing.nextAlign(overlay)
        XCTAssertEqual(overlay.align, .trailing)
        overlay = StoryTextEditing.nextAlign(overlay)
        XCTAssertEqual(overlay.align, .center)

        let place = TextOverlay(text: "京都", kind: .place)
        XCTAssertEqual(StoryTextEditing.nextAlign(place), place)
    }

    /// 打つ画面の文字の大きさは焼き込みと同じ式（写真の短い辺 × 割合）
    func testTypingFontSizeMatchesBurnInFormula() {
        let overlay = TextOverlay(text: "a", size: 0.1)
        XCTAssertEqual(StoryTextEditing.typingFontSize(overlay, photoShortSide: 400, fallbackWidth: 300),
                       TextOverlay.fontSize(0.1, in: CGSize(width: 400, height: 900)), accuracy: 0.0001)
        // 写真の大きさが分からないときは画面の幅で代える
        XCTAssertEqual(StoryTextEditing.typingFontSize(overlay, photoShortSide: 0, fallbackWidth: 300),
                       30, accuracy: 0.0001)
    }

    /// 写真の短い辺は、写真を枠いっぱいに**埋めた**ときの短い辺（置いたあとの `StoryCanvas` と同じ）
    func testPhotoShortSideUsesFilledPhoto() {
        let canvas = CGSize(width: 390, height: 700)
        // 3:4 の縦の写真: 高さで埋まる（700 / 4 × 3 = 525 が幅＝短い辺）
        XCTAssertEqual(StoryTextEditing.photoShortSide(canvas: canvas, image: CGSize(width: 3000, height: 4000)),
                       525, accuracy: 0.001)
        // 横長の写真も高さで埋まり、短い辺は枠の高さ
        XCTAssertEqual(StoryTextEditing.photoShortSide(canvas: canvas, image: CGSize(width: 4000, height: 3000)),
                       700, accuracy: 0.001)
        // 枠より縦に長い写真は幅で埋まり、短い辺は枠の幅
        XCTAssertEqual(StoryTextEditing.photoShortSide(canvas: canvas, image: CGSize(width: 1000, height: 3000)),
                       390, accuracy: 0.001)
        // 写真の大きさが分からなければ枠を写真とみなす
        XCTAssertEqual(StoryTextEditing.photoShortSide(canvas: canvas, image: nil), 390, accuracy: 0.001)
        // 枠が測れていなければ 0（呼ぶ側が画面の幅で代える）
        XCTAssertEqual(StoryTextEditing.photoShortSide(canvas: .zero, image: CGSize(width: 3, height: 4)), 0)
    }

    /// 打つ画面で縮めて見せる倍率。**収まるなら 1（大きくはしない）**、はみ出す向きの比で縮める
    func testFitScaleShrinksOnlyWhenOverflowing() {
        let area = CGSize(width: 300, height: 400)
        XCTAssertEqual(StoryTextEditing.fitScale(content: CGSize(width: 100, height: 50), available: area), 1)
        XCTAssertEqual(StoryTextEditing.fitScale(content: CGSize(width: 600, height: 50), available: area),
                       0.5, accuracy: 0.0001)
        XCTAssertEqual(StoryTextEditing.fitScale(content: CGSize(width: 100, height: 800), available: area),
                       0.5, accuracy: 0.0001)
        // 両方はみ出したら、きつい方
        XCTAssertEqual(StoryTextEditing.fitScale(content: CGSize(width: 600, height: 1000), available: area),
                       0.4, accuracy: 0.0001)
        // 下限より小さくはしない（字もキャレットも掴めなくなる）
        XCTAssertEqual(StoryTextEditing.fitScale(content: CGSize(width: 30000, height: 50), available: area),
                       StoryTextEditing.minFitScale, accuracy: 0.0001)
        // 測れない値では縮めない
        XCTAssertEqual(StoryTextEditing.fitScale(content: CGSize(width: 600, height: 50), available: .zero), 1)
        XCTAssertEqual(StoryTextEditing.fitScale(content: CGSize(width: Double.infinity, height: 1), available: area), 1)
    }

    /// はみ出しは**置き場所と回しを入れて**枠と比べる（大きさだけではない）
    func testOverflowUsesPlacementAndRotation() {
        let canvas = CGSize(width: 393, height: 700)
        // 真ん中なら 330 幅は収まる
        XCTAssertFalse(StoryTextEditing.overflow(content: CGSize(width: 330, height: 40),
                                                 center: CGPoint(x: 196, y: 300), rotation: 0, canvas: canvas).any)
        // 同じ大きさでも右に寄せれば右が切れる
        XCTAssertEqual(StoryTextEditing.overflow(content: CGSize(width: 330, height: 40),
                                                 center: CGPoint(x: 354, y: 300), rotation: 0, canvas: canvas),
                       StoryTextEditing.Overflow(width: true, height: false))
        // 縦に回した 500 幅は、横は収まる（縦 500 < 700）
        XCTAssertFalse(StoryTextEditing.overflow(content: CGSize(width: 500, height: 40),
                                                 center: CGPoint(x: 196, y: 350), rotation: .pi / 2, canvas: canvas).any)
        // 回さなければ 500 幅は横にはみ出す
        XCTAssertTrue(StoryTextEditing.overflow(content: CGSize(width: 500, height: 40),
                                                center: CGPoint(x: 196, y: 350), rotation: 0, canvas: canvas).width)
        // 上の端
        XCTAssertEqual(StoryTextEditing.overflow(content: CGSize(width: 100, height: 100),
                                                 center: CGPoint(x: 196, y: 20), rotation: 0, canvas: canvas),
                       StoryTextEditing.Overflow(width: false, height: true))
        XCTAssertFalse(StoryTextEditing.overflow(content: CGSize(width: 900, height: 900),
                                                 center: .zero, rotation: 0, canvas: .zero).any)
    }

    /// 打つ画面の並べ方: 縮みは**欄の大きさ×打つ画面の空き**。収まれば真ん中
    func testTypingLayoutScalesToAvailableSpace() {
        let overlay = TextOverlay(text: "港の朝焼け")
        let layout = StoryTextEditing.typingLayout(overlay: overlay, typing: CGSize(width: 330, height: 40),
                                                   available: CGSize(width: 281, height: 300),
                                                   area: CGSize(width: 393, height: 324))
        XCTAssertEqual(layout.scale, 281.0 / 330.0, accuracy: 0.0001)
        XCTAssertEqual(layout.horizontal, .center)
        XCTAssertFalse(layout.pinBottom)
    }

    /// 下限まで縮めても収まらない向きは、**キャレットのいる側**の端を見せる。
    /// 寄せるかどうかは空き（281）ではなく欄の置き場（393）で見る
    func testTypingLayoutPinsTheCaretSide() {
        let available = CGSize(width: 281, height: 300)
        let area = CGSize(width: 393, height: 324)
        // 1200 × 0.35 = 420 > 393 → 寄せる。改行の無い文字は行の末尾（右）
        let oneLine = StoryTextEditing.typingLayout(overlay: TextOverlay(text: "長い一行"),
                                                    typing: CGSize(width: 1200, height: 40),
                                                    available: available, area: area)
        XCTAssertEqual(oneLine.scale, StoryTextEditing.minFitScale, accuracy: 0.0001)
        XCTAssertEqual(oneLine.horizontal, .trailing)
        // 1100 × 0.35 = 385: 空き（281）は超えるが置き場（393）には収まる → 寄せない
        XCTAssertEqual(StoryTextEditing.typingLayout(overlay: TextOverlay(text: "a"),
                                                     typing: CGSize(width: 1100, height: 40),
                                                     available: available, area: area).horizontal, .center)
        // 改行した文字は揃えの側
        var left = TextOverlay(text: "一行目\n二")
        left.align = .leading
        XCTAssertEqual(StoryTextEditing.typingLayout(overlay: left, typing: CGSize(width: 1200, height: 80),
                                                     available: available, area: area).horizontal, .leading)
        var right = left
        right.align = .trailing
        XCTAssertEqual(StoryTextEditing.typingLayout(overlay: right, typing: CGSize(width: 1200, height: 80),
                                                     available: available, area: area).horizontal, .trailing)
        // 1行の札（撮影地）は改行が無いので右
        XCTAssertEqual(StoryTextEditing.typingLayout(overlay: TextOverlay(text: "京都", kind: .place),
                                                     typing: CGSize(width: 1200, height: 40),
                                                     available: available, area: area).horizontal, .trailing)
        // 縦: 1200 × 0.35 = 420 > 324 → 下（打っている最終行）を見せる
        let tall = StoryTextEditing.typingLayout(overlay: TextOverlay(text: "a\nb"),
                                                 typing: CGSize(width: 100, height: 1200),
                                                 available: available, area: area)
        XCTAssertTrue(tall.pinBottom)
        XCTAssertEqual(tall.horizontal, .center)
    }

    /// 打つ画面で測る文字は、欄に見えている行を全部数える（最後の改行・空白だけの文字も）
    func testTypingMeasureTextCountsVisibleLines() {
        XCTAssertEqual(StoryTextEditing.typingMeasureText(TextOverlay(text: "港\n"), placeholder: "見本"), "港\n ")
        XCTAssertEqual(StoryTextEditing.typingMeasureText(TextOverlay(text: "港"), placeholder: "見本"), "港")
        // 空なら見本、改行だけなら見本ではなくその行
        XCTAssertEqual(StoryTextEditing.typingMeasureText(TextOverlay(text: ""), placeholder: "見本"), "見本")
        XCTAssertEqual(StoryTextEditing.typingMeasureText(TextOverlay(text: "\n\n"), placeholder: "見本"), "\n\n ")
        // 札は印ごと測る
        XCTAssertEqual(StoryTextEditing.typingMeasureText(TextOverlay(text: "京都", kind: .place), placeholder: "見本"),
                       "📍 京都")
    }
}
