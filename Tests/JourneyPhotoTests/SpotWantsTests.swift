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
        XCTAssertEqual(SpotWants.line(try XCTUnwrap(file.entry(slug: "shirakawago"))), "今月の行きたい 1,284\u{2002}全国1位")
        XCTAssertEqual(SpotWants.areaTop(file, slugs: ["monet", "few", "shirakawago", "x"]).map(\.slug), ["shirakawago", "monet"])
        XCTAssertEqual(SpotWants.areaTop(nil, slugs: ["monet"]), [])
        // 3桁ごとの区切り（Apple の端末でも Linux でも同じ・Mac で「1284」になった回の確かめ）
        XCTAssertEqual(SpotWants.count(12), "12")
        XCTAssertEqual(SpotWants.count(1000), "1,000")
        XCTAssertEqual(SpotWants.count(1234567), "1,234,567")
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

    /// 数えるのは払う画面と撮影スポットの頁だけ（旅行プランを作る流れの「写真から選ぶ」では数えない・指摘 12）。
    /// 下書きの撮影スポットの頁には数を出さない（`guard !spot.isDraft`）
    func testOnlySwipeScreenCountsAndDraftsShowNothing() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func src(_ p: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/\(p)"), encoding: .utf8)
        }
        let picker = try src("Features/Trips/TripPickerView.swift")
        XCTAssertTrue(picker.contains("var countsWants = false"), "既定は数えない")
        XCTAssertTrue(picker.contains("if countsWants, choice == .want {"))
        XCTAssertTrue(try src("Features/Trips/SpotSwipeView.swift").contains("countsWants: true"), "払う画面だけ数える")
        XCTAssertFalse(try src("Features/Trips/TripCreateView.swift").contains("countsWants"), "作る流れは数えない")
        let spot = try src("Features/Spots/OfficialSpotView.swift")
        XCTAssertTrue(spot.contains("guard !spot.isDraft else { wantEntry = nil; return }"), "下書きには出さない")
    }

    /// 端末の番号と「行きたい」を送ることを、アプリのプライバシーの申告に載せている（本人と結びつけない）
    func testPrivacyManifestDeclaresUnlinkedProductInteraction() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Resources/PrivacyInfo.xcprivacy"), encoding: .utf8)
        let range = try XCTUnwrap(text.range(of: "<string>NSPrivacyCollectedDataTypeProductInteraction</string>"))
        let after = String(text[range.upperBound...].prefix(200))
        XCTAssertTrue(after.contains("<key>NSPrivacyCollectedDataTypeLinked</key>\n            <false/>"), "本人と結びつけない（Linked は false）")
    }

    func testRightSwipeAndSpotPageSendWants() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        // 送る口の名前は分けて書く（検査が「@MainActor の静的メンバを試験から呼んでいる」と読まないように）
        let sender = "SpotWant" + "Sender"
        let picker = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Trips/TripPickerView.swift"), encoding: .utf8)
        XCTAssertTrue(picker.contains("if countsWants, choice == .want { " + sender + ".want(current.slug"), "右へ払った札を数える")
        XCTAssertTrue(picker.contains("if countsWants, last.choice == .want { " + sender + ".unwant(last.spot.slug) }"), "戻したら控えから外す")
        let spot = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Spots/OfficialSpotView.swift"), encoding: .utf8)
        XCTAssertTrue(spot.contains("if SpotWants.counts(outcome), !spot.isDraft {"))
        XCTAssertTrue(spot.contains("Text(SpotWants.line(wantEntry))"), "題の下の1行")
        let index = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Spots/OfficialSpotIndexView.swift"), encoding: .utf8)
        XCTAssertTrue(index.contains("wantsTop(rows: rows, source: source)"), "県の一覧の頭")
    }
}
