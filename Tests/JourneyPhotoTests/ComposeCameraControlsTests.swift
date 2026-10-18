import XCTest
@testable import JourneyPhoto

/// 「構図を重ねて撮る」の撮影画面（2026-10-16 owner「回転がないのしんどい」「UI を隠さないと全体が見れない」
/// 「標準のカメラ App と遜色なく」）: 回す・UI を隠す・拡大・ピント・明るさ・音量ボタン。
final class ComposeCameraControlsTests: XCTestCase {

    private let portrait = 0.75

    private func segments(_ marks: [GuideMark]) -> [(GuidePoint, GuidePoint)] {
        marks.compactMap { if case .segment(let a, let b) = $0.shape { return (a, b) } else { return nil } }
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: - 回す: 角度

    func testRotationSnapsNearQuarters() {
        XCTAssertEqual(CompositionGuide.snappedRotation(4), 0)
        XCTAssertEqual(CompositionGuide.snappedRotation(-3), 0)
        XCTAssertEqual(CompositionGuide.snappedRotation(357), 0)
        XCTAssertEqual(CompositionGuide.snappedRotation(95), 90)
        XCTAssertEqual(CompositionGuide.snappedRotation(184), 180)
        XCTAssertEqual(CompositionGuide.snappedRotation(-88), 270)
        // 吸い付く幅の外はそのまま
        XCTAssertEqual(CompositionGuide.snappedRotation(20), 20, accuracy: 1e-9)
        XCTAssertEqual(CompositionGuide.snappedRotation(-30), 330, accuracy: 1e-9)
        XCTAssertEqual(CompositionGuide.normalizedRotation(.nan), 0)
        XCTAssertTrue(CompositionGuide.isQuarterRotation(270))
        XCTAssertFalse(CompositionGuide.isQuarterRotation(20))
    }

    func testRotateRightGoesToTheNextQuarter() {
        XCTAssertEqual(CompositionGuide.rotatedRight(0), 90)
        XCTAssertEqual(CompositionGuide.rotatedRight(37), 90)
        XCTAssertEqual(CompositionGuide.rotatedRight(90), 180)
        XCTAssertEqual(CompositionGuide.rotatedRight(270), 0)
        // 4回で元へ
        var d = 0.0
        for _ in 0..<4 { d = CompositionGuide.rotatedRight(d) }
        XCTAssertEqual(d, 0)
    }

    func testRotationSplitsIntoQuartersAndRest() {
        XCTAssertEqual(CompositionGuide.rotationParts(100).quarters, 1)
        XCTAssertEqual(CompositionGuide.rotationParts(100).residual, 10, accuracy: 1e-9)
        XCTAssertEqual(CompositionGuide.rotationParts(350).quarters, 0)
        XCTAssertEqual(CompositionGuide.rotationParts(350).residual, -10, accuracy: 1e-9)
        XCTAssertEqual(CompositionGuide.rotationParts(270).quarters, 3)
        XCTAssertEqual(CompositionGuide.rotationParts(270).residual, 0, accuracy: 1e-9)
    }

    // MARK: - 回す: 線

    func testQuarterRotationTurnsTheLinesClockwise() {
        // 地平線（y = 2/3・下寄り）を右に 90° → 縦の線 x = 1/3（下にあったものは左へ）
        let h = segments(CompositionGuide.screenMarks(.horizon, variant: 0, aspect: portrait, quarterTurns: 0,
                                                      levelDegrees: 0, rotationQuarters: 1))
        XCTAssertEqual(h.count, 1)
        XCTAssertEqual(h[0].0.x, 1.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(h[0].1.x, 1.0 / 3, accuracy: 1e-9)
        // 180° 回すと「地面を広く」と同じ線
        let upside = segments(CompositionGuide.screenMarks(.horizon, variant: 0, aspect: portrait, quarterTurns: 0,
                                                           levelDegrees: 0, rotationQuarters: 2))
        XCTAssertEqual(upside.count, 1)
        XCTAssertEqual(upside[0].0.y, 1.0 / 3, accuracy: 1e-9)
        // 0 回はこれまでと同じ（覚えてある向き・反転の値の見え方を変えない）
        for kind in CompositionKind.allCases {
            for v in 0..<kind.variantCount {
                XCTAssertEqual(CompositionGuide.screenMarks(kind, variant: v, aspect: portrait, quarterTurns: 0,
                                                            levelDegrees: 0, rotationQuarters: 0),
                               CompositionGuide.screenMarks(kind, variant: v, aspect: portrait, quarterTurns: 0,
                                                            levelDegrees: 0), "\(kind)")
            }
        }
    }

    func testQuarterRotationRefitsInsteadOfStretching() {
        // 正方形の枠を 90° 回しても、3:4 の写真の上で正方形のまま（引き伸ばすと 4:3 に潰れる）
        let square = CompositionGuide.screenMarks(.square, variant: 0, aspect: portrait, quarterTurns: 0,
                                                  levelDegrees: 0, rotationQuarters: 1)
        guard case .dimOutside(let c)? = square.first?.shape else { return XCTFail("暗がりが無い") }
        XCTAssertEqual(c.width * portrait, c.height, accuracy: 1e-9)
        // 16:9 の枠を 90° 回すと、写真の上で 9:16 の枠（構図として正しい向き）
        let wide = CompositionGuide.screenMarks(.ratio16x9, variant: 0, aspect: portrait, quarterTurns: 0,
                                                levelDegrees: 0, rotationQuarters: 1)
        guard case .dimOutside(let w)? = wide.first?.shape else { return XCTFail("暗がりが無い") }
        XCTAssertEqual(w.width * portrait / w.height, 9.0 / 16, accuracy: 1e-9)
        // 全種類・全向き・全回転で枠の内
        for turns in 0..<4 {
            for kind in CompositionKind.allCases {
                for v in 0..<kind.variantCount {
                    for p in CompositionGuide.screenMarks(kind, variant: v, aspect: portrait, quarterTurns: 0,
                                                           levelDegrees: 0, rotationQuarters: turns)
                        .flatMap(\.samplePoints) {
                        XCTAssertTrue((-1e-9...1 + 1e-9).contains(p.x) && (-1e-9...1 + 1e-9).contains(p.y),
                                      "\(kind) \(v) \(turns)")
                    }
                }
            }
        }
    }

    func testFlipComesBeforeRotation() {
        // 反転（向き）が先・回転が後: 対角の「左上→右下」(0) を右に 90° → 「左下→右上」の線。
        // 回してから反転する順だと「左上→右下」のまま残る
        let rotated = segments(CompositionGuide.screenMarks(.diagonals, variant: 0, aspect: portrait, quarterTurns: 0,
                                                            levelDegrees: 0, rotationQuarters: 1))
        XCTAssertEqual(rotated.count, 1)
        let (a, b) = rotated[0]
        let lowLeft = a.x < b.x ? a : b, other = a.x < b.x ? b : a
        XCTAssertEqual(lowLeft.y, 1, accuracy: 1e-9)
        XCTAssertEqual(other.y, 0, accuracy: 1e-9)
        // 決めた順のとおり: 向きを付けた形を、回した後の枠の比率で作ってから時計回りに回す
        for v in 0..<CompositionKind.negativeSpace.variantCount {
            let expected = CompositionGuide.marks(.negativeSpace, variant: v, aspect: 1 / portrait)
                .map { CompositionGuide.clockwiseTransform(1).apply($0) }
            XCTAssertEqual(CompositionGuide.screenMarks(.negativeSpace, variant: v, aspect: portrait, quarterTurns: 0,
                                                        levelDegrees: 0, rotationQuarters: 1), expected)
        }
    }

    func testLevelIgnoresRotation() {
        XCTAssertEqual(CompositionGuide.screenMarks(.level, variant: 0, aspect: portrait, quarterTurns: 0,
                                                    levelDegrees: 3, rotationQuarters: 1),
                       CompositionGuide.screenMarks(.level, variant: 0, aspect: portrait, quarterTurns: 0,
                                                    levelDegrees: 3))
    }

    func testDimBandsCoverTheCornersWhenTilted() {
        let crop = GuideRect(x: 0, y: 0.125, width: 1, height: 0.75)
        // 回さないときはこれまでと同じ（枠の内側だけ）
        let flat = CompositionGuide.dimBands(crop: crop, margin: 0)
        XCTAssertEqual(flat[0], GuideRect(x: 0, y: 0, width: 1, height: 0.125))
        // 30° 回すと、枠の角は回す前の座標で枠の外へ出る。伸ばした帯がそこを覆う
        let bands = CompositionGuide.dimBands(crop: crop, margin: 1 / portrait)
        let w = portrait, h = 1.0, t = -30 * Double.pi / 180
        for corner in [(0.0, 0.0), (w, 0.0), (0.0, h), (w, h)] {
            let dx = corner.0 - w / 2, dy = corner.1 - h / 2
            let x = (w / 2 + dx * cos(t) - dy * sin(t)) / w, y = h / 2 + dx * sin(t) + dy * cos(t)
            let covered = bands.contains { x >= $0.x && x <= $0.maxX && y >= $0.y && y <= $0.maxY }
            let inCrop = x >= crop.x && x <= crop.maxX && y >= crop.y && y <= crop.maxY
            XCTAssertTrue(covered || inCrop, "\(corner)")
            XCTAssertFalse(flat.contains { x >= $0.x && x <= $0.maxX && y >= $0.y && y <= $0.maxY } || inCrop,
                           "伸ばさないと抜ける角があるはず \(corner)")
        }
    }

    // MARK: - 回す: 覚える

    func testRotationIsRememberedUntilTheCompositionIsChosenAgain() {
        let suite = "ComposeCameraControlsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = CompositionPreferences(defaults: defaults)
        // 前の版で覚えた向き（反転）はそのまま読める
        defaults.set(["goldenSpiral": 2], forKey: "journey-photo-composition-variants")
        XCTAssertEqual(prefs.rotation(for: .goldenSpiral), 0)
        prefs.setRotation(90, for: .goldenSpiral)
        prefs.setRotation(450, for: nil)
        XCTAssertEqual(prefs.rotation(for: .goldenSpiral), 90)
        XCTAssertEqual(prefs.rotation(for: nil), 90)
        XCTAssertEqual(prefs.variant(for: .goldenSpiral), 2)
        // 選び直したら 0 に戻る（向きは残る）
        prefs.select(.goldenSpiral)
        XCTAssertEqual(prefs.rotation(for: .goldenSpiral), 0)
        XCTAssertEqual(prefs.variant(for: .goldenSpiral), 2)
        // 壊れた値は 0
        defaults.set(["thirds": "x"], forKey: "journey-photo-composition-rotations")
        XCTAssertEqual(prefs.rotation(for: .thirds), 0)
    }

    // MARK: - 拡大

    func testZoomLevelsFollowTheLenses() {
        // 三眼（超広角・広角・望遠 3×）: 0.5 / 1 / 2 / 3
        let triple = ComposeControls.zoomLevels(hasUltraWide: true, switchOver: [2, 6], minFactor: 1, maxFactor: 123)
        XCTAssertEqual(triple.presets, [0.5, 1, 2, 3])
        XCTAssertEqual(triple.factor(display: 1), 2)
        XCTAssertEqual(triple.maxFactor, ComposeControls.maxDisplayZoom * 2)
        // 二眼の広角（超広角・広角）: 0.5 / 1 / 2
        XCTAssertEqual(ComposeControls.zoomLevels(hasUltraWide: true, switchOver: [2], minFactor: 1, maxFactor: 30).presets,
                       [0.5, 1, 2])
        // 二眼（広角・望遠 2×）: 1 / 2
        XCTAssertEqual(ComposeControls.zoomLevels(hasUltraWide: false, switchOver: [2], minFactor: 1, maxFactor: 16).presets,
                       [1, 2])
        // 広角1つでも 2×（切り出し）は出す。寄れない端末（最大 1）では 1× だけ
        XCTAssertEqual(ComposeControls.zoomLevels(hasUltraWide: false, switchOver: [], minFactor: 1, maxFactor: 10).presets,
                       [1, 2])
        XCTAssertEqual(ComposeControls.zoomLevels(hasUltraWide: false, switchOver: [], minFactor: 1, maxFactor: 1).presets,
                       [1])
    }

    func testPinchAndLabels() {
        let levels = ComposeControls.zoomLevels(hasUltraWide: true, switchOver: [2, 6], minFactor: 1, maxFactor: 100)
        XCTAssertEqual(ComposeControls.pinchedFactor(start: 2, magnification: 1.5, levels: levels), 3)
        XCTAssertEqual(ComposeControls.pinchedFactor(start: 2, magnification: 0.1, levels: levels), 1)
        XCTAssertEqual(ComposeControls.pinchedFactor(start: 2, magnification: 100, levels: levels), 20)
        XCTAssertEqual(ComposeControls.activePreset(display: 1.4, presets: levels.presets), 1)
        XCTAssertEqual(ComposeControls.activePreset(display: 0.5, presets: levels.presets), 0.5)
        XCTAssertEqual(ComposeControls.zoomLabel(0.5, active: false), ".5")
        XCTAssertEqual(ComposeControls.zoomLabel(1.4, active: true), "1.4×")
        XCTAssertEqual(ComposeControls.zoomLabel(2, active: false), "2")
        XCTAssertEqual(ComposeControls.zoomAccessibility(0.5), "0.5倍")
    }

    // MARK: - 指の読み分け・ピント・明るさ

    func testTouchEndTellsTapSwipeAndNothing() {
        XCTAssertEqual(ComposeControls.touchEnd(dx: 3, dy: 2, seconds: 0.1, adjustedExposure: false, locked: false,
                                                afterMultiTouch: false), .tap)
        // 長押しで固定した・明るさを動かした・2本指の直後はタップにしない
        XCTAssertEqual(ComposeControls.touchEnd(dx: 0, dy: 0, seconds: 0.1, adjustedExposure: false, locked: true,
                                                afterMultiTouch: false), .none)
        XCTAssertEqual(ComposeControls.touchEnd(dx: 0, dy: 40, seconds: 0.3, adjustedExposure: true, locked: false,
                                                afterMultiTouch: false), .none)
        XCTAssertEqual(ComposeControls.touchEnd(dx: -90, dy: 5, seconds: 0.2, adjustedExposure: false, locked: false,
                                                afterMultiTouch: true), .none)
        // 横に長く払う＝作例、短い払い・縦は何もしない
        XCTAssertEqual(ComposeControls.touchEnd(dx: -90, dy: 5, seconds: 0.2, adjustedExposure: false, locked: false,
                                                afterMultiTouch: false), .swipe(-90))
        XCTAssertEqual(ComposeControls.touchEnd(dx: 30, dy: 0, seconds: 0.2, adjustedExposure: false, locked: false,
                                                afterMultiTouch: false), .none)
        XCTAssertEqual(ComposeControls.touchEnd(dx: 10, dy: 90, seconds: 0.2, adjustedExposure: false, locked: false,
                                                afterMultiTouch: false), .none)
    }

    func testExposureDragAndBias() {
        XCTAssertTrue(ComposeControls.isExposureDrag(dx: 2, dy: -30, focusShown: true))
        XCTAssertFalse(ComposeControls.isExposureDrag(dx: 2, dy: -30, focusShown: false))
        XCTAssertFalse(ComposeControls.isExposureDrag(dx: 40, dy: -30, focusShown: true))
        // 上へ 120pt で +1 EV・範囲の内
        XCTAssertEqual(ComposeControls.exposureBias(start: 0, dy: -120, min: -2, max: 2), 1, accuracy: 1e-9)
        XCTAssertEqual(ComposeControls.exposureBias(start: 0, dy: 1000, min: -2, max: 2), -2)
    }

    func testDevicePointIsTheLandscapeSensorCoordinate() {
        // 縦の画面の左上 → カメラの (0, 1)、右下 → (1, 0)、真ん中はそのまま
        XCTAssertEqual(ComposeControls.devicePoint(x: 0, y: 0, width: 300, height: 400).x, 0)
        XCTAssertEqual(ComposeControls.devicePoint(x: 0, y: 0, width: 300, height: 400).y, 1)
        XCTAssertEqual(ComposeControls.devicePoint(x: 300, y: 400, width: 300, height: 400).x, 1)
        XCTAssertEqual(ComposeControls.devicePoint(x: 150, y: 200, width: 300, height: 400).y, 0.5)
        XCTAssertEqual(ComposeControls.devicePoint(x: 75, y: 100, width: 300, height: 400).x, 0.25)
        XCTAssertEqual(ComposeControls.devicePoint(x: 75, y: 100, width: 300, height: 400).y, 0.75)
    }

    func testMultiTouchQuietWindow() {
        let now = Date()
        XCTAssertTrue(ComposeControls.isAfterMultiTouch(last: now.addingTimeInterval(-0.2), now: now))
        XCTAssertFalse(ComposeControls.isAfterMultiTouch(last: now.addingTimeInterval(-1), now: now))
        XCTAssertFalse(ComposeControls.isAfterMultiTouch(last: nil, now: now))
    }

    // MARK: - UI を隠す・撮る

    func testHiddenShutterOnlyWhereItDoesNotCoverTheFrame() {
        // 390×763 の面に 3:4 の枠（390×520）→ 下の余り 121pt に 76pt のシャッターが入る
        XCTAssertTrue(ComposeControls.hiddenShutterFits(containerHeight: 763, frameHeight: 520, shutter: 76))
        XCTAssertFalse(ComposeControls.hiddenShutterFits(containerHeight: 600, frameHeight: 520, shutter: 76))
    }

    func testCanShoot() {
        XCTAssertTrue(ComposeControls.canShoot(ready: true, capturing: false, sheetOpen: false))
        XCTAssertFalse(ComposeControls.canShoot(ready: true, capturing: true, sheetOpen: false))
        XCTAssertFalse(ComposeControls.canShoot(ready: true, capturing: false, sheetOpen: true))
        XCTAssertFalse(ComposeControls.canShoot(ready: false, capturing: false, sheetOpen: false))
    }

    // MARK: - 確かめ役の指摘（2026-10-16）

    func testPinchDoesNotRotateAndTwistNeedsFifteenDegrees() {
        var t = ComposeControls.Twist()
        // つまむ量が先に大きい（1.3 倍）→ 拡大の指。あとでひねっても回さない
        t = ComposeControls.nextTwist(t, rotation: 4, magnification: 1.3)
        XCTAssertTrue(t.blocked)
        t = ComposeControls.nextTwist(t, rotation: 40, magnification: 1.3)
        XCTAssertFalse(t.engaged)
        XCTAssertEqual(ComposeControls.effectiveTwist(rotation: 40, state: t), 0)
        // つまむ量が小さく、ひねりが 15° 未満 → まだ回さない
        var u = ComposeControls.nextTwist(ComposeControls.Twist(), rotation: 10, magnification: 1.05)
        XCTAssertFalse(u.engaged)
        XCTAssertFalse(u.blocked)
        XCTAssertEqual(ComposeControls.effectiveTwist(rotation: 10, state: u), 0)
        // 15° を越えたら効く。越えた所から数える（跳ねない）
        u = ComposeControls.nextTwist(u, rotation: -16, magnification: 1.05)
        XCTAssertTrue(u.engaged)
        XCTAssertEqual(ComposeControls.effectiveTwist(rotation: -16, state: u), -1, accuracy: 1e-9)
        XCTAssertEqual(ComposeControls.effectiveTwist(rotation: -105, state: u), -90, accuracy: 1e-9)
        // 効いた後に指を逆へ戻して 0° をまたいでも、続けて数える（30° 跳ばない）
        XCTAssertEqual(ComposeControls.effectiveTwist(rotation: 10, state: u), 25, accuracy: 1e-9)
        XCTAssertEqual(ComposeControls.effectiveTwist(rotation: 0, state: u), 15, accuracy: 1e-9)
        let right = ComposeControls.nextTwist(ComposeControls.Twist(), rotation: 20, magnification: 1)
        XCTAssertEqual(ComposeControls.effectiveTwist(rotation: 20, state: right), 5, accuracy: 1e-9)
        XCTAssertEqual(ComposeControls.effectiveTwist(rotation: -10, state: right), -25, accuracy: 1e-9)
        // 一度効いたら、あとで拡大が大きくなっても離すまで効いたまま
        XCTAssertTrue(ComposeControls.nextTwist(u, rotation: -20, magnification: 2).engaged)
    }

    func testSnapFeedbackOnlyWhenSnapping() {
        XCTAssertEqual(ComposeControls.snapSignal(shownRotation: 90, baseRotation: 0, twisting: true), 1)
        XCTAssertEqual(ComposeControls.snapSignal(shownRotation: 90, baseRotation: 0, twisting: false), -1)
        XCTAssertEqual(ComposeControls.snapSignal(shownRotation: 100, baseRotation: 0, twisting: true), -1)
        XCTAssertEqual(ComposeControls.snapSignal(shownRotation: 360, baseRotation: 270, twisting: true), 0)
        // 効いた瞬間（足す角度 0・もとの角度のまま）は鳴らさない
        XCTAssertEqual(ComposeControls.snapSignal(shownRotation: 90, baseRotation: 90, twisting: true), -1)
        XCTAssertEqual(ComposeControls.snapSignal(shownRotation: 0, baseRotation: 3, twisting: true), -1)
        // 鳴るのは吸い付いたときだけ（-1 に戻るとき・同じ値のままでは鳴らない）
        XCTAssertTrue(ComposeControls.snapFeedbackFires(old: -1, new: 1))
        XCTAssertFalse(ComposeControls.snapFeedbackFires(old: 1, new: -1))
        XCTAssertFalse(ComposeControls.snapFeedbackFires(old: 1, new: 1))
    }

    func testCumulativeRotationTurnsTheShortWay() {
        // 270° から右へ → 360°（0° に戻すと絵が逆に 270° 回る）
        XCTAssertEqual(ComposeControls.rotatedRightCumulative(270), 360)
        XCTAssertEqual(ComposeControls.rotatedRightCumulative(37), 90)
        XCTAssertEqual(CompositionGuide.normalizedRotation(ComposeControls.rotatedRightCumulative(270)), 0)
        // 吸い付きも累積のまま
        XCTAssertEqual(ComposeControls.snappedCumulative(364), 360)
        XCTAssertEqual(ComposeControls.snappedCumulative(-93), -90)
        XCTAssertEqual(ComposeControls.snappedCumulative(20), 20)
        // 真っ直ぐに戻す先はいちばん近い 360° の倍数
        XCTAssertEqual(ComposeControls.straightened(450), 360)
        XCTAssertEqual(ComposeControls.straightened(90), 0)
        // 参考写真の縦横は決まった角度で決める
        XCTAssertTrue(ComposeControls.referenceSwapsAxes(committedRotation: 450))
        XCTAssertFalse(ComposeControls.referenceSwapsAxes(committedRotation: 360))
    }

    func testExposureIsNotReadDuringTwoFingers() {
        XCTAssertFalse(ComposeControls.isExposureDrag(dx: 2, dy: -30, focusShown: true, afterMultiTouch: true))
        XCTAssertTrue(ComposeControls.isExposureDrag(dx: 2, dy: -30, focusShown: true, afterMultiTouch: false))
    }

    func testZoomIdentifiersDifferPerStep() {
        XCTAssertEqual(ComposeControls.zoomIdentifier(0.5), "composeGuide.zoom.0_5")
        XCTAssertEqual(ComposeControls.zoomIdentifier(1), "composeGuide.zoom.1")
        XCTAssertEqual(ComposeControls.zoomIdentifier(3), "composeGuide.zoom.3")
        XCTAssertTrue(ComposeControls.shutterFlashHold > 0)
    }

    func testReviewFixesAreWired() throws {
        let view = try source("Sources/JourneyPhoto/Features/Spots/ComposeGuideView.swift")
        // 暗転: true を描かせてから false へ（同じ処理の中で戻さない）
        XCTAssertFalse(view.contains("shutterFlash = true\n        withAnimation"))
        XCTAssertTrue(view.contains("ComposeControls.shutterFlashHold * 1_000_000_000"))
        // 振動は吸い付いたときだけ
        XCTAssertTrue(view.contains("ComposeControls.snapFeedbackFires(old: old, new: new)"))
        // ひねりは読み分けてから（拡大の指では回さない）
        XCTAssertTrue(view.contains("twistState = ComposeControls.nextTwist(twistState"))
        XCTAssertTrue(view.contains("ComposeControls.effectiveTwist(rotation: twist, state: twistState)"))
        // 参考写真の縦横は決まった角度で
        XCTAssertTrue(view.contains("ComposeControls.referenceSwapsAxes(committedRotation: rotation)"))
        // 指が取り消されたら後始末・長押しは指が触れている間だけ
        XCTAssertTrue(view.contains(".onChange(of: touchActive) { _, active in touchActivityChanged(active) }"))
        XCTAssertTrue(view.contains("guard !Task.isCancelled, touchActive, var t = touch"))
        // 拡大の段: 当たり 44・字は JPFont.mono・段ごとの識別子
        XCTAssertTrue(view.contains(".frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)"))
        XCTAssertTrue(view.contains(".accessibilityIdentifier(ComposeControls.zoomIdentifier(preset))"))
        XCTAssertTrue(view.contains("camera.stopObservingSubjectArea()"))
        let camera = try source("Sources/JourneyPhoto/Features/Spots/ComposeCamera.swift")
        // 見張りを外す
        let stopBody = try XCTUnwrap(camera.components(separatedBy: "func stopObservingSubjectArea() {").dropFirst().first?
            .components(separatedBy: "\n    }").first)
        XCTAssertTrue(stopBody.contains("NotificationCenter.default.removeObserver(subjectObserver)"))
        XCTAssertTrue(stopBody.contains("subjectObserver = nil"))
        let deinitBody = try XCTUnwrap(camera.components(separatedBy: "deinit {").dropFirst().first?
            .components(separatedBy: "\n    }").first)
        XCTAssertTrue(deinitBody.contains("NotificationCenter.default.removeObserver(subjectObserver)"))
        // 流し始める前に 1× の倍率（開いた瞬間に 0.5× を見せない）
        let configure = try XCTUnwrap(camera.components(separatedBy: "session.addOutput(output)").dropFirst().first)
        let beforeRun = try XCTUnwrap(configure.components(separatedBy: "session.startRunning()").first)
        XCTAssertTrue(beforeRun.contains("device.videoZoomFactor = CGFloat(Self.levels(for: device).factor(display: 1))"))
    }

    @MainActor
    func testObserverCanBeRemoved() async {
        let camera = ComposeCamera()
        camera.stopObservingSubjectArea()
        XCTAssertFalse(camera.isObservingSubjectArea)
    }

    // MARK: - 画面の作り（文字で見張る）

    func testScreenWiresRotateHideAndCameraControls() throws {
        let view = try source("Sources/JourneyPhoto/Features/Spots/ComposeGuideView.swift")
        // 回す: 90° のボタン（読み上げ・英語も）と 2本指のひねり。線にも参考写真にも同じ角度
        XCTAssertTrue(view.contains(#"L("構図を右に90度回す", "Rotate the guide 90° right")"#))
        XCTAssertTrue(view.contains("composeGuide.rotate"))
        XCTAssertTrue(view.contains("RotateGesture()"))
        XCTAssertTrue(view.contains("rotationDegrees: shownRotation"))
        XCTAssertTrue(view.contains("rotatedReference("))
        // 隠す: ボタン、隠している間は上下の帯を出さない、タップで戻す、写真の指を止める
        XCTAssertTrue(view.contains("composeGuide.hideUI"))
        XCTAssertTrue(view.contains("if !uiHidden { topBar }"))
        XCTAssertTrue(view.contains("if !uiHidden { controls }"))
        XCTAssertTrue(view.contains("if uiHidden {\n                setHidden(false)"))
        XCTAssertTrue(view.contains(".allowsHitTesting(!uiHidden)"))
        // 撮る: 音量ボタン・シャッター・読み上げが同じ入口（撮れるときだけ）
        XCTAssertTrue(view.contains("CaptureButtonInteraction(enabled: canShoot)"))
        XCTAssertTrue(view.contains(".accessibilityAction(.magicTap) { Task { await shootIfReady() } }"))
        XCTAssertTrue(view.contains("Button { Task { await shootIfReady() } }"))
        // ライブラリの写真の指はタップを外へ通す（ピント）
        XCTAssertTrue(view.contains("DragGesture(minimumDistance: 4)"))
        XCTAssertFalse(view.contains(".gesture(DragGesture(minimumDistance: 0)\n                        .updating($dragTranslation)"))
        let camera = try source("Sources/JourneyPhoto/Features/Spots/ComposeCamera.swift")
        XCTAssertTrue(camera.contains("AVCaptureEventInteraction"))
        XCTAssertTrue(camera.contains("guard event.phase == .ended"))
        XCTAssertTrue(camera.contains(".builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera"))
    }

    // MARK: - 開いたときの向き（2026-10-18 owner「縦空くのは嫌」）

    private let frame = ComposeGuide.frameAspect

    func testLandscapeReferenceStartsTurnedNinety() {
        // 横長（4:3・16:9）の作例は縦の枠へ 90° 回して重ねる（拡大・切り取りなしで収まる）
        XCTAssertEqual(ComposeControls.autoRotation(referenceWidth: 4000, referenceHeight: 3000,
                                                    frameAspect: frame, heldQuarterTurns: 0), 90)
        XCTAssertEqual(ComposeControls.autoRotation(referenceWidth: 1920, referenceHeight: 1080,
                                                    frameAspect: frame, heldQuarterTurns: 0), 90)
    }

    func testPortraitAndSquareReferenceStayStraight() {
        XCTAssertEqual(ComposeControls.autoRotation(referenceWidth: 3000, referenceHeight: 4000,
                                                    frameAspect: frame, heldQuarterTurns: 0), 0)
        XCTAssertEqual(ComposeControls.autoRotation(referenceWidth: 1000, referenceHeight: 1000,
                                                    frameAspect: frame, heldQuarterTurns: 0), 0)
        // ほぼ正方形（差 2% 未満）も回さない
        XCTAssertEqual(ComposeControls.autoRotation(referenceWidth: 1010, referenceHeight: 1000,
                                                    frameAspect: frame, heldQuarterTurns: 0), 0)
        // 枠が横長なら回さない・壊れた大きさは 0
        XCTAssertEqual(ComposeControls.autoRotation(referenceWidth: 4000, referenceHeight: 3000,
                                                    frameAspect: 4.0 / 3, heldQuarterTurns: 0), 0)
        XCTAssertEqual(ComposeControls.autoRotation(referenceWidth: 0, referenceHeight: 3000,
                                                    frameAspect: frame, heldQuarterTurns: 0), 0)
        XCTAssertEqual(ComposeControls.autoRotation(referenceWidth: .nan, referenceHeight: 3000,
                                                    frameAspect: frame, heldQuarterTurns: 0), 0)
    }

    func testAutoRotationFollowsHeldLandscapeSide() {
        // 既定（縦持ち・平置き・逆さま・左へ倒した横持ち）は 90°。上を右へ倒した横持ちだけ 270°
        for held in [0, 2, 3, -1] {
            XCTAssertEqual(ComposeControls.autoRotation(referenceWidth: 4, referenceHeight: 3,
                                                        frameAspect: frame, heldQuarterTurns: held), 90, "held \(held)")
        }
        XCTAssertEqual(ComposeControls.autoRotation(referenceWidth: 4, referenceHeight: 3,
                                                    frameAspect: frame, heldQuarterTurns: 1), 270)
        XCTAssertEqual(ComposeControls.autoRotation(referenceWidth: 4, referenceHeight: 3,
                                                    frameAspect: frame, heldQuarterTurns: 5), 270)
    }

    func testMirroredReferenceKeepsSameTurn() {
        // 左右反転は上下を変えないので、回す向きも同じ
        for held in 0..<4 {
            XCTAssertEqual(
                ComposeControls.autoRotation(referenceWidth: 4, referenceHeight: 3, frameAspect: frame,
                                             heldQuarterTurns: held, mirrored: true),
                ComposeControls.autoRotation(referenceWidth: 4, referenceHeight: 3, frameAspect: frame,
                                             heldQuarterTurns: held, mirrored: false))
        }
        XCTAssertEqual(ComposeControls.autoRotation(referenceWidth: 3, referenceHeight: 4, frameAspect: frame,
                                                    heldQuarterTurns: 0, mirrored: true), 0)
    }

    func testOpeningUsesAutoOverRememberedWhenReferenceShown() {
        // 作例があれば、覚えた角度（前の写真のための向き）より自動の向き
        XCTAssertEqual(ComposeControls.decidedRotation(.opened, current: 0, manual: false, auto: 90, remembered: 180), 90)
        XCTAssertEqual(ComposeControls.decidedRotation(.opened, current: 0, manual: false, auto: 0, remembered: 270), 0)
        // 作例なしの入口は今まで通り覚えた角度
        XCTAssertEqual(ComposeControls.decidedRotation(.opened, current: 0, manual: false, auto: nil, remembered: 270), 270)
    }

    func testReferenceChangeRedecidesEvenAfterManualTurn() {
        // 横長 → 縦長へ選び直したら 0°（人が回していても作例が変われば自動へ）
        XCTAssertEqual(ComposeControls.decidedRotation(.referenceChanged, current: 90, manual: true, auto: 0, remembered: 90), 0)
        // 縦長 → 横長へ選び直したら 90°
        XCTAssertEqual(ComposeControls.decidedRotation(.referenceChanged, current: 0, manual: false, auto: 90, remembered: 0), 90)
        // 累積のまま短く回る（360° から 90° へは 450°）
        XCTAssertEqual(ComposeControls.decidedRotation(.referenceChanged, current: 360, manual: false, auto: 90, remembered: 0), 450)
        // 参考写真が無くなった（ライブラリを選ぶ前）は今のまま
        XCTAssertNil(ComposeControls.decidedRotation(.referenceChanged, current: 90, manual: false, auto: nil, remembered: 0))
    }

    func testCompositionChosenReturnsToInitialTurn() {
        // 構図を選び直したら、横長の作例なら 90°、無ければ真っ直ぐ（以前の動き）
        XCTAssertEqual(ComposeControls.decidedRotation(.compositionChosen, current: 180, manual: true, auto: 90, remembered: 0), 90)
        XCTAssertEqual(ComposeControls.decidedRotation(.compositionChosen, current: 450, manual: true, auto: nil, remembered: 90), 360)
        XCTAssertEqual(ComposeControls.decidedRotation(.compositionChosen, current: 90, manual: false, auto: 0, remembered: 0), 0)
    }

    func testHeldTurnRespectsManualTurn() {
        // 人が回した向きは、持ち替えても回し直さない
        XCTAssertNil(ComposeControls.decidedRotation(.heldTurned, current: 0, manual: true, auto: 270, remembered: 0))
        // 自動のままなら写真が立つ側へ（90° → 270° は +180°）
        XCTAssertEqual(ComposeControls.decidedRotation(.heldTurned, current: 90, manual: false, auto: 270, remembered: 0,
                                                       held: 1), 270)
        XCTAssertNil(ComposeControls.decidedRotation(.heldTurned, current: 90, manual: false, auto: nil, remembered: 0))
    }

    func testNearestCumulative() {
        XCTAssertEqual(ComposeControls.nearestCumulative(to: 0, from: 450), 360)
        XCTAssertEqual(ComposeControls.nearestCumulative(to: 270, from: 0), -90)
        XCTAssertEqual(ComposeControls.nearestCumulative(to: 90, from: -90), 90)
        XCTAssertEqual(ComposeControls.nearestCumulative(to: 90, from: .nan), 90)
    }

    func testViewUsesAutoRotation() throws {
        // 画面が決め直しをつないでいること（開いたとき・参考写真が替わった・構図を選び直した・持ち替えた）
        let view = try source("Sources/JourneyPhoto/Features/Spots/ComposeGuideView.swift")
        XCTAssertTrue(view.contains(".opened, current: 0, manual: false, auto: auto"))
        XCTAssertTrue(view.contains(".onChange(of: referenceIdentity) { _, _ in applyAutoRotation(.referenceChanged) }"))
        XCTAssertTrue(view.contains(".onChange(of: quarterTurns) { _, _ in applyAutoRotation(.heldTurned) }"))
        XCTAssertTrue(view.contains("applyAutoRotation(.compositionChosen, animated: false)"))
        XCTAssertFalse(view.contains("rotation = ComposeControls.straightened(rotation)"))
    }

    // MARK: - 横持ちの線と作例（2026-10-18）

    func testLinesFollowReferenceWhileShown() {
        XCTAssertEqual(ComposeControls.linesQuarterTurns(held: 3, kind: .goldenSpiral, referenceShown: true), 0)
        XCTAssertEqual(ComposeControls.linesQuarterTurns(held: 1, kind: .thirds, referenceShown: true), 0)
        // 線だけのときは今まで通り持った向き
        XCTAssertEqual(ComposeControls.linesQuarterTurns(held: 3, kind: .goldenSpiral, referenceShown: false), 3)
        // 水準器はいつも持った向き
        XCTAssertEqual(ComposeControls.linesQuarterTurns(held: 3, kind: .level, referenceShown: true), 3)
    }

    func testLandscapeHoldKeepsLinesOnTheTurnedReference() {
        // 横長の作例を 90° 回して開き、端末を左へ倒して（持った向き 3）横に持つ
        let kind = CompositionKind.goldenSpiral
        let turns = Int(ComposeControls.autoRotation(referenceWidth: 4, referenceHeight: 3,
                                                     frameAspect: portrait, heldQuarterTurns: 3) / 90)
        XCTAssertEqual(turns, 1)
        func lines(held: Int) -> [GuideMark] {
            CompositionGuide.screenMarks(kind, variant: 0, aspect: portrait,
                                         quarterTurns: ComposeControls.linesQuarterTurns(
                                            held: held, kind: kind, referenceShown: true),
                                         levelDegrees: 0, rotationQuarters: turns)
        }
        // 作例は画面に貼り付いているので、持ち替えても線は動かない（作例とずれない）
        XCTAssertEqual(lines(held: 3), lines(held: 0))
        // 横に持った人から見て、線は横の写真の向きで立つ（回していない横持ちの線と同じ）
        XCTAssertEqual(lines(held: 3), CompositionGuide.screenMarks(kind, variant: 0, aspect: portrait,
                                                                    quarterTurns: 3, levelDegrees: 0))
        // 以前の作り（持った向きのぶんも回す）では、作例から 90° ずれていた
        XCTAssertNotEqual(lines(held: 3), CompositionGuide.screenMarks(kind, variant: 0, aspect: portrait,
                                                                       quarterTurns: 3, levelDegrees: 0,
                                                                       rotationQuarters: turns))
    }

    func testViewPassesLinesQuarterTurns() throws {
        let view = try source("Sources/JourneyPhoto/Features/Spots/ComposeGuideView.swift")
        XCTAssertTrue(view.contains("quarterTurns: ComposeControls.linesQuarterTurns("))
    }

    // MARK: - 見直しの指摘（2026-10-18）

    func testBackToPortraitKeepsSidewaysTurn() {
        // 時計回りの横持ち（270°）から縦持ち・逆さまに戻しても、作例を 180° ひっくり返さない
        for held in [0, 2] {
            XCTAssertNil(ComposeControls.decidedRotation(.heldTurned, current: 270, manual: false, auto: 90,
                                                         remembered: 0, held: held), "held \(held)")
            XCTAssertNil(ComposeControls.decidedRotation(.heldTurned, current: -90, manual: false, auto: 90,
                                                         remembered: 0, held: held), "held \(held)")
            XCTAssertNil(ComposeControls.decidedRotation(.heldTurned, current: 90, manual: false, auto: 90,
                                                         remembered: 0, held: held), "held \(held)")
        }
        // 逆の横持ちへ替えたときは、写真が立つ側へ回し直す
        XCTAssertEqual(ComposeControls.decidedRotation(.heldTurned, current: 270, manual: false, auto: 90,
                                                       remembered: 0, held: 3), 450)
        // 真っ直ぐ（0°）のときは今まで通り自動の向きへ
        XCTAssertEqual(ComposeControls.decidedRotation(.heldTurned, current: 0, manual: false, auto: 90,
                                                       remembered: 0, held: 0), 90)
    }

    func testOpeningHeldTurnIsNotAnimated() {
        XCTAssertFalse(ComposeControls.animatesHeldTurn(secondsSinceAppear: 0))
        XCTAssertFalse(ComposeControls.animatesHeldTurn(secondsSinceAppear: 0.3))
        XCTAssertTrue(ComposeControls.animatesHeldTurn(secondsSinceAppear: ComposeControls.openingSettle))
        XCTAssertTrue(ComposeControls.animatesHeldTurn(secondsSinceAppear: 5))
        let view = try? source("Sources/JourneyPhoto/Features/Spots/ComposeGuideView.swift")
        XCTAssertTrue(view?.contains("if reduceMotion || !animated || settling {") ?? false)
    }

    func testHidingReferenceKeepsLineTurn() throws {
        // 作例を隠しているだけのときは、線の向きを作例に合わせたまま（隠すたびに 90° 回らない）
        let view = try source("Sources/JourneyPhoto/Features/Spots/ComposeGuideView.swift")
        XCTAssertTrue(view.contains("held: quarterTurns, kind: composition, referenceShown: hasReference)"))
        // hasReference は「隠しているか」を含まない
        let start = try XCTUnwrap(view.range(of: "private var hasReference: Bool {"))
        let body = view[start.upperBound...].prefix(while: { $0 != "}" })
        XCTAssertFalse(body.contains("hidden"))
        // 隠している間（線の向きは hasReference で決まる）と出している間で、線が同じ
        let kind = CompositionKind.goldenSpiral
        let shown = ComposeControls.linesQuarterTurns(held: 3, kind: kind, referenceShown: true)
        let hiddenButPresent = ComposeControls.linesQuarterTurns(held: 3, kind: kind, referenceShown: true)
        XCTAssertEqual(CompositionGuide.screenMarks(kind, variant: 0, aspect: portrait, quarterTurns: shown,
                                                    levelDegrees: 0, rotationQuarters: 1),
                       CompositionGuide.screenMarks(kind, variant: 0, aspect: portrait, quarterTurns: hiddenButPresent,
                                                    levelDegrees: 0, rotationQuarters: 1))
    }
}
