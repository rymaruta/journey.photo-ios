import XCTest
@testable import JourneyPhoto

/// 「行きたい場所」の地図から旅行プランを作る（`SavedSpotsTrip`）。
///
/// 選択の出し入れ・近い順の案（同じ座標・1件・日付変更線の付近）・プランへ渡す中身・
/// どのプランに入っているかの突き合わせ
final class SavedSpotsTripTests: XCTestCase {

    private func spot(_ slug: String, name: String, coords: (Double, Double)?,
                      prefecture: String = "京都府") throws -> OfficialSpot {
        let c = coords.map { ",\"coords\":{\"lat\":\($0.0),\"lng\":\($0.1)}" } ?? ""
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data(
            "{\"spotId\":\"sp_\(slug)\",\"slug\":\"\(slug)\",\"name\":\"\(name)\",\"stage\":\"published\",\"region\":{\"prefecture\":\"\(prefecture)\"}\(c)}".utf8))
    }

    private func official(_ slug: String, _ lat: Double, _ lng: Double,
                          prefecture: String = "京都府") throws -> SavedSpotsMap.Item {
        let rows = OfficialWishlist.rows(keys: ["SPOT-\(slug)"],
                                         index: [try spot(slug, name: slug, coords: (lat, lng), prefecture: prefecture)])
        return SavedSpotsMap.item(try XCTUnwrap(rows.first))
    }

    private func place(_ slug: String, _ lat: Double, _ lng: Double) -> SavedSpotsMap.Item {
        SavedSpotsMap.item(DerivedSpot.Place(label: slug.capitalized, slug: slug, photos: [], broader: [],
                                             categories: [], coords: Photo.Coords(lat: lat, lng: lng)))
    }

    // MARK: - 選択の出し入れ

    /// 押すと入り、押し直すと外れる。押した順を覚える
    func testToggleAddsAndRemovesInOrder() {
        var s = SavedSpotsTrip.Selection()
        XCTAssertTrue(s.isEmpty)
        XCTAssertTrue(s.toggle("a"))
        XCTAssertTrue(s.toggle("b"))
        XCTAssertTrue(s.toggle("c"))
        XCTAssertEqual(s.keys, ["a", "b", "c"])
        XCTAssertTrue(s.toggle("b"), "押し直すと外れる")
        XCTAssertEqual(s.keys, ["a", "c"])
        XCTAssertFalse(s.contains("b"))
        s.remove("a")
        XCTAssertEqual(s.keys, ["c"])
        XCTAssertEqual(s.count, 1)
    }

    /// 上限を越えては足さない（外すのはできる）
    func testToggleStopsAtTheLimit() {
        var s = SavedSpotsTrip.Selection()
        for i in 0..<SavedSpotsTrip.selectMax { XCTAssertTrue(s.toggle("k\(i)")) }
        XCTAssertFalse(s.toggle("over"))
        XCTAssertEqual(s.count, SavedSpotsTrip.selectMax)
        XCTAssertTrue(s.toggle("k0"), "上限でも外せる")
        XCTAssertTrue(s.toggle("over"))
    }

    /// 地図に無い鍵（開いている間に外れたもの）は数えない
    func testSelectionItemsDropMissingKeys() {
        let a = place("a", 35, 135)
        var s = SavedSpotsTrip.Selection()
        s.toggle("gone")
        s.toggle("a")
        XCTAssertEqual(s.items(in: [a]).map(\.key), ["a"])
    }

    /// 選べるのはプランに入れる鍵があるものだけ（スラッグの無い撮影地は選べない）
    func testCanSelect() throws {
        XCTAssertTrue(SavedSpotsTrip.canSelect(try official("a", 35, 135)))
        XCTAssertTrue(SavedSpotsTrip.canSelect(place("kyoto", 35, 135)))
        let noSlug = SavedSpotsMap.item(DerivedSpot.Place(label: "名前だけ", slug: "", photos: [], broader: [],
                                                          categories: [], coords: Photo.Coords(lat: 1, lng: 1)))
        XCTAssertFalse(SavedSpotsTrip.canSelect(noSlug))
        let unknown = SavedSpotsMap.item(OfficialWishlist.rows(keys: ["SPOT-gone"], index: [])[0])
        XCTAssertFalse(SavedSpotsTrip.canSelect(unknown), "索引に無いスポットは spotId が無い")
    }

    /// `SPOT-` で始まるスラッグの撮影地は `.location` にしない（スポットの鍵と混ぜない・`SavedSpotKey`）
    func testPlaceWithOfficialLookingSlugIsNotSelectable() {
        let odd = SavedSpotsMap.item(DerivedSpot.Place(label: "紛らわしい", slug: "SPOT-kiyomizu", photos: [],
                                                       broader: [], categories: [],
                                                       coords: Photo.Coords(lat: 35, lng: 135)))
        XCTAssertNil(SavedSpotsTrip.tripItem(odd))
        XCTAssertFalse(SavedSpotsTrip.canSelect(odd))
        XCTAssertNil(SavedSpotsTrip.draft([odd]))
    }

    // MARK: - 近い順

    /// 最初に選んだ場所から、いちばん近い未訪の場所へ進む
    func testNearestOrderIsGreedyFromTheFirstPick() {
        let tokyo = place("tokyo", 35.68, 139.76)
        let osaka = place("osaka", 34.69, 135.50)
        let kyoto = place("kyoto", 35.01, 135.77)
        let sapporo = place("sapporo", 43.06, 141.35)
        // 選んだ順: 東京・大阪・札幌・京都
        let order = SavedSpotsTrip.nearestOrder([tokyo, osaka, sapporo, kyoto]).map(\.key)
        // 東京 → 京都（東京から最も近い）→ 大阪 → 札幌
        XCTAssertEqual(order, ["tokyo", "kyoto", "osaka", "sapporo"])
    }

    /// **いまいる場所から**近い順（貪欲法）。「最初の場所からの距離で並べるだけ」とは答えが違う例:
    /// 赤道上の A(0°)・B(東 1°)・C(西 1.5°)・D(東 2°)。A からの距離順なら A・B・C・D だが、
    /// B に着いたら D（1°）が C（2.5°）より近い → A・B・D・C
    func testNearestOrderMovesFromTheCurrentPlace() {
        let a = place("a", 0, 0)
        let b = place("b", 0, 1)
        let c = place("c", 0, -1.5)
        let d = place("d", 0, 2)
        XCTAssertEqual(SavedSpotsTrip.nearestOrder([a, c, d, b]).map(\.key), ["a", "b", "d", "c"])
    }

    /// 1件はそのまま・0件は空
    func testNearestOrderSingleAndEmpty() {
        let a = place("a", 35, 135)
        XCTAssertEqual(SavedSpotsTrip.nearestOrder([a]).map(\.key), ["a"])
        XCTAssertTrue(SavedSpotsTrip.nearestOrder([]).isEmpty)
    }

    /// 同じ座標は選んだ順のまま（毎回同じ並び）。同じ鍵は1度だけ
    func testNearestOrderSameCoordinatesKeepPickOrder() {
        let a = place("a", 35, 135)
        let b = place("b", 35, 135)
        let c = place("c", 35, 135)
        XCTAssertEqual(SavedSpotsTrip.nearestOrder([c, a, b]).map(\.key), ["c", "a", "b"])
        XCTAssertEqual(SavedSpotsTrip.nearestOrder([a, b, a]).map(\.key), ["a", "b"])
    }

    /// 日付変更線の付近: 東経 179.9° の次は（経度の数では遠い）西経 179.9° が近い
    func testNearestOrderAcrossTheDateLine() {
        let east = place("east", -16.5, 179.9)     // フィジーの東
        let fiji = place("fiji", -17.7, 178.0)
        let west = place("west", -16.5, -179.9)    // 線の向こう側
        let tonga = place("tonga", -21.1, -175.2)
        // east から: west（約 22km）が fiji（約 230km）より近い
        let order = SavedSpotsTrip.nearestOrder([east, fiji, tonga, west]).map(\.key)
        XCTAssertEqual(order.first, "east")
        XCTAssertEqual(order[1], "west", "日付変更線の向こうでも近ければ次に回る")
        XCTAssertEqual(Set(order), ["east", "west", "fiji", "tonga"])
    }

    // MARK: - プランへの受け渡し

    /// 中身: 近い順の `TripItem`（スポットは spotId、撮影地は slug）・日付なし・題は地域から
    func testDraftCarriesOrderedTripItems() throws {
        let kyoto = try official("kiyomizu", 34.99, 135.78)
        let nara = try official("todaiji", 34.69, 135.84, prefecture: "奈良県")
        let osaka = place("osaka", 34.69, 135.50)
        // 選んだ順: 清水寺・大阪・東大寺 → 近い順: 清水寺・東大寺（約 34km。大阪は約 42km）・大阪
        let draft = try XCTUnwrap(SavedSpotsTrip.draft([kyoto, osaka, nara]))
        XCTAssertEqual(draft.days.count, 1)
        XCTAssertNil(draft.days[0].date, "日付は日程の画面で入れる（送らない）")
        XCTAssertEqual(draft.days[0].items, [
            .spot(spotId: "sp_kiyomizu", note: nil),
            .spot(spotId: "sp_todaiji", note: nil),
            .location(slug: "osaka", note: nil),
        ])
        XCTAssertEqual(draft.title, "京都府・奈良県の旅")
    }

    /// 撮影地だけなら地域が無いので「行きたい場所の旅」
    func testDraftTitleFallsBackWithoutRegions() throws {
        let draft = try XCTUnwrap(SavedSpotsTrip.draft([place("a", 1, 1)]))
        XCTAssertEqual(draft.title, "行きたい場所の旅")
        XCTAssertEqual(draft.days[0].items, [.location(slug: "a", note: nil)])
    }

    /// 1日の上限（サーバーの 20 か所）を越えたら次の日へ。場所は落とさない
    func testDraftSplitsDaysAtTheServerLimit() throws {
        let items = (0..<25).map { place("p\($0)", 35 + Double($0) * 0.01, 135) }
        let draft = try XCTUnwrap(SavedSpotsTrip.draft(items))
        XCTAssertEqual(draft.days.map(\.items.count), [TripPlanService.itemsPerDayMax, 5])
        XCTAssertEqual(draft.days.flatMap(\.items).count, 25)
    }

    /// 入れられる場所が無ければ作らない
    func testDraftIsNilWithoutUsableItems() {
        let noSlug = SavedSpotsMap.item(DerivedSpot.Place(label: "x", slug: "", photos: [], broader: [],
                                                          categories: [], coords: Photo.Coords(lat: 1, lng: 1)))
        XCTAssertNil(SavedSpotsTrip.draft([noSlug]))
        XCTAssertNil(SavedSpotsTrip.draft([]))
    }

    func testCreateLabel() {
        XCTAssertEqual(SavedSpotsTrip.createLabel(count: 3), "この 3 か所で旅行プランを作る")
    }

    // MARK: - どのプランに入っているか

    func testMembershipMatchesPlans() throws {
        let kyoto = try official("kiyomizu", 34.99, 135.78)
        let osaka = place("osaka", 34.69, 135.50)
        let other = place("nara", 34.68, 135.80)
        let plans = [
            TripPlan(planId: "p1", title: "関西の旅", days: [
                TripDay(items: [.spot(spotId: "sp_kiyomizu", note: nil), .location(slug: "osaka", note: "朝")]),
                TripDay(items: [.spot(spotId: "sp_kiyomizu", note: nil)]),   // 同じプランに2度でも1度
            ]),
            TripPlan(planId: "p2", title: "", days: [TripDay(items: [.spot(spotId: "sp_kiyomizu", note: nil)])]),
        ]
        let m = SavedSpotsTrip.membership(plans)
        XCTAssertEqual(SavedSpotsTrip.plans(containing: kyoto, in: m), ["関西の旅", "無題のプラン"])
        XCTAssertEqual(SavedSpotsTrip.plans(containing: osaka, in: m), ["関西の旅"], "ひとことが付いていても同じ場所")
        XCTAssertEqual(SavedSpotsTrip.plans(containing: other, in: m), [])
        XCTAssertEqual(SavedSpotsTrip.membershipPhrase(["関西の旅"]), "旅行プラン「関西の旅」に入っています")
        XCTAssertEqual(SavedSpotsTrip.membershipPhrase(["a", "b"]), "旅行プラン 2 件に入っています")
        XCTAssertNil(SavedSpotsTrip.membershipPhrase([]))
    }
}
