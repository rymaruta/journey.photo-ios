import XCTest
@testable import JourneyPhoto

/// 写真の詳細で写真を下に引いて前の画面へ戻る（2026-11-13 owner 決定・札 #592・`PhotoDetailPull`）
final class PhotoDetailPullTests: XCTestCase {

    /// 上に居て、下向きで、縦が横より大きいときだけ始める
    func testStartsOnlyWhenAtTopAndPullingDown() {
        XCTAssertTrue(PhotoDetailPull.starts(dx: 0, dy: 12, atTop: true))
        XCTAssertTrue(PhotoDetailPull.starts(dx: 10, dy: 10, atTop: true), "斜め 45° までは引く側")
        XCTAssertFalse(PhotoDetailPull.starts(dx: 0, dy: -12, atTop: true), "上へ払う指を奪った（説明・コメントへ流れない）")
        XCTAssertFalse(PhotoDetailPull.starts(dx: 0, dy: 12, atTop: false), "下まで読んでいる途中で上へ戻す指を奪った")
        XCTAssertFalse(PhotoDetailPull.starts(dx: 30, dy: 12, atTop: true), "横の払い（束の写真の送り・端からの戻る）を奪った")
        XCTAssertFalse(PhotoDetailPull.starts(dx: -30, dy: 12, atTop: true), "左向きの横の払いを奪った")
        XCTAssertFalse(PhotoDetailPull.starts(dx: 0, dy: 0, atTop: true))
    }

    /// 上に居るか（送りの止まり際の端数は上とみなす）
    func testIsAtTop() {
        XCTAssertTrue(PhotoDetailPull.isAtTop(offsetY: 0, insetTop: 0))
        XCTAssertTrue(PhotoDetailPull.isAtTop(offsetY: 0.6, insetTop: 0), "端数で上に居ないことにした")
        XCTAssertTrue(PhotoDetailPull.isAtTop(offsetY: -59, insetTop: 59), "上の余白のある送りで上と見なかった")
        XCTAssertFalse(PhotoDetailPull.isAtTop(offsetY: 4, insetTop: 0))
        XCTAssertFalse(PhotoDetailPull.isAtTop(offsetY: -50, insetTop: 59))
    }

    /// 引いた量（と勢い）が 120pt に届けば戻る。足りなければ元に戻る
    func testClosesByDistanceOrFlick() {
        XCTAssertEqual(PhotoDetailPull.closeDistance, StoryReel.closeDistance, "人のストーリーの下へ払う距離とそろえる")
        XCTAssertTrue(PhotoDetailPull.closes(dy: 130, velocityY: 0))
        XCTAssertTrue(PhotoDetailPull.closes(dy: 120, velocityY: 0))
        XCTAssertFalse(PhotoDetailPull.closes(dy: 80, velocityY: 0), "足りない量で戻った")
        XCTAssertTrue(PhotoDetailPull.closes(dy: 40, velocityY: 400), "短く素早く払って戻れない（40 + 400 × 0.499 ≒ 240）")
        XCTAssertFalse(PhotoDetailPull.closes(dy: 40, velocityY: 100), "ゆっくり少し引いただけで戻った")
        XCTAssertFalse(PhotoDetailPull.closes(dy: 200, velocityY: -600), "引いてから上へ払い戻したのに戻った")
        XCTAssertEqual(PhotoDetailPull.projectionSeconds, 0.499, accuracy: 0.0005)
    }

    /// 引くほど縮む（下限 0.75）。「視差効果を減らす」では縮めない
    func testScaleShrinksWithPullUnlessReduceMotion() {
        XCTAssertEqual(PhotoDetailPull.scale(dy: 0, reduceMotion: false), 1)
        XCTAssertEqual(PhotoDetailPull.scale(dy: 200, reduceMotion: false), 0.875, accuracy: 0.0001)
        XCTAssertEqual(PhotoDetailPull.scale(dy: 400, reduceMotion: false), 0.75, accuracy: 0.0001)
        XCTAssertEqual(PhotoDetailPull.scale(dy: 900, reduceMotion: false), 0.75, accuracy: 0.0001, "下限より縮んだ")
        XCTAssertEqual(PhotoDetailPull.scale(dy: -50, reduceMotion: false), 1, "上へ戻した指で大きくなった")
        XCTAssertEqual(PhotoDetailPull.scale(dy: 300, reduceMotion: true), 1, "視差効果を減らすでも縮んだ")
    }

    /// 写真は指に付いて動く（縦は下向きだけ）。下の説明は薄れる。角は引いている間だけ丸める
    func testOffsetFadeAndCorners() {
        let shift = PhotoDetailPull.offset(dx: -24, dy: 90)
        XCTAssertEqual(shift.x, -24)
        XCTAssertEqual(shift.y, 90)
        XCTAssertEqual(PhotoDetailPull.offset(dx: 0, dy: -30).y, 0, "指を上へ戻すと写真が元の位置より上へ出た")

        XCTAssertEqual(PhotoDetailPull.restOpacity(dy: 0), 1)
        XCTAssertEqual(PhotoDetailPull.restOpacity(dy: 100), 0.5, accuracy: 0.0001)
        XCTAssertEqual(PhotoDetailPull.restOpacity(dy: 300), 0)
        XCTAssertEqual(PhotoDetailPull.restOpacity(dy: -40), 1)

        XCTAssertFalse(PhotoDetailPull.rounds(dy: 0))
        XCTAssertTrue(PhotoDetailPull.rounds(dy: 1))
    }
}
