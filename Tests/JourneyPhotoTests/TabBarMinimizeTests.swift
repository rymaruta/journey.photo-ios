import XCTest
@testable import JourneyPhoto

/// 下の札を下へ送ったときに縮める（2026-11-14・人間工学の点検 7・`TabBarMinimize`）
final class TabBarMinimizeTests: XCTestCase {

    /// 縮めるのはホームと探すの 2 つだけ（写真を流して見るタブ）
    func testOnlyHomeAndSearchMinimize() {
        XCTAssertTrue(TabBarMinimize.minimizesOnScrollDown(.home))
        XCTAssertTrue(TabBarMinimize.minimizesOnScrollDown(.search))
        XCTAssertFalse(TabBarMinimize.minimizesOnScrollDown(.post))
        XCTAssertFalse(TabBarMinimize.minimizesOnScrollDown(.map))
        XCTAssertFalse(TabBarMinimize.minimizesOnScrollDown(.mypage))
    }

    /// TabView に付いていて、iOS 26 の時だけ `.onScrollDown`（iOS 17〜25 は付けない）
    func testRootTabViewAppliesMinimizeOnlyOnIOS26() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func source(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }
        let rootView = try source("Sources/JourneyPhoto/App/RootView.swift")
        XCTAssertTrue(rootView.contains(".modifier(TabBarMinimizeOnScroll(tab: selection))"), "ホームの TabView に縮める設定が付いていない")
        let modifier = try source("Sources/JourneyPhoto/App/TabBarMinimize.swift")
        XCTAssertTrue(modifier.contains("if #available(iOS 26, *) {"))
        XCTAssertTrue(modifier.contains("content.tabBarMinimizeBehavior(TabBarMinimize.minimizesOnScrollDown(tab) ? .onScrollDown : .never)"))
    }
}
