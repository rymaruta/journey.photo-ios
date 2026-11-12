import XCTest
@testable import JourneyPhoto

/// 旅行プランの共有の確かめ役の指摘（2026-11-12・札 #562）。
///
/// 見張ること:
///  - **409 の送り直しも回数を数え、上限で止まる**（数えていないと、読み直しが古い姿を返し続けたときに上限なしに送り直す）
///  - サーバーが `rev` の無い日程を 409 で断るようになった（journey.photo-web #602）。手元が共有と知らないプランでも
///    409 なら読み直して送り直し、読み直した共有の姿は「変わった」と見えて重ね直しの道に入り、版を添えて送る
///  - 会話の文に中黒の区切りを使わない（2026-11-12 の決まり）
///  - 会話の入力は 500 字まで（サーバーの `TRIP_CHAT_TEXT_MAX`）
final class TripShareReviewFixTests: XCTestCase {

    // MARK: - 409 の送り直し

    /// 送るたびに 409 が返り続ける（読み直しが古い姿を返す）ときの、送り直しの回数
    private func attemptsWhenAlways409(conflict: Bool) -> Int {
        var rebases = 0
        var attempts = 0
        while attempts < 50 {
            attempts += 1
            switch TripAutosave.afterSave(ok: false, conflict: conflict, rebases: rebases) {
            case .retry(let counted): rebases = counted
            case .fail, .done: return attempts
            }
        }
        return attempts
    }

    func testConflictRetriesAreCountedAndStop() {
        XCTAssertEqual(attemptsWhenAlways409(conflict: true), TripAutosave.maxRebases + 1,
                       "409 の送り直しは上限で止まる（数えていないと 50 回まで回る）")
        XCTAssertEqual(attemptsWhenAlways409(conflict: false), 1, "409 でない失敗は送り直さない")
    }

    func testAfterSave() {
        XCTAssertEqual(TripAutosave.afterSave(ok: true, conflict: false, rebases: 2), .done)
        XCTAssertEqual(TripAutosave.afterSave(ok: false, conflict: true, rebases: 0), .retry(rebases: 1))
        XCTAssertEqual(TripAutosave.afterSave(ok: false, conflict: true, rebases: TripAutosave.maxRebases), .fail)
        XCTAssertEqual(TripAutosave.afterSave(ok: false, conflict: false, rebases: 0), .fail)
    }

    /// 手元は本人だけのプランの姿（共有を知らない）、サーバーは共有した姿。409 のあとの読み直しで
    /// 「変わった」と見え（重ね直しの道）、読み直した姿は版を持つ（次に送るときに添える）
    func testUnsharedLocalPlanRecoversAfter409() throws {
        let local = TripPlan(planId: "p", title: "秋の金沢", updatedAt: "2026-11-12T01:00:00.000Z")
        XCTAssertEqual(TripAutosave.afterSave(ok: false, conflict: true, rebases: 0), .retry(rebases: 1),
                       "手元が共有と知らなくても、409 なら送り直す")
        let fresh = try JSONDecoder.api.decode(TripPlanList.self, from: Data(#"""
        {"plans":[{"planId":"p","title":"秋の金沢","shared":true,"ownerId":"u1","memberIds":["u1","u2"],"rev":5,
          "updatedAt":"2026-11-12T02:00:00.000Z","days":[]}]}
        """#.utf8)).plans
        let server = fresh.first { $0.planId == "p" }
        XCTAssertTrue(TripAutosave.conflicted(base: local, server: server))
        XCTAssertEqual(server?.share?.rev, 5)
        var patch = TripPlanService.Patch()
        patch.days = []
        patch.rev = server?.share?.rev
        let body = String(data: try JSONEncoder().encode(patch), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("\"rev\":5"))
    }

    // MARK: - 中黒の区切り（2026-11-12 の決まり）

    func testChatEventHasNoMiddleDot() {
        for s in [TripShareText.eventAdded, TripShareText.eventDay(0), TripShareText.memberCount(3)] {
            XCTAssertNil(s.range(of: "[·・]", options: .regularExpression), s)
        }
        XCTAssertEqual(TripShareText.eventDay(0), L("1日目", "Day 1"))
    }

    /// 共有の画面の文字に、中黒の区切りを書いていない（画面は Linux で描けないので、書いてあるもので見る）
    func testTripShareSourcesHaveNoMiddleDotSeparator() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
        let files = ["Features/Trips/TripShareViews.swift", "Core/Text/TripShareText.swift"]
        var bad: [String] = []
        for f in files {
            let lines = try String(contentsOf: root.appendingPathComponent(f), encoding: .utf8).components(separatedBy: "\n")
            for (i, line) in lines.enumerated() {
                let code = line.components(separatedBy: "//").first ?? line
                // 文字列の中の「 · 」「·」「 ・ 」（区切り）。注記の中は見ない
                if code.range(of: #""[^"]*(·|\s・\s)[^"]*""#, options: .regularExpression) != nil {
                    bad.append("\(f):\(i + 1)")
                }
            }
        }
        XCTAssertEqual(bad, [], "画面の文字に中黒の区切りがある")
    }

    // MARK: - 入力の上限

    func testChatDraftIsLimitedTo500() {
        XCTAssertEqual(TripShareText.chatTextMax, 500)
        let full = String(repeating: "あ", count: 500)
        XCTAssertEqual(TripShareText.limitedDraft(old: full, new: full + "い"), full)
        XCTAssertEqual(PostLimits.length(TripShareText.limitedDraft(old: "", new: String(repeating: "あ", count: 600))), 500)
        XCTAssertEqual(TripShareText.limitedDraft(old: "", new: "こんにちは"), "こんにちは")
    }
}
