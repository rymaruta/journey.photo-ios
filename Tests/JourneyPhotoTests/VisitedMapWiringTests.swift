import XCTest
@testable import JourneyPhoto

/// 🔴 行った県マップの画面が、判定の関数・入口・設定につながっていること（札 #503）。
///
/// 判定は `VisitedPrefecturesTests` などで縛っているが、**画面側のつなぎを外しても**それらは通ったままになる。
/// 画面は Linux で描けないので、ソースに**つなぎの呼び出しが残っていること**を見る。
/// 書き方を変えたら、ここも合わせて直す（消したら落ちるのが目的）
final class VisitedMapWiringTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
        // 注記（`//`）の中は数えない
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func visitedSources() throws -> [(path: String, text: String)] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto/Features/Profile")
        return try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasPrefix("Visited") && $0.hasSuffix(".swift") }
            .sorted()
            .map { ("Features/Profile/" + $0, try source("Features/Profile/" + $0)) }
    }

    /// 入口: マイページの「旅の記録」の下に札。バッジ「都道府県」の詳細からも入れる
    func testEntriesAreWired() throws {
        let myPage = try source("Features/Profile/MyPageView.swift")
        let travel = myPage.range(of: "                        travelRecord\n")
        let entry = myPage.range(of: "VisitedMapEntryCard()")
        XCTAssertNotNil(travel, "マイページの旅の記録が見つからない")
        XCTAssertNotNil(entry, "マイページに入口の札が無い")
        if let travel, let entry { XCTAssertLessThan(travel.lowerBound, entry.lowerBound, "札は旅の記録の下") }

        let shelf = try source("Features/Profile/BadgeShelfView.swift")
        XCTAssertTrue(shelf.contains(#"badge.key == "prefectures""#), "バッジ「都道府県」だけに出す")
        XCTAssertTrue(shelf.contains("isMine && badge.key"), "自分の棚だけに出す")
        XCTAssertTrue(shelf.contains("VisitedMapScreen()"))
        let medal = try source("Features/Profile/MedalViewerView.swift")
        XCTAssertTrue(medal.contains("VisitedMapText.openFromBadge"))

        let card = try source("Features/Profile/VisitedMapEntryCard.swift")
        XCTAssertTrue(card.contains("VisitedMapText.entryAccessibility(record.visitedCount)"))
        XCTAssertTrue(card.contains("minHeight: JPHeight.tallRow"), "入口の札は 64pt 以上")
        // 地図タブには混ぜない
        let map = try source("Features/Map/PhotoMapView.swift")
        XCTAssertFalse(map.contains("VisitedMap"), "行った県は地図タブに混ぜない")
    }

    /// 画面: 開くとき記録を読み、拡大中はスクロールを止め、触覚・読み上げ・取り消しを結ぶ
    func testScreenIsWired() throws {
        let screen = try source("Features/Profile/VisitedMapScreen.swift")
        for needle in [
            "model.open(userId: auth.userId)",
            ".scrollDisabled(viewport.isZoomed && mode == .map)",
            ".sensoryFeedback(.impact(weight: .light), trigger: model.lightTick)",
            ".sensoryFeedback(.success, trigger: model.successTick)",
            "UIAccessibility.post(notification: .announcement, argument: text)",
            "Button { model.undo() }",
            "model.markAllVisited()",
            "model.clearAll()",
            "VisitedBottomBar(model: model)",
            "model.selected == nil",
            ".sensoryFeedback(.warning, trigger: model.warningTick)",
            "model.voiceOverOn = ",
            "VisitedMapText.quickHint",
            "environment.photos.myPhotos()",
            "PrefectureMapGeometry.bundled",
            "VisitedPrefectureList(model: model)",
            "VisitedPrefectureCard(model: model",
            "TabRouter.shared.openPost(.photo)",
        ] {
            XCTAssertTrue(screen.contains(needle), "画面のつなぎが無い: \(needle)")
        }
    }

    func testCanvasIsWired() throws {
        let canvas = try source("Features/Profile/VisitedMapCanvasView.swift")
        for needle in [
            "geometry.prefecture(at: unit, tolerance: tolerance)",
            "VisitedMapText.prefectureAccessibility(",
            "VisitedMapStyle.fill(forLevel:",
            "@Environment(\\.accessibilityReduceMotion)",
            "guard new != nil, !reduceMotion else { return }",
            "guard !reduceMotion, let start = liftStart else { return 0 }",
            "guard !reduceMotion, old.count == new.count else { return }",
            "model.openCard(name)",
            "model.tap(name)",
            "MagnifyGesture()",
            "start.isZoomed",
        ] {
            XCTAssertTrue(canvas.contains(needle), "地図のつなぎが無い: \(needle)")
        }
        // 色は段の表から（画面に色の数を書かない）
        XCTAssertFalse(canvas.contains("0xF3DCA6"))
        XCTAssertFalse(canvas.contains("0x796440"))
    }

    /// 札: 「−」で減らし、候補は「記録する」まで数に入らない
    func testCardIsWired() throws {
        let card = try source("Features/Profile/VisitedPrefectureCard.swift")
        for needle in ["model.remove(prefecture)", "model.add(prefecture)", "model.dismissCandidate(prefecture)",
                       "model.restoreCandidate(prefecture)", "model.changeDay(prefecture", "VisitedMapText.candidateNote",
                       "jpPillButton(.accent)", "jpPillButton(.outline)", "minHeight: WebTheme.minTapTarget"] {
            XCTAssertTrue(card.contains(needle), "札のつなぎが無い: \(needle)")
        }
    }

    /// 🔴 県の札（シート）の下に確かめ・「取り消す」・祝いが隠れない
    func testBarAndCelebrationAreNotHiddenBehindTheCard() throws {
        let card = try source("Features/Profile/VisitedPrefectureCard.swift")
        XCTAssertTrue(card.contains(".overlay(alignment: .bottom) { VisitedBottomBar(model: model) }"),
                      "札の中に確かめ・取り消すの帯が無い")
        let screen = try source("Features/Profile/VisitedMapScreen.swift")
        // 画面側の帯と祝いは、札が開いている間は出さない（札の下に隠れる／二重にしない）
        XCTAssertTrue(screen.contains("if model.selected == nil { VisitedBottomBar(model: model) }"))
        XCTAssertTrue(screen.contains("if let celebration = model.celebration, model.selected == nil"),
                      "祝いは札を閉じたあとに出す")
        let bar = try source("Features/Profile/VisitedBottomBar.swift")
        for needle in ["model.undo()", "toast.offersUndo", "VisitedQuickBar(model: model)"] {
            XCTAssertTrue(bar.contains(needle), "帯のつなぎが無い: \(needle)")
        }
    }

    /// 🔴 案 A（札 #510・2026-11-10 owner「Aで作って」）: スイッチ「タップで回数を足す」と同じ日の確かめが無い。
    /// 戻したら落ちる
    func testNoTapSwitchAndNoSameDayConfirmation() throws {
        var files = try visitedSources()
        files.append(("Core/Text/VisitedMapText.swift", try source("Core/Text/VisitedMapText.swift")))
        for (path, text) in files {
            for word in ["addsOnTap", "Toggle(", "pendingSameDay", "confirmSameDay", "cancelSameDay", "confirmingSameDay",
                         "hasVisit(", "sameDayTitle", "switchTitle", "タップで回数を足す", "今日は記録済みです"] {
                XCTAssertFalse(text.contains(word), "\(path) にスイッチ・同じ日の確かめの名残り: \(word)")
            }
        }
    }

    /// 🔴 案 A の配線: 押す＝足す（`model.tap`）・長押し＝足さずに帯（`model.peek`）。地図・一覧とも同じ。
    /// 動かした・ピンチした指と、長押しで帯を出した指では足さない
    func testTapAddsAndLongPressPeeksOnMapAndList() throws {
        let canvas = try source("Features/Profile/VisitedMapCanvasView.swift")
        for needle in ["let outcome = VisitedMapTouch.onRelease(moved: didMove, pinched: didPinch, longPressFired: firedLong,",
                       "model.release(outcome, on: hit.name)",
                       "guard VisitedMapTouch.firesLongPress(sameTouch: touchBegan == began, fingerDown: fingerDown,",
                       "@GestureState private var fingerDown = false",
                       ".updating($fingerDown) { _, state, _ in state = true }",
                       ".onChange(of: fingerDown) { _, down in",
                       "if touchBegan == began { resetTouch() }",
                       "model.peek(hit.name)",
                       "longPressFired = began",
                       "let selected = model.selected ?? model.quickBar?.prefecture",
                       ".accessibilityAction { model.tap(name) }",
                       ".accessibilityAction(named: VisitedMapText.removeOne) { model.decrease(name) }",
                       ".accessibilityAction(named: VisitedMapText.details) { model.openCard(name) }",
                       "VisitedMapText.tapHint",
                       "guard !reduceMotion, let name = model.addPulsePrefecture else { return }"] {
            XCTAssertTrue(canvas.contains(needle), "地図のつなぎが無い: \(needle)")
        }
        XCTAssertFalse(canvas.contains("model.openCard(hit.name)"), "長押しで札を開く形に戻った")
        XCTAssertFalse(canvas.contains("nonisolated static let longPressSeconds: Double = 0.5"), "長押しの長さを二重に持っている")
        let list = try source("Features/Profile/VisitedPrefectureList.swift")
        for needle in ["if VisitedMapTouch.swallowsTap(on: name, after: longPressed, now: Date()) {",
                       "model.tap(name)",
                       ".simultaneousGesture(LongPressGesture(minimumDuration: VisitedMapTouch.longPressSeconds).onEnded { _ in",
                       "model.peek(name)",
                       ".buttonStyle(.plain)",
                       ".accessibilityAction(named: VisitedMapText.removeOne) { model.decrease(name) }"] {
            XCTAssertTrue(list.contains(needle), "一覧のつなぎが無い: \(needle)")
        }
        // 一覧の器はまとまりにしてから名前を付ける（行の名前を上書きしない・Mac 947）
        XCTAssertTrue(list.contains(".accessibilityElement(children: .contain)\n        .accessibilityIdentifier(\"visitedMap.list\")"),
                      "一覧の器の名前が行の名前を上書きする形に戻った")
        // 一覧は Button のまま（スクロールと押した見た目を保つ）。手振りを2つ並べる形に戻さない
        XCTAssertFalse(list.contains(".onTapGesture"), "一覧の行が onTapGesture に戻った")
        XCTAssertFalse(list.contains(".onLongPressGesture"), "一覧の行が onLongPressGesture に戻った")
        let model = try source("Features/Profile/VisitedMapModel.swift")
        for needle in ["if !quick { record.restoreCandidate(prefecture) }",
                       "if quickBarHeld { setQuickBarHeld(false) }",
                       "func release(_ outcome: VisitedMapTouch.Outcome, on prefecture: String)"] {
            XCTAssertTrue(model.contains(needle), "モデルのつなぎが無い: \(needle)")
        }
    }

    /// 🔴 押した県の帯: ［−］［＋］は同じ大きさ（同じ部品 `stepButton`）・0 回で［−］を止める・［詳しく］で札・
    /// 触っている間は消さない・黒地の上の真鍮は［詳しく］の字だけ・地は surface-2
    func testQuickBarIsWired() throws {
        let bar = try source("Features/Profile/VisitedBottomBar.swift")
        for needle in ["enabled: count > 0,\n                       id: \"visitedMap.quick.minus\") { model.quickRemove() }",
                       "id: \"visitedMap.quick.plus\") { model.quickAdd() }",
                       "enabled: count < VisitedPrefectures.maxCount",
                       "Button { model.openCard(name) }",
                       "VisitedMapText.details",
                       ".frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)",
                       ".updating($touching)",
                       ".onChange(of: touching) { _, held in model.setQuickBarHeld(held) }",
                       ".background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: JPRadius.l))",
                       "if model.quickBar != nil, model.celebration == nil",
                       ".onDisappear { model.setQuickBarHeld(false) }",
                       "if typeSize.isAccessibilitySize {",
                       "ViewThatFits(in: .horizontal) {",
                       "if count >= VisitedPrefectures.maxCount {",
                       "VisitedMapText.limitShort",
                       ".lineLimit(3)",
                       "guard !reduceMotion, old != new else { return }"] {
            XCTAssertTrue(bar.contains(needle), "帯のつなぎが無い: \(needle)")
        }
        // ［−］と［＋］は同じ部品（同じ大きさ・同じ押しやすさ）
        XCTAssertEqual(bar.components(separatedBy: "stepButton(systemName:").count - 1, 3 /* 定義1 + 使う2 */)
        // 減らすときに確かめのダイアログを出さない（［＋］で戻せる）
        XCTAssertFalse(bar.contains("confirmationDialog"))
        XCTAssertFalse(bar.contains("alert("))
    }

    /// 🔴 指の途中状態は、`onEnded` が来なくても次の指で作り直す。＋−は実際の枠の大きさで拡大する
    func testGestureStateIsRebuiltAndZoomUsesTheRealFrame() throws {
        let canvas = try source("Features/Profile/VisitedMapCanvasView.swift")
        for needle in ["isNewTouch(start: value.startLocation, translation: value.translation)",
                       "private func resetTouch()", "let fresh = pinchStart == nil || pinchLocation != value.startLocation",
                       "zoomControls(container: container)", "viewport.stepped(1, content: geometry.size, container: container)",
                       "longPressTick += 1"] {
            XCTAssertTrue(canvas.contains(needle), "地図のつなぎが無い: \(needle)")
        }
        let screen = try source("Features/Profile/VisitedMapScreen.swift")
        XCTAssertFalse(screen.contains("containerGuess"), "＋−に推定の枠を渡している")
    }

    /// 🔴 2026-11-09 owner: 模様（点・線・格子）はやめ、色だけで分ける。模様の描画・定義が戻ったら落ちる。
    /// 段も 0 回・1 回・2 回・3 回以上の4つ（「4 回以上」を戻したら落ちる）
    func testNoPatternsAndNoFourPlusLevel() throws {
        var files = try visitedSources()
        files.append(("Core/Text/PrefectureMapGeometry.swift", try source("Core/Text/PrefectureMapGeometry.swift")))
        files.append(("Core/Text/VisitedMapText.swift", try source("Core/Text/VisitedMapText.swift")))
        files.append(("Core/Text/VisitedPrefectures.swift", try source("Core/Text/VisitedPrefectures.swift")))
        for (path, text) in files {
            for word in ["patternPath", "pattern(forLevel", "enum Pattern", ".hatch", ".stripes", "case dots", "case grid",
                         "inkOnBright", "inkOnDark", "legendFourPlus", "4 回以上", "4+\""] {
                XCTAssertFalse(text.contains(word), "\(path) に模様・4 回以上の名残り: \(word)")
            }
            // 形で切るのは写真の候補の破線（と見本の 0 の縁）を内側だけに描くときだけ。模様を重ねる切り方は戻さない
            XCTAssertFalse(text.contains("layer.clip(to:"), "\(path) が県の形で切って模様を重ねている")
            XCTAssertLessThanOrEqual(text.components(separatedBy: ".clip(to:").count - 1, 1,
                                     "\(path) で形を切る所が増えた（模様の名残り？）")
        }
    }

    /// 🔴 板 04b「縁と状態」: 候補の破線は県の内側だけ（形で切って線幅を倍）・選択中は黒の隙間＋白の縁・
    /// 押している間の色。縁の中央に破線を描く形に戻ったら落ちる（2 段目の隣で 1.34 に溶ける）
    func testEdgesAndStatesFollowBoard04b() throws {
        let canvas = try source("Features/Profile/VisitedMapCanvasView.swift")
        for needle in ["inside.clip(to: item.path)",
                       "VisitedMapStyle.candidateInsideWidth * 2",
                       "let selected = model.selected",
                       "VisitedMapStyle.selectedGapWidth * 2",
                       "VisitedMapStyle.pressedFill(forLevel: level)",
                       ".updating($pressed)",
                       "@GestureState private var pressed: String?",
                       "? nil : prefecture(at: value.startLocation, container: container)?.name",
                       "VisitedMapStyle.paintedEdgeWidth",
                       "VisitedMapStyle.zeroEdgeWidth"] {
            XCTAssertTrue(canvas.contains(needle), "地図に無い: \(needle)")
        }
        XCTAssertFalse(canvas.contains("StrokeStyle(lineWidth: 1.5, dash: [3, 3])"), "候補の破線が縁の中央に戻った")
        let swatch = try source("Features/Profile/VisitedPrefectureList.swift")
        XCTAssertTrue(swatch.contains("VisitedMapStyle.candidateInsideWidth * 2"), "凡例の候補の見本が内側の破線でない")
    }

    /// 🔴 凡例の見本・一覧・地図の塗りは、同じ色の表（`VisitedMapStyle.fill(forLevel:)`）だけを読む（色の写しを作らない）
    func testLegendAndMapShareOneColorTable() throws {
        for path in ["Features/Profile/VisitedPrefectureList.swift", "Features/Profile/VisitedMapCanvasView.swift",
                     "Features/Profile/VisitedMapEntryCard.swift"] {
            let text = try source(path)
            XCTAssertTrue(text.contains("VisitedMapStyle.fill(forLevel:"), "\(path) が色の表を読んでいない")
            XCTAssertNil(text.range(of: "0x[0-9A-Fa-f]{6}", options: .regularExpression), "\(path) に色の写しがある")
        }
        let list = try source("Features/Profile/VisitedPrefectureList.swift")
        XCTAssertTrue(list.contains("VisitedSwatch(level: level"), "一覧の見本が無い")
        let screen = try source("Features/Profile/VisitedMapScreen.swift")
        for needle in ["legendZero", "legendTimes(1)", "legendTimes(2)", "legendThreePlus"] {
            XCTAssertTrue(screen.contains(needle), "凡例に無い: \(needle)")
        }
        XCTAssertEqual(screen.components(separatedBy: "legendItem(level:").count - 1, 6 /* 定義1 + 使う5 */,
                       "凡例は 0 回・1・2・3 回以上・写真の候補の5つ")
        // 板 04b: 少ない → 多いの順、区切り線、候補
        let order = ["legendZero", "legendTimes(1)", "legendTimes(2)", "legendThreePlus",
                     "Color.white.opacity(0.14)).frame(width: 1, height: 16)", "legendCandidate"]
            .compactMap { screen.range(of: $0)?.lowerBound }
        XCTAssertEqual(order.count, 6, "凡例の部品が足りない")
        XCTAssertEqual(order, order.sorted(), "凡例の並びが 0・1・2・3 回以上・区切り線・候補でない")
    }

    /// 回数の色の作り方に Pro の名前を出さない（`VisitedMapStyle.color` を通す）
    func testColorsDoNotGoThroughProNames() throws {
        for (path, text) in try visitedSources() where !path.hasSuffix("VisitedMapEntryCard.swift") {
            XCTAssertFalse(text.contains("ProMarkColors"), "\(path) が Pro の名前の部品を直に呼んでいる")
        }
    }

    /// 🔴 塗り・回数は報酬にも他人への公開にも結ばない（不正の誘因を作らない）。
    /// 行った県の画面の層が、硬貨・バッジ・家具・Pro・サーバーへの書き込みに触れていない
    func testScreensAreNotTiedToRewardsOrServerWrites() throws {
        let forbidden = ["Camper", "Trunk", "BadgeCatalog", "BadgeStatus", "ProStatus", "Purchase", "StoreKit",
                         "environment.camper", "environment.trunk", "environment.api", "environment.social",
                         "environment.profiles", "environment.uploads", "environment.purchases",
                         "URLSession", "APIClient", "authorized("]
        let files = try visitedSources()
        XCTAssertGreaterThanOrEqual(files.count, 6, "行った県の画面が見つからない")
        for (path, text) in files {
            for word in forbidden {
                XCTAssertFalse(text.contains(word), "\(path) が \(word) に触れている（報酬・公開・サーバーと結ばない）")
            }
        }
    }

    /// 文字の大きさ: 本文系の最小は 12。数で書く字は 12 未満にしない
    func testNoTinyFixedFonts() throws {
        for (path, text) in try visitedSources() {
            for line in text.components(separatedBy: "\n") where line.contains(".system(size:") {
                let rest = line.components(separatedBy: ".system(size:").last ?? ""
                let digits = String(rest.prefix(while: { $0 == " " || $0.isNumber || $0 == "." }))
                    .trimmingCharacters(in: .whitespaces)
                if let size = Double(digits) {
                    XCTAssertGreaterThanOrEqual(size, 12, "\(path) に 12 未満の字: \(line)")
                }
            }
        }
    }

    /// 系統の赤を画面の行に出さない
    func testNoSystemRedInVisitedScreens() throws {
        for (path, text) in try visitedSources() {
            XCTAssertFalse(text.contains("Color.red"), "\(path) に系統の赤")
        }
    }
}
