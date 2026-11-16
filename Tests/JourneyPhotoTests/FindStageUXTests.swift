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

    /// 🔴 **件数のバッジ（ピンの右上にはみ出す・中心から約 (32, -30)）を押しても閉じない**（確かめ役の指摘・2026-11-16）
    func testTappingTheCountBadgeDoesNotCloseTheCard() async {
        let pin = CGPoint(x: 100, y: 100)
        // バッジの位置を `PhotoMapView` の寸法から出す（右上の角に揃え、10・8 だけ外へ。バッジは 24）
        let half = PhotoMapView.photoPinSize / 2
        let badgeCorner = CGPoint(x: pin.x + half + PhotoMapView.badgeOffset.x, y: pin.y - half + PhotoMapView.badgeOffset.y)
        let badgeCenter = CGPoint(x: badgeCorner.x - 12, y: badgeCorner.y + 12)
        XCTAssertFalse(MapCardDismiss.closes(tap: badgeCorner, pinPoints: [pin]), "バッジの右上の角を押して閉じた")
        XCTAssertFalse(MapCardDismiss.closes(tap: badgeCenter, pinPoints: [pin]), "バッジを押して閉じた")
        XCTAssertTrue(MapCardDismiss.closes(tap: CGPoint(x: 100, y: 160), pinPoints: [pin]), "ピンの下の空いた所で閉じない")
        XCTAssertTrue(MapCardDismiss.closes(tap: CGPoint(x: 160, y: 100), pinPoints: [pin]), "ピンの右の空いた所で閉じない")
    }

    /// 2回たたいて寄せたら閉じない（2回目で予約を取り消す）。予約し直したら前の予約は効かない
    func testDoubleTapCancelsThePendingClose() async {
        var pending = MapCardDismiss.Pending()
        let first = pending.schedule()
        XCTAssertTrue(pending.isCurrent(first))
        pending.cancel()
        XCTAssertFalse(pending.isCurrent(first), "2回たたいても閉じる予約が残った")
        let second = pending.schedule()
        let third = pending.schedule()
        XCTAssertFalse(pending.isCurrent(second))
        XCTAssertTrue(pending.isCurrent(third))
        // 2回目は 1回目から約 0.3 秒以内に来るので、それより長く待つ
        XCTAssertGreaterThan(MapCardDismiss.closeDelayNanoseconds, 300_000_000)
    }

    /// 🔴 **2回目の押しは予約し直さない**（Mac run 1436: 2回押しの取り消しの後に2回目の1回押しが届き、閉じていた）。
    /// 間をあけた押しは、また予約する
    func testSecondTapOfADoubleTapDoesNotReschedule() async {
        var pending = MapCardDismiss.Pending()
        let t0 = Date(timeIntervalSince1970: 1000)
        let first = pending.tap(at: t0)
        XCTAssertNotNil(first)
        pending.cancel()   // 2回押しの合図が先に届いた
        XCTAssertNil(pending.tap(at: t0.addingTimeInterval(0.2)), "2回目の押しで閉じる予約をし直した")
        XCTAssertFalse(pending.isCurrent(first!))
        // 2回押しの合図が後から届いても、先に届いても、閉じる予約は残らない
        var other = MapCardDismiss.Pending()
        let a = other.tap(at: t0)!
        XCTAssertNil(other.tap(at: t0.addingTimeInterval(0.25)))
        XCTAssertFalse(other.isCurrent(a), "2回目の押しで1回目の予約が残った")
        // 間をあけた押しは、また予約する
        let later = other.tap(at: t0.addingTimeInterval(2))
        XCTAssertNotNil(later)
        XCTAssertTrue(other.isCurrent(later!))
    }

    /// 待つ間に札が替わったら（別の Apple の地点を押した）閉じない
    func testSnapshotDetectsANewCard() async {
        let before = MapCardDismiss.Snapshot(pin: nil, official: nil, place: "a")
        XCTAssertEqual(before, MapCardDismiss.Snapshot(pin: nil, official: nil, place: "a"))
        XCTAssertNotEqual(before, MapCardDismiss.Snapshot(pin: nil, official: nil, place: "b"))
        XCTAssertNotEqual(before, MapCardDismiss.Snapshot(pin: "p", official: nil, place: nil))
    }

    /// 写真の詳細: 2回たたいたとき、いいねの状態が今の1枚の分でなければ何もしない（ハートも出さない）
    func testDoubleTapUsesOnlyTheCurrentPhotosLikedState() async {
        XCTAssertEqual(PhotoDetailRules.likedForDoubleTap(modelPhotoId: "p1", currentId: "p1", liked: true), true)
        XCTAssertEqual(PhotoDetailRules.likedForDoubleTap(modelPhotoId: "p1", currentId: "p1", liked: false), false)
        XCTAssertNil(PhotoDetailRules.likedForDoubleTap(modelPhotoId: "p0", currentId: "p1", liked: false),
                     "前の写真のいいねの状態で決めた")
    }

    /// 写真の詳細の配線: 2回たたく判定は今の1枚の値で、ハートは送るときだけ。写真・人が替わったら続きの読みを捨てる
    func testPhotoDetailDoubleTapAndReadyWiring() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let view = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/PhotoDetail/PhotoDetailView.swift"),
                              encoding: .utf8)
        let tap = try XCTUnwrap(view.components(separatedBy: "private func doubleTapLike(").dropFirst().first).prefix(1600)
        XCTAssertTrue(tap.contains("if auth.userId != nil, liked == nil { return }"), "今の1枚の値が無いのに先へ進む")
        XCTAssertTrue(tap.contains("alreadyLiked: liked ?? false"))
        XCTAssertFalse(tap.contains("alreadyLiked: model.liked"), "前の写真のいいねの状態で決めている")
        let task = try XCTUnwrap(view.components(separatedBy: ".task(id: PhotoDetailRules.reloadKey(").dropFirst().first).prefix(400)
        XCTAssertTrue(task.contains("reactionsReadyFor = nil"), "写真・人が替わっても前の読みで続きを送る")
    }

    /// 探す: 種類のチップも0件の間は畳み、選んでいれば残す
    func testCategoryChipsFoldOnZeroHit() async {
        XCTAssertFalse(SearchView.showsCategoryChips(zeroHit: true, categoryChosen: false))
        XCTAssertTrue(SearchView.showsCategoryChips(zeroHit: true, categoryChosen: true), "選んだ種類を外す手立てが消える")
        XCTAssertTrue(SearchView.showsCategoryChips(zeroHit: false, categoryChosen: false))
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
