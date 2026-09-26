import XCTest
@testable import JourneyPhoto

/// 現在地の周りの写真（モック3-7）。
final class NearbyPhotosTests: XCTestCase {

    private func photo(_ id: String, lat: Double?, lng: Double?) throws -> Photo {
        let c = (lat != nil && lng != nil) ? ",\"coords\":{\"lat\":\(lat!),\"lng\":\(lng!)}" : ""
        return try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\"\(c)}".utf8))
    }

    /// 東京駅のあたり
    private let here = Photo.Coords(lat: 35.68, lng: 139.77)

    /// 近い順。**遠いものは範囲で落ちる**
    func testSortedByDistanceAndClipped() throws {
        let near = try photo("near", lat: 35.69, lng: 139.77)      // 約1km
        let mid = try photo("mid", lat: 35.72, lng: 139.77)        // 約4km
        let far = try photo("far", lat: 35.45, lng: 139.63)        // 約27km
        let found = NearbyPhotos.photos([far, mid, near], near: here, withinKm: 5)
        XCTAssertEqual(found.map(\.photo.id), ["near", "mid"])
        XCTAssertLessThan(found[0].km, found[1].km)
    }

    /// **座標の無い写真は入らない。** 距離を測りようが無いものを
    /// 「近い」と言わない
    func testPhotosWithoutCoordsAreNotNearby() throws {
        let found = NearbyPhotos.photos([try photo("no", lat: nil, lng: nil)],
                                        near: here, withinKm: 50)
        XCTAssertTrue(found.isEmpty)
    }

    /// 🔴 **持っていない精度を言わない。** 座標は約1kmに丸めてあるので、
    /// 1km 未満を「0.3km」とは書かない
    func testSubKilometreIsNotSpelledOut() {
        let label = NearbyPhotos.label(km: 0.3)
        XCTAssertEqual(label, L("1km以内", "within 1 km"))
        XCTAssertFalse(label.contains("0.3"))
    }

    /// 距離には必ず「約」を付ける（丸めた座標から出した値なので）
    func testDistancesAreMarkedApproximate() {
        XCTAssertTrue(NearbyPhotos.label(km: 3.14).contains(L("約", "about")))
        XCTAssertTrue(NearbyPhotos.label(km: 42).contains(L("約", "about")))
    }

    /// **1km 未満の範囲は選ばせない**（丸めより細かい線は引けない）
    func testNoRadiusFinerThanTheRounding() {
        XCTAssertFalse(NearbyPhotos.radiusChoices.contains { $0 < 1 })
    }

    /// 見出しは**数えた件数**（「8件」のような決め打ちを置かない）
    func testHeadingCountsWhatWasFound() {
        XCTAssertTrue(NearbyPhotos.heading(radiusKm: 5, count: 0).contains("0"))
        XCTAssertTrue(NearbyPhotos.heading(radiusKm: 5, count: 12).contains("12"))
    }
}

/// 写真の詳細の「この近くで撮られた写真」（板 02）
final class NearbyAroundPhotoTests: XCTestCase {

    private func photo(_ id: String, lat: Double?, lng: Double?, group: String? = nil,
                       owner: String? = nil) throws -> Photo {
        let c = (lat != nil && lng != nil) ? ",\"coords\":{\"lat\":\(lat!),\"lng\":\(lng!)}" : ""
        let g = group.map { ",\"groupId\":\"\($0)\"" } ?? ""
        let o = owner.map { ",\"userId\":\"\($0)\"" } ?? ""
        return try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\"\(c)\(g)\(o)}".utf8))
    }

    /// 近い順・自分は入らない・遠いものは落ちる
    func testNearestFirstWithoutSelf() throws {
        let me = try photo("me", lat: 35.68, lng: 139.77)
        let near = try photo("near", lat: 35.69, lng: 139.77)
        let mid = try photo("mid", lat: 35.71, lng: 139.77)
        let far = try photo("far", lat: 34.69, lng: 135.50)
        XCTAssertEqual(NearbyPhotos.around(me, in: [far, mid, me, near]).map(\.id), ["near", "mid"])
    }

    /// **座標の無い写真には節ごと出さない**
    func testNoCoordsMeansNothing() throws {
        let me = try photo("me", lat: nil, lng: nil)
        let near = try photo("near", lat: 35.69, lng: 139.77)
        XCTAssertTrue(NearbyPhotos.around(me, in: [near]).isEmpty)
    }

    /// 同じ投稿の束は上で送れるので、ここに二度並べない
    /// （上の束＝開いた一覧の中の兄弟）
    func testSameGroupIsLeftOut() throws {
        let me = try photo("me", lat: 35.68, lng: 139.77, group: "g1", owner: "u1")
        let sibling = try photo("sib", lat: 35.68, lng: 139.77, group: "g1", owner: "u1")
        let other = try photo("other", lat: 35.68, lng: 139.77, group: "g2", owner: "u1")
        XCTAssertEqual(NearbyPhotos.around(me, in: [sibling, other], context: [me, sibling]).map(\.id),
                       ["other"])
    }

    /// 🔴 **上に出ていない兄弟は落とさない。** 上の束は開いた一覧の中だけ
    /// なので、全公開写真から兄弟を落とすと**どこにも出ない**写真ができる
    /// （以前の実装。一覧にこの1枚しか居なかった回）
    func testSiblingNotShownAboveStaysNearby() throws {
        let me = try photo("me", lat: 35.68, lng: 139.77, group: "g1", owner: "u1")
        let sibling = try photo("sib", lat: 35.68, lng: 139.77, group: "g1", owner: "u1")
        XCTAssertEqual(NearbyPhotos.around(me, in: [me, sibling], context: [me]).map(\.id), ["sib"])
    }

    /// 🔴 **持ち主の違う写真は、同じ `groupId` でも束ではない**
    /// （`PhotoGroups.groupKey`）。文字だけで比べると巻き添えで消える
    func testSameGroupIdOfAnotherOwnerIsKept() throws {
        let me = try photo("me", lat: 35.68, lng: 139.77, group: "g1", owner: "u1")
        let stranger = try photo("theirs", lat: 35.68, lng: 139.77, group: "g1", owner: "u2")
        XCTAssertEqual(NearbyPhotos.around(me, in: [stranger], context: [me, stranger]).map(\.id),
                       ["theirs"])
    }

    /// 持ち主の無い写真は束にしない（`groupKey` と同じ）。同じ `groupId` でも残す
    func testGroupIdWithoutOwnerIsNotAGroup() throws {
        let me = try photo("me", lat: 35.68, lng: 139.77, group: "g1")
        let other = try photo("other", lat: 35.68, lng: 139.77, group: "g1")
        XCTAssertEqual(NearbyPhotos.around(me, in: [other], context: [me, other]).map(\.id), ["other"])
    }

    /// 同じ写真が2回来ても1回だけ・上限で切る
    func testDedupAndLimit() throws {
        let me = try photo("me", lat: 35.68, lng: 139.77)
        let a = try photo("a", lat: 35.68, lng: 139.77)
        let b = try photo("b", lat: 35.68, lng: 139.77)
        let c = try photo("c", lat: 35.68, lng: 139.77)
        XCTAssertEqual(NearbyPhotos.around(me, in: [a, a, b, c], limit: 2).map(\.id), ["a", "b"])
    }
}
