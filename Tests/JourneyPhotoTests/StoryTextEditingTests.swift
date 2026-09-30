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

    /// 押すと打つ画面を開くのはスタンプ以外（時刻・日付は書体・色・大きさを直す）
    func testWhichOverlaysOpenTyping() {
        let opens = TextOverlay.Kind.allCases.filter {
            StoryTextEditing.opensTyping(TextOverlay(text: "x", kind: $0))
        }
        XCTAssertEqual(Set(opens), [.text, .place, .song, .hashtag, .time, .date])
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

    /// **打つ画面で暗い文字に明るい下敷きを敷く**（owner 2026-09-30「文字入力してるけど出てこない」）。
    /// 白 → 黒の見た目へ1回押すだけで墨の字になり、暗くした写真の上で消えていた
    func testTypingLightPlateOnlyForDarkInk() {
        let dark = StoryTextEditing.nextStyle(TextOverlay(text: "文字"))
        XCTAssertEqual(dark.style, .dark)
        XCTAssertTrue(StoryTextEditing.typingNeedsLightPlate(dark), "黒の見た目の墨の字が見えない")
        // 白の字・帯・スタンプには敷かない
        XCTAssertFalse(StoryTextEditing.typingNeedsLightPlate(TextOverlay(text: "文字")))
        XCTAssertFalse(StoryTextEditing.typingNeedsLightPlate(dark.withStyle(.banner)))
        XCTAssertFalse(StoryTextEditing.typingNeedsLightPlate(TextOverlay(text: "⭐️", kind: .stamp)))
        // 縁取りの暗い色は、描く色（`drawnHex`）が読める明るさへ寄せられるので敷かない
        var outline = TextOverlay(text: "文字").withStyle(.outline)
        outline.customHex = 0x202020
        XCTAssertFalse(StoryTextEditing.typingNeedsLightPlate(outline))
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

    /// 打つ画面の並べ方: 縮みは**欄の大きさ×打つ画面の空き**。収まれば真ん中（ずらさない）
    func testTypingLayoutScalesToAvailableSpace() {
        let layout = StoryTextEditing.typingLayout(overlay: TextOverlay(text: "港の朝焼け"),
                                                   typing: CGSize(width: 330, height: 40), lastLineWidth: 330,
                                                   available: CGSize(width: 281, height: 300),
                                                   area: CGSize(width: 281, height: 324))
        XCTAssertEqual(layout.scale, 281.0 / 330.0, accuracy: 0.0001)
        XCTAssertEqual(layout.offsetX, 0)
        XCTAssertFalse(layout.pinBottom)
    }

    /// キャレット（最終行の末尾）の、枠の左端からの見た目の位置
    private func caretX(_ layout: StoryTextEditing.TypingLayout, overlay: TextOverlay, typing: CGSize,
                        lastLine: Double, frame: Double) -> Double {
        let width = Double(typing.width) * layout.scale
        let left = (frame - width) / 2 + layout.offsetX
        let multiline = overlay.text.contains("\n")
        switch multiline ? overlay.align : .trailing {
        case .leading: return left + lastLine * layout.scale
        case .center: return left + (width + lastLine * layout.scale) / 2
        case .trailing: return left + width
        }
    }

    /// 下限まで縮めても枠に収まらないとき、**どの揃え・どの行の長さでもキャレットが枠の中**
    func testTypingLayoutKeepsCaretInsideFrame() {
        let available = CGSize(width: 281, height: 300)
        let area = CGSize(width: 281, height: 324)
        let cases: [(String, TextOverlay.Align, Double, Double)] = [
            ("長い一行", .center, 1200, 1200),          // 改行なし
            ("一\n二", .leading, 2400, 1000),          // 前の行が長く最終行も長い（fb7acab の回帰）
            ("一\n二", .leading, 2400, 40),            // 前の行が長く最終行は短い
            ("一\n二", .leading, 1200, 1200),          // 最終行がいちばん長い
            ("一\n二", .center, 3000, 1000),
            ("一\n二", .center, 3000, 40),
            ("一\n二", .trailing, 2400, 100),
        ]
        for (text, align, total, last) in cases {
            var overlay = TextOverlay(text: text)
            overlay.align = align
            let typing = CGSize(width: total, height: 80)
            let layout = StoryTextEditing.typingLayout(overlay: overlay, typing: typing, lastLineWidth: last,
                                                       available: available, area: area)
            XCTAssertEqual(layout.scale, StoryTextEditing.minFitScale, accuracy: 0.0001)
            let x = caretX(layout, overlay: overlay, typing: typing, lastLine: last, frame: 281)
            XCTAssertGreaterThanOrEqual(x, -0.001, "\(align) \(total)/\(last)")
            XCTAssertLessThanOrEqual(x, 281.001, "\(align) \(total)/\(last)")
        }
    }

    /// 帯の余白もキャレットの位置に入る（左揃えは左の余白の後ろ、右揃えは右の余白の手前）
    func testTypingLayoutCountsBannerPadding() {
        let pad = 20.0
        var left = TextOverlay(text: "一\n二")
        left.align = .leading
        // 最終行 780: 余白込みで (20 + 780) × 0.35 = 280 ≤ 281 → 左端から見せればキャレットは枠の中
        let l = StoryTextEditing.typingLayout(overlay: left, typing: CGSize(width: 2400, height: 80),
                                              lastLineWidth: 780, padding: pad,
                                              available: CGSize(width: 281, height: 300),
                                              area: CGSize(width: 281, height: 324))
        let width = 2400 * l.scale
        let leftEdge = (281 - width) / 2 + l.offsetX
        XCTAssertEqual(leftEdge, 0, accuracy: 0.001)
        // 最終行 790: (20 + 790) × 0.35 = 283.5 > 281 → 余白の分まで数えて 2.5 だけ左へずらす
        let l2 = StoryTextEditing.typingLayout(overlay: left, typing: CGSize(width: 2400, height: 80),
                                               lastLineWidth: 790, padding: pad,
                                               available: CGSize(width: 281, height: 300),
                                               area: CGSize(width: 281, height: 324))
        XCTAssertEqual((281 - width) / 2 + l2.offsetX, -2.5, accuracy: 0.001)
        // 右揃え: 欄の右端を枠の右端に揃え（余白ごと見せる）、キャレットは余白×縮みだけ内側
        var right = left
        right.align = .trailing
        let r = StoryTextEditing.typingLayout(overlay: right, typing: CGSize(width: 2400, height: 80),
                                              lastLineWidth: 100, padding: pad,
                                              available: CGSize(width: 281, height: 300),
                                              area: CGSize(width: 281, height: 324))
        let rightEdge = (281 - width) / 2 + r.offsetX + width
        XCTAssertEqual(rightEdge, 281, accuracy: 0.001)
        XCTAssertEqual(rightEdge - pad * r.scale, 274, accuracy: 0.001)
    }

    /// 揃えの側を見せられるなら見せる（左揃えで最終行が短ければ左端から）
    func testTypingLayoutPrefersAlignedSide() {
        var left = TextOverlay(text: "一行目\n二")
        left.align = .leading
        let layout = StoryTextEditing.typingLayout(overlay: left, typing: CGSize(width: 2400, height: 80),
                                                   lastLineWidth: 40, available: CGSize(width: 281, height: 300),
                                                   area: CGSize(width: 281, height: 324))
        let width = 2400 * StoryTextEditing.minFitScale
        // 左端（0）に置いた位置 = 真ん中から (281 - width)/2 の逆
        XCTAssertEqual(layout.offsetX, -(281 - width) / 2, accuracy: 0.001)
        // 縦: 1200 × 0.35 = 420 > 324 → 下を見せる
        XCTAssertTrue(StoryTextEditing.typingLayout(overlay: TextOverlay(text: "a\nb"),
                                                    typing: CGSize(width: 100, height: 1200), lastLineWidth: 100,
                                                    available: CGSize(width: 281, height: 300),
                                                    area: CGSize(width: 281, height: 324)).pinBottom)
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

    /// 最終行（キャレットのいる行）。札は印ごと
    func testLastLine() {
        XCTAssertEqual(StoryTextEditing.lastLine(TextOverlay(text: "一行目\n二行目")), "二行目")
        XCTAssertEqual(StoryTextEditing.lastLine(TextOverlay(text: "港\n")), "")
        XCTAssertEqual(StoryTextEditing.lastLine(TextOverlay(text: "京都", kind: .place)), "📍 京都")
    }

    // MARK: - 指で直接動かす

    /// 2本指の始めの位置の下の札。**上に重なっている方（並びの後ろ）を先に**・札の外は nil
    func testOverlayAtPrefersTopmostAndHonorsSlop() {
        let bottom = StoryTextEditing.Placed(id: UUID(), center: CGPoint(x: 100, y: 100),
                                             size: CGSize(width: 100, height: 40), rotation: 0)
        let top = StoryTextEditing.Placed(id: UUID(), center: CGPoint(x: 120, y: 100),
                                          size: CGSize(width: 100, height: 40), rotation: 0)
        XCTAssertEqual(StoryTextEditing.overlay(at: CGPoint(x: 110, y: 100), in: [bottom, top], slop: 0), top.id)
        XCTAssertEqual(StoryTextEditing.overlay(at: CGPoint(x: 55, y: 100), in: [bottom, top], slop: 0), bottom.id)
        // 札の外（余白なし）は無し、余白の内側なら当たる
        XCTAssertNil(StoryTextEditing.overlay(at: CGPoint(x: 100, y: 140), in: [bottom], slop: 0))
        XCTAssertEqual(StoryTextEditing.overlay(at: CGPoint(x: 100, y: 140), in: [bottom], slop: 25), bottom.id)
        XCTAssertNil(StoryTextEditing.overlay(at: CGPoint(x: 100, y: 100), in: []))
    }

    /// **指の真下の札が、余白で当たった上の札より先**（あとから置いた札の余白が下の札の真上を覆っても）。
    /// 真下に無ければ、余白の内側で中心がいちばん近い札
    func testOverlayAtPrefersTheOneDirectlyUnderTheFinger() {
        let small = StoryTextEditing.Placed(id: UUID(), center: CGPoint(x: 200, y: 300),
                                            size: CGSize(width: 40, height: 20), rotation: 0)
        let later = StoryTextEditing.Placed(id: UUID(), center: CGPoint(x: 200, y: 335),
                                            size: CGSize(width: 200, height: 30), rotation: 0)
        // (200, 300) は small の真上、later の余白（y 296〜374）の内側
        XCTAssertEqual(StoryTextEditing.overlay(at: CGPoint(x: 200, y: 300), in: [small, later], slop: 24), small.id)
        // どちらの真下でもない (200, 316): small の中心から 16、later の中心から 19 → small
        XCTAssertEqual(StoryTextEditing.overlay(at: CGPoint(x: 200, y: 316), in: [small, later], slop: 24), small.id)
    }

    /// 回した札は、回した向きの矩形で当てる（45° は向きの符号を取り違えると外れる）
    func testOverlayAtFollowsRotationDirection() {
        // 横長の札を時計回りに 45°（右下がり）
        let tilted = StoryTextEditing.Placed(id: UUID(), center: CGPoint(x: 200, y: 200),
                                             size: CGSize(width: 200, height: 10), rotation: .pi / 4)
        XCTAssertEqual(StoryTextEditing.overlay(at: CGPoint(x: 260, y: 260), in: [tilted], slop: 0), tilted.id)
        XCTAssertNil(StoryTextEditing.overlay(at: CGPoint(x: 260, y: 140), in: [tilted], slop: 0))
    }

    /// 2本指の操作の相手: もう片方の相手 → はっきり運んでいた札 → 指の間の札 → 写真
    func testGestureTargetOrder() {
        let under = UUID(), carried = UUID(), other = UUID()
        XCTAssertEqual(StoryTextEditing.gestureTarget(other: .photo, under: { under }, carried: carried), .photo)
        XCTAssertEqual(StoryTextEditing.gestureTarget(other: .overlay(other), under: { under }, carried: carried),
                       .overlay(other))
        // はっきり運んでいた札が、指の間の札より先（小さな札を運んで回すと指の間が外れる）
        XCTAssertEqual(StoryTextEditing.gestureTarget(other: nil, under: { under }, carried: carried), .overlay(carried))
        XCTAssertEqual(StoryTextEditing.gestureTarget(other: nil, under: { under }, carried: nil), .overlay(under))
        XCTAssertEqual(StoryTextEditing.gestureTarget(other: nil, under: { nil }, carried: nil), .photo)
    }

    /// 「はっきり運んでいた」は 24pt 以上（指を置いただけ・少し触れただけの札に2本指を取られない）
    func testIsCarried() {
        XCTAssertFalse(StoryTextEditing.isCarried(CGSize(width: 10, height: 10)))
        XCTAssertTrue(StoryTextEditing.isCarried(CGSize(width: 0, height: 24)))
        XCTAssertTrue(StoryTextEditing.isCarried(CGSize(width: -20, height: -20)))
    }

    /// ゴミ箱は、指がいったん外に出た回だけ効く（ゴミ箱の上に置いた札を少しずらしても消えない）
    func testTrashArmsOnlyAfterLeaving() {
        let canvas = CGSize(width: 400, height: 800)
        let c = StoryTextEditing.trashCenter(canvas: canvas)
        XCTAssertFalse(StoryTextEditing.trashArmed(wasArmed: false, finger: c, canvas: canvas))
        XCTAssertTrue(StoryTextEditing.trashArmed(wasArmed: false, finger: CGPoint(x: 200, y: 300), canvas: canvas))
        XCTAssertTrue(StoryTextEditing.trashArmed(wasArmed: true, finger: c, canvas: canvas))
    }

    /// 回した札は、回した向きの矩形で当てる（縦に回した横長の札の上下の端でも掴める）
    func testOverlayAtFollowsRotation() {
        let upright = StoryTextEditing.Placed(id: UUID(), center: CGPoint(x: 200, y: 200),
                                              size: CGSize(width: 200, height: 20), rotation: .pi / 2)
        // 回す前なら外（上へ 80）、縦に回すと札の中
        XCTAssertEqual(StoryTextEditing.overlay(at: CGPoint(x: 200, y: 120), in: [upright], slop: 0), upright.id)
        // 回す前なら中（右へ 80）、縦に回すと札の外
        XCTAssertNil(StoryTextEditing.overlay(at: CGPoint(x: 280, y: 200), in: [upright], slop: 0))
    }

    /// 真ん中の縦・横の線に吸い付く（距離の内側だけ・向きごと）
    func testSnapToCenterLines() {
        let canvas = CGSize(width: 400, height: 800)
        let near = StoryTextEditing.snap(CGPoint(x: 205, y: 300), canvas: canvas)
        XCTAssertEqual(near.point, CGPoint(x: 200, y: 300))
        XCTAssertTrue(near.vertical)
        XCTAssertFalse(near.horizontal)
        let both = StoryTextEditing.snap(CGPoint(x: 193, y: 406), canvas: canvas)
        XCTAssertEqual(both.point, CGPoint(x: 200, y: 400))
        XCTAssertTrue(both.vertical && both.horizontal)
        let far = StoryTextEditing.snap(CGPoint(x: 220, y: 300), canvas: canvas)
        XCTAssertEqual(far.point, CGPoint(x: 220, y: 300))
        XCTAssertFalse(far.vertical || far.horizontal)
        // 枠が測れていなければ何もしない
        XCTAssertEqual(StoryTextEditing.snap(CGPoint(x: 1, y: 1), canvas: .zero).point, CGPoint(x: 1, y: 1))
    }

    /// ゴミ箱は下の真ん中。**指の位置**が半径の内側なら入る
    func testTrashZone() {
        let canvas = CGSize(width: 400, height: 800)
        let c = StoryTextEditing.trashCenter(canvas: canvas)
        XCTAssertEqual(c, CGPoint(x: 200, y: 800 - StoryTextEditing.trashBottomInset))
        XCTAssertTrue(StoryTextEditing.isOverTrash(c, canvas: canvas))
        XCTAssertTrue(StoryTextEditing.isOverTrash(CGPoint(x: c.x + 30, y: c.y - 30), canvas: canvas))
        XCTAssertFalse(StoryTextEditing.isOverTrash(CGPoint(x: c.x + 40, y: c.y + 40), canvas: canvas))
        XCTAssertFalse(StoryTextEditing.isOverTrash(CGPoint(x: 200, y: 300), canvas: canvas))
        XCTAssertFalse(StoryTextEditing.isOverTrash(c, canvas: .zero))
    }
}
