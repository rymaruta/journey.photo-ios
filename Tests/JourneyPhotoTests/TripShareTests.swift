import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 旅行プランを仲間と共有（2026-11-12・札 #553・資料「SNS をもっと SNS に」2b）。
///
/// 見張ること:
///  - 共有したプラン（`shared: true`）の欄と、ほかの仲間が「足した人」を読む。形が欠けたら本人だけのプランとして読む
///  - 日程を送るときに版（`rev`）を添える。添えるのは共有したプランだけ
///  - 書き込みの応答が共有したプランを読めなかった（`sharedFailed`）とき、前に見えていた共有したプランを消さない
///  - **ぶつかったら、読み直したプランの上に自分の変更だけを重ねる**（仲間の変更を消さない）
///  - 受信箱・プッシュの会話の印 `trip_<planId>` は DM の会話 ID と混ざらない
final class TripShareTests: XCTestCase {

    private func plans(_ json: String) throws -> TripPlanList {
        try JSONDecoder.api.decode(TripPlanList.self, from: Data(json.utf8))
    }

    // MARK: - 読む

    func testDecodesSharedPlanAndAddedBy() throws {
        let list = try plans(#"""
        {"plans":[{"planId":"p1","title":"秋の金沢","shared":true,"ownerId":"u1","memberIds":["u1","u2"],"rev":4,
          "days":[{"items":[{"kind":"spot","spotId":"sp_1"},{"kind":"spot","spotId":"sp_2","by":"u2"},{"kind":"location","slug":"金沢","by":"u2"}]}]},
          {"planId":"p2","title":"ひとり","days":[]}],"sharedFailed":true}
        """#)
        XCTAssertTrue(list.sharedFailed)
        XCTAssertEqual(list.plans[0].share, TripShare(ownerId: "u1", memberIds: ["u1", "u2"], rev: 4))
        XCTAssertEqual(list.plans[0].addedBy, ["s:sp_2": "u2", "l:金沢": "u2"])
        XCTAssertEqual(list.plans[0].days[0].items.count, 3, "足した人の欄があっても項目は読める")
        XCTAssertNil(list.plans[1].share)
        XCTAssertFalse(try plans(#"{"plans":[]}"#).sharedFailed)
    }

    /// 版が無い（壊れた・古いサーバー）なら本人だけのプランとして読む（開けなくしない）
    func testSharedWithoutRevReadsAsOwnPlan() throws {
        let list = try plans(#"{"plans":[{"planId":"p1","title":"x","shared":true,"ownerId":"u1","days":[]}]}"#)
        XCTAssertEqual(list.plans.count, 1)
        XCTAssertNil(list.plans[0].share)
    }

    // MARK: - 送る

    func testPatchCarriesRevOnlyWhenSet() throws {
        var patch = TripPlanService.Patch()
        patch.title = "t"
        let own = String(data: try JSONEncoder().encode(patch), encoding: .utf8) ?? ""
        XCTAssertFalse(own.contains("rev"))
        patch.rev = 7
        let shared = String(data: try JSONEncoder().encode(patch), encoding: .utf8) ?? ""
        XCTAssertTrue(shared.contains("\"rev\":7"))
    }

    func testSharedFailedKeepsPreviousSharedPlans() {
        let mine = TripPlan(planId: "own", title: "ひとり")
        let shared = TripPlan(planId: "s1", title: "仲間", share: TripShare(ownerId: "u2", memberIds: ["u1", "u2"], rev: 1))
        let failed = TripPlanList(plans: [mine], sharedFailed: true)
        XCTAssertEqual(TripPlansModel.merged(previous: [mine, shared], response: failed).map(\.planId), ["own", "s1"])
        // 読めた回は応答のとおり（抜けたプランは消える）
        XCTAssertEqual(TripPlansModel.merged(previous: [mine, shared], response: TripPlanList(plans: [mine])).map(\.planId), ["own"])
    }

    // MARK: - ぶつかったときの重ね直し

    private func day(_ ids: String...) -> TripDay { TripDay(items: ids.map { .spot(spotId: $0, note: nil) }) }
    private func ids(_ days: [TripDay]) -> [[String]] {
        days.map { $0.items.map { if case .spot(let id, _) = $0 { return id } else { return "?" } } }
    }

    func testRebaseKeepsBothAdditions() {
        let base = [day("a", "b")]
        let mine = [day("a", "b", "mine")]
        let server = [day("a", "b", "friend")]
        XCTAssertEqual(ids(TripShareText.rebase(base: base, mine: mine, server: server)), [["a", "b", "friend", "mine"]])
    }

    func testRebaseMovesAcrossDaysAndKeepsFriendsRemoval() {
        let base = [day("a", "b"), day("c")]
        // 自分: b を2日目の先頭へ動かした
        let mine = [day("a"), day("b", "c")]
        // 仲間: a を外し、d を足した
        let server = [day("b", "d"), day("c")]
        XCTAssertEqual(ids(TripShareText.rebase(base: base, mine: mine, server: server)), [["d"], ["b", "c"]])
    }

    func testRebaseRemovalAndNewDay() {
        let base = [day("a", "b")]
        let mine = [day("a"), day("x")]           // b を外して、新しい日に x
        let server = [day("a", "b", "c")]          // 仲間は c を足した
        XCTAssertEqual(ids(TripShareText.rebase(base: base, mine: mine, server: server)), [["a", "c"], ["x"]])
    }

    /// 仲間が外した場所を、自分が動かしただけなら戻さない
    func testRebaseDoesNotResurrectFriendsRemoval() {
        let base = [day("a", "b")]
        let mine = [day("b", "a")]
        let server = [day("a")]
        XCTAssertEqual(ids(TripShareText.rebase(base: base, mine: mine, server: server)), [["a"]])
    }

    func testRebaseCopiesOnlyMyNote() {
        let base = [TripDay(items: [.spot(spotId: "a", note: nil), .spot(spotId: "b", note: nil)])]
        let mine = [TripDay(items: [.spot(spotId: "a", note: "朝いち"), .spot(spotId: "b", note: nil)])]
        let server = [TripDay(items: [.spot(spotId: "a", note: nil), .spot(spotId: "b", note: "仲間のひとこと")])]
        let out = TripShareText.rebase(base: base, mine: mine, server: server)
        XCTAssertEqual(out[0].items, [.spot(spotId: "a", note: "朝いち"), .spot(spotId: "b", note: "仲間のひとこと")])
    }

    func testRebaseDateTakesMineOnlyWhenChanged() {
        XCTAssertEqual(TripShareText.rebaseDate(base: "2026-11-22", mine: "2026-11-22", server: "2026-11-23"), "2026-11-23")
        XCTAssertEqual(TripShareText.rebaseDate(base: "2026-11-22", mine: "2026-11-21", server: "2026-11-23"), "2026-11-21")
    }

    // MARK: - 受信箱・知らせ

    func testConversationIdRoundTripAndPush() {
        XCTAssertEqual(TripShareText.planId(fromConversation: TripShareText.conversationId(planId: "11111111-2222-4333-8444-555555555555")),
                       "11111111-2222-4333-8444-555555555555")
        XCTAssertNil(TripShareText.planId(fromConversation: "aaa_bbb"), "DM の会話 ID はプランの印にならない")
        XCTAssertNil(TripShareText.planId(fromConversation: "trip_"))
        XCTAssertEqual(NotificationRouter.dmConversationId(["type": "tripchat", "planId": "p-1"]), "trip_p-1")
        XCTAssertEqual(NotificationRouter.dmConversationId(["type": "tripshare", "planId": "p-1"]), "trip_p-1")
        XCTAssertNil(NotificationRouter.dmConversationId(["type": "tripchat", "planId": "../x"]))
    }

    func testAddedByShowsOnlyOthers() {
        let plan = TripPlan(planId: "p", title: "t", days: [day("a", "b")],
                            share: TripShare(ownerId: "me", memberIds: ["me", "u2"], rev: 1),
                            addedBy: ["s:a": "u2", "s:b": "me"])
        let members = [TripMember(id: "me", name: "わたし", username: nil, deleted: nil, owner: true),
                       TripMember(id: "u2", name: "あお", username: nil, deleted: nil, owner: nil)]
        XCTAssertEqual(TripShareText.addedBy(plan, .spot(spotId: "a", note: nil), members: members, me: "me"),
                       L("あお が足しました", "Added by あお"))
        XCTAssertNil(TripShareText.addedBy(plan, .spot(spotId: "b", note: nil), members: members, me: "me"))
        let own = TripPlan(planId: "q", title: "t", days: [day("a")], addedBy: ["s:a": "u2"])
        XCTAssertNil(TripShareText.addedBy(own, .spot(spotId: "a", note: nil), members: members, me: "me"), "共有していないプランには出さない")
    }

    func testInviteLinkIsWebPage() {
        XCTAssertEqual(TripInviteLink(token: "abc_DEF-123", expiresAt: nil).url?.absoluteString, "https://journey-photo.com/t?t=abc_DEF-123")
    }
}
