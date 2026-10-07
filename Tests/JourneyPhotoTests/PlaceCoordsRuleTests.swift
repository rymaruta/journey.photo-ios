import XCTest
@testable import JourneyPhoto

/// 撮影地と一緒に写真の座標を送るかの共通の決まり（`PlaceCoordsRule`・2026-10-07 判断）。
/// 投稿・編集・ストーリーが同じ (a)(b)(c) で決める
final class PlaceCoordsRuleTests: XCTestCase {

    private func spot(_ slug: String, name: String, lat: Double, lng: Double) -> OfficialSpot {
        let json = #"{"spotId":"sp_\#(slug)","slug":"\#(slug)","name":"\#(name)","stage":"published","coords":{"lat":\#(lat),"lng":\#(lng)}}"#
        return try! JSONDecoder.api.decode(OfficialSpot.self, from: Data(json.utf8))
    }

    private let taken = Photo.Coords(lat: 34.13, lng: 133.64)
    private var spots: [OfficialSpot] { [spot("takaya", name: "高屋神社", lat: 34.14, lng: 133.64)] }

    private func pending() -> PendingPhoto {
        PendingPhoto(prepared: ImagePreparer.Prepared(data: Data(), fileName: "p.jpg", contentType: "image/jpeg",
                                                      exif: nil, coords: taken, takenOn: nil))
    }

    // MARK: - 投稿 (c)

    /// 地名の自動入力が時間切れで、近くのスポットの名前を正しく打った → 写真の座標を残す
    func testUploadTypedNearbySpotNameKeepsPhotoCoords() {
        var item = pending()
        item.location = "高屋神社"
        XCTAssertEqual(item.coordsToSend(spots: spots), taken)
        XCTAssertNil(item.coordsToSend(spots: []), "索引が無ければ (c) は当たらない")
        XCTAssertTrue(item.needsSpotIndex)
    }

    /// 自動で入ったスポット名に「, 観音寺市」を手で足した → 写真の座標を残す。「東京」は送らない
    func testUploadAppendedAreaToSpotKeepsPhotoCoords() {
        var item = pending()
        item.fillAutomatically("高屋神社")
        XCTAssertFalse(item.needsSpotIndex, "自動の地名のままなら索引は要らない")
        item.location = "高屋神社, 観音寺市"
        XCTAssertEqual(item.coordsToSend(spots: spots), taken)
        item.location = "東京"
        XCTAssertNil(item.coordsToSend(spots: spots))
        // 写真から 5km より遠いスポットの名前でも送らない
        let far = [spot("tower", name: "東京タワー", lat: 35.66, lng: 139.75)]
        item.location = "東京タワー"
        XCTAssertNil(item.coordsToSend(spots: far))
    }

    // MARK: - 編集 (c)

    /// 編集でスポット名に「, 香川」を足しても、写真の近くのスポットならピンを消さない
    func testEditAppendingAreaToNearbySpotKeepsPin() {
        XCTAssertFalse(EditPlaceRules.clearsCoords(openedLocation: "高屋神社", currentLocation: "高屋神社, 香川",
                                                   pickedCoords: false, photoCoords: taken, spots: spots))
        XCTAssertTrue(EditPlaceRules.clearsCoords(openedLocation: "高屋神社", currentLocation: "東京",
                                                  pickedCoords: false, photoCoords: taken, spots: spots))
        XCTAssertTrue(EditPlaceRules.clearsCoords(openedLocation: "高屋神社", currentLocation: "",
                                                  pickedCoords: false, photoCoords: taken, spots: spots))
        XCTAssertTrue(EditPlaceRules.keepsCoordsOnReplace(openedLocation: "高屋神社", openedHasCoords: true,
                                                          currentLocation: "高屋神社, 香川",
                                                          newPhotoCoords: taken, spots: spots))
        XCTAssertTrue(EditPlaceRules.needsSpotIndex(openedLocation: "高屋神社", currentLocation: "高屋神社, 香川",
                                                    pickedCoords: false, photoCoords: taken))
        XCTAssertFalse(EditPlaceRules.needsSpotIndex(openedLocation: "高屋神社", currentLocation: "高屋神社",
                                                     pickedCoords: false, photoCoords: taken))
    }

    // MARK: - 索引を待つ

    /// 要らない・もうある → 読まない。要る → 読む。遅すぎる → 待たずに空（写真の座標を送らない側）
    func testIndexIsFetchedOnlyWhenNeededWithTimeout() async {
        let fetched = spots
        let unused = await PlaceCoordsRule.index(current: [], needed: false, fetch: {
            XCTFail("要らないのに読んだ"); return nil
        })
        XCTAssertTrue(unused.isEmpty)
        let kept = await PlaceCoordsRule.index(current: fetched, needed: true, fetch: {
            XCTFail("もうあるのに読んだ"); return nil
        })
        XCTAssertEqual(kept.map(\.slug), ["takaya"])
        let loaded = await PlaceCoordsRule.index(current: [], needed: true, fetch: { fetched })
        XCTAssertEqual(loaded.map(\.slug), ["takaya"])
        let slow = await PlaceCoordsRule.index(current: [], needed: true, wait: .milliseconds(50), fetch: {
            try? await Task.sleep(for: .seconds(5))
            return fetched
        })
        XCTAssertTrue(slow.isEmpty)
    }

    /// ストーリー: 撮影地があり GPS の写真があって索引が無いときだけ待つ
    func testStoryWaitsForIndexOnlyWhenNeeded() {
        var place = StorySpotSuggestion.Place()
        XCTAssertFalse(place.needsSpotIndex([taken], spots: []), "撮影地が空")
        place.location = "高屋神社"
        XCTAssertTrue(place.needsSpotIndex([taken], spots: []))
        XCTAssertFalse(place.needsSpotIndex([taken], spots: spots), "索引がある")
        XCTAssertFalse(place.needsSpotIndex([nil], spots: []), "GPS の写真が無い")
    }
}
