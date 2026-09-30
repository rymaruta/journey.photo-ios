import XCTest
@testable import JourneyPhoto

/// 下の「ホーム」をもう一度押したら、ホームのフィードが一番上へ戻る合図。
/// 「マップ」をもう一度押したら、地図が現在地へ戻る合図。
@MainActor
final class TabRouterTests: XCTestCase {

    /// 🔴 **選ばれている「ホーム」を押したときだけ合図を出す。**
    /// 別の札から来たときに出すと、ホームを開き直すたびに勝手に上へ飛ぶ
    func testOnlyReselectingHomeAsksToScrollToTop() async {
        let router = TabRouter()
        router.tabTapped(.home, alreadySelected: false)   // 別の札からホームへ
        router.tabTapped(nil, alreadySelected: true)      // 探すを開いたまま探す
        XCTAssertEqual(router.homeTopRequests, 0)

        router.tabTapped(.home, alreadySelected: true)
        XCTAssertEqual(router.homeTopRequests, 1)
        XCTAssertEqual(router.mapLocateRequests, 0)
    }

    /// **回数で伝える。** 真偽値だと2回目に「変わっていない」と見なされて効かない
    func testEveryReselectCounts() async {
        let router = TabRouter()
        router.tabTapped(.home, alreadySelected: true)
        router.tabTapped(.home, alreadySelected: true)
        XCTAssertEqual(router.homeTopRequests, 2)
    }

    /// 🔴 **選ばれている「マップ」を押したときだけ現在地へ。** 別の札から
    /// 地図へ来たときに出すと、指で動かして見ていた場所から引き戻す。
    /// ホームの合図とは別の数で伝える（取り違えるとホームが上へ飛ぶ）
    func testOnlyReselectingMapAsksForCurrentLocation() async {
        let router = TabRouter()
        router.mapRootOnScreen = true
        router.tabTapped(.map, alreadySelected: false)    // 別の札から地図へ
        XCTAssertEqual(router.mapLocateRequests, 0)

        router.tabTapped(.map, alreadySelected: true)
        router.tabTapped(.map, alreadySelected: true)
        XCTAssertEqual(router.mapLocateRequests, 2)
        XCTAssertEqual(router.homeTopRequests, 0)
    }

    /// 🔴 **詳細を開いたまま押した1回目は、現在地へは行かない**（iOS が
    /// 地図まで戻すだけ）。押した瞬間に見るので、戻りで地図の `onAppear` が
    /// 先に走っても1回で両方は起きない
    func testReselectWithDetailPushedOnlyGoesBack() async {
        let router = TabRouter()
        router.mapRootOnScreen = false
        router.tabTapped(.map, alreadySelected: true)
        XCTAssertEqual(router.mapLocateRequests, 0)

        router.mapRootOnScreen = true   // 地図まで戻った
        router.tabTapped(.map, alreadySelected: true)
        XCTAssertEqual(router.mapLocateRequests, 1)
    }

    /// 下の札と合図の対応。取り違えると「マップ」でホームが上へ飛ぶ
    func testTabsMapToTheirReselectSignal() async {
        XCTAssertEqual(RootView.Tab.home.reselectable, .home)
        XCTAssertEqual(RootView.Tab.map.reselectable, .map)
        XCTAssertNil(RootView.Tab.search.reselectable)
        XCTAssertNil(RootView.Tab.post.reselectable)
        XCTAssertNil(RootView.Tab.mypage.reselectable)
    }

    /// 見出しの「探す」・メニューの「撮影地マップ」・見出しの「メニュー」は
    /// **それぞれ別の数で**伝える（1つにまとめると、どこへ移るか取り違える）
    func testHeaderAndMenuRoutesCountSeparately() async {
        let router = TabRouter()
        router.openSearch()
        router.openSearch()
        router.openMap()
        router.openMenu()
        XCTAssertEqual(router.searchRequests, 2)
        XCTAssertEqual(router.mapRequests, 1)
        XCTAssertEqual(router.menuRequests, 1)
        XCTAssertEqual(router.myPageRequests, 0)
    }

    /// 探すの0件の出口は語を地図へ渡す。地図は一度だけ受け取り、
    /// 語なしで開き直した回に古い語が残らない。空の語は地図の語を消す合図
    func testOpenMapCarriesQueryOnce() async {
        let router = TabRouter()
        router.openMap(query: "  京都 ")
        XCTAssertEqual(router.mapRequests, 1)
        XCTAssertEqual(router.takePendingMapQuery(rootOnScreen: true), "京都")
        XCTAssertNil(router.takePendingMapQuery(rootOnScreen: true))

        router.openMap(query: "奈良")
        router.openMap()
        XCTAssertEqual(router.mapRequests, 3)
        XCTAssertNil(router.takePendingMapQuery(rootOnScreen: true))

        // 空の語は「地図の前の語を消す」として渡す（タグで探した0件から）。語なし（nil）とは分ける
        router.openMap(query: "   ")
        XCTAssertEqual(router.takePendingMapQuery(rootOnScreen: true), "")
        router.openMap(query: "")
        XCTAssertEqual(router.takePendingMapQuery(rootOnScreen: true), "")
    }

    /// 地図に詳細を積んでいる間は渡さず残し、根に戻ったときに渡す
    /// （積んだまま絞ると、押した元の行が消えて詳細が黙って閉じる）
    func testPendingMapQueryWaitsForMapRoot() async {
        let router = TabRouter()
        router.openMap(query: "京都")
        XCTAssertNil(router.takePendingMapQuery(rootOnScreen: false))
        XCTAssertEqual(router.pendingMapQuery, "京都")
        XCTAssertEqual(router.takePendingMapQuery(rootOnScreen: true), "京都")
    }

    /// 人が下の札を押したら、残っていた語は捨てる（どの札でも・同じ札の押し直しでも）。
    /// 普通に「マップ」を開いた回に、前の語があとから当たらない
    func testTabTapDiscardsPendingMapQuery() async {
        let router = TabRouter()
        router.openMap(query: "京都")
        router.tabTapped(.map, alreadySelected: false)
        XCTAssertNil(router.takePendingMapQuery(rootOnScreen: true))

        router.openMap(query: "奈良")
        router.tabTapped(nil, alreadySelected: false)
        XCTAssertNil(router.takePendingMapQuery(rootOnScreen: true))

        // 地図の根を見ているときの押し直し（現在地へ）も捨てる
        router.mapRootOnScreen = true
        router.openMap(query: "神戸")
        router.tabTapped(.map, alreadySelected: true)
        XCTAssertNil(router.takePendingMapQuery(rootOnScreen: true))
    }

    /// 詳細を積んだ地図で「マップ」を押し直した回は捨てない。iOS が根まで戻し、
    /// その `onAppear` で待っていた語を受け取る
    func testTabTapBackToMapRootKeepsPendingMapQuery() async {
        let router = TabRouter()
        router.mapRootOnScreen = false
        router.openMap(query: "京都")
        router.tabTapped(.map, alreadySelected: true)
        XCTAssertEqual(router.mapLocateRequests, 0)
        XCTAssertEqual(router.takePendingMapQuery(rootOnScreen: true), "京都")
    }
}
