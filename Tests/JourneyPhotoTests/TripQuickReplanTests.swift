import XCTest
@testable import JourneyPhoto

/// 「もっとゆっくり」「雨なら」を AI を使わずに組み直す（2026-11-24・owner「『もっとゆっくり』とかのボタンの使い勝手悪すぎる」）
final class TripQuickReplanTests: XCTestCase {

    private func spot(_ id: String, _ category: String, lat: Double, lng: Double, prefecture: String = "石川県") throws -> OfficialSpot {
        let json = """
        {"spotId":"\(id)","slug":"\(id)","name":"\(id)","stage":"published","category":"\(category)",
         "coords":{"lat":\(lat),"lng":\(lng)},"region":{"prefecture":"\(prefecture)"}}
        """
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data(json.utf8))
    }

    private func item(_ id: String) -> TripItem { .spot(spotId: id, note: nil) }
    private func ids(_ days: [TripDay]) -> [[String]] {
        days.map { $0.items.compactMap { if case .spot(let id, _) = $0 { return id } else { return nil } } }
    }

    // MARK: - もっとゆっくり

    func testSlowerCap() {
        XCTAssertEqual(TripQuickReplan.slowerCap([5, 2]), 3)
        XCTAssertEqual(TripQuickReplan.slowerCap([4]), 3)
        XCTAssertEqual(TripQuickReplan.slowerCap([3, 3]), 2)
        XCTAssertNil(TripQuickReplan.slowerCap([2, 1]), "2か所以下はもう減らさない")
        XCTAssertNil(TripQuickReplan.slowerCap([]))
    }

    /// 見本のプラン（金沢・福井の旅）の形: 1日目 3か所（うち千里浜だけ遠い）、2日目 2か所。
    /// 押すと 1日2か所までになり、遠回りの千里浜を外す（2日目は空きが無いので「外しました　戻す」へ）
    func testSlowerDropsTheOutOfWayPlaceFirst() throws {
        let rows = [
            try spot("higashi", "町並み", lat: 36.572, lng: 136.666),
            try spot("castle", "城", lat: 36.565, lng: 136.659),
            try spot("chirihama", "海岸", lat: 36.89, lng: 136.77),
            try spot("kochomon", "海岸", lat: 36.0, lng: 135.95, prefecture: "福井県"),
            try spot("echizen", "岬", lat: 35.98, lng: 135.96, prefecture: "福井県"),
        ]
        let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.spotId, $0) })
        let days = [TripDay(date: "2026-12-24", items: [item("higashi"), item("chirihama"), item("castle")]),
                    TripDay(date: "2026-12-25", items: [item("kochomon"), item("echizen")])]
        let r = TripQuickReplan.slower(days) { if case .spot(let id, _) = $0 { return byId[id]?.coords } else { return nil } }
        XCTAssertTrue(r.changed)
        XCTAssertEqual(ids(r.days), [["higashi", "castle"], ["kochomon", "echizen"]])
        XCTAssertEqual(r.dropped, [TripAIRevise.Dropped(day: 0, index: 1, item: item("chirihama"))])
        XCTAssertEqual(r.days.map(\.date), ["2026-12-24", "2026-12-25"], "日付は変えない")
        XCTAssertEqual(r.line, L("1日2か所までにしました。1か所を外しました", ""))
    }

    /// あふれた所は、空きのある別の日の近くへ移す（30km 以内）。遠ければ外す
    func testSlowerMovesToANearbyDayWithRoom() throws {
        let a = try spot("a", "寺社", lat: 35.00, lng: 135.70)
        let b = try spot("b", "寺社", lat: 35.00, lng: 135.71)
        let c = try spot("c", "寺社", lat: 35.00, lng: 135.72)
        let d = try spot("d", "寺社", lat: 35.00, lng: 135.80)   // a〜c から約8〜9km
        let e = try spot("e", "寺社", lat: 35.01, lng: 135.80)
        let byId = Dictionary(uniqueKeysWithValues: [a, b, c, d, e].map { ($0.spotId, $0) })
        let days = [TripDay(items: [item("a"), item("b"), item("c"), item("d")]), TripDay(items: [item("e")])]
        let r = TripQuickReplan.slower(days) { if case .spot(let id, _) = $0 { return byId[id]?.coords } else { return nil } }
        XCTAssertEqual(ids(r.days), [["a", "b", "c"], ["d", "e"]])
        XCTAssertEqual(r.moved, 1)
        XCTAssertTrue(r.dropped.isEmpty)
        // 撮影地（座標の無い行）は外さず残す
        let withLocation = [TripDay(items: [.location(slug: "金沢駅", note: nil), item("a"), item("b"), item("c")])]
        let r2 = TripQuickReplan.slower(withLocation) { if case .spot(let id, _) = $0 { return byId[id]?.coords } else { return nil } }
        XCTAssertTrue(r2.days[0].items.contains(.location(slug: "金沢駅", note: nil)))
        XCTAssertEqual(r2.days[0].items.count, 3, "4か所 → 1日3か所まで")
    }

    func testSlowerAtTwoADayDoesNothing() {
        let days = [TripDay(items: [item("a"), item("b")])]
        let r = TripQuickReplan.slower(days) { _ in nil }
        XCTAssertFalse(r.changed)
        XCTAssertEqual(r.days, days)
        XCTAssertEqual(r.line, L("もう1日2か所までです。日程はそのままです", ""))
    }

    // MARK: - 雨なら

    /// 屋外の所を、20km 以内のいちばん近い屋内（日程に無い所）に同じ位置で替える。替えた元は「外しました　戻す」へ。メモは元に残る
    func testRainSwapsOutdoorForNearestIndoor() throws {
        let park = try spot("park", "公園", lat: 36.56, lng: 136.66)
        let temple = try spot("temple", "寺社", lat: 36.57, lng: 136.66)
        let museum = try spot("museum", "美術館", lat: 36.561, lng: 136.658)
        let farMuseum = try spot("far", "博物館", lat: 37.5, lng: 137.3)
        let cape = try spot("cape", "岬", lat: 37.53, lng: 137.33)
        let lookup = Dictionary(uniqueKeysWithValues: [park, temple, museum, farMuseum, cape].map { ($0.spotId, $0) })
        let days = [TripDay(items: [.spot(spotId: "park", note: "朝いち"), item("temple")]),
                    TripDay(items: [item("cape"), item("far")])]
        let r = TripQuickReplan.rain(days, spots: lookup, pool: Array(lookup.values))
        XCTAssertEqual(ids(r.days), [["museum", "temple"], ["cape", "far"]], "岬の近くの博物館はもう日程にある")
        XCTAssertEqual(r.dropped, [TripAIRevise.Dropped(day: 0, index: 0, item: .spot(spotId: "park", note: "朝いち"))])
        XCTAssertEqual(r.swapped, 1)
        XCTAssertEqual(r.line, L("屋外の1か所を近くの屋内に替えました。1か所は近くに屋内が無いのでそのままです", ""))
    }

    func testRainWithNothingOutdoorSaysSo() throws {
        let temple = try spot("temple", "寺社", lat: 35, lng: 135)
        let r = TripQuickReplan.rain([TripDay(items: [item("temple")])], spots: ["temple": temple], pool: [temple])
        XCTAssertFalse(r.changed)
        XCTAssertEqual(r.line, L("雨でも回りやすい所ばかりです。日程はそのままです", ""))
    }

    /// 屋外と屋内の種類は重ならない
    func testCategoriesDoNotOverlap() {
        XCTAssertTrue(TripQuickReplan.outdoor.isDisjoint(with: TripQuickReplan.indoor))
    }

    /// チップは AI を呼ばない（画面のコードの形で確かめる: チップは `quick` へ、AI の `run` は「書いて頼む」だけ）
    func testChipsDoNotCallAI() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto/Features/Trips/AI/TripReplanViews.swift")
        let views = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(views.contains("quick(t)"))
        XCTAssertFalse(views.contains("run(t.title"), "チップが AI の組み直しを呼んでいる")
    }
}
