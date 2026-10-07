import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// App Store の評価をお願いする頃合い（`ReviewPrompt`・`ReviewPromptStore`・2026-10-07）。
///
/// 2026-09-28 から公開しているが評価が0件。**うれしい瞬間のあとに、控えめに**お願いする。
/// OS の札そのものは模型では出せないので、ここでは「いつ頼むか」の決まりを見る
@MainActor
final class ReviewPromptTests: XCTestCase {

    private let day: TimeInterval = 86_400

    // MARK: - 決まり

    /// うれしい瞬間が3回たまるまでは頼まない
    func testAsksOnlyAfterThreeHappyMoments() async {
        let now = Date()
        for count in 0..<3 {
            XCTAssertFalse(ReviewPrompt.shouldAsk(happyMoments: count, currentVersion: "1.0.67",
                                                  lastAskedVersion: nil, lastAskedAt: nil, now: now))
        }
        XCTAssertTrue(ReviewPrompt.shouldAsk(happyMoments: 3, currentVersion: "1.0.67",
                                             lastAskedVersion: nil, lastAskedAt: nil, now: now))
    }

    /// 🔴 **同じ版では二度頼まない**。版が上がっても、前回から90日は空ける
    func testNeverTwiceInOneVersionAndWaitsNinetyDays() async {
        let now = Date()
        XCTAssertFalse(ReviewPrompt.shouldAsk(happyMoments: 10, currentVersion: "1.0.67",
                                              lastAskedVersion: "1.0.67", lastAskedAt: now.addingTimeInterval(-200 * day), now: now),
                       "同じ版でもう一度頼んだ")
        XCTAssertFalse(ReviewPrompt.shouldAsk(happyMoments: 10, currentVersion: "1.0.70",
                                              lastAskedVersion: "1.0.67", lastAskedAt: now.addingTimeInterval(-30 * day), now: now),
                       "前回から90日たたないうちに頼んだ")
        XCTAssertTrue(ReviewPrompt.shouldAsk(happyMoments: 3, currentVersion: "1.0.70",
                                             lastAskedVersion: "1.0.67", lastAskedAt: now.addingTimeInterval(-91 * day), now: now))
        // 版が分からない（読めなかった）ときは頼まない
        XCTAssertFalse(ReviewPrompt.shouldAsk(happyMoments: 3, currentVersion: " ",
                                              lastAskedVersion: nil, lastAskedAt: nil, now: now))
    }

    // MARK: - 数えて覚える

    private func makeStore(version: String = "1.0.67", now: Date = Date(), preview: Bool = false)
        -> (ReviewPromptStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = ReviewPromptStore(defaults: defaults, currentVersion: { version },
                                      now: { now }, isPreview: { preview })
        return (store, defaults)
    }

    /// 3回目で `RootView` に頼む合図が出て、頼んだら数が戻り、同じ版では二度と合図しない
    func testStoreSignalsOnTheThirdMomentAndOnlyOncePerVersion() async {
        let (store, _) = makeStore()
        store.noteHappyMoment(); store.noteHappyMoment()
        XCTAssertEqual(store.requests, 0)
        store.noteHappyMoment()
        XCTAssertEqual(store.requests, 1, "3回目で合図していない")
        XCTAssertTrue(store.consume())
        XCTAssertEqual(store.happyMoments, 0, "頼んだあと数を戻していない")
        for _ in 0..<5 { store.noteHappyMoment() }
        XCTAssertEqual(store.requests, 1, "同じ版でもう一度合図した")
        XCTAssertFalse(store.consume(), "同じ版でもう一度頼めてしまう")
    }

    /// 頼んだ版と日は端末に残り、次の起動（作り直した部品）でも二度頼まない
    func testRemembersAcrossLaunches() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let first = ReviewPromptStore(defaults: defaults, currentVersion: { "1.0.67" }, now: Date.init, isPreview: { false })
        for _ in 0..<3 { first.noteHappyMoment() }
        XCTAssertTrue(first.consume())
        let second = ReviewPromptStore(defaults: defaults, currentVersion: { "1.0.67" }, now: Date.init, isPreview: { false })
        for _ in 0..<3 { second.noteHappyMoment() }
        XCTAssertFalse(second.shouldAsk, "起動し直したら同じ版でもう一度頼めてしまう")
    }

    /// 絵を撮るための入り方（UI テスト）では数えない——OS の札が画面の絵を覆わないように
    func testPreviewSessionNeverCounts() async {
        let (store, _) = makeStore(preview: true)
        for _ in 0..<5 { store.noteHappyMoment() }
        XCTAssertEqual(store.happyMoments, 0)
        XCTAssertEqual(store.requests, 0)
    }

    // MARK: - うれしい瞬間を数える場所

    /// 「行きたい」に入れた回は数え、外した回・失敗した回は数えない
    func testWishlistAddCountsAsAHappyMoment() async {
        let shared = ReviewPromptStore.shared
        let wishlist = WishlistStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        wishlist.use(userId: nil)   // 未ログイン＝端末だけ（`.local`）
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let service = SavedSpotService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                                      tokenProvider: StubTokenProvider(token: "t"),
                                                      session: URLSession(configuration: config)))
        let before = shared.happyMoments
        let added = await WishlistSync.set("山中湖", wanted: true, store: wishlist, service: service)
        XCTAssertEqual(added, .local(wanted: true))
        XCTAssertEqual(shared.happyMoments, before + 1, "「行きたい」に入れたのに数えていない")
        _ = await WishlistSync.set("山中湖", wanted: false, store: wishlist, service: service)
        XCTAssertEqual(shared.happyMoments, before + 1, "外した回まで数えた")
    }

    /// 投稿が全部上がった回・評価のお願いを `RootView` が受けていること（画面は模型で動かせないので書いてあることを見る）
    func testUploadAndRootViewAreWired() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
        let upload = try String(contentsOf: root.appendingPathComponent("Features/Upload/UploadViewModel.swift"), encoding: .utf8)
        XCTAssertTrue(upload.contains("if didPostAll { ReviewPromptStore.shared.noteHappyMoment() }"),
                      "投稿が全部上がった回を数えていない")
        let view = try String(contentsOf: root.appendingPathComponent("App/RootView.swift"), encoding: .utf8)
        XCTAssertTrue(view.contains("tabsWithReviewPrompt"), "評価のお願いの合図を受けていない")
        XCTAssertTrue(view.contains("requestReview()"), "OS に評価のお願いを頼んでいない")
        XCTAssertTrue(view.contains("reviewPrompt.consume()"), "頼んだことを覚えていない（同じ版で何度も頼む）")
    }
}
