import XCTest
@testable import JourneyPhoto

/// 端末の一冊から投稿の流れ（`LibraryTripModel`）へ、地名と時間帯を渡す（2026-10-17）。
///
/// 2026-10-18 判断: `LibraryTripModel` は `@MainActor` の型で、その静的メンバ（`forgetPlaceNames`）を
/// 呼ぶテストは `@MainActor` のテストのクラスに置く（`Tools/check-swift-refs.js` の 5 番）。
/// `DeviceTripsTests` 全体を `@MainActor` にすると、その検査がファイルごと外れるので、別のファイルに分ける
@MainActor
final class DeviceTripPostFlowTests: XCTestCase {

    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    /// 2026-09-12 00:00 JST
    private let base = Date(timeIntervalSince1970: 1_789_138_800)
    private let home = (lat: 35.68, lng: 139.76)    // 東京
    private let kyoto = (lat: 35.01, lng: 135.77)   // 約370km

    /// 家の日常20枚＋京都の旅6枚（`DeviceTripsTests` と同じ形）
    private func library() -> [LibraryShot] {
        (0..<20).map { LibraryShot(id: "h\($0)", date: base.addingTimeInterval((-24 * 30 + Double($0) * 5) * 3600),
                                   lat: home.lat, lng: home.lng) }
            + (0..<6).map { LibraryShot(id: "k\($0)", date: base.addingTimeInterval((10 + Double($0)) * 3600),
                                        lat: kyoto.lat, lng: kyoto.lng) }
    }

    /// 🔴 **投稿の流れは、棚が引いた地名と時間帯をそのまま使う**（2026-10-17）。
    /// もう一度地図に聞くと、一冊につき1回の約束を破り、答えが返るまで日が目安のままになる。
    /// 時間帯が無い地名だけは写さない（写すと、流れが時間帯を引きに行かなくなる）
    func testPostFlowReusesThePlaceTheShelfAlreadyLookedUp() async throws {
        LibraryTripModel.forgetPlaceNames()
        defer { LibraryTripModel.forgetPlaceNames() }
        let trip = try XCTUnwrap(DeviceTrips.found(in: library()).first)
        let model = LibraryTripModel()
        model.adoptDevicePlace(of: trip, names: [trip.id: "京都市"], zones: [:])
        XCTAssertNil(model.name(for: trip.center), "時間帯の無い地名を覚えると、流れが時間帯を引きに行けない")
        XCTAssertNil(model.zone(for: trip.center))

        model.adoptDevicePlace(of: trip, names: [trip.id: "京都市"], zones: [trip.id: tokyo.identifier])
        XCTAssertEqual(model.name(for: trip.center), "京都市")
        XCTAssertEqual(model.zone(for: trip.center)?.identifier, tokyo.identifier)
        // 流れが先に覚えた分は、棚の別の答えで上書きしない
        model.adoptDevicePlace(of: trip, names: [trip.id: "別の市"], zones: [trip.id: "Europe/Paris"])
        XCTAssertEqual(model.name(for: trip.center), "京都市")
        XCTAssertEqual(model.zone(for: trip.center)?.identifier, tokyo.identifier)

        let list = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto/Features/Trips/LibraryTripListView.swift"), encoding: .utf8)
        let task = try XCTUnwrap(list.range(of: "model.adoptDevicePlace"))
        let load = try XCTUnwrap(list.range(of: "await model.load"))
        XCTAssertLessThan(task.lowerBound, load.lowerBound, "地名を写す前に旅を探している")
        let book = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto/Features/Trips/DeviceTripShelf.swift"), encoding: .utf8)
        XCTAssertTrue(book.contains("DeviceTrips.shown(trip, trips: store.trips, zones: store.zones)"))
        XCTAssertTrue(book.contains("openTripImport(shown)"))
    }
}
