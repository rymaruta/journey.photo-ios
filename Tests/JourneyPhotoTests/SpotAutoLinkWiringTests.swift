import XCTest
@testable import JourneyPhoto

/// 写真から撮影スポットを引く所すべてで「`spotId` → 無ければ表 → 外した写真は結ばない」を使う
/// （2026-10-31・journey.photo-ios#425）: 撮影スポットの行の枚数・県の段・撮影スポットの頁の写真・
/// 写真の詳細の札（チップ）・この近くの撮影スポット・本人の「外す」
final class SpotAutoLinkWiringTests: XCTestCase {

    private func spot(_ id: String, prefecture: String?, lat: Double, lng: Double) throws -> OfficialSpot {
        let region = prefecture.map { ",\"region\":{\"prefecture\":\"\($0)\"}" } ?? ""
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data(
            "{\"spotId\":\"\(id)\",\"slug\":\"\(id)\",\"name\":\"\(id)\",\"stage\":\"published\"\(region),\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}}".utf8))
    }

    private func photo(_ fields: [String: Any]) throws -> Photo { try SpotAutoLinkTests.photo(fields) }

    /// 蔵王キツネ村（宮城県）。写真の撮影地に県名が無い（本番の「夢の中」と同じ形）
    private func fixture() throws -> (spots: [OfficialSpot], photos: [Photo], links: SpotPhotoLinks) {
        let fox = try spot("sp_fox", prefecture: "宮城県", lat: 38.02, lng: 140.55)
        let photos = [
            try photo(["id": "dream", "location": "蔵王キツネ村, 白石市"]),
            try photo(["id": "mine", "spotId": "sp_fox", "location": "白石市"]),
            try photo(["id": "removed", "spotAuto": "off", "location": "蔵王キツネ村"]),
        ]
        // 外した写真が作り直しの前で表に残っていても結ばない
        let links = SpotPhotoLinks(links: ["dream": "sp_fox", "removed": "sp_fox"])
        return ([fox], photos, links)
    }

    // MARK: - 撮影スポットの行の枚数・県の段

    func testSpotRowCountsAutoLinkedPhotos() throws {
        let f = try fixture()
        XCTAssertEqual(OfficialSpotList.rows(f.spots, photos: f.photos, from: nil, links: f.links).first?.photoCount, 2)
        XCTAssertEqual(OfficialSpotList.rows(f.spots, photos: f.photos, from: nil).first?.photoCount, 1,
                       "表を渡さないときは今までどおり spotId だけ")
    }

    /// 🔴 県の段の「写真 N枚」と行の「写真 N枚」を同じ結びで数える（以前は段を撮影地の文字で数え、
    /// 撮影地に県名の無い写真は行に数えられて段には入らなかった）
    func testRegionSectionPutsLinkedPhotosWithTheirSpot() throws {
        let f = try fixture()
        let sections = RegionList.sections(photos: f.photos, spots: f.spots, links: f.links, from: nil)
        let miyagi = try XCTUnwrap(sections.first { $0.key == .prefecture("宮城県") })
        XCTAssertEqual(Set(miyagi.photos.map(\.id)), ["dream", "mine"])
        XCTAssertEqual(miyagi.photos.count, miyagi.spots.first?.photoCount, "段と行の枚数が食い違う")
        XCTAssertEqual(RegionList.countLabel(miyagi), L("1件 · 写真 2枚", "1 spot · 2 photos"))
        // 外した写真（座標なし・県名なし）は結ばない＝段に分けられない
        XCTAssertEqual(sections.first { $0.key == .unknown }?.photos.map(\.id), ["removed"])
    }

    // MARK: - 撮影スポットの頁の写真

    func testSpotPagePhotosUseTheSameOrder() throws {
        let f = try fixture()
        XCTAssertEqual(SpotPhotoLinks.photos(f.photos, linkedTo: "sp_fox", links: f.links).map(\.id), ["dream", "mine"])
        XCTAssertEqual(SpotPhotoLinks.photos(f.photos, linkedTo: "sp_fox", links: .empty).map(\.id), ["mine"])
    }

    // MARK: - 写真の詳細

    /// 札（チップ）: 表を読む前は `spotId` だけ・読んだら表・外す／戻すを送っている間は送った向き
    func testChipSpotId() throws {
        let dream = try photo(["id": "dream"])
        let links = SpotPhotoLinks(links: ["dream": "sp_fox"])
        XCTAssertNil(SpotAutoNotice.chipSpotId(photo: dream, links: nil, pendingOff: nil, candidate: nil))
        XCTAssertEqual(SpotAutoNotice.chipSpotId(photo: dream, links: links, pendingOff: nil, candidate: "sp_fox"), "sp_fox")
        XCTAssertNil(SpotAutoNotice.chipSpotId(photo: dream, links: links, pendingOff: true, candidate: "sp_fox"))
        let removed = try photo(["id": "removed", "spotAuto": "off"])
        XCTAssertEqual(SpotAutoNotice.chipSpotId(photo: removed, links: .empty, pendingOff: false, candidate: "sp_fox"), "sp_fox",
                       "元に戻すを押したのに札が出ない")
        let mine = try photo(["id": "mine", "spotId": "sp_me"])
        XCTAssertEqual(SpotAutoNotice.chipSpotId(photo: mine, links: nil, pendingOff: true, candidate: nil), "sp_me")
    }

    /// 「この近くの撮影スポット」は、自動で結ばれた写真には出さない（「撮影スポット」の札が受け持つ）
    func testNearbySpotKeyHidesForAutoLinkedPhotos() throws {
        let dream = try photo(["id": "dream", "coords": ["lat": 38.0, "lng": 140.56]])
        XCTAssertNotNil(PhotoTrip.nearbySpotKey(photo: dream, linkedSpotId: nil))
        XCTAssertNil(PhotoTrip.nearbySpotKey(photo: dream, linkedSpotId: "sp_fox"))
        XCTAssertEqual(PhotoTrip.spot(id: " sp_fox ", in: [try spot("sp_fox", prefecture: nil, lat: 0, lng: 0)])?.spotId, "sp_fox")
    }

    /// 本人の「外す」の札: 本人だけ・`spotId` の無い公開の写真で、結ぶ先があるときだけ。送っている間は送った向き
    func testOwnerNoticeState() throws {
        let links = SpotPhotoLinks(links: ["dream": "sp_fox"])
        let dream = try photo(["id": "dream"])
        XCTAssertEqual(SpotAutoNotice.state(photo: dream, isMine: true, links: links, rule: nil, pendingOff: nil),
                       .init(spotId: "sp_fox", off: false))
        XCTAssertNil(SpotAutoNotice.state(photo: dream, isMine: false, links: links, rule: nil, pendingOff: nil), "人の写真に出した")
        XCTAssertNil(SpotAutoNotice.state(photo: dream, isMine: true, links: nil, rule: nil, pendingOff: nil), "表を読む前に出した")
        XCTAssertEqual(SpotAutoNotice.state(photo: dream, isMine: true, links: links, rule: nil, pendingOff: true)?.off, true)
        // 外した写真（表に無い）は決まりで求めた先で「元に戻す」を出す
        let removed = try photo(["id": "removed", "spotAuto": "off"])
        XCTAssertEqual(SpotAutoNotice.state(photo: removed, isMine: true, links: .empty, rule: "sp_fox", pendingOff: nil),
                       .init(spotId: "sp_fox", off: true))
        XCTAssertNil(SpotAutoNotice.state(photo: try photo(["id": "dream", "spotId": "sp_me"]), isMine: true,
                                          links: links, rule: nil, pendingOff: nil), "本人が選んだ spotId に出した")
    }

    /// 言葉は Web の `SpotAutoNotice.tsx` と同じ（「結ぶ」にそろえ、「まとめ」は使わない）
    func testNoticeWordingMatchesWeb() {
        XCTAssertEqual(SpotAutoNoticeText.title(spotName: "蔵王キツネ村", off: false),
                       L("撮影スポット「蔵王キツネ村」に結びました", "Linked to the photo spot “蔵王キツネ村”"))
        XCTAssertEqual(SpotAutoNoticeText.title(spotName: "蔵王キツネ村", off: true),
                       L("「蔵王キツネ村」への自動の結びつけを外しています", "Automatic link to “蔵王キツネ村” removed"))
        XCTAssertEqual(SpotAutoNoticeText.button(off: false), L("違う場所なので外す", "Different place — remove"))
        XCTAssertEqual(SpotAutoNoticeText.button(off: true), L("元に戻す", "Restore"))
        XCTAssertEqual(SpotAutoNoticeText.eyebrow, L("あなたにだけ表示", "Only you can see this"))
        for text in [SpotAutoNoticeText.title(spotName: "x", off: false), SpotAutoNoticeText.body(off: false),
                     SpotAutoNoticeText.body(off: true), SpotUploadAuto.note(on: true), SpotAutoLink.spotPageNote] {
            XCTAssertFalse(text.contains("まとめ"), text)
            XCTAssertFalse(text.contains("撮りどき"), text)
        }
    }

    // MARK: - 画面のつなぎ（画面の部品は Linux で動かせないので、ソースで縛る）

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func testScreensAreWired() throws {
        let detail = try source("Sources/JourneyPhoto/Features/PhotoDetail/PhotoDetailView.swift")
        XCTAssertTrue(detail.contains("photoLinks == nil && SpotAutoLink.explicitSpotId(shown) == nil\n            ? .loading : PhotoTrip.stage(photoSpotId: linkedSpotId, loaded: tripLoaded)"),
                      "表を読む前に行き先を出す・表を使っていない・spotId のある写真まで表を待つ")
        XCTAssertTrue(detail.contains("SpotLinkRevision.shared.bump()"), "外した・戻したを開いている頁に知らせていない")
        XCTAssertTrue(detail.contains(".task(id: \"links|\\(shown.id)|\\(isMine)\") { await loadPhotoLinks() }"))
        XCTAssertTrue(detail.contains("heading(hero)\n                // 自動の結びの「外す」（撮った本人だけ・案の板 PhotoIOS: 題と日時のすぐ下）\n                spotAutoNotice"))
        XCTAssertTrue(detail.contains("try await environment.photos.setSpotAuto(photoId: photoId, off: nextOff)"))
        XCTAssertTrue(detail.contains("spotAutoPending[photoId] = nil\n                spotAutoFailures[photoId] ="),
                      "失敗したときに元の表示に戻していない")
        let spotView = try source("Sources/JourneyPhoto/Features/Spots/OfficialSpotView.swift")
        XCTAssertTrue(spotView.contains("SpotPhotoLinks.photos(photos, linkedTo: spot.spotId, links: photoLinks)"))
        XCTAssertTrue(spotView.contains("let links = await environment.spots.fetchPhotoLinks()"))
        let map = try source("Sources/JourneyPhoto/Features/Map/PhotoMapView.swift")
        XCTAssertTrue(map.contains("OfficialSpotList.rows(spots, photos: model.photos, from: center, links: model.photoLinks)"))
        XCTAssertTrue(map.contains("aliases: model.spotAliases, links: model.photoLinks, from: center)"))
        let upload = try source("Sources/JourneyPhoto/Features/Upload/UploadView.swift")
        XCTAssertTrue(upload.contains("if let row = model.autoSpotRow(for: item) {\n                        autoSpotToggle(row, itemId: item.id)"))
        XCTAssertTrue(upload.contains("model.fetchSpotMatchIndex = { [spots = environment.spots] in await spots.fetchMatchIndex() }"))
    }
}
