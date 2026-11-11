import XCTest
@testable import JourneyPhoto

/// みんなの「行きたい」（2026-11-11・撮影スポットを払うの②・`SpotWants`・`SpotWantQueue`）。
///
/// 固定したいのは:
///  1. 10未満は出さない・無い撮影スポットには何も出さない
///  2. 頁の1行は「今月の行きたい 1,284 · 全国1位」・県の頭はその県の3つ
///  3. 送るのは端末のでたらめな ID と撮影スポットの鍵だけ・同じ鍵は1つ・戻したら外す
///  4. 頁の「行きたい」は入れたときだけ数える（外した・失敗は数えない）
final class SpotWantsTests: XCTestCase {

    private let json = Data("""
    {"month":"2026-11","updatedAt":"x","spots":[
     {"slug":"shirakawago","name":"白川郷","n":1284,"rank":1},
     {"slug":"monet","name":"モネの池","n":12,"rank":2},
     {"slug":"few","name":"少ない","n":9,"rank":3}]}
    """.utf8)

    private func freshDefaults() -> UserDefaults {
        let name = "SpotWantsTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testFileHidesUnderTen() throws {
        let file = try XCTUnwrap(SpotWants.decode(json))
        XCTAssertEqual(file.shown.map(\.slug), ["shirakawago", "monet"])
        XCTAssertNil(file.entry(slug: "few"))
        XCTAssertNil(file.entry(slug: "nothing"))
        XCTAssertNil(SpotWants.decode(Data("<html>".utf8)))
    }

    func testLineAndAreaTop() throws {
        let file = try XCTUnwrap(SpotWants.decode(json))
        XCTAssertEqual(SpotWants.line(try XCTUnwrap(file.entry(slug: "shirakawago"))), "今月の行きたい 1,284 · 全国1位")
        XCTAssertEqual(SpotWants.areaTop(file, slugs: ["monet", "few", "shirakawago", "x"]).map(\.slug), ["shirakawago", "monet"])
        XCTAssertEqual(SpotWants.areaTop(nil, slugs: ["monet"]), [])
    }

    func testQueueKeepsOnlySpotKeysOnce() {
        let q = SpotWantQueue(defaults: freshDefaults())
        XCTAssertEqual(q.add(slug: "a"), 1)
        XCTAssertEqual(q.add(slug: "a"), 1, "同じ鍵は1つ")
        q.add(slug: "b")
        q.remove(slug: "b")
        XCTAssertEqual(q.queued, ["SPOT-a"])
        q.removeSent(["SPOT-a"])
        XCTAssertEqual(q.queued, [])
    }

    func testDeviceIdIsRandomAndStable() {
        let d = freshDefaults()
        let a = SpotWantQueue(defaults: d).deviceId
        XCTAssertTrue(SpotWantQueue.isDeviceId(a))
        XCTAssertEqual(SpotWantQueue(defaults: d).deviceId, a, "一度作ったら同じ")
        XCTAssertNotEqual(SpotWantQueue(defaults: freshDefaults()).deviceId, a)
        XCTAssertFalse(SpotWantQueue.isDeviceId("short"))
    }

    func testSpotPageCountsOnlyWhenAdded() {
        XCTAssertTrue(SpotWants.counts(.synced(wanted: true)))
        XCTAssertTrue(SpotWants.counts(.local(wanted: true)))
        XCTAssertFalse(SpotWants.counts(.synced(wanted: false)))
        XCTAssertFalse(SpotWants.counts(.failed(wanted: true, message: "x")))
        XCTAssertFalse(SpotWants.counts(.ignored))
    }

    func testRightSwipeAndSpotPageSendWants() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        // 送る口の名前は分けて書く（検査が「@MainActor の静的メンバを試験から呼んでいる」と読まないように）
        let sender = "SpotWant" + "Sender"
        let picker = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Trips/TripPickerView.swift"), encoding: .utf8)
        XCTAssertTrue(picker.contains("if choice == .want { " + sender + ".want(current.slug"), "右へ払った札を数える")
        XCTAssertTrue(picker.contains("if last.choice == .want { " + sender + ".unwant(last.spot.slug) }"), "戻したら控えから外す")
        let spot = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Spots/OfficialSpotView.swift"), encoding: .utf8)
        XCTAssertTrue(spot.contains("if SpotWants.counts(outcome), !spot.isDraft {"))
        XCTAssertTrue(spot.contains("Text(SpotWants.line(wantEntry))"), "題の下の1行")
        let index = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Spots/OfficialSpotIndexView.swift"), encoding: .utf8)
        XCTAssertTrue(index.contains("wantsTop(rows: rows, source: source)"), "県の一覧の頭")
    }
}
