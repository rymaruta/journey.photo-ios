import XCTest

@testable import JourneyPhoto

/// 使い勝手の見直し（2026-11-16）の「見つける」の段: 地図の札（A7）・マップ（A9）・探す（A10）
@MainActor
final class FindStageUXTests: XCTestCase {

    // MARK: A7 地図を押せば札が閉じる

    /// 🔴 **ピンの上を押したときは閉じない**——ピンのボタンが札を開く合図と同時に届くので、
    /// ここで閉じると開いた札がすぐ消える。空いている所なら閉じる
    func testTappingTheMapClosesTheCardButNotOnAPin() async {
        let pins = [CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 400)]
        XCTAssertTrue(MapCardDismiss.closes(tap: CGPoint(x: 200, y: 250), pinPoints: pins))
        XCTAssertFalse(MapCardDismiss.closes(tap: CGPoint(x: 100, y: 100), pinPoints: pins), "ピンの真上で閉じた")
        XCTAssertFalse(MapCardDismiss.closes(tap: CGPoint(x: 120, y: 120), pinPoints: pins),
                       "ピンの印（44pt）の角を押して閉じた")
        XCTAssertTrue(MapCardDismiss.closes(tap: CGPoint(x: 140, y: 140), pinPoints: pins))
        XCTAssertTrue(MapCardDismiss.closes(tap: .zero, pinPoints: []), "ピンが無い地図で閉じない")
    }

    // MARK: A9 マップ

    /// 3つ目の札は写真の撮影地の一覧なので「撮影地」（場所の呼び名の決まり）。識別子は変えない
    func testListModeIsCalledShootingPlaces() async {
        XCTAssertEqual(PhotoMapViewModel.Mode.list.label, "撮影地")
        XCTAssertEqual(PhotoMapViewModel.Mode.list.tabIdentifier, "map.mode.list")
        XCTAssertEqual(PhotoMapViewModel.Mode.allCases.map(\.label), ["地図", "スポット", "撮影地"])
    }

    /// 「このエリアを検索」は指で地図を動かした後だけ。絞っている間は解除の口として出し続ける
    func testSearchThisAreaAppearsOnlyAfterTheMapMoved() async {
        XCTAssertFalse(MapAreaButton.shows(areaApplied: false, movedByUser: false), "開いたばかりの地図で出した")
        XCTAssertTrue(MapAreaButton.shows(areaApplied: false, movedByUser: true))
        XCTAssertTrue(MapAreaButton.shows(areaApplied: true, movedByUser: false), "範囲の解除の口を消した")
    }

    /// 種類のチップで観光スポットのピンを隠しているときだけ1行で知らせる（隠すピンが無ければ言わない）
    func testCategoryNoteOnlyWhenSpotsAreActuallyHidden() async {
        XCTAssertTrue(PhotoMapViewModel.categoryHidesSpots(category: "landscape", wouldShow: 3))
        XCTAssertFalse(PhotoMapViewModel.categoryHidesSpots(category: "landscape", wouldShow: 0))
        XCTAssertFalse(PhotoMapViewModel.categoryHidesSpots(category: nil, wouldShow: 3))
        XCTAssertEqual(PhotoMapView.categoryHidesSpotsLine("風景"), "「風景」で絞っている間は、観光スポットを出しません")
        XCTAssertFalse(PhotoMapView.categoryHidesSpotsLine("風景").contains("・"))
    }

    /// 札の「行きたい」の模型の寸法（高さ 44・押せる大きさ）
    func testCardButtonsKeepTheTapTarget() async {
        XCTAssertGreaterThanOrEqual(PhotoMapView.cardButtonHeight, 44)
        XCTAssertEqual(PhotoMapView.categoryNoteHeight, 36)
    }

    // MARK: A10 探す

    /// 明朝の「探す」は下へ送ったら・字を打ったら畳む。頭に戻って空なら出し直す
    func testSearchTitleFoldsWhenScrolledOrTyped() async {
        XCTAssertTrue(SearchHeader.showsTitle(scrolledDown: false, query: ""))
        XCTAssertFalse(SearchHeader.showsTitle(scrolledDown: true, query: ""), "下へ送っても大見出しが残る")
        XCTAssertFalse(SearchHeader.showsTitle(scrolledDown: false, query: "京都"), "字を打っても大見出しが残る")
        XCTAssertTrue(SearchHeader.showsTitle(scrolledDown: false, query: "  "))
        // 畳む・出すの行き来でちらつかない（畳むのは 24 送ってから、出すのは 4 まで戻ってから）
        XCTAssertFalse(SearchHeader.scrolledDown(top: -10, was: false))
        XCTAssertTrue(SearchHeader.scrolledDown(top: -30, was: false))
        XCTAssertTrue(SearchHeader.scrolledDown(top: -10, was: true), "少し戻しただけで出し直してちらつく")
        XCTAssertFalse(SearchHeader.scrolledDown(top: 0, was: true))
    }

    /// 範囲のチップは字を打ってから。選んだ範囲が残っていれば外せるように出す
    func testScopeChipsAppearAfterTyping() async {
        XCTAssertFalse(SearchHeader.showsScopeChips(query: "", scopeIsAll: true), "打つ前に範囲のチップを出した")
        XCTAssertTrue(SearchHeader.showsScopeChips(query: "京都", scopeIsAll: true))
        XCTAssertTrue(SearchHeader.showsScopeChips(query: "", scopeIsAll: false), "選んだ範囲を外す口を消した")
    }
}
