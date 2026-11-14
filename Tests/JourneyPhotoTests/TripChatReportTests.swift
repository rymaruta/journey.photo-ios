import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 旅行プランの会話の1通の通報とブロック（2026-11-14・札 #597・審査ガイドライン 1.2）。
///
/// 見張ること:
///  - 長押しの「通報」「ブロック」は**ほかの仲間の文の通にだけ**出る（自分の通・「日程に足しました」の札には出ない）
///  - 退会した人の通は通報だけ（ブロックの相手にならない・DM の「…」と同じ）
///  - 通報は `POST /trip-share/{planId}/report` に `{messageId, reason, note}` で送る（DM の口 `/dm/{id}/report` ではない）
///  - 理由は DM の会話の通報と同じ選び方（なりすましは「その他」＋補足の頭の印）
final class TripChatReportTests: XCTestCase {

    private static let planId = "11111111-2222-4333-8444-555555555555"
    private static let messageId = "aaaaaaaa-0000-4000-8000-000000000001"

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.reset()
    }

    override func tearDown() {
        StubProtocol.reset()
        super.tearDown()
    }

    private func service() -> TripShareService {
        TripShareService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                        tokenProvider: StubTokenProvider(token: "t"), session: session,
                                        retryPause: { _ in }))
    }

    private func message(mine: Bool = false, text: String? = "朝のひがし茶屋街", event: Bool = false) -> TripChatMessage {
        TripChatMessage(id: Self.messageId, from: mine ? "me" : "friend", mine: mine, t: "2026-11-10T09:00:00Z",
                        text: event ? nil : text,
                        event: event ? .init(type: "added", item: .spot(spotId: "sp_1", note: nil), day: 0) : nil)
    }

    // MARK: - メニューに出る条件

    func testOthersTextMessageOffersReportAndBlock() {
        XCTAssertEqual(TripShareText.messageActions(message(), authorDeleted: false), [.report, .block])
    }

    func testOwnMessageOffersNothing() {
        XCTAssertEqual(TripShareText.messageActions(message(mine: true), authorDeleted: false), [])
    }

    func testAddedEventOffersNothing() {
        XCTAssertEqual(TripShareText.messageActions(message(event: true), authorDeleted: false), [])
    }

    func testDeletedAuthorOffersReportOnly() {
        XCTAssertEqual(TripShareText.messageActions(message(), authorDeleted: true), [.report])
    }

    func testBlankTextOffersNothing() {
        XCTAssertEqual(TripShareText.messageActions(message(text: "  \n"), authorDeleted: false), [])
    }

    // MARK: - 送り先の形

    func testReportPostsToTripShareRoute() async throws {
        StubProtocol.respond(status: 200, body: #"{"success":true}"#)
        try await service().report(planId: Self.planId, messageId: Self.messageId,
                                   reason: DMReportReason.impersonation.serverReason,
                                   note: DMReportReason.impersonation.note(adding: " 名前を変えている "))
        XCTAssertEqual(StubProtocol.requests.last, "POST /trip-share/\(Self.planId)/report")
        let body = try XCTUnwrap(StubProtocol.lastBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["messageId"] as? String, Self.messageId)
        XCTAssertEqual(json["reason"] as? String, "other")
        XCTAssertEqual(json["note"] as? String, "なりすまし：名前を変えている")
    }

    /// 補足が空なら送らない（サーバーは欠けた補足を「無し」と読む）
    func testReportOmitsEmptyNote() async throws {
        StubProtocol.respond(status: 200, body: #"{"success":true}"#)
        try await service().report(planId: Self.planId, messageId: Self.messageId, reason: .harassment, note: "  ")
        let body = try XCTUnwrap(StubProtocol.lastBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["reason"] as? String, "harassment")
        XCTAssertNil(json["note"] as? String)
    }

    /// パスに入れられない id は要求を出さない
    func testRejectsUnsafeIds() async {
        for (plan, msg) in [("../user/account", Self.messageId), (Self.planId, "a/b")] {
            do {
                try await service().report(planId: plan, messageId: msg, reason: .spam, note: nil)
                XCTFail("危ない id で要求を出した: \(plan) \(msg)")
            } catch {
                XCTAssertEqual(error as? APIError, .invalidIdentifier)
            }
        }
        XCTAssertEqual(StubProtocol.requestCount, 0)
    }
}
