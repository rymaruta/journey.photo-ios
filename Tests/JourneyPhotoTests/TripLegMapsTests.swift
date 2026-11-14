import XCTest
@testable import JourneyPhoto

/// 区間の行を押すと Apple のマップを開く（2026-11-12 owner「Apple の地図を開いたり、何線に乗ればいいかはできる？」）。
/// 何線に乗るかはアプリの中では出せない（`MKDirectionsTransportType.transit` は到着時刻の見込みだけ）ので、
/// 公共交通の経路で Apple のマップを開き、地図のアプリに出させる。開く手段の決め方（`TripTravel.mapsMode`）を数で確かめる
final class TripLegMapsTests: XCTestCase {

    private func leg(_ a: (Double, Double), _ b: (Double, Double)) -> TripTravel.Leg {
        TripTravel.Leg(from: .init(name: "金沢駅", coords: Photo.Coords(lat: a.0, lng: a.1), number: 1),
                       to: .init(name: "兼六園", coords: Photo.Coords(lat: b.0, lng: b.1), number: 2))
    }

    /// 約 0.5km・約 1.1km・約 2.3km・約 60km
    private var veryNear: TripTravel.Leg { leg((36.5781, 136.6479), (36.5745, 136.6510)) }
    private var near: TripTravel.Leg { leg((36.5781, 136.6479), (36.5700, 136.6560)) }
    private var mid: TripTravel.Leg { leg((36.5781, 136.6479), (36.5622, 136.6626)) }
    private var far: TripTravel.Leg { leg((36.5781, 136.6479), (36.2376, 136.1260)) }

    private func e(_ mode: TripTravel.Mode, min: Int) -> TripTravel.Estimate { .init(mode: mode, seconds: min * 60) }

    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 測った距離の前提（区間の作りの値で、決め方の境目の両側にあること）
    func testDistancesUsedHere() {
        XCTAssertLessThan(veryNear.kilometers, TripTravel.walkOpenKm)
        XCTAssertGreaterThan(near.kilometers, TripTravel.walkOpenKm)
        XCTAssertLessThan(near.kilometers, TripTravel.walkFirstKm)
        XCTAssertGreaterThan(mid.kilometers, TripTravel.walkFirstKm)
    }

    /// 歩き 15 分以内は歩き、それより長ければ電車など（乗り換えを地図のアプリで見る）
    func testWalkWithinFifteenMinutesElseTransit() {
        XCTAssertEqual(TripTravel.mapsMode([e(.walking, min: 8), e(.transit, min: 9)], leg: near, settled: true), .walking)
        XCTAssertEqual(TripTravel.mapsMode([e(.walking, min: 15), e(.transit, min: 9)], leg: near, settled: true), .walking,
                       "15 分ちょうどは歩き")
        XCTAssertEqual(TripTravel.mapsMode([e(.walking, min: 16), e(.transit, min: 9)], leg: near, settled: true), .transit)
        XCTAssertEqual(TripTravel.mapsMode([e(.automobile, min: 50), e(.transit, min: 80)], leg: far, settled: true), .transit,
                       "車のほうが早くても、何線に乗るかを見せる電車など")
    }

    /// 電車などが返らない（路線が無い）区間は、返った車・歩きで開く（何も出ない公共交通の画面を開かない）
    func testNoTransitRouteFallsBack() {
        XCTAssertEqual(TripTravel.mapsMode([e(.automobile, min: 50)], leg: far, settled: true), .automobile)
        XCTAssertEqual(TripTravel.mapsMode([e(.walking, min: 22)], leg: near, settled: true), .walking)
        XCTAssertEqual(TripTravel.mapsMode([e(.automobile, min: 50)], leg: far, settled: false), .transit,
                       "まだ聞いている間は電車など（返れば電車など、返らなければ聞き終えたときに車）")
    }

    /// 見込みがまだ無い（聞いている・圏外・聞きすぎで止めた・返らない）: まっすぐ 1km 以内は歩き、ほかは電車など
    func testWithoutEstimatesUsesDistance() {
        for settled in [false, true] {
            XCTAssertEqual(TripTravel.mapsMode([], leg: veryNear, settled: settled), .walking)
            XCTAssertEqual(TripTravel.mapsMode([], leg: near, settled: settled), .transit)
            XCTAssertEqual(TripTravel.mapsMode([], leg: far, settled: settled), .transit)
        }
    }

    /// 行の字は、開く手段を先頭に（押す前に何で開くかが分かる）。ほかは聞いた順
    func testRowShowsTheOpenedModeFirst() {
        let returned = [e(.automobile, min: 50), e(.transit, min: 80)]
        let mode = TripTravel.mapsMode(returned, leg: far, settled: true)
        XCTAssertEqual(TripTravel.ordered(returned, first: mode).map(\.mode), [.transit, .automobile])
        let walk = [e(.walking, min: 10), e(.transit, min: 9)]
        XCTAssertEqual(TripTravel.ordered(walk, first: .walking).map(\.mode), [.walking, .transit])
        XCTAssertEqual(TripTravel.ordered([], first: .transit), [])
    }

    /// 押したときの説明（読み上げのヒント）は開く手段で言う。公共交通は「何線に乗るか」が地図のアプリに出ると言う
    func testHintSaysWhatOpens() {
        XCTAssertEqual(TripLegRow.hint(.estimates, mode: .transit),
                       "Apple のマップで、電車などの経路を開きます。何線に乗るか、乗り換え、時刻が出ます")
        XCTAssertEqual(TripLegRow.hint(.loading, mode: .walking), "Apple のマップで、歩きの経路を開きます")
        XCTAssertEqual(TripLegRow.hint(.unavailable, mode: .automobile), "Apple のマップで、車の経路を開きます")
        XCTAssertTrue(TripLegRow.hint(.long, mode: .transit).contains("Google フライト"), "長い移動はシート（前と同じ）")
    }

    /// 並びが変わる（≡ で運ぶ・外す・戻す・足す）と区間の鍵が変わり、日程の画面は `.task(id: layout.key)` で聞き直す
    func testReorderChangesTheLegKeySoTheScreenAsksAgain() throws {
        let a = TripTravel.Stop("金沢駅", Photo.Coords(lat: 36.5781, lng: 136.6479), 1)
        let b = TripTravel.Stop("兼六園", Photo.Coords(lat: 36.5622, lng: 136.6626), 2)
        let c = TripTravel.Stop("東尋坊", Photo.Coords(lat: 36.2376, lng: 136.1260), 3)
        func key(_ days: [[TripTravel.Stop]]) -> String {
            TripTravel.planLegs(days).flatMap { $0 }.map(\.key).joined(separator: ";")
        }
        let before = key([[a, b, c]])
        XCTAssertNotEqual(before, key([[a, c, b]]), "運ぶ")
        XCTAssertNotEqual(before, key([[a, c]]), "外す")
        XCTAssertEqual(before, key([[a, b, c]]), "戻すと同じ鍵（控えの見込みを使う・聞き直さない）")
        XCTAssertEqual(before, key([[a, b], [c]]), "日を替えても同じ区間（前の日からの区間）は同じ鍵で控えを使う")
        let detail = try source("Sources/JourneyPhoto/Features/Trips/TripPlanDetailView.swift")
        XCTAssertTrue(detail.contains("var key: String { all.map(\\.key).joined(separator: \";\") }"))
        XCTAssertTrue(detail.contains(".task(id: layout.key) { requestTravel(layout.all) }"))
    }

    /// 行を押すと Apple のマップ（区間の両端・開く手段）。シートの Apple のボタンも同じ部品。
    /// 長い移動はシート。名前で探し直してから渡す。今いる場所は使わない
    func testRowOpensAppleMapsDirectly() throws {
        let views = try source("Sources/JourneyPhoto/Features/Trips/TripLegViews.swift")
        XCTAssertTrue(views.contains("guard state != .long else { details(); return }"))
        XCTAssertTrue(views.contains(".open(leg, mode: mode, search: search)"), "行は Apple のマップを開く")
        XCTAssertTrue(views.contains(".open(leg, mode: mode, search: true)"), "シートも同じ部品")
        XCTAssertTrue(views.contains("MKMapItem.openMaps(with: [origin, target], launchOptions: launchOptions(mode))"),
                      "出発と到着の2つを渡す（1つだと今いる場所から）")
        XCTAssertTrue(views.contains(".accessibilityIdentifier(\"trip.leg.more\")"), "出る時刻の目安とGoogle マップへの入口")
        XCTAssertFalse(views.contains("openMode("), "古い決め方を残さない")
        XCTAssertFalse(views.contains("forCurrentLocation"), "今いる場所を取らない")
        let detail = try source("Sources/JourneyPhoto/Features/Trips/TripPlanDetailView.swift")
        XCTAssertTrue(detail.contains("mode: TripTravel.mapsMode(estimates, leg: leg, settled: settled)"),
                      "シートの手段は行と同じ決め方")
    }

    /// 画面の文に禁止の区切り（・ ·）を新しく入れていない
    func testNewWordingHasNoDots() {
        for mode in TripTravel.Mode.allCases {
            let hint = TripTravel.mapsHint(mode)
            XCTAssertFalse(hint.contains("・") || hint.contains("·"), hint)
        }
    }
}
