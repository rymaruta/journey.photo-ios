import XCTest
@testable import JourneyPhoto

/// 人間工学の見直しの案（2026-11-25・案 1〜6）。決まり（画面を持たない計算）と、画面のつなぎ込み（ソースの文字）。
/// 指の動き（引く・押さえてずらす）の本物は UI テスト（`ScreenshotTests`）と実機で見る
final class ErgonomicsReview1125Tests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        // 注記（`//`・`///`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    // MARK: - 案 1: AI に頼むを下へ引いて閉じる

    /// 上に居て、下向きで、縦が横より大きいときだけ。字を打っている間は始めない（まずキーボードを下ろす）
    func testAskScreenPullStartsOnlyAtTopDownwardAndNotWhileTyping() {
        XCTAssertTrue(PhotoDetailPull.askScreenStarts(dx: 2, dy: 12, atTop: true, typing: false))
        XCTAssertFalse(PhotoDetailPull.askScreenStarts(dx: 2, dy: 12, atTop: false, typing: false), "読んでいる途中の送りで閉じる")
        XCTAssertFalse(PhotoDetailPull.askScreenStarts(dx: 2, dy: -12, atTop: true, typing: false), "上へ払って閉じる")
        XCTAssertFalse(PhotoDetailPull.askScreenStarts(dx: 20, dy: 8, atTop: true, typing: false), "観光スポットの札の横の送りで閉じる")
        XCTAssertFalse(PhotoDetailPull.askScreenStarts(dx: 0, dy: 30, atTop: true, typing: true), "字を打っている間に閉じる")
        // 閉じる所は写真の画面と同じ 120pt（勢いを足した行き先）
        XCTAssertTrue(PhotoDetailPull.closes(dy: 121, velocityY: 0))
        XCTAssertFalse(PhotoDetailPull.closes(dy: 80, velocityY: 0))
    }

    /// 画面まるごとが指に付いて下がり（縮めない）、離すと閉じる。× と VoiceOver の「戻る」は残す
    func testAskScreenIsWiredToPullClose() throws {
        let ask = try source("Features/Search/AskScreen.swift")
        XCTAssertTrue(ask.contains("DetailPullFollow(drag: pull, part: .screen, reduceMotion: reduceMotion, content: screen)"),
                      "画面が指に付いて下がらない")
        XCTAssertTrue(ask.contains("PhotoDetailPull.askScreenStarts(dx: dx, dy: dy, atTop: atTop, typing: focused)"))
        XCTAssertTrue(ask.contains("if pull.release(dy: dy, velocityY: velocityY, reduceMotion: reduceMotion) { close() }"),
                      "離しても閉じない（× と同じ閉じ方をしない）")
        XCTAssertTrue(ask.contains(".background { pullCatcher }"), "引く指を受けていない")
        XCTAssertTrue(ask.contains("SheetCloseButton(action: close)"), "× を外した（押して済む道が無い）")
        XCTAssertTrue(ask.contains(".accessibilityAction(.escape) { close() }"), "VoiceOver の「戻る」で閉じない")
        let follow = try source("Features/PhotoDetail/DetailPullCatcher.swift")
        XCTAssertTrue(follow.contains("case .screen:\n            content.offset(y: PhotoDetailPull.offset(dx: dx, dy: dy).y)"),
                      "画面まるごとが下へだけ動く形でない")
    }

    // MARK: - 案 2: 旅行プランの失敗を「もう一度」1回に

    /// 送り直せる失敗は「もう一度」、項目が変わった失敗は「閉じる」。電波が無いときは押す時を言う
    func testTripPlanFailureRetryAndWording() {
        for kind in [TripPlanFailure.Kind.save, .share, .delete] {
            let failure = TripPlanFailure(kind: kind, detail: "断られました")
            XCTAssertTrue(failure.canRetry, "\(kind) を送り直せない")
            XCTAssertEqual(failure.actionTitle, L("もう一度", "Retry"))
            XCTAssertEqual(failure.message(offline: true), TripPlanFailure.offlineMessage)
            XCTAssertEqual(failure.message(offline: false), "断られました")
        }
        for kind in [TripPlanFailure.Kind.note, .move] {
            let failure = TripPlanFailure(kind: kind, detail: "項目が変わりました")
            XCTAssertFalse(failure.canRetry, "\(kind) は送り直しても同じなのに「もう一度」を出す")
            XCTAssertEqual(failure.actionTitle, L("閉じる", "Close"))
            XCTAssertEqual(failure.message(offline: true), "項目が変わりました", "送り直さない失敗に電波の話をしている")
        }
        XCTAssertEqual(TripPlanFailure(kind: .move, detail: "").title, L("動かせませんでした", "Couldn't move"))
        XCTAssertEqual(TripPlanFailure(kind: .save, detail: "").title, L("保存できませんでした", "Couldn't save"))
        XCTAssertEqual(Set([TripPlanFailure.Kind.save, .note, .move, .share, .delete]
            .map { TripPlanFailure(kind: $0, detail: "").title }).count, 5, "見出しが失敗ごとに分かれていない")
        // 払って閉じる: 横か下へ 60pt
        XCTAssertTrue(TripPlanFailure.swipeCloses(dx: -70, dy: 0))
        XCTAssertTrue(TripPlanFailure.swipeCloses(dx: 0, dy: 61))
        XCTAssertFalse(TripPlanFailure.swipeCloses(dx: 20, dy: -80), "上へ払って閉じた")
    }

    /// 🔴 5つの窓（OK だけの `.alert`）を外し、下の帯（板の状態の帯 `JPStateBand`）に出す。ひとことを書く欄（入力）は窓のまま
    func testTripPlanFailuresUseBottomBandNotAlerts() throws {
        let plan = try source("Features/Trips/TripPlanDetailView.swift")
        for title in ["保存できませんでした", "ひとことを入れられませんでした", "動かせませんでした", "共有できませんでした", "削除できませんでした"] {
            XCTAssertFalse(plan.contains(".alert(L(\"\(title)\""), "「\(title)」がまだ真ん中の窓")
        }
        XCTAssertTrue(plan.contains(".alert(L(\"ひとこと\", \"Note\"),"), "ひとことを書く欄（入力）まで外した")
        XCTAssertTrue(plan.contains(".safeAreaInset(edge: .bottom) { failureBand }"), "失敗の帯が下に無い")
        XCTAssertTrue(plan.contains("JPStateBand(kind: isOffline && failure.canRetry ? .offline : .partial,"), "板の状態の帯を使っていない")
        // どの失敗も帯へ。送り直せる失敗は「もう一度」に同じ操作を結ぶ
        XCTAssertTrue(plan.contains("fail(.save, Self.problemText(problem, shared: plan?.share != nil), retry: { saveAndLeave() })"))
        XCTAssertTrue(plan.contains("retry: { Task { await share(with: peer) } })"))
        XCTAssertTrue(plan.contains("retry: { removePlan() })"))
        XCTAssertTrue(plan.contains("fail(.move,"))
        XCTAssertTrue(plan.contains("fail(.note,"))
        XCTAssertFalse(plan.contains("canPresentAlert"), "窓を出してよいかの見張りが残っている（帯は画面を止めない）")
    }

    // MARK: - 案 3: 本棚の背は、押して・ずらして・離して開く

    /// 段の左端からの位置で背を引く（押せる幅＝背の幅＋間）。段の外・上下に外れたら nil
    func testSpineSlotIndexFollowsHitWidths() {
        let slots = [33.0, 47, 40]
        XCTAssertEqual(TripBookshelf.slotIndex(at: 0, slots: slots), 0)
        XCTAssertEqual(TripBookshelf.slotIndex(at: 32.9, slots: slots), 0)
        XCTAssertEqual(TripBookshelf.slotIndex(at: 33, slots: slots), 1)
        XCTAssertEqual(TripBookshelf.slotIndex(at: 119.9, slots: slots), 2)
        XCTAssertNil(TripBookshelf.slotIndex(at: 120, slots: slots), "段の右の空きで背が浮く")
        XCTAssertNil(TripBookshelf.slotIndex(at: -1, slots: slots))
        XCTAssertEqual(TripBookshelf.slideTarget(x: 40, y: -29, height: 220, slots: slots), 1, "少し上へずれただけで浮きが消える")
        XCTAssertNil(TripBookshelf.slideTarget(x: 40, y: -31, height: 220, slots: slots), "段の上へ外しても浮きが残る（やめられない）")
        XCTAssertNil(TripBookshelf.slideTarget(x: 40, y: 251, height: 220, slots: slots))
        // 押さえたとみなすまでは短く、指の動き出し（10pt）より動いたら送り・払いに渡す
        XCTAssertLessThanOrEqual(TripBookshelf.holdSeconds, 0.2)
        XCTAssertEqual(TripBookshelf.holdSlop, 10)
    }

    /// 振動は「ずらして別の背に替わった時」だけ。押さえた時・外した時・同じ背に戻った時は鳴らさない。離すと浮いている背が開く
    func testSpineSlideBuzzesOnlyWhenSwitchingAndOpensLifted() {
        var slide = TripBookshelf.Slide(start: 0)
        XCTAssertEqual(slide.opens, 0, "押さえて離した背が開かない")
        XCTAssertFalse(slide.move(to: 0), "同じ背のままで鳴った")
        XCTAssertTrue(slide.move(to: 1), "隣にずらしても鳴らない")
        XCTAssertEqual(slide.opens, 1, "ずらした先の背が開かない（押した背が開く）")
        XCTAssertFalse(slide.move(to: nil), "外したときに鳴った")
        XCTAssertNil(slide.opens, "外して離したのに開く（やめられない）")
        XCTAssertFalse(slide.move(to: 1), "外して同じ背に戻っただけで鳴った")
        XCTAssertTrue(slide.move(to: 2))
        var gap = TripBookshelf.Slide(start: nil)
        XCTAssertFalse(gap.move(to: 0), "空きから背に入っただけで鳴った")
    }

    /// 🔴 背はボタンにしない（押した背に指が縛られ、ずらせない）。段の指の部品が開く。押した時・棚に戻った時の振動を外し、
    /// 開き切った時の振動は残す。前の直し（BookMemo・SpineLook・背は stage を見張らない）はそのまま
    func testShelfUsesSlideCatcherAndTrimsHaptics() throws {
        let shelf = try source("Features/Trips/TripShelf.swift")
        XCTAssertFalse(shelf.contains("SpineButtonStyle"), "押した瞬間に鳴るボタンの形が残っている")
        XCTAssertFalse(shelf.contains(".sensoryFeedback(.impact(weight: .light), trigger: returned)"), "棚に戻った時に鳴る")
        XCTAssertTrue(shelf.contains("SpineSlideCatcher("), "段の指の部品が無い")
        XCTAssertTrue(shelf.contains("slots: row.map { TripBookshelf.hitWidth(photos: $0.photoCount) },"), "押せる幅が並びと合わない")
        XCTAssertTrue(shelf.contains("onOpen: { index in"))
        XCTAssertTrue(shelf.contains(".background { SpineSlideFeedback(lifter: lifter) }"), "ずらして替わった時の振動が無い")
        XCTAssertTrue(shelf.contains(".accessibilityAddTraits(.isButton)"), "読み上げでボタンとして読まれない")
        XCTAssertTrue(shelf.contains(".accessibilityAction { openBook(book) }"), "読み上げで開けない")
        XCTAssertTrue(shelf.contains(".contextMenu {"), "長押しで表紙を見る道を外した")
        XCTAssertTrue(shelf.contains("@StateObject private var lifter = SpineLifter()"), "浮きを棚の @State に置いた（ずらすたびに棚ぜんぶを作り直す）")
        let stage = try source("Features/Trips/TripBookStage.swift")
        XCTAssertTrue(stage.contains(".sensoryFeedback(.impact(flexibility: .soft), trigger: bounced)"), "開き切った時の振動を外した")
        let catcher = try source("Features/Trips/SpineSlideCatcher.swift")
        XCTAssertTrue(catcher.contains("tap.require(toFail: hold)"), "押さえて離した指を、もう1回の押しに数える")
        XCTAssertTrue(catcher.contains("gestureRecognizer === hold && other is UIPanGestureRecognizer && other.view === host"),
                      "押さえている間に縦の送り・札の横の払いが動く")
        XCTAssertTrue(catcher.contains(".sensoryFeedback(.selection, trigger: lifter.switches)"))
    }

    // MARK: - 案 4: 探すの欄を下に

    /// 再生器が欄と重なるときだけ、欄を再生器の上へ積む。動かして離れたら 0
    func testSearchFieldStacksAboveMiniPlayerOnlyWhenOverlapping() {
        let field = CGRect(x: 16, y: 700, width: 358, height: 52)
        XCTAssertEqual(MiniPlayerPlacement.clearance(field: field, player: nil), 0)
        // いちばん下の右（初めの所）: 欄の下端 752、再生器の上端 708 → 752 − 708 + 8 = 52
        let bottom = CGRect(x: 98, y: 708, width: 280, height: 60)
        XCTAssertEqual(MiniPlayerPlacement.clearance(field: field, player: bottom), 52)
        // 上へ動かした: 重ならない
        XCTAssertEqual(MiniPlayerPlacement.clearance(field: field, player: CGRect(x: 98, y: 300, width: 280, height: 60)), 0)
        // 横に外れている（細い画面の外）: 重ならない
        XCTAssertEqual(MiniPlayerPlacement.clearance(field: field, player: CGRect(x: 400, y: 708, width: 280, height: 60)), 0)
        XCTAssertEqual(MiniPlayerPlacement.clearance(field: .zero, player: bottom), 0, "測る前に持ち上げた")
    }

    /// 🔴 欄は上の見出しから外し、下の差し込み（キーボードの上に乗る）へ。探すの body は再生器を見張らない
    func testSearchFieldMovedToBottom() throws {
        let search = try source("Features/Search/SearchView.swift")
        XCTAssertTrue(search.contains(".safeAreaInset(edge: .bottom, spacing: 0) {\n            SearchBottomField(content: searchField)"),
                      "探すの欄が下に無い")
        XCTAssertEqual(search.components(separatedBy: "searchField\n").count - 1, 0, "上の見出しにも欄が残っている")
        XCTAssertFalse(search.contains("MiniPlayerPlacementStore"), "探すの重い body が再生器の置き場所を見張っている")
        let bottom = try source("Features/Search/SearchBottomField.swift")
        XCTAssertTrue(bottom.contains("MiniPlayerPlacement.clearance(field: resting, player: placement.restingFrame)"))
        XCTAssertTrue(bottom.contains("toasts.keepClearAbove"), "知らせが欄に重なる")
        let bar = try source("Features/Common/MiniPlayerBar.swift")
        XCTAssertTrue(bar.contains(".onDisappear { placement.restingFrame = nil }"), "曲が止まっても欄が持ち上がったまま")
    }

    // MARK: - 案 5: AI の答えの字を大きな字の設定に合わせる

    /// 🔴 答えの中の字は数で決めず、設定に合わせて大きくなる（`jpSystemFont`・板の「標準に無い字は追従させる」）。
    /// 写真の無い所の印（決まった大きさの枠）と、丸の中の番号（24pt の丸）だけは今のまま
    func testAskAnswerTextFollowsDynamicType() throws {
        for file in ["Features/Search/AskAnswerParts.swift", "Features/Search/AskSpotCarousel.swift"] {
            let text = try source(file)
            let fixed = text.components(separatedBy: "\n").filter { $0.contains(".font(.system(size:") }
            let allowed = fixed.filter { $0.contains(".font(.system(size: 22))") || $0.contains("size: 12, weight: .bold).monospacedDigit()") }
            XCTAssertEqual(fixed.count, allowed.count, "\(file) に設定に合わせない字が残っている: \(fixed)")
        }
        let parts = try source("Features/Search/AskAnswerParts.swift")
        XCTAssertTrue(parts.contains("Text(act.label)\n                        .jpSystemFont(15, weight: .semibold, relativeTo: .subheadline)"),
                      "答えの主ボタンの字が大きくならない")
        let carousel = try source("Features/Search/AskSpotCarousel.swift")
        XCTAssertTrue(carousel.contains("Text(L(\"電波が届かないので AI に聞けません\", \"No signal, so AI isn't available\"))\n                    .jpSystemFont(13, weight: .semibold, relativeTo: .footnote)"),
                      "電波が無い時の帯の字が大きくならない")
    }

    // MARK: - 案 6: 「透明度を下げる」でガラスの札を黒に

    /// 設定がオンの人だけ透けない地。オフの人は今のまま（黒 55%＋ぼかし）
    func testGlassBecomesOpaqueWithReduceTransparency() throws {
        XCTAssertEqual(JPGlassLook.look(reduceTransparency: true), .opaque)
        XCTAssertEqual(JPGlassLook.look(reduceTransparency: false), .seeThrough)
        XCTAssertEqual(JPGlassLook.tint, 0.55, "板のガラスの黒を変えた")
        let glass = try source("Core/Design/Glass.swift")
        XCTAssertTrue(glass.contains("@Environment(\\.accessibilityReduceTransparency) private var reduceTransparency"),
                      "「透明度を下げる」の設定を読んでいない")
        XCTAssertTrue(glass.contains("modifier(JPGlassFace(shape: shape, border: border))"))
        XCTAssertTrue(glass.contains(".background(WebTheme.sheet, in: shape)"), "透けない地が板の #161617 でない")
        XCTAssertEqual(BrandPalette.surface2, 0x161617)
    }
}
