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
        // **写真ごとに選んだほうが先**: 「高屋」の画面から開いて「高屋神社」を選んだら高屋神社
        let screen = UploadSpotTarget(spotId: "sp_aaaaaaaaaaaa", name: "高屋", coords: nil)
        XCTAssertEqual(UploadSpotTarget.spotIdToSend(screen: screen, for: item), "sp_0123456789ab",
                       "選んだ候補と違うスポットの spotId が付く")
        // 選んでいなければ画面の行き先
        item.pickedSpot = nil
        XCTAssertEqual(UploadSpotTarget.spotIdToSend(screen: screen, for: item), "sp_aaaaaaaaaaaa")
        item.pickedSpot = target
        // 撮影地を空にしたら付けない
        item.location = ""
        XCTAssertNil(UploadSpotTarget.spotIdToSend(screen: nil, for: item), "撮影地を空にした")
    }

    /// スポットの頁の「投稿しました」は、その頁のスポットで送ったときだけ
    func testPostedToSpotCountsOnlyTheScreensSpot() {
        let screen = UploadSpotTarget(spotId: "sp_aaaaaaaaaaaa", name: "高屋", coords: nil)
        XCTAssertTrue(UploadSpotTarget.countsForScreen(sentSpotId: "sp_aaaaaaaaaaaa", screen: screen,
                                                       published: true, everyone: true))
        XCTAssertFalse(UploadSpotTarget.countsForScreen(sentSpotId: "sp_0123456789ab", screen: screen,
                                                        published: true, everyone: true), "別のスポットを選んだ投稿")
        XCTAssertFalse(UploadSpotTarget.countsForScreen(sentSpotId: "sp_0123456789ab", screen: nil,
                                                        published: true, everyone: true), "スポットの画面から開いていない")
        XCTAssertFalse(UploadSpotTarget.countsForScreen(sentSpotId: nil, screen: screen, published: true, everyone: true))
        XCTAssertFalse(UploadSpotTarget.countsForScreen(sentSpotId: "sp_aaaaaaaaaaaa", screen: screen,
                                                        published: false, everyone: true), "下書き")
        XCTAssertFalse(UploadSpotTarget.countsForScreen(sentSpotId: "sp_aaaaaaaaaaaa", screen: screen,
                                                        published: true, everyone: false), "範囲を絞った")
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

    // MARK: - 2. 写真を送った直後に前の写真のものを出さない・4. 読み込み中は行きたいを出さない

    func testStageUsesOnlyTheCurrentPhotosSpotId() throws {
        let spot = try takaya
        let a = PhotoTrip.Loaded(spotId: "sp_0123456789ab", spot: spot, index: [spot], photos: nil)
        // 前の写真（a）の読み込みだけが残っている状態で、別の spotId の写真へ送った
        let next = try photo("n", location: "金沢", spotId: "sp_ffffffffffff")
        let stage = PhotoTrip.stage(photoSpotId: next.spotId, loaded: a)
        XCTAssertNil(stage.loaded, "前の写真のスポットを出している")
        XCTAssertNil(PhotoTrip.sectionDestination(photo: next, stage: stage),
                     "読み込み中に行きたいを出すと、読み終わりで鍵が変わる")
        // spotId の無い写真へ送った → 前の写真のスポットは使わず、撮影地の行き先
        let plain = try photo("p", location: "金沢")
        let none = PhotoTrip.stage(photoSpotId: plain.spotId, loaded: a)
        XCTAssertNil(none.loaded)
        XCTAssertEqual(PhotoTrip.sectionDestination(photo: plain, stage: none)?.wishKey, LocationSlug.make("金沢"))
        // 同じ spotId（前後の空白は同じに見る）なら使う
        let same = PhotoTrip.stage(photoSpotId: " sp_0123456789ab ", loaded: a)
        XCTAssertEqual(same.loaded?.spot?.slug, "takaya-shrine")
        let here = try photo("s", location: "高屋神社", spotId: "sp_0123456789ab")
        XCTAssertEqual(PhotoTrip.sectionDestination(photo: here, stage: same)?.wishKey, "SPOT-takaya-shrine")
        // 読み終えたが索引に無い → 撮影地に戻る（スポットの行・経路・時刻は出ない）
        let missing = PhotoTrip.Loaded(spotId: "sp_ffffffffffff", spot: nil, index: [], photos: nil)
        let fallback = PhotoTrip.sectionDestination(photo: next, stage: PhotoTrip.stage(photoSpotId: next.spotId, loaded: missing))
        XCTAssertNil(fallback?.spot)
        XCTAssertEqual(fallback?.wishKey, LocationSlug.make("金沢"))
    }

    // MARK: - 7. 撮影地の「行きたい」は公開の写真だけ

    func testPlaceWishOnlyForPublicPhotos() throws {
        func decoded(_ extra: String) throws -> Photo {
            try JSONDecoder.api.decode(Photo.self, from: Data(
                "{\"id\":\"x\",\"src\":\"/uploads/x.jpg\",\"location\":\"金沢\"\(extra)}".utf8))
        }
        XCTAssertNotNil(PhotoTrip.destination(photo: try decoded(""), spot: nil), "公開の一覧の写真（published 無し）")
        XCTAssertNotNil(PhotoTrip.destination(photo: try decoded(",\"published\":true,\"audience\":\"everyone\""), spot: nil))
        XCTAssertNil(PhotoTrip.destination(photo: try decoded(",\"published\":false"), spot: nil), "下書き")
        XCTAssertNil(PhotoTrip.destination(photo: try decoded(",\"audience\":\"followers\""), spot: nil), "フォロワーのみ")
        XCTAssertNil(PhotoTrip.destination(photo: try decoded(",\"audience\":\"closeFriends\""), spot: nil), "親しい友達")
        XCTAssertNil(PhotoTrip.destination(photo: try decoded(",\"audience\":\"somethingNew\""), spot: nil), "知らない範囲は絞った側")
        // 台帳のスポットは公開の台帳なので、絞った写真でも出す
        XCTAssertNotNil(PhotoTrip.destination(photo: try decoded(",\"published\":false"), spot: try takaya))
    }

    // MARK: - 4. 白夜・極夜・日付変更線

    func testPolarDaysFallBackToSeasons() throws {
        // スヴァールバル（北緯78°）の夏至の頃は白夜、冬至の頃は極夜——ゴールデンアワーが無い日は季節へ
        let svalbard = try spot(#"{"spotId":"sp_000000000003","slug":"longyearbyen","name":"ロングイェールビーン","stage":"published","coords":{"lat":78.22,"lng":15.65},"timeZone":"Arctic/Longyearbyen","region":{"country":"ノルウェー"},"seasons":["summer"]}"#)
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let midsummer = Date(timeIntervalSince1970: 1_781_870_400)   // 2026-06-19 12:00 UTC
        let midwinter = Date(timeIntervalSince1970: 1_797_854_400)   // 2026-12-21 12:00 UTC
        for now in [midsummer, midwinter] {
            XCTAssertNil(PhotoTrip.nextGolden(spot: svalbard, now: now, deviceZone: utc))
            XCTAssertEqual(PhotoTrip.whenLine(spot: svalbard, now: now, deviceZone: utc), L("撮りどき 夏", "Best in Summer"))
        }
    }

    func testDatelineSpotUsesItsOwnCalendar() throws {
        // トンガ（UTC+13）。UTC では 10/13 の 23:00 でも、その土地では 10/14 の正午
        let tonga = try spot(#"{"spotId":"sp_000000000004","slug":"nukualofa","name":"ヌクアロファ","stage":"published","coords":{"lat":-21.14,"lng":-175.2},"timeZone":"Pacific/Tongatapu","region":{"country":"トンガ"}}"#)
        let tokyo = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let now = Date(timeIntervalSince1970: 1_791_932_400)   // 2026-10-13 23:00 UTC = 10/14 12:00 トンガ
        let line = try XCTUnwrap(PhotoTrip.whenLine(spot: tonga, now: now, deviceZone: tokyo))
        XCTAssertTrue(line.contains(L("今日", "today")), "その土地の今日の夕方: \(line)")
        XCTAssertTrue(line.contains("18:") || line.contains("17:"), line)
        XCTAssertTrue(line.contains(L("（現地）", " (local)")))
    }

    // MARK: - 6. 写真の編集で撮影地をスポットの名前から離したら spotId を外す

    func testEditDropsSpotIdWhenThePlaceLeavesTheSpot() throws {
        let index = [try takaya]
        func clears(_ now: String, spots: [OfficialSpot]? = index, id: String? = "sp_0123456789ab") -> Bool {
            EditPlaceRules.clearsSpotId(spotId: id, openedLocation: "高屋神社", currentLocation: now, spots: spots)
        }
        XCTAssertTrue(clears("東京タワー"))
        XCTAssertTrue(clears(""), "撮影地を空にした")
        XCTAssertTrue(clears("", spots: nil), "空にしたら索引が無くても外す")
        XCTAssertFalse(clears("高屋神社, 香川"), "県を足しただけ")
        XCTAssertFalse(clears("高屋神社"), "変えていない")
        XCTAssertFalse(clears("東京タワー", spots: nil), "索引が読めない（分からないまま外さない）")
        XCTAssertFalse(clears("東京タワー", spots: []), "索引にその spotId が無い")
        XCTAssertFalse(clears("東京タワー", id: nil), "紐付けの無い写真")
        XCTAssertTrue(EditPlaceRules.needsSpotIndexForSpotId(spotId: "sp_0123456789ab", openedLocation: "高屋神社",
                                                             currentLocation: "東京タワー"))
        XCTAssertFalse(EditPlaceRules.needsSpotIndexForSpotId(spotId: nil, openedLocation: "高屋神社", currentLocation: "東京"))

        // 送る本文は "spotId": null（サーバーは null で外す）。外さない回はキーごと載せない
        var patch = PhotoPatch()
        patch.location = "東京タワー"
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(patch), as: UTF8.self).contains("spotId"))
        patch.clearSpotId = true
        XCTAssertTrue(String(decoding: try JSONEncoder().encode(patch), as: UTF8.self).contains("\"spotId\":null"))
        var only = PhotoPatch()
        only.clearSpotId = true
        XCTAssertFalse(only.isEmpty, "外すだけの保存が空と見なされる")

        let photo = try JSONDecoder.api.decode(Photo.self, from: Data(
            #"{"id":"e","src":"/uploads/e.jpg","location":"高屋神社","spotId":"sp_0123456789ab"}"#.utf8))
        var fields = EditPhotoChanges.Fields(opening: photo)
        fields.location = "東京タワー"
        XCTAssertTrue(EditPhotoChanges.patch(photo: photo, openedAudience: .everyone, fields: fields, spots: index).clearSpotId)
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
        // 読んだ spotId を覚え、今の写真の spotId と同じときだけ使う（値の決まりは下の `testStage…`）
        XCTAssertTrue(view.contains("PhotoTrip.stage(photoSpotId: shown.spotId, loaded: tripLoaded)"))
        XCTAssertTrue(view.contains("tripLoaded = PhotoTrip.Loaded(spotId: id, spot: PhotoTrip.spot(for: shown, in: rows),"))
        XCTAssertTrue(view.contains("if let loaded = tripStage.loaded, let spot = loaded.spot {\n            NavigationLink {\n                // 写真は"),
                      "撮影スポットの行が OfficialSpotView へ行かない")
        XCTAssertTrue(view.contains("OfficialSpotView(spot: spot, spots: loaded.index, photos: hidden.visible(loaded.photos ?? []),"),
                      "撮影地に1枚しか無い写真でスポットの頁に写真を渡していない")
        XCTAssertTrue(view.contains(".accessibilityIdentifier(\"photo.spotGuide\")"))
        // 見出しの撮影地の行の下・題の上（板 02 の位置）
        let heading = try XCTUnwrap(view.components(separatedBy: "private var heading: some View {").dropFirst().first)
        XCTAssertTrue(heading.prefix(200).contains("placeRow\n            spotGuideRow"))
        // 3・4. いいね・コメント・保存・共有の段の下に「行き先」の段
        XCTAssertTrue(view.contains("socialBar(proxy)\n            tripSection"))
        XCTAssertTrue(view.contains("PhotoTrip.sectionDestination(photo: shown, stage: tripStage)"))
        XCTAssertTrue(view.contains(".id(shown.id)"), "写真を送っても前の写真の経路の仕事が残る")
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
