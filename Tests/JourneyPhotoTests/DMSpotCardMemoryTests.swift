import XCTest
@testable import JourneyPhoto

/// **DM の会話が、払った直後から固まった件の直し**（2026-11-12・1.1.85）。
///
/// 会話の行は `LazyVStack` が作り直し、そのたびに観光スポットの札（`DMSpotCard`）の `@State` は初めの値に戻る。
/// 初めの値がいつも「読み込み中」（高さ 250）だと、作り直した札は読み込み中 → 読み終えた札と高さが替わり、
/// 払った直後から主スレッドが戻らなくなった（Mac run 1186: 印なし 61 秒、札の高さを固定・状態を替えないと 2〜3 秒）。
/// 直しは、読み終えた中身をスラッグごとに覚え（`DMSpotCardMemory`）、作り直した札はそこから始めること。
final class DMSpotCardMemoryTests: XCTestCase {

    override func setUp() {
        DMSpotCardMemory.forgetAll()
    }

    override func tearDown() {
        DMSpotCardMemory.forgetAll()
    }

    private func spot(_ slug: String) throws -> OfficialSpot {
        let json = "{\"spotId\":\"sp_\(slug)\",\"slug\":\"\(slug)\",\"name\":\"兼六園\",\"stage\":\"published\"}"
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data(json.utf8))
    }

    /// 読み終えた札は、作り直しても同じ中身から始まる（読み込み中を挟まない）
    func testFoundSpotIsRememberedForTheNextCard() throws {
        let kenrokuen = try spot("kenrokuen")
        XCTAssertNil(DMSpotCardMemory.phase(for: "kenrokuen"))
        DMSpotCardMemory.remember(.found(kenrokuen, [kenrokuen]), for: "kenrokuen", failed: false)
        XCTAssertEqual(DMSpotCardMemory.phase(for: "kenrokuen"), .found(kenrokuen, [kenrokuen]))
        XCTAssertEqual(DMSpotCardMemory.phase(for: "kenrokuen", now: Date().addingTimeInterval(3600)), .found(kenrokuen, [kenrokuen]),
                       "読めた札は時間で忘れない（忘れると作り直した札がまた読み込み中から始まる）")
        XCTAssertNil(DMSpotCardMemory.phase(for: "other"), "ほかのスラッグには効かない")
    }

    /// 索引に無いスラッグの「読めない」は覚える。索引を取れなかった「読めない」は 60 秒だけ（電波が戻れば読み直す）
    func testMissingIsRememberedAndFailureExpires() {
        let now = Date()
        DMSpotCardMemory.remember(.missing, for: "gone", failed: false, now: now)
        DMSpotCardMemory.remember(.missing, for: "offline", failed: true, now: now)
        XCTAssertEqual(DMSpotCardMemory.phase(for: "gone", now: now.addingTimeInterval(3600)), .missing)
        XCTAssertEqual(DMSpotCardMemory.phase(for: "offline", now: now.addingTimeInterval(59)), .missing)
        XCTAssertNil(DMSpotCardMemory.phase(for: "offline", now: now.addingTimeInterval(DMSpotCardMemory.failedLifetime)))
    }

    /// 「読み込み中」は覚えない（覚えると読み終えた中身に替わらない）
    func testLoadingIsNotRemembered() {
        DMSpotCardMemory.remember(.loading, for: "kenrokuen", failed: false)
        XCTAssertNil(DMSpotCardMemory.phase(for: "kenrokuen"))
    }

    /// 札は覚えた中身から始まり、読み終えたら覚える。覚えた中身で始まった札は読み直さない（高さを替えない）
    func testCardStartsFromTheRememberedPhase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let card = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Messages/DMSpotCard.swift"),
                              encoding: .utf8)
        XCTAssertTrue(card.contains("DMSpotCardMemory.phase(for: slug)"), "札がいつも読み込み中から始まる")
        XCTAssertTrue(card.contains("_phase = State(initialValue: start ?? .loading)"))
        XCTAssertTrue(card.contains("guard phase == .loading else { return }\n            await load()"), "覚えた札を読み直している")
        XCTAssertTrue(card.contains("DMSpotCardMemory.remember(settled, for: slug, failed: failed)"), "読み終えた中身を覚えていない")
        XCTAssertFalse(card.contains("@State private var phase: Phase = "), "札の状態の初めの値が決め打ち（作り直すと読み込み中に戻る）")
    }

    /// 🔴 固まる件の直し: 札はどの状態でも同じ枠（`DMSpotCardBox`）に入る。枠の大きさが中身で替わらないことは
    /// `DMSpotCardBoxTests`（iOS だけ）が測る。ここでは Linux でも、枠を通らない道が無いことを読む
    func testEveryPhaseIsDrawnInTheFixedBox() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let card = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Messages/DMSpotCard.swift"),
                              encoding: .utf8)
        XCTAssertTrue(card.contains("DMSpotCardBox { phaseView }"), "札が枠に入っていない（読み込み中から読み終えると高さが替わる）")
        XCTAssertTrue(card.contains("case .loading:") && card.contains("card(spot, index: index, fillsBox: true)")
                      && card.contains("missingCard"), "読み込み中・読めた・読めないのどれかが枠の外にある")
    }
}
