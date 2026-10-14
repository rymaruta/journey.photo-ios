import XCTest
@testable import JourneyPhoto

/// 写真から、次の旅へ（2026-10-14）: 写真の詳細 → 撮影スポット・行きたい・いつ／どう行く・同じ場所で撮って投稿
final class PhotoTripTests: XCTestCase {

    private func photo(_ id: String, location: String? = nil, spotId: String? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"/uploads/\(id).jpg\""]
        if let location { fields.append("\"location\":\"\(location)\"") }
        if let spotId { fields.append("\"spotId\":\"\(spotId)\"") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func spot(_ json: String) throws -> OfficialSpot {
        try JSONDecoder().decode(OfficialSpot.self, from: Data(json.utf8))
    }

    private var takaya: OfficialSpot {
        get throws {
            try spot(#"{"spotId":"sp_0123456789ab","slug":"takaya-shrine","name":"高屋神社","stage":"published","coords":{"lat":34.14,"lng":133.64},"region":{"prefecture":"香川県"},"seasons":["autumn","spring"]}"#)
        }
    }

    // MARK: - 1. 写真 → 撮影スポット（`spotId` だけで引く）

    func testSpotIsFoundOnlyBySpotId() throws {
        let index = [try takaya]
        XCTAssertEqual(PhotoTrip.spot(for: try photo("a", spotId: "sp_0123456789ab"), in: index)?.slug, "takaya-shrine")
        XCTAssertNil(PhotoTrip.spot(for: try photo("b", location: "高屋神社"), in: index),
                     "撮影地の文字列では台帳の行に当てない（紐付けは spotId だけ）")
        XCTAssertNil(PhotoTrip.spot(for: try photo("c", spotId: "sp_ffffffffffff"), in: index), "索引に無い行")
        XCTAssertNil(PhotoTrip.spot(for: try photo("d", spotId: "sp_0123456789ab"), in: nil), "索引が読めない")
        XCTAssertNil(PhotoTrip.spot(for: try photo("e", spotId: "  "), in: index), "空の spotId")
    }

    // MARK: - 3. 行きたい（鍵はスポットの頁・撮影地の頁と同じ）

    func testWishKeyMatchesTheSpotPageAndThePlacePage() throws {
        let spot = try takaya
        let onSpot = try XCTUnwrap(PhotoTrip.destination(photo: try photo("a", location: "高屋神社, 香川", spotId: spot.spotId),
                                                         spot: spot))
        // `OfficialSpotView.wishKey` と同じ（`SavedSpotKey.official(spot.slug)`）
        XCTAssertEqual(onSpot.wishKey, SavedSpotKey.official(spot.slug))
        XCTAssertEqual(onSpot.wishKey, "SPOT-takaya-shrine")
        XCTAssertEqual(onSpot.name, "高屋神社")

        // 台帳の行が無い写真は撮影地のスラッグ（`SpotDetailView` の「行きたい」の鍵 = `DerivedSpot.Place.slug`）
        let onPlace = try XCTUnwrap(PhotoTrip.destination(photo: try photo("b", location: "Paris"), spot: nil))
        XCTAssertEqual(onPlace.wishKey, LocationSlug.make("Paris"))
        XCTAssertFalse(SavedSpotKey.isOfficial(onPlace.wishKey), "撮影地の鍵に SPOT- を付けない（別物を1件に見せない）")
    }

    /// 行き先の分からない写真には何も出さない（壊れない）
    func testNoDestinationWithoutSpotOrPlace() throws {
        XCTAssertNil(PhotoTrip.destination(photo: try photo("a"), spot: nil), "spotId も撮影地も無い")
        XCTAssertNil(PhotoTrip.destination(photo: try photo("b", location: "   "), spot: nil), "空白だけの撮影地")
        XCTAssertNil(PhotoTrip.destination(photo: try photo("c", location: "---"), spot: nil),
                     "スラッグが空になる撮影地（押しても何も残らない）")
        // spotId があっても索引で引けなければ、撮影地にもどる
        let fallback = PhotoTrip.destination(photo: try photo("d", location: "金沢", spotId: "sp_ffffffffffff"), spot: nil)
        XCTAssertEqual(fallback?.wishKey, LocationSlug.make("金沢"))
        XCTAssertNil(fallback?.spot)
        XCTAssertFalse(PhotoTrip.offersDirections(fallback), "撮影地の文字列には経路を出さない")
    }

    // MARK: - 4. いつ・どう行く

    func testWhenLineIsTheNextGoldenHourInTheSpotsClock() throws {
        let spot = try takaya
        let tokyo = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        // 2026-10-14 12:00 JST（朝のゴールデンアワーは過ぎている → 今日の夕方）
        let noon = Date(timeIntervalSince1970: 1_791_946_800)
        let line = try XCTUnwrap(PhotoTrip.whenLine(spot: spot, now: noon, deviceZone: tokyo))
        XCTAssertTrue(line.hasPrefix(L("次のゴールデンアワー \(L("今日", "today"))", "Next golden hour \(L("今日", "today"))")), line)
        XCTAssertTrue(line.contains("17:"), "夕方の時刻: \(line)")
        XCTAssertFalse(line.contains(L("（現地）", " (local)")), "同じ時計なら「現地」と添えない")

        // 23:00 JST → 明日の朝
        let night = noon.addingTimeInterval(11 * 3600)
        let tomorrow = try XCTUnwrap(PhotoTrip.whenLine(spot: spot, now: night, deviceZone: tokyo))
        XCTAssertTrue(tomorrow.contains(L("明日", "tomorrow")), tomorrow)
        XCTAssertTrue(tomorrow.contains("05:") || tomorrow.contains("06:"), tomorrow)

        // 端末が別の時計なら「現地」と添える
        let paris = try XCTUnwrap(TimeZone(identifier: "Europe/Paris"))
        XCTAssertTrue(try XCTUnwrap(PhotoTrip.whenLine(spot: spot, now: noon, deviceZone: paris)).contains(L("（現地）", " (local)")))
    }

    func testWhenLineFallsBackToSeasonsAndOtherwiseShowsNothing() throws {
        let noCoords = try spot(#"{"spotId":"sp_000000000001","slug":"x","name":"X","stage":"published","seasons":["winter","autumn","bogus"]}"#)
        XCTAssertEqual(PhotoTrip.whenLine(spot: noCoords, now: Date()),
                       L("撮りどき 秋・冬", "Best in Autumn, Winter"), "季節は巡りの順・知らない季節は落とす")
        let bare = try spot(#"{"spotId":"sp_000000000002","slug":"y","name":"Y","stage":"review"}"#)
        XCTAssertNil(PhotoTrip.whenLine(spot: bare, now: Date()), "分からないときは行ごと出さない（作り話をしない）")
        XCTAssertTrue(PhotoTrip.offersDirections(.spot(try takaya)))
        XCTAssertFalse(PhotoTrip.offersDirections(.spot(bare)), "座標の無いスポットには経路を出さない")
        XCTAssertFalse(PhotoTrip.offersDirections(nil))
    }

    // MARK: - 2. 投稿で撮影地の欄から撮影スポットを選ぶ → spotId

    func testPickedSpotInThePlaceFieldSendsSpotId() {
        let target = UploadSpotTarget(spotId: "sp_0123456789ab", name: "高屋神社", coords: nil)
        var item = PendingPhoto(prepared: ImagePreparer.Prepared(data: Data(), fileName: "p.jpg", contentType: "image/jpeg",
                                                                  exif: nil, coords: nil, takenOn: nil))
        item.location = "高屋神社"
        XCTAssertNil(UploadSpotTarget.spotIdToSend(screen: nil, for: item), "選んでいない写真には付けない")
        item.pickedSpot = target
        XCTAssertEqual(UploadSpotTarget.spotIdToSend(screen: nil, for: item), "sp_0123456789ab")
        // スポットの画面から開いた行き先が先
        let screen = UploadSpotTarget(spotId: "sp_aaaaaaaaaaaa", name: "高屋", coords: nil)
        XCTAssertEqual(UploadSpotTarget.spotIdToSend(screen: screen, for: item), "sp_aaaaaaaaaaaa")
        // 撮影地を空にしたら付けない
        item.location = ""
        XCTAssertNil(UploadSpotTarget.spotIdToSend(screen: nil, for: item), "撮影地を空にした")
    }

    /// 手で書き換えたら外す（選んだ名前のままのときだけ持つ）
    func testRewritingThePlaceDropsThePickedSpot() {
        let target = UploadSpotTarget(spotId: "sp_0123456789ab", name: "高屋神社", coords: nil)
        XCTAssertTrue(UploadSpotTarget.keepsPicked(target, typed: "高屋神社"))
        XCTAssertFalse(UploadSpotTarget.keepsPicked(target, typed: "高屋神社の雲海"))
        XCTAssertFalse(UploadSpotTarget.keepsPicked(target, typed: "東京タワー"))
        XCTAssertFalse(UploadSpotTarget.keepsPicked(nil, typed: "高屋神社"))
    }

    // MARK: - 5. 作例を重ねて撮った1枚 → 投稿

    func testComposeShotOpensTheSpotUploadOnlyWhenPosted() {
        XCTAssertFalse(SpotComposePost.opensUpload(nil), "閉じるで閉じた回は投稿画面を開かない")
        let capture = ComposeShot(data: Data([1]), metadata: [:], capturedAt: Date()).cameraCapture
        XCTAssertTrue(SpotComposePost.opensUpload(capture))
    }

    // MARK: - 画面のつなぎ（画面の部品は Linux で動かせないので、ソースで縛る）

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func testPhotoDetailIsWiredToTheSpotAndTheTripSection() throws {
        let view = try source("Sources/JourneyPhoto/Features/PhotoDetail/PhotoDetailView.swift")
        // 1. 既存の索引の口で引き、spotId の無い写真は読みに行かない
        XCTAssertTrue(view.contains(".task(id: shown.spotId ?? \"\") { await loadTripSpot() }"))
        XCTAssertTrue(view.contains("await environment.spots.fetchIndexRows()"))
        XCTAssertTrue(view.contains("tripSpot = PhotoTrip.spot(for: shown, in: rows)"))
        let load = try XCTUnwrap(view.components(separatedBy: "private func loadTripSpot() async {").dropFirst().first)
        let guardPart = try XCTUnwrap(load.components(separatedBy: "fetchIndexRows").first)
        XCTAssertTrue(guardPart.contains("tripSpot = nil"), "spotId の無い写真で前の写真のスポットが残る")
        XCTAssertTrue(view.contains("if let spot = tripSpot {\n            NavigationLink {\n                OfficialSpotView(spot: spot"),
                      "撮影スポットの行が OfficialSpotView へ行かない")
        XCTAssertTrue(view.contains(".accessibilityIdentifier(\"photo.spotGuide\")"))
        // 見出しの撮影地の行の下・題の上（板 02 の位置）
        let heading = try XCTUnwrap(view.components(separatedBy: "private var heading: some View {").dropFirst().first)
        XCTAssertTrue(heading.prefix(200).contains("placeRow\n            spotGuideRow"))
        // 3・4. いいね・コメント・保存・共有の段の下に「行き先」の段
        XCTAssertTrue(view.contains("socialBar(proxy)\n            tripSection"))
        XCTAssertTrue(view.contains("PhotoTrip.destination(photo: shown, spot: tripSpot)"))
        XCTAssertTrue(view.contains("tripSpot.flatMap { PhotoTrip.whenLine(spot: $0, now: Date()) }"),
                      "「いつ」は台帳のスポットのときだけ")

        let section = try source("Sources/JourneyPhoto/Features/PhotoDetail/PhotoTripSection.swift")
        XCTAssertTrue(section.contains("let key = destination.wishKey"))
        XCTAssertTrue(section.contains(".toggle(key, store: wishlist, service: environment.savedSpots)"),
                      "行きたいがスポットの頁と同じ仕組み（行きたいの同期）を通らない")
        XCTAssertTrue(section.contains("\"flag.fill\" : \"flag\""), "保存（しおり）・いいね（ハート）と印を分ける")
        XCTAssertTrue(section.contains("if PhotoTrip.offersDirections(destination) {"))
        XCTAssertTrue(section.contains(".openDirections(name: name, coords: coords, stillWanted: { onScreen })"))
        XCTAssertTrue(section.contains(".frame(minHeight: WebTheme.minTapTarget)"), "押せるものは 44pt")
        XCTAssertTrue(section.contains(".accessibilityAddTraits(wanted ? .isSelected : [])"), "選んだ状態を読み上げない")
    }

    func testUploadPlaceFieldWiresThePickedSpot() throws {
        let field = try source("Sources/JourneyPhoto/Features/Upload/PlaceSearchField.swift")
        let pick = try XCTUnwrap(field.range(of: "pickedSpot?.wrappedValue = UploadSpotTarget(spot)"))
        let set = try XCTUnwrap(field.range(of: "location = spot.name"))
        XCTAssertLessThan(pick.lowerBound, set.lowerBound, "紐付けを location より後に入れると、書き換えと読まれて外れる")
        XCTAssertTrue(field.contains("!UploadSpotTarget.keepsPicked(pickedSpot.wrappedValue, typed: value)"))
        let upload = try source("Sources/JourneyPhoto/Features/Upload/UploadView.swift")
        XCTAssertTrue(upload.contains("pickedSpot: $item.pickedSpot)"))
        let model = try source("Sources/JourneyPhoto/Features/Upload/UploadViewModel.swift")
        XCTAssertTrue(model.contains("draft.spotId = UploadSpotTarget.spotIdToSend(screen: spot, for: item)"))
        // 写真の編集は撮影スポットの候補を出さない（座標の食い違い・`PlaceSearchField.offersSpots` の注記）
        let edit = try source("Sources/JourneyPhoto/Features/Profile/EditPhotoView.swift")
        XCTAssertTrue(edit.contains("PlaceSearchField(location: $location, coords: $pickedCoords)"))
    }

    func testComposeGuideFromASpotCanPost() throws {
        let spot = try source("Sources/JourneyPhoto/Features/Spots/OfficialSpotView.swift")
        XCTAssertTrue(spot.contains("onPost: { capture in pendingCapture = capture },"))
        XCTAssertTrue(spot.contains("onDismiss: { if SpotComposePost.opensUpload(pendingCapture) { showUpload = true } })"))
        XCTAssertTrue(spot.contains("UploadView(spot: UploadSpotTarget(spot), onPosted:"))
        XCTAssertTrue(spot.contains("}, initialCapture: pendingCapture) }"), "撮った1枚がスポットの投稿に入らない")
        let guide = try source("Sources/JourneyPhoto/Features/Spots/ComposeGuideView.swift")
        XCTAssertTrue(guide.contains("} else if onPost != nil {\n                    // 撮影スポットの作例から開いたとき"),
                      "作例ありの撮る画面に「投稿」が無い")
        XCTAssertTrue(guide.contains("HStack(spacing: 12) { thumbButton; postButton }"))
    }
}
