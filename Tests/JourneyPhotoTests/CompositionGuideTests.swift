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
        XCTAssertEqual(CompositionKind.goldenSpiral.variantCount, 8)
        XCTAssertEqual(CompositionKind.fibonacciGrid.variantCount, 8)
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

    func testSpiralEyeAndSquaresConverge() {
        // 横長（4番＝変換なし）の渦は (0.7236, 0.2764)
        let eye = CompositionGuide.spiralEye(variant: 4)
        XCTAssertEqual(eye.x, 0.7236, accuracy: 0.0001)
        XCTAssertEqual(eye.y, 0.2764, accuracy: 0.0001)
        // 弧の中心は渦へ近づく（最後の正方形の弧の中心が渦のすぐそば）
        let last = CompositionGuide.spiralSquares().last!
        XCTAssertEqual(last.arcCenter.x, eye.x, accuracy: 0.02)
        XCTAssertEqual(last.arcCenter.y, eye.y, accuracy: 0.02)
        // 8通りの渦はどれも別の位置で、0〜1 の内
        let eyes = (0..<8).map { CompositionGuide.spiralEye(variant: $0) }
        for e in eyes { XCTAssertTrue((0...1).contains(e.x) && (0...1).contains(e.y)) }
        let distinct = Set(eyes.map { "\(($0.x * 1000).rounded()),\(($0.y * 1000).rounded())" })
        XCTAssertEqual(distinct.count, 4, "縦長・横長で同じ角に来るので位置は 4 か所")
    }

    func testSpiralArcsAreContinuous() {
        // 1つの弧の終わりが次の弧の始まり（線が途切れない）
        for v in 0..<8 {
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
        XCTAssertEqual(segments(CompositionGuide.marks(.armature, variant: 0, aspect: portrait)).count, 14)
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
        prefs.setVariant(6, for: .goldenSpiral)
        XCTAssertEqual(prefs.variant(for: .goldenSpiral), 6)
        prefs.setVariant(99, for: .radial)
        XCTAssertEqual(prefs.variant(for: .radial), 4)
        prefs.setLineOpacity(2)
        XCTAssertEqual(prefs.lineOpacity, 0.7)
        // 知らない名前（構図を減らした版の残り）は既定へ
        defaults.set("removed-kind", forKey: "journey-photo-composition-last")
        XCTAssertEqual(prefs.lastKind, .thirds)
    }
}
