import XCTest
@testable import JourneyPhoto

/// 手に取って運ぶ（2026-11-12・札 #543・`PhotoLift`）と、つまむと地図（`PinchToMap`）。
final class PhotoLiftTests: XCTestCase {

    private let w = 390.0, h = 844.0

    // MARK: - 行き先（上の帯・右の半円・下の顔の段）

    func testTargets() {
        XCTAssertEqual(PhotoLift.target(x: 200, y: 60, width: w, height: h, faces: 4, allowsStory: true), .story, "上の帯")
        // 右の半円の中心は右の縁・高さ 430（章の模型）。中心から 100pt 左は中
        XCTAssertEqual(PhotoLift.target(x: 300, y: 430, width: w, height: h, faces: 4, allowsStory: true), .save, "右の半円")
        XCTAssertNil(PhotoLift.target(x: 280, y: 430, width: w, height: h, faces: 4, allowsStory: true), "半円の外（110pt 左）で保存した")
        // 下の段は横に4つに割る
        XCTAssertEqual(PhotoLift.target(x: 10, y: 800, width: w, height: h, faces: 4, allowsStory: true), .face(0))
        XCTAssertEqual(PhotoLift.target(x: 389, y: 800, width: w, height: h, faces: 4, allowsStory: true), .face(3))
        XCTAssertNil(PhotoLift.target(x: 100, y: 800, width: w, height: h, faces: 0, allowsStory: true), "顔が無いのに送る先が出た")
        // 真ん中は行き先なし（元に戻る）。左の縁も使わない
        XCTAssertNil(PhotoLift.target(x: 195, y: 430, width: w, height: h, faces: 4, allowsStory: true))
        XCTAssertNil(PhotoLift.target(x: 2, y: 430, width: w, height: h, faces: 4, allowsStory: true), "左の縁（戻るの払い）を行き先にした")
    }

    /// 近づくと吸い付き始める（帯・半円の外側 40pt）
    func testNear() {
        XCTAssertEqual(PhotoLift.near(x: 200, y: 140, width: w, height: h, faces: 4, allowsStory: true), .story)
        XCTAssertNil(PhotoLift.near(x: 200, y: 160, width: w, height: h, faces: 4, allowsStory: true))
        XCTAssertEqual(PhotoLift.near(x: 260, y: 430, width: w, height: h, faces: 4, allowsStory: true), .save)
    }

    // MARK: - 弾く（離す直前 90ms の速さ 0.5pt/ms 以上・20pt 以上動いた）

    private func path(_ points: [(Double, Double, Double)]) -> [(t: Double, x: Double, y: Double)] {
        points.map { (t: $0.0, x: $0.1, y: $0.2) }
    }

    func testFlickDirections() {
        // 右へ 30pt を 0.05秒（600pt/秒）
        XCTAssertEqual(PhotoLift.flick(samples: path([(0, 100, 400), (0.05, 130, 400)])), .save)
        XCTAssertEqual(PhotoLift.flick(samples: path([(0, 100, 400), (0.05, 100, 370)])), .story)
        XCTAssertEqual(PhotoLift.flick(samples: path([(0, 100, 400), (0.05, 100, 430)])), .faces)
        XCTAssertNil(PhotoLift.flick(samples: path([(0, 100, 400), (0.05, 70, 400)])), "左へ弾いて何かした（左は戻る）")
    }

    func testFlickNeedsSpeedAndDistance() {
        // 遅い（400pt/秒）
        XCTAssertNil(PhotoLift.flick(samples: path([(0, 100, 400), (0.075, 130, 400)])))
        // 速いが 20pt に届かない
        XCTAssertNil(PhotoLift.flick(samples: path([(0, 100, 400), (0.01, 115, 400)])))
        // ゆっくり運んで最後に止まった（直前 90ms は動いていない）
        XCTAssertNil(PhotoLift.flick(samples: path([(0, 100, 400), (0.5, 200, 400), (0.6, 200, 400), (0.7, 200, 400)])))
        // 速く運んで、離す前の 90ms は止まっていた（全体の平均は 500pt/秒）——弾いたことにしない
        XCTAssertNil(PhotoLift.flick(samples: path([(0, 100, 400), (0.1, 200, 400), (0.15, 200, 400), (0.2, 200, 400)])),
                     "離す直前ではなく、全体の速さで弾いたと見なした")
        // 直前 90ms より前の速い動きは見ない
        XCTAssertNil(PhotoLift.flick(samples: path([(0, 100, 400), (0.02, 160, 400), (0.5, 161, 400)])))
    }

    /// 離した1回の行き先: 運んだ先が先、無ければ弾いた向き、下へ弾いたら顔の段を開いたまま
    @MainActor
    func testResolve() async {
        let size = CGSize(width: w, height: h)
        let samples = [PhotoLiftCenter.Sample(t: 0, x: 195, y: 400), PhotoLiftCenter.Sample(t: 0.05, x: 195, y: 430)]
        let down = PhotoLift.resolve(point: CGPoint(x: 195, y: 430), samples: samples, size: size, faces: 4, allowsStory: true)
        XCTAssertNil(down.target)
        XCTAssertTrue(down.openFaces)
        // 運んだ先（指の跡がある・20pt 以上動いた）。動かさずに離したら元へ戻る（`YubiReviewTests`）
        let carried = [PhotoLiftCenter.Sample(t: 0, x: 195, y: 430), PhotoLiftCenter.Sample(t: 1, x: 320, y: 430)]
        let onSave = PhotoLift.resolve(point: CGPoint(x: 320, y: 430), samples: carried, size: size, faces: 4, allowsStory: true)
        XCTAssertEqual(onSave.target, .save)
        let none = PhotoLift.resolve(point: CGPoint(x: 195, y: 430), samples: [], size: size, faces: 4, allowsStory: true)
        XCTAssertNil(none.target)
        XCTAssertFalse(none.openFaces)
    }

    func testTexts() {
        XCTAssertEqual(PhotoLift.releaseLabel(.save), "離すと 保存")
        XCTAssertEqual(PhotoLift.releaseLabel(nil), "離すと 元に戻る")
        XCTAssertEqual(PhotoLift.releaseLabel(.face(0), faceName: "ken.t"), "離すと ken.t へ送る")
        XCTAssertEqual(PhotoLift.doneMessage(.save, faceName: nil), "保存しました")
        XCTAssertEqual(PhotoLift.shareText(title: "白い道", url: "https://journey-photo.com/photo/a"),
                       "白い道\nhttps://journey-photo.com/photo/a")
        XCTAssertEqual(PhotoLift.shareText(title: " ", url: "u"), "u")
    }

    // MARK: - つまむと地図

    func testPinchToMap() {
        XCTAssertEqual(PinchToMap.progress(scale: 1), 0)
        XCTAssertEqual(PinchToMap.progress(scale: 0.6), 1)
        XCTAssertEqual(PinchToMap.progress(scale: 0.8), 0.5, accuracy: 0.0001)
        XCTAssertFalse(PinchToMap.passedStep(scale: 0.9))
        XCTAssertTrue(PinchToMap.passedStep(scale: 0.84))
        // 段で離すと戻る・地図の所まで縮めて離すと地図
        XCTAssertFalse(PinchToMap.opensMap(endScale: 0.7, hasPlace: true), "段で離して地図へ行った（歯止めが無い）")
        XCTAssertTrue(PinchToMap.opensMap(endScale: 0.55, hasPlace: true))
        // 撮影地の無い写真は段で止まるだけ
        XCTAssertFalse(PinchToMap.opensMap(endScale: 0.3, hasPlace: false))
        XCTAssertEqual(PinchToMap.displayScale(scale: 0.3, hasPlace: false), PinchToMap.stepScale)
        XCTAssertEqual(PinchToMap.displayScale(scale: 0.3, hasPlace: true), PinchToMap.minDisplayScale)
        XCTAssertEqual(PinchToMap.displayScale(scale: 1.4, hasPlace: true), 1, "広げる向きで写真を大きくした")
    }
}
