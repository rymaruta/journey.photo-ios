import XCTest
@testable import JourneyPhoto

/// 「構図を重ねて撮る」（Pro・2026-10-10）の線の計算（`CompositionGuide`）と、端末に覚える値
/// （`CompositionPreferences`）。
final class CompositionGuideTests: XCTestCase {

    private let portrait = 0.75   // 3:4（縦持ちの撮れる範囲）
    private let landscape = 4.0 / 3

    private func segments(_ marks: [GuideMark]) -> [(GuidePoint, GuidePoint)] {
        marks.compactMap { if case .segment(let a, let b) = $0.shape { return (a, b) } else { return nil } }
    }

    // MARK: - 一覧

    func testThirtySevenKindsInSixSections() {
        XCTAssertEqual(CompositionKind.allCases.count, 37)
        XCTAssertEqual(CompositionSection.allCases.map { $0.kinds.count }, [9, 4, 7, 9, 5, 3])
        // 名前はどれも日本語・英語の両方がある
        for kind in CompositionKind.allCases {
            XCTAssertFalse(kind.japaneseName.isEmpty)
            XCTAssertFalse(kind.englishName.isEmpty)
            XCTAssertFalse(kind.tip.isEmpty)
        }
        XCTAssertEqual(CompositionKind.defaultKind, .thirds)
    }

    func testVariantCountsMatchDesign() {
        // 縦長の4通りだけ（横長は 3:4 で潰れて楕円になるので外した・2026-10-10）
        XCTAssertEqual(CompositionKind.goldenSpiral.variantCount, 4)
        XCTAssertEqual(CompositionKind.fibonacciGrid.variantCount, 4)
        XCTAssertEqual(CompositionKind.goldenTriangle.variantCount, 2)
        XCTAssertEqual(CompositionKind.radial.variantCount, 5)
        XCTAssertEqual(CompositionKind.negativeSpace.variantCount, 4)
        XCTAssertEqual(CompositionKind.lShape.variantCount, 4)
        XCTAssertEqual(CompositionKind.zShape.variantCount, 2)
        XCTAssertEqual(CompositionKind.diagonals.variantCount, 3)
        XCTAssertEqual(CompositionKind.otherRatios.variantCount, 4)
        XCTAssertFalse(CompositionKind.thirds.hasVariants)
        // 向きの名前は重ならない（読み上げで聞き分けられる）
        for kind in CompositionKind.allCases where kind.hasVariants {
            let names = (0..<kind.variantCount).map { kind.variantName($0) }
            XCTAssertEqual(Set(names).count, names.count, "\(kind) の向きの名前が重なる: \(names)")
        }
        XCTAssertEqual(CompositionKind.radial.nextVariant(after: 4), 0)
    }

    // MARK: - 定番

    func testThirdsAndPhiGridPositions() {
        let thirds = segments(CompositionGuide.marks(.thirds, variant: 0, aspect: portrait))
        XCTAssertEqual(thirds.count, 4)
        XCTAssertTrue(thirds.contains { abs($0.0.x - 1.0 / 3) < 1e-9 && $0.0.x == $0.1.x })
        let phi = segments(CompositionGuide.marks(.phiGrid, variant: 0, aspect: portrait))
        let xs = phi.filter { $0.0.x == $0.1.x }.map { $0.0.x }.sorted()
        XCTAssertEqual(xs.count, 2)
        XCTAssertEqual(xs[0], 0.382, accuracy: 0.001)
        XCTAssertEqual(xs[1], 0.618, accuracy: 0.001)
    }

    func testSquareGridMakesSquaresInPixels() {
        // 3:4: 縦は 1/6 ごと、横は 0.75/6 = 0.125 ごと（ピクセルの上で正方形）
        let lines = segments(CompositionGuide.marks(.squareGrid, variant: 0, aspect: portrait))
        let ys = lines.filter { $0.0.y == $0.1.y }.map { $0.0.y }.sorted()
        XCTAssertEqual(ys.count, 7)
        XCTAssertEqual(ys[0], 0.125, accuracy: 1e-9)
    }

    func testHinomaruIsARoundCircleOfAThirdOfTheShortSide() {
        let marks = CompositionGuide.marks(.hinomaru, variant: 0, aspect: portrait)
        guard case .ellipse(let rect)? = marks.first?.shape else { return XCTFail("円が無い") }
        // ピクセルの上: 幅 = rect.width × 0.75、高さ = rect.height × 1 が同じで、短辺 0.75 の 1/3
        XCTAssertEqual(rect.width * portrait, rect.height, accuracy: 1e-9)
        XCTAssertEqual(rect.height, portrait / 3, accuracy: 1e-9)
    }

    // MARK: - 黄金比

    func testGoldenTriangleFootAtThreeByFour() {
        let feet = CompositionGuide.goldenTriangleFeet(variant: 0, aspect: portrait)
        XCTAssertEqual(feet[0].x, 0.64, accuracy: 1e-9)
        XCTAssertEqual(feet[0].y, 0.36, accuracy: 1e-9)
        // 垂線は本当に直角（ピクセルの上で、左上→足 と 対角線 の内積が 0）
        let d = (portrait, -1.0)
        let v = (feet[0].x * portrait, feet[0].y)
        XCTAssertEqual(v.0 * d.0 + v.1 * d.1, 0, accuracy: 1e-9)
    }

    func testFallingGoldenTriangleFeetByHand() {
        // 右下がり（左上→右下の対角線）。手計算（幅 0.75・高さ 1 の面）:
        // 右上 (0.75, 0) から下ろした足 = t·(0.75, 1)、t = 0.75² / (1 + 0.75²) = 0.36 → (0.27, 0.36) → 0〜1 で (0.36, 0.36)
        // 左下 (0, 1) から下ろした足 = t·(0.75, 1)、t = 1 / (1 + 0.75²) = 0.64 → (0.48, 0.64) → 0〜1 で (0.64, 0.64)
        let feet = CompositionGuide.goldenTriangleFeet(variant: 1, aspect: portrait)
        XCTAssertEqual(feet[0].x, 0.36, accuracy: 1e-9)
        XCTAssertEqual(feet[0].y, 0.36, accuracy: 1e-9)
        XCTAssertEqual(feet[1].x, 0.64, accuracy: 1e-9)
        XCTAssertEqual(feet[1].y, 0.64, accuracy: 1e-9)
        // 線もその足へ引いている（右上→足・左下→足）
        let lines = segments(CompositionGuide.marks(.goldenTriangle, variant: 1, aspect: portrait))
        XCTAssertTrue(lines.contains { $0.0 == GuidePoint(x: 1, y: 0) && abs($0.1.x - 0.36) < 1e-9 && abs($0.1.y - 0.36) < 1e-9 })
        XCTAssertTrue(lines.contains { $0.0 == GuidePoint(x: 0, y: 1) && abs($0.1.x - 0.64) < 1e-9 && abs($0.1.y - 0.64) < 1e-9 })
    }

    func testSpiralEyeAndSquaresConverge() {
        // 渦（縦長・上下左右とも反転＝3番）は (0.7236, 0.2764)、反転なし（0番）は (0.2764, 0.7236)
        let eye = CompositionGuide.spiralEye(variant: 3)
        XCTAssertEqual(eye.x, 0.7236, accuracy: 0.0001)
        XCTAssertEqual(eye.y, 0.2764, accuracy: 0.0001)
        let eye0 = CompositionGuide.spiralEye(variant: 0)
        XCTAssertEqual(eye0.x, 0.2764, accuracy: 0.0001)
        XCTAssertEqual(eye0.y, 0.7236, accuracy: 0.0001)
        // 弧の中心は渦へ近づく（変換前の横長の長方形で、最後の正方形の弧の中心が渦のすぐそば）
        let last = CompositionGuide.spiralSquares().last!
        XCTAssertEqual(last.arcCenter.x, 0.7236, accuracy: 0.02)
        XCTAssertEqual(last.arcCenter.y, 0.2764, accuracy: 0.02)
        // 4通りの渦はどれも別の角で、0〜1 の内
        let eyes = (0..<4).map { CompositionGuide.spiralEye(variant: $0) }
        for e in eyes { XCTAssertTrue((0...1).contains(e.x) && (0...1).contains(e.y)) }
        let distinct = Set(eyes.map { "\(($0.x * 1000).rounded()),\(($0.y * 1000).rounded())" })
        XCTAssertEqual(distinct.count, 4)
    }

    func testSpiralArcsAreContinuous() {
        // 1つの弧の終わりが次の弧の始まり（線が途切れない）
        for v in 0..<4 {
            let arcs = CompositionGuide.marks(.goldenSpiral, variant: v, aspect: portrait)
            XCTAssertEqual(arcs.count, CompositionGuide.spiralSteps)
            for (a, b) in zip(arcs, arcs.dropFirst()) {
                let end = a.samplePoints.last!, start = b.samplePoints.first!
                XCTAssertEqual(end.x, start.x, accuracy: 1e-6, "向き \(v)")
                XCTAssertEqual(end.y, start.y, accuracy: 1e-6, "向き \(v)")
            }
        }
    }

    // MARK: - 対角・幾何

    func testDynamicSymmetryReciprocalHitsTheRightEdge() {
        // 3:4: 左上からの逆対角は右端 y = 0.5625、4:3: 下端 x = 0.5625
        let p = segments(CompositionGuide.marks(.dynamicSymmetry, variant: 0, aspect: portrait))
        let fromTopLeft = p.first { $0.0 == GuidePoint(x: 0, y: 0) && $0.1.x == 1 && $0.1.y < 1 }
        XCTAssertNotNil(fromTopLeft)
        XCTAssertEqual(fromTopLeft?.1.y ?? 0, 0.5625, accuracy: 1e-9)
        let l = segments(CompositionGuide.marks(.dynamicSymmetry, variant: 0, aspect: landscape))
        let down = l.first { $0.0 == GuidePoint(x: 0, y: 0) && $0.1.y == 1 && $0.1.x < 1 }
        XCTAssertNotNil(down)
        XCTAssertEqual(down?.1.x ?? 0, 0.5625, accuracy: 1e-9)
        XCTAssertEqual(p.count, 6, "対角 2 ＋ 逆対角 4")
    }

    func testArmatureHasFourteenLines() {
        let lines = segments(CompositionGuide.marks(.armature, variant: 0, aspect: portrait))
        XCTAssertEqual(lines.count, 14)
        // 手計算: 各角から、その角に触れない2辺の中点へ（8本）
        let expected: [(Double, Double, Double, Double)] = [
            (0, 0, 1, 0.5), (0, 0, 0.5, 1),     // 左上 → 右辺の中点・下辺の中点
            (1, 0, 0, 0.5), (1, 0, 0.5, 1),     // 右上 → 左辺・下辺
            (0, 1, 1, 0.5), (0, 1, 0.5, 0),     // 左下 → 右辺・上辺
            (1, 1, 0, 0.5), (1, 1, 0.5, 0),     // 右下 → 左辺・上辺
        ]
        for e in expected {
            XCTAssertTrue(lines.contains { $0.0 == GuidePoint(x: e.0, y: e.1) && $0.1 == GuidePoint(x: e.2, y: e.3) },
                          "角 (\(e.0), \(e.1)) → 中点 (\(e.2), \(e.3)) が無い")
        }
    }

    func testDiagonal45IsFortyFiveDegreesInPixels() {
        for seg in segments(CompositionGuide.marks(.diagonal45, variant: 0, aspect: portrait)) {
            let dx = (seg.1.x - seg.0.x) * portrait, dy = seg.1.y - seg.0.y
            XCTAssertEqual(abs(dx), abs(dy), accuracy: 1e-9)
        }
    }

    // MARK: - 比率の枠

    func testCropRects() {
        let square = CompositionGuide.cropRect(.square, variant: 0, aspect: portrait)!
        XCTAssertEqual(square.width, 1, accuracy: 1e-9)
        XCTAssertEqual(square.height, 0.75, accuracy: 1e-9)
        XCTAssertEqual(square.y, 0.125, accuracy: 1e-9)
        // 9:16 は 3:4 の枠より細い。高さいっぱいで、幅はピクセルの上で 9:16（0.5625 ÷ 0.75 = 0.75）
        let story = CompositionGuide.cropRect(.ratio9x16, variant: 0, aspect: portrait)!
        XCTAssertEqual(story.height, 1, accuracy: 1e-9)
        XCTAssertEqual(story.width * portrait / story.height, 9.0 / 16, accuracy: 1e-9)
        // 正方形の枠（1:1）の中なら 9:16 は 幅 0.5625・高さ 1
        let inSquare = CompositionGuide.cropRect(.ratio9x16, variant: 0, aspect: 1)!
        XCTAssertEqual(inSquare.width, 0.5625, accuracy: 1e-9)
        XCTAssertNil(CompositionGuide.cropRect(.thirds, variant: 0, aspect: portrait))
        // 比率の枠は外を暗くする
        XCTAssertTrue(CompositionGuide.marks(.ratio16x9, variant: 0, aspect: portrait).contains {
            if case .dimOutside = $0.shape { return true } else { return false }
        })
    }

    // MARK: - 形の段は破線

    func testShapeSectionIsDashed() {
        for kind in CompositionSection.shape.kinds {
            let lines = CompositionGuide.marks(kind, variant: 0, aspect: portrait).filter { !$0.isFill }
            XCTAssertFalse(lines.isEmpty)
            XCTAssertTrue(lines.allSatisfy(\.dashed), "\(kind) が破線でない")
        }
        XCTAssertFalse(CompositionGuide.marks(.thirds, variant: 0, aspect: portrait).contains(where: \.dashed))
    }

    // MARK: - 全部の構図・全部の向きで、数でない値が無く範囲の内

    func testEveryKindAndVariantStaysInsideTheFrame() {
        for aspect in [portrait, landscape, 1, 9.0 / 16, 0.0, .nan] {
            for kind in CompositionKind.allCases {
                for v in -1...kind.variantCount {
                    let marks = CompositionGuide.marks(kind, variant: v, aspect: aspect)
                    XCTAssertFalse(marks.isEmpty, "\(kind) \(v)")
                    for mark in marks {
                        for p in mark.samplePoints {
                            XCTAssertTrue(p.x.isFinite && p.y.isFinite, "\(kind) \(v) \(aspect)")
                            XCTAssertTrue((-1e-9...1 + 1e-9).contains(p.x) && (-1e-9...1 + 1e-9).contains(p.y),
                                          "\(kind) 向き \(v) 比 \(aspect): \(p)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - 水準器

    func testLevel() {
        XCTAssertEqual(CompositionGuide.levelAngle(gravityX: 0, gravityY: -1) ?? 99, 0, accuracy: 1e-9)
        // 右へ 10° 傾けると、画面の上の水平線は反時計回り（負）
        let t = 10 * Double.pi / 180
        XCTAssertEqual(CompositionGuide.levelAngle(gravityX: sin(t), gravityY: -cos(t)) ?? 0, -10, accuracy: 1e-9)
        XCTAssertNil(CompositionGuide.levelAngle(gravityX: 0, gravityY: 0), "平らに置いたら向きが決まらない")
        XCTAssertTrue(CompositionGuide.isLevel(0.5))
        XCTAssertTrue(CompositionGuide.isLevel(-89.4))
        XCTAssertFalse(CompositionGuide.isLevel(3))
        XCTAssertTrue(CompositionGuide.levelMarks(aspect: portrait, degrees: 0.2)[0].bold)
        XCTAssertFalse(CompositionGuide.levelMarks(aspect: portrait, degrees: 5)[0].bold)
    }

    // MARK: - 横持ち・水準器の描き直し

    func testQuarterTurnsFromTheLevelAngle() {
        XCTAssertEqual(CompositionGuide.quarterTurns(levelDegrees: 0, previous: 0), 0)
        // 上を右に向けた横持ち（時計回りに 90°）→ 画面の上の水平線は -90°
        XCTAssertEqual(CompositionGuide.quarterTurns(levelDegrees: -88, previous: 0), 1)
        XCTAssertEqual(CompositionGuide.quarterTurns(levelDegrees: 90, previous: 0), 3)
        XCTAssertEqual(CompositionGuide.quarterTurns(levelDegrees: 179, previous: 0), 2)
        // 斜め（境目の近く）・平らに置いた → 前のまま
        XCTAssertEqual(CompositionGuide.quarterTurns(levelDegrees: -45, previous: 1), 1)
        XCTAssertEqual(CompositionGuide.quarterTurns(levelDegrees: nil, previous: 3), 3)
    }

    func testLandscapeRotatesTheLinesToThePhoto() {
        // 縦持ちは今までどおり
        XCTAssertEqual(CompositionGuide.screenMarks(.horizon, variant: 0, aspect: portrait, quarterTurns: 0, levelDegrees: 0),
                       CompositionGuide.marks(.horizon, variant: 0, aspect: portrait))
        // 横持ち（1）: 写真の水平線 y = 2/3（下寄り）は、画面では縦の線 x = 2/3（写真の下＝画面の右）
        let horizon = segments(CompositionGuide.screenMarks(.horizon, variant: 0, aspect: portrait,
                                                            quarterTurns: 1, levelDegrees: -90))
        XCTAssertEqual(horizon.count, 1)
        XCTAssertEqual(horizon[0].0.x, 2.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(horizon[0].1.x, 2.0 / 3, accuracy: 1e-9)
        // 1:1 の枠は写真（4:3）の中で計算する。画面の上では 幅 1・高さ 0.75
        let dim = CompositionGuide.screenMarks(.square, variant: 0, aspect: portrait, quarterTurns: 1, levelDegrees: -90)
        guard case .dimOutside(let crop)? = dim.first?.shape else { return XCTFail("暗がりが無い") }
        XCTAssertEqual(crop.width, 1, accuracy: 1e-9)
        XCTAssertEqual(crop.height, 0.75, accuracy: 1e-9)
        // 水準器: 横持ちで 0.5° 傾き → 太い（水平に近い）・線は画面の上でほぼ縦
        let level = CompositionGuide.screenMarks(.level, variant: 0, aspect: portrait, quarterTurns: 1, levelDegrees: -90.5)
        XCTAssertTrue(level[0].bold)
        guard case .segment(let a, let b) = level[0].shape else { return XCTFail() }
        XCTAssertLessThan(abs((b.x - a.x) * portrait), abs(b.y - a.y) * 0.05)
        // 全種類・全向き・横持ちでも範囲の内
        for q in 0..<4 {
            for kind in CompositionKind.allCases {
                for v in 0..<kind.variantCount {
                    for p in CompositionGuide.screenMarks(kind, variant: v, aspect: portrait, quarterTurns: q,
                                                           levelDegrees: Double(q) * -90).flatMap(\.samplePoints) {
                        XCTAssertTrue((-1e-9...1 + 1e-9).contains(p.x) && (-1e-9...1 + 1e-9).contains(p.y), "\(kind) \(v) \(q)")
                    }
                }
            }
        }
    }

    func testLevelIgnoresTinyChanges() {
        XCTAssertTrue(CompositionGuide.levelNeedsUpdate(from: nil, to: 0.02))
        XCTAssertFalse(CompositionGuide.levelNeedsUpdate(from: 1.0, to: 1.05))
        XCTAssertTrue(CompositionGuide.levelNeedsUpdate(from: 1.0, to: 1.1))
        XCTAssertFalse(CompositionGuide.levelNeedsUpdate(from: 1.0, to: .nan))
    }

    // MARK: - 最近・覚える値

    func testRecentsDeduplicateAndKeepFour() {
        var list: [CompositionKind] = []
        for kind in [CompositionKind.thirds, .goldenSpiral, .thirds, .armature, .square, .level, .tunnel] {
            list = CompositionGuide.recents(adding: kind, to: list)
        }
        XCTAssertEqual(list, [.tunnel, .level, .square, .armature])
        XCTAssertEqual(CompositionGuide.recents(adding: .square, to: list), [.square, .tunnel, .level, .armature])
    }

    func testPreferencesRememberChoices() {
        let suite = "CompositionGuideTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = CompositionPreferences(defaults: defaults)
        // 何も選んでいなければ三分割・濃さは既定
        XCTAssertEqual(prefs.lastKind, .thirds)
        XCTAssertEqual(prefs.lineOpacity, CompositionGuide.defaultLineOpacity)
        prefs.select(.goldenSpiral)
        prefs.select(.armature)
        prefs.select(.goldenSpiral)
        XCTAssertEqual(prefs.lastKind, .goldenSpiral)
        XCTAssertEqual(prefs.recents, [.goldenSpiral, .armature])
        // 「なし」は覚えるが、最近には足さない
        prefs.select(nil)
        XCTAssertNil(prefs.lastKind)
        XCTAssertEqual(prefs.recents, [.goldenSpiral, .armature])
        prefs.setVariant(2, for: .goldenSpiral)
        XCTAssertEqual(prefs.variant(for: .goldenSpiral), 2)
        // 前の版で覚えた横長の向き（4〜7）は範囲の内へ丸める
        defaults.set(["goldenSpiral": 6], forKey: "journey-photo-composition-variants")
        XCTAssertEqual(prefs.variant(for: .goldenSpiral), 3)
        prefs.setVariant(99, for: .radial)
        XCTAssertEqual(prefs.variant(for: .radial), 4)
        prefs.setLineOpacity(2)
        XCTAssertEqual(prefs.lineOpacity, 0.7)
        // 知らない名前（構図を減らした版の残り）は既定へ
        defaults.set("removed-kind", forKey: "journey-photo-composition-last")
        XCTAssertEqual(prefs.lastKind, .thirds)
    }
}
