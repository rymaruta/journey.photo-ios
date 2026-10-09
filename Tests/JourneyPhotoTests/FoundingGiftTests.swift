import XCTest
@testable import JourneyPhoto

/// 初期ユーザー章を贈る全画面（板 65・2026-10-09）。持っていて飾っていない人にだけ・
/// 飾ったら二度と出さない・「あとで」は合わせて3回まで・人ごとに覚える。
final class FoundingGiftTests: XCTestCase {

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "foundinggift-\(UUID().uuidString)")!
    }

    private func profile(_ json: String) throws -> UserProfile {
        try JSONDecoder.api.decode(UserProfile.self, from: Data(json.utf8))
    }

    private var early: String { #""badges":{"earlyUser":{"tier":1,"at":"2026-10-09T10:00:00Z"},"first":{"tier":1}}"# }

    /// 🔴 **初期ユーザー章を持っていない人には出さない**
    func testNoBadgeNoGift() throws {
        let gate = FoundingGiftGate(defaults: defaults())
        XCTAssertFalse(gate.shouldPresent(userId: "u1", profile: try profile(#"{"userId":"u1","badges":{"first":{"tier":1}}}"#)))
        XCTAssertFalse(gate.shouldPresent(userId: "u1", profile: try profile(#"{"userId":"u1"}"#)))
    }

    /// 持っていて飾っていない人には出す
    func testEarlyUserNotDisplayedGetsGift() throws {
        let gate = FoundingGiftGate(defaults: defaults())
        XCTAssertTrue(gate.shouldPresent(userId: "u1", profile: try profile(#"{"userId":"u1",\#(early),"displayBadge":"first"}"#)))
    }

    /// 🔴 **もう飾っている人には出さない**（覚えて、あとで外しても出さない）
    func testAlreadyDisplayedNeverShows() throws {
        let d = defaults()
        let gate = FoundingGiftGate(defaults: d)
        XCTAssertFalse(gate.shouldPresent(userId: "u1", profile: try profile(#"{"userId":"u1",\#(early),"displayBadge":"earlyUser"}"#)))
        XCTAssertFalse(gate.shouldPresent(userId: "u1", profile: try profile(#"{"userId":"u1",\#(early)}"#)))
    }

    /// 🔴 **飾ったら二度と出さない**
    func testAcceptedNeverShowsAgain() throws {
        let gate = FoundingGiftGate(defaults: defaults())
        let p = try profile(#"{"userId":"u1",\#(early)}"#)
        gate.noteShown(userId: "u1")
        gate.noteAccepted(userId: "u1")
        XCTAssertFalse(gate.shouldPresent(userId: "u1", profile: p))
    }

    /// 🔴 **「あとで」は次の起動でまた出すが、合わせて3回まで**（しつこくしない）
    func testLaterShowsUpToThreeTimes() throws {
        let gate = FoundingGiftGate(defaults: defaults())
        let p = try profile(#"{"userId":"u1",\#(early)}"#)
        for _ in 0..<FoundingGiftGate.maxShows {
            XCTAssertTrue(gate.shouldPresent(userId: "u1", profile: p))
            gate.noteShown(userId: "u1")
        }
        XCTAssertFalse(gate.shouldPresent(userId: "u1", profile: p))
    }

    /// 人ごとに覚える（同じ端末で別の人が入っても、その人には出す）
    func testRemembersPerUser() throws {
        let gate = FoundingGiftGate(defaults: defaults())
        gate.noteAccepted(userId: "u1")
        XCTAssertTrue(gate.shouldPresent(userId: "u2", profile: try profile(#"{"userId":"u2",\#(early)}"#)))
        XCTAssertFalse(gate.shouldPresent(userId: "", profile: try profile(#"{"userId":"u2",\#(early)}"#)))
    }

    /// 名前は表示名、無ければ @ユーザー名
    func testName() throws {
        XCTAssertEqual(FoundingGiftGate.name(try profile(#"{"userId":"u1","displayName":" りゅうへい ","username":"ryuhei"}"#)), "りゅうへい")
        XCTAssertEqual(FoundingGiftGate.name(try profile(#"{"userId":"u1","displayName":"  ","username":"ryuhei"}"#)), "@ryuhei")
        XCTAssertEqual(FoundingGiftGate.name(try profile(#"{"userId":"u1"}"#)), "")
    }

    /// 板の寸法: 390pt の画面でメダル 360pt、小さい画面では縮める
    func testMedalSide() {
        XCTAssertEqual(FoundingGiftLayout.medalSide(screenWidth: 390), 360)
        XCTAssertEqual(FoundingGiftLayout.medalSide(screenWidth: 320), 290)
        XCTAssertEqual(FoundingGiftLayout.medalSide(screenWidth: 430), 360)
    }

    /// 配線: 起動のあと（「新しくなったこと」を閉じたあと）に確かめ、飾ったら覚えてマイページを読み直す
    func testWiredIntoRoot() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/App/RootView.swift"),
                                encoding: .utf8)
        XCTAssertTrue(source.contains("tabsWithFoundingGift"))
        XCTAssertTrue(source.contains("onDismiss: { Task { await presentFoundingGiftIfNeeded() } }"))
        XCTAssertTrue(source.contains("FoundingGiftGate().noteAccepted(userId: userId)"))
        XCTAssertTrue(source.contains("gate.noteShown(userId: userId)"))
        let view = try String(contentsOf: root.appendingPathComponent(
            "Sources/JourneyPhoto/Features/Profile/FoundingGiftView.swift"), encoding: .utf8)
        XCTAssertTrue(view.contains("patch.displayBadge = Clearable(FoundingGiftGate.badgeKey)"))
        XCTAssertTrue(view.contains("受け取って、プロフィールに飾る"))
    }
}
