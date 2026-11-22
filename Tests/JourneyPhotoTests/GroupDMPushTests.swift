import XCTest
@testable import JourneyPhoto

/// グループの DM の知らせ（2026-11-20・札 #582）。`NotificationRouter`（@MainActor）を呼ぶので型ごと主スレッドで流す
@MainActor
final class GroupDMPushTests: XCTestCase {

    // MARK: - 知らせ（thread-id で束ねる・押すとその会話へ）

    func testPushThreadIdAndRouting() async throws {
        let gid = "6f1c2a10-0000-4000-8000-000000000001"
        let payload: [AnyHashable: Any] = ["aps": ["alert": ["title": "けん、みお", "body": "みお からメッセージが届きました"],
                                                   "thread-id": gid],
                                           "type": "group", "groupId": gid]
        XCTAssertEqual(NotificationRouter.dmConversationId(payload), "group_\(gid)", "押してもグループの会話へ行かない")
        XCTAssertEqual(GroupText.groupId(fromConversation: "group_\(gid)"), gid)
        XCTAssertTrue(GroupText.opens("group_\(gid)", me: "me-0000"), "人が替わった後の門でグループの知らせを落とす")
        XCTAssertFalse(GroupText.opens("a_b", me: "me-0000"), "自分の入っていない1対1の会話を開く")
        // 読んだら通知センターから外す（同じ会話の知らせを拾う）
        let delivered: [(id: String, userInfo: [AnyHashable: Any])] = [("n1", payload), ("n2", ["type": "dm", "convId": "a_b"])]
        XCTAssertEqual(AppBadge.deliveredIds(delivered, conversationId: "group_\(gid)"), ["n1"])
        // 形の違う id は受け取らない
        XCTAssertNil(NotificationRouter.dmConversationId(["type": "group", "groupId": "../x"]))
        XCTAssertNil(GroupText.groupId(fromConversation: "group_"))
        // 受信箱は知らせの印をグループの会話へ積む
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let inbox = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Messages/DMInboxView.swift"), encoding: .utf8)
        XCTAssertTrue(inbox.contains("GroupText.groupId(fromConversation: id)"))
    }

}
