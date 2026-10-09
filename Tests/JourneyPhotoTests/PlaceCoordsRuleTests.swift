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

    /// 🔴 **取り消しに応えない読み込みでも、`wait` で戻る**（2026-10-09 owner「ストーリーで写真を選んだのに
    /// 投稿できない」）。以前は子タスクの組（`withTaskGroup`）で競わせていて、抜けるときに読み込みの終わりを
    /// 待っていた。本番の索引は区分の読み込みを取り消さない（`OfficialSpotService.loadShard`）ので、
    /// 2秒のはずの待ちが通信の時間切れ（20秒）まで延び、その間「シェアする」は押しても何も起きなかった
    func testIndexWaitEndsEvenIfFetchIgnoresCancellation() async {
        let gate = Gate()
        let fetched = spots
        let box = SpotsBox()
        let run = Task {
            let found = await PlaceCoordsRule.index(current: [], needed: true, wait: .milliseconds(50), fetch: {
                await gate.wait()   // 取り消しても戻らない読み込み
                return fetched
            })
            await box.set(found)
        }
        // 直っていなければ戻らない。上限（5秒）で試験を落とし、門を開けて片づける
        let returned = await box.waitForValue(seconds: 5)
        await gate.open()
        await run.value
        XCTAssertTrue(returned, "取り消しに応えない読み込みを待ち続けて、索引の待ちが上限で終わらない")
        let result = await box.value
        XCTAssertEqual(result?.isEmpty, true, "時間切れなら空（写真の座標を送らない側）")
    }

    /// `lookup` は**時間切れ・読めなかったを nil で返す**（「スポットが無い」と分ける）。要らない・もうあるは `current`
    func testLookupTellsUnknownApartFromNoSpots() async {
        let fetched = spots
        let unknown = await PlaceCoordsRule.lookup(current: [], needed: true, wait: .milliseconds(50), fetch: {
            try? await Task.sleep(for: .seconds(5))
            return fetched
        })
        XCTAssertNil(unknown, "時間切れは「分からない」")
        let failed = await PlaceCoordsRule.lookup(current: [], needed: true, fetch: { nil })
        XCTAssertNil(failed, "読めなかったも「分からない」")
        let none = await PlaceCoordsRule.lookup(current: [], needed: true, fetch: { [] })
        XCTAssertEqual(none?.isEmpty, true, "読めて0件は「スポットが無い」")
        let unused = await PlaceCoordsRule.lookup(current: [], needed: false, fetch: { nil })
        XCTAssertEqual(unused?.isEmpty, true, "要らないときは current")
    }

    // MARK: - 編集: 索引が分からないときは座標を消さない

    /// 🔴 **索引を読めなかった（nil）ときは、書き換えた撮影地でも座標を消さない**（2026-10-09 のレビュー）。
    /// 以前は時間切れの空の索引で (c) が当たらず `coords: null` を送り、サーバーのピンが黙って消えた。
    /// 撮影地を空にした回は索引が要らないので消す
    func testEditSaveKeepsCoordsWhenIndexIsUnknown() {
        XCTAssertFalse(EditPlaceRules.clearsCoords(openedLocation: "高屋神社", currentLocation: "高屋神社, 香川",
                                                   pickedCoords: false, photoCoords: taken, spots: nil))
        XCTAssertTrue(EditPlaceRules.clearsCoords(openedLocation: "高屋神社", currentLocation: "",
                                                  pickedCoords: false, photoCoords: taken, spots: nil),
                      "撮影地を空にした回は索引が分からなくても消す")
        // 読めて当たらない（自宅の町を「東京」に）は今までどおり消す
        XCTAssertTrue(EditPlaceRules.clearsCoords(openedLocation: "高屋神社", currentLocation: "東京",
                                                  pickedCoords: false, photoCoords: taken, spots: spots))
        // 保存の差分（`EditPhotoChanges.patch`）も同じ
        let photo = try! JSONDecoder.api.decode(Photo.self, from: Data(#"""
        {"id":"p1","src":"https://x/p1.jpg","title":"t","location":"高屋神社","coords":{"lat":34.13,"lng":133.64},
         "published":true}
        """#.utf8))
        var fields = EditPhotoChanges.Fields(opening: photo)
        fields.location = "高屋神社, 香川"
        let unknown = EditPhotoChanges.patch(photo: photo, openedAudience: .everyone, fields: fields, spots: nil)
        XCTAssertFalse(unknown.clearCoords, "索引が分からないのにピンを消している")
        XCTAssertEqual(unknown.location, "高屋神社, 香川")
    }

    /// 差し替え: 索引が分からないときは、書き換えた撮影地でもピンを残す（空にした回は残さない）
    func testReplaceKeepsPinWhenIndexIsUnknown() {
        XCTAssertTrue(EditPlaceRules.keepsCoordsOnReplace(openedLocation: "高屋神社", openedHasCoords: true,
                                                          currentLocation: "高屋神社, 香川",
                                                          newPhotoCoords: taken, spots: nil))
        XCTAssertFalse(EditPlaceRules.keepsCoordsOnReplace(openedLocation: "高屋神社", openedHasCoords: true,
                                                           currentLocation: "", newPhotoCoords: taken, spots: nil))
        XCTAssertFalse(EditPlaceRules.keepsCoordsOnReplace(openedLocation: "高屋神社", openedHasCoords: false,
                                                           currentLocation: "高屋神社, 香川",
                                                           newPhotoCoords: taken, spots: nil),
                       "元からピンの無い写真には書かない")
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

/// 試験で、別の仕事が書いた結果を待つ（同期の無い箱を使わない）
actor SpotsBox {
    private(set) var value: [OfficialSpot]?
    func set(_ value: [OfficialSpot]) { self.value = value }

    /// 結果が入るまで待つ。**上限で諦めて false**（壊れた回に試験ごと固まらない）
    func waitForValue(seconds: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while value == nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return value != nil
    }
}
