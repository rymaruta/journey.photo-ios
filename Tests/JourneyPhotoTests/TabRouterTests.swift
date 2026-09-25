import XCTest
@testable import JourneyPhoto

/// 下の「ホーム」をもう一度押したら、ホームのフィードが一番上へ戻る合図。
@MainActor
final class TabRouterTests: XCTestCase {

    /// 🔴 **選ばれている「ホーム」を押したときだけ合図を出す。**
    /// 別の札から来たときに出すと、ホームを開き直すたびに勝手に上へ飛ぶ
    func testOnlyReselectingHomeAsksToScrollToTop() async {
        let router = TabRouter()
        router.tabTapped(isHome: true, alreadySelected: false)   // 別の札からホームへ
        router.tabTapped(isHome: false, alreadySelected: true)   // 探すを開いたまま探す
        XCTAssertEqual(router.homeTopRequests, 0)

        router.tabTapped(isHome: true, alreadySelected: true)
        XCTAssertEqual(router.homeTopRequests, 1)
    }

    /// **回数で伝える。** 真偽値だと2回目に「変わっていない」と見なされて効かない
    func testEveryReselectCounts() async {
        let router = TabRouter()
        router.tabTapped(isHome: true, alreadySelected: true)
        router.tabTapped(isHome: true, alreadySelected: true)
        XCTAssertEqual(router.homeTopRequests, 2)
    }
}
