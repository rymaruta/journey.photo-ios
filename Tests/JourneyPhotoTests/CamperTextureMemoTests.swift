import XCTest
@testable import JourneyPhoto

/// 素材の貼り絵の控え（2026-10-28）: 部屋を組むたび・家具の小さな絵を描くたびに同じ貼り絵を描き直していた
/// （Linux の Debug で部屋 1 回の下ごしらえ 8.2 秒のうち約 7 秒）。控えても見た目は変わらない
final class CamperTextureMemoTests: XCTestCase {

    /// どの種類も、控えた絵は描き直した絵と画素まで同じ。1 回描けば控えに残る
    func testMemoizedTexturesMatchFreshlyDrawnOnes() {
        for kind in CamperTextureKind.allCases {
            let memo = CamperTextures.make(kind)
            XCTAssertTrue(CamperTextures.isMemoized(kind), "\(kind) が控えに残らない")
            XCTAssertEqual(memo, CamperTextures.generate(kind), "\(kind) の控えが描き直した絵と違う")
            XCTAssertEqual(CamperTextures.make(kind), memo, kind.rawValue)
        }
    }

    /// 部屋の下ごしらえで使った貼り絵は控えに残る（次に組むときは描き直さない）。控えた絵で組んでも貼り絵の中身は同じ
    func testRoomPlanReusesTextures() {
        let layout = CamperRoomLayout.make(.car, stage: .camper)
        let doc = CamperRoomRules.starterDocument(layout)
        let first = CamperRoomScenePlan.make(layout, doc: doc, paint: 0xFFFFFF)
        var kinds = 0
        for key in first.bitmaps.keys {
            let bare = key.hasPrefix("emit.") ? String(key.dropFirst(5)) : key
            guard let kind = CamperTextureKind.allCases.first(where: { bare.hasPrefix($0.rawValue + ".") }) else { continue }
            kinds += 1
            XCTAssertTrue(CamperTextures.isMemoized(kind), "\(key) の貼り絵が控えに無い")
        }
        XCTAssertGreaterThan(kinds, 10)
        let second = CamperRoomScenePlan.make(layout, doc: doc, paint: 0xFFFFFF)
        XCTAssertEqual(first.bitmaps, second.bitmaps)
    }
}
