import XCTest
@testable import JourneyPhoto

/// 新しいメッセージの「フォローしている人がいません」に押せる一手を置く（2026-11-23 判断・使いづらい所の点検）。
///
/// 受信箱が空 →「新しいメッセージ」を押す → フォロー中0人だと、押せるものが何も無い行き止まりだった。
/// 板 Components の空の並び（何が無いか → どうすれば埋まるか → 押せる一手）どおり、
/// フォローする人に出会う所（ホーム）へ1手で出し、受信箱のシートを下ろして移った先を見せる。
/// 画面は Linux で描けないので、判断は値で、配線は元のコードを読んで確かめる
final class DMNoFollowingExitTests: XCTestCase {

    /// 受信箱から開く形（1対1・何人でも）だけ出す。人を足す形は受信箱の外からも開くので出さない
    func testBrowseIsOfferedOnlyFromTheInboxModes() {
        XCTAssertTrue(GroupPick.offersBrowseWhenNoFollowing(.single))
        XCTAssertTrue(GroupPick.offersBrowseWhenNoFollowing(.start))
        XCTAssertFalse(GroupPick.offersBrowseWhenNoFollowing(.add(present: [], seatsLeft: 3)))
        XCTAssertFalse(GroupPick.offersBrowseWhenNoFollowing(
            .extend(peer: DMPeerSeed(id: "ken", name: "けん", username: nil))))
        // 受信箱が開く形は必ず一手を持つ
        XCTAssertTrue(GroupPick.offersBrowseWhenNoFollowing(GroupPick.startMode(groupsAvailable: true)))
        XCTAssertTrue(GroupPick.offersBrowseWhenNoFollowing(GroupPick.startMode(groupsAvailable: false)))
    }

    /// 0人の空に一手があり、押すとホームへ（いいね・保存の空と同じ言葉と道）
    func testEmptyStateHasTheBrowseAction() throws {
        let view = try source("Features/Messages/DMNewMessageView.swift")
        let empty = slice(view, from: "if candidates.isEmpty && !hasMoreThanShown {", to: "} else {")
        XCTAssertTrue(empty.contains("EmptyState("), "0人の空の部品が見つからない")
        XCTAssertTrue(empty.contains("GroupPick.offersBrowseWhenNoFollowing(mode)"), "形で一手を出し分けていない")
        XCTAssertTrue(empty.contains("actionTitle: browse ? MyPageEmpty.browseTitle : nil"), "一手の言葉が無い")
        XCTAssertTrue(empty.contains("TabRouter.shared.openHome()"), "一手がホームへ出ない")
        XCTAssertTrue(empty.contains("\"dm.new.emptyBrowse\""), "UI テストの道しるべが無い")
    }

    /// ホームへ移るときは受信箱のシートを下ろす（残ると移った先が見えない）
    func testGoingHomeClosesTheInboxSheet() throws {
        let root = try source("App/RootView.swift")
        let messages = slice(root, from: "private var tabsWithMessages: some View {", to: ".sheet(isPresented: $showMessages")
        XCTAssertTrue(messages.contains(".onChange(of: tabRouter.homeRequests) { _, _ in showMessages = false }"),
                      "ホームへ移っても受信箱のシートが残る")
    }

    // MARK: - 下ごしらえ

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/\(path)"), encoding: .utf8)
    }

    private func slice(_ text: String, from start: String, to end: String) -> String {
        guard let a = text.range(of: start) else { return "" }
        let rest = text[a.upperBound...]
        guard let b = rest.range(of: end) else { return String(rest) }
        return String(rest[..<b.lowerBound])
    }
}
