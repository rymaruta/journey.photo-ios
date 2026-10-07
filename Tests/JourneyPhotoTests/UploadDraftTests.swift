import XCTest
@testable import JourneyPhoto

final class UploadDraftTests: XCTestCase {

    /// **座標は端末側でも丸めてから送る。** サーバーも丸めるが、
    /// 丸める前の値を電波に乗せる理由が無い。
    func testCoordsAreRoundedToAboutOneKilometer() throws {
        var draft = PhotoDraft()
        draft.coords = Photo.Coords(lat: 34.123456, lng: 133.987654)
        let body = draft.saveBody(key: "uploads/u/1.jpg", publicUrl: "https://x/1.jpg")
        XCTAssertEqual(body.coords?.lat, 34.12)
        XCTAssertEqual(body.coords?.lng, 133.99)
    }

    /// **入っていた撮影地を本人が空にしたら、座標も送らない。**
    /// 自宅の地名を消しても座標（約1km）が送られて地図に出ていた。
    /// ただし**自動入力が間に合わなかっただけ**なら送る（Web と同じ・d525… の回帰の芽）
    func testCoordsFollowWhetherTheUserClearedThePlace() {
        let prepared = ImagePreparer.Prepared(data: Data(), fileName: "p.jpg", contentType: "image/jpeg",
                                              exif: nil, coords: Photo.Coords(lat: 34.12, lng: 133.99), takenOn: nil)
        var item = PendingPhoto(prepared: prepared)
        // 撮影地がまだ入っていない（自動入力が間に合わない）→ 送る
        XCTAssertNotNil(item.coordsToSend)
        // 自動で入った → 送る
        item.fillAutomatically("観音寺市")
        XCTAssertNotNil(item.coordsToSend)
        // 本人が空にした → 送らない
        item.location = ""
        XCTAssertNil(item.coordsToSend)
        // 自動で入った地名に戻した → また送る
        item.location = "観音寺市"
        XCTAssertNotNil(item.coordsToSend)
        // 消したあと空白だけ打った → 送るときは空なので、座標も送らない
        item.location = ""
        item.location = "  "
        XCTAssertNil(item.coordsToSend)
    }

    // MARK: - 書き換えた撮影地と写真の座標（2026-10-07 判断）

    private func shotAtHome() -> ImagePreparer.Prepared {
        ImagePreparer.Prepared(data: Data(), fileName: "p.jpg", contentType: "image/jpeg",
                               exif: nil, coords: Photo.Coords(lat: 34.12, lng: 133.66), takenOn: nil)
    }

    /// 🔴 **自動で入った地名を書き換えたら、写真の座標を送らない。** 自宅の町の地名を
    /// 「東京」に直しても、ピンが自宅のあたりに立っていた
    func testRewrittenPlaceDropsPhotoCoords() {
        var item = PendingPhoto(prepared: shotAtHome())
        item.fillAutomatically("観音寺市")
        item.location = "東京"
        XCTAssertNil(item.coordsToSend, "書き換えた地名に写真の位置のピンが立つ")
        // 一字だけ足しても同じ（人が変えた）
        item.location = "観音寺市内"
        XCTAssertNil(item.coordsToSend)
        // 自動入力が間に合う前に打った地名にも、写真の座標を付けない
        var typed = PendingPhoto(prepared: shotAtHome())
        typed.location = "東京"
        XCTAssertNil(typed.coordsToSend)
    }

    /// 候補から選び直したら、選んだ地名の座標を送る（人が選んだ場所）
    func testPickedPlaceSendsItsCoords() {
        var item = PendingPhoto(prepared: shotAtHome())
        item.fillAutomatically("観音寺市")
        let tokyo = Photo.Coords(lat: 35.68, lng: 139.77)
        // `PlaceSearchField` の候補の選び方と同じ順（座標 → 地名）
        item.pickedCoords = tokyo
        item.location = "東京都千代田区"
        XCTAssertEqual(item.coordsToSend, tokyo)
    }

    /// 自動で入った地名を一字も変えなければ、写真の座標を今までどおり送る（前後の空白は見ない）
    func testUntouchedAutoPlaceKeepsPhotoCoords() {
        var item = PendingPhoto(prepared: shotAtHome())
        item.fillAutomatically("観音寺市")
        XCTAssertEqual(item.coordsToSend, shotAtHome().coords)
        item.location = "観音寺市 "
        XCTAssertEqual(item.coordsToSend, shotAtHome().coords)
    }

    /// 空にしたら送らない（今までどおり）。書き換えてから空にしても同じ
    func testClearedPlaceSendsNoCoords() {
        var item = PendingPhoto(prepared: shotAtHome())
        item.fillAutomatically("観音寺市")
        item.location = "東京"
        item.location = ""
        XCTAssertNil(item.coordsToSend)
        XCTAssertNil(item.coordsToSend(spot: nil))
    }

    /// 自動入力は投稿画面の道（`fillPlaceName`・スポットから開いた回）から `fillAutomatically` を通る。
    /// 直に `location` へ入れると、自動の地名が「人が書き換えた」に見えてピンが消える
    func testAutoFillGoesThroughFillAutomatically() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto/Features/Upload/UploadViewModel.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("items[index].fillAutomatically(next)"))
        XCTAssertTrue(source.contains("photo.fillAutomatically(spot.name)"))
    }

    /// スポットから開いた投稿で県を足した（紐付けは残る）なら、スポットの近くで撮った写真の座標を送る。
    /// スポットから遠い写真に、手でスポットの名前を打っても写真の座標は付けない
    func testSpotTiedPlaceKeepsNearbyPhotoCoords() {
        let spot = UploadSpotTarget(spotId: "sp_0123456789ab", name: "高屋神社",
                                    coords: Photo.Coords(lat: 34.12, lng: 133.63))
        var item = PendingPhoto(prepared: shotAtHome())
        item.fillAutomatically(spot.name)
        item.location = "高屋神社, 香川"
        XCTAssertEqual(item.coordsToSend(spot: spot), shotAtHome().coords)
        var far = PendingPhoto(prepared: ImagePreparer.Prepared(
            data: Data(), fileName: "p.jpg", contentType: "image/jpeg", exif: nil,
            coords: Photo.Coords(lat: 35.66, lng: 139.75), takenOn: nil))
        far.location = "高屋神社"
        XCTAssertNil(far.coordsToSend(spot: spot), "東京で撮った写真が高屋神社のピンとして出る")
    }

    /// 🔴 **位置の無い写真をスポットから投稿したら、撮影地を書き足してもピンが残る。**
    /// スポットの座標を `pickedCoords` に入れていたので、撮影地の欄の文字が変わると
    /// 捨てられ、`spotId` は付いたまま座標だけ消えていた
    @MainActor
    func testSpotCoordsSurviveEditingThePlaceText() async {
        let spotCoords = Photo.Coords(lat: 34.12, lng: 133.63)
        let spot = UploadSpotTarget(spotId: "sp_0123456789ab", name: "高屋神社", coords: spotCoords)
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"))
        let model = UploadViewModel(uploads: UploadService(api: api), albums: AlbumService(api: api),
                                    photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        model.spot = spot
        let prepared = ImagePreparer.Prepared(data: Data(), fileName: "p.jpg", contentType: "image/jpeg",
                                              exif: nil, coords: nil, takenOn: nil)
        model.append(prepared)
        var item = model.items[0]
        XCTAssertEqual(item.coordsToSend(spot: spot), spotCoords)
        // 撮影地の欄が座標を捨てる（`PlaceSearchField` が文字の変化で nil にする）
        item.location = "高屋神社, 香川"
        item.pickedCoords = nil
        XCTAssertEqual(item.coordsToSend(spot: spot), spotCoords, "spotId は付くのにピンが消えた")
        // スポットの名前が消えた・スポットを外した・撮影地を空にした → 送らない
        item.location = "観音寺市"
        XCTAssertNil(item.coordsToSend(spot: spot))
        item.location = "高屋神社"
        XCTAssertNil(item.coordsToSend(spot: UploadSpotTarget?.none))
        item.location = ""
        XCTAssertNil(item.coordsToSend(spot: spot))
    }

    /// 位置のある写真は、スポットから開いても写真の座標を送る
    func testPhotoCoordsWinOverSpotCoords() {
        let taken = Photo.Coords(lat: 34.10, lng: 133.60)
        let spot = UploadSpotTarget(spotId: "sp_0123456789ab", name: "高屋神社",
                                    coords: Photo.Coords(lat: 34.12, lng: 133.63))
        var item = PendingPhoto(prepared: ImagePreparer.Prepared(
            data: Data(), fileName: "p.jpg", contentType: "image/jpeg", exif: nil, coords: taken, takenOn: nil))
        item.location = "高屋神社"
        XCTAssertEqual(item.coordsToSend(spot: spot), taken)
    }

    /// **押し直しでも束の印を変えない。** 送るたびに作り直すと、5枚のうち2枚が
    /// 失敗して押し直したとき 3枚と2枚の2つの束に割れ、1枚だけ残ると印が消えていた
    func testGroupIdIsKeptAcrossRetries() {
        var made = 0
        let make = { () -> String in made += 1; return "g\(made)" }
        let first = UploadGrouping.groupIdForSubmit(current: nil, grouping: true, count: 5, make: make)
        XCTAssertEqual(first, "g1")
        // 2枚失敗して押し直す／1枚だけ残って押し直す
        XCTAssertEqual(UploadGrouping.groupIdForSubmit(current: first, grouping: true, count: 2, make: make), "g1")
        XCTAssertEqual(UploadGrouping.groupIdForSubmit(current: first, grouping: true, count: 1, make: make), "g1")
        XCTAssertEqual(made, 1)
        // 最初から1枚なら印は付けない。まとめない設定なら付けない
        XCTAssertNil(UploadGrouping.groupIdForSubmit(current: nil, grouping: true, count: 1, make: make))
        XCTAssertNil(UploadGrouping.groupIdForSubmit(current: "g1", grouping: false, count: 5, make: make))
    }

    /// スポットの画面から開いた投稿は `spotId` を送る。**本人が撮影地を空にした写真には
    /// 付けない**（場所を伏せたのに、スポットの紐付けで場所が分かってしまう）。
    /// 普通の投稿は送らない（キーごと落ちる）
    func testSpotIdIsSentOnlyForSpotUploadsWithPlaceKept() throws {
        let target = UploadSpotTarget(spotId: "sp_0123456789ab", name: "高屋神社",
                                      coords: Photo.Coords(lat: 34.1, lng: 133.6))
        let prepared = ImagePreparer.Prepared(data: Data(), fileName: "p.jpg", contentType: "image/jpeg",
                                              exif: nil, coords: nil, takenOn: nil)
        var item = PendingPhoto(prepared: prepared)
        item.location = target.name
        XCTAssertEqual(UploadSpotTarget.spotIdToSend(target, for: item), "sp_0123456789ab")
        XCTAssertNil(UploadSpotTarget.spotIdToSend(nil, for: item), "普通の投稿")
        item.location = ""
        XCTAssertNil(UploadSpotTarget.spotIdToSend(target, for: item), "撮影地を空にした")
        item.location = "東京タワー"
        XCTAssertNil(UploadSpotTarget.spotIdToSend(target, for: item), "撮影地を別の場所に変えた")
        item.location = "高屋神社, 香川"
        XCTAssertEqual(UploadSpotTarget.spotIdToSend(target, for: item), "sp_0123456789ab", "県を足しただけで外した")

        // 写真の位置: 無い → 扱う。近い → 扱う。遠い（別の旅の写真）→ 扱わない
        func shot(_ c: Photo.Coords?) -> ImagePreparer.Prepared {
            ImagePreparer.Prepared(data: Data(), fileName: "p.jpg", contentType: "image/jpeg",
                                   exif: nil, coords: c, takenOn: nil)
        }
        XCTAssertTrue(target.covers(shot(nil)))
        XCTAssertTrue(target.covers(shot(Photo.Coords(lat: 34.12, lng: 133.62))))
        XCTAssertFalse(target.covers(shot(Photo.Coords(lat: 35.66, lng: 139.75))), "東京の写真")

        // ボタンの形: 写真が並ぶ・投稿した → 枠線、写真の無い画面 → 真鍮、代表写真がある → 白
        XCTAssertEqual(OfficialSpotView.postButtonStyle(hasCover: true, hasLinked: true, postedHere: false), .outline)
        XCTAssertEqual(OfficialSpotView.postButtonStyle(hasCover: false, hasLinked: false, postedHere: true), .outline)
        XCTAssertEqual(OfficialSpotView.postButtonStyle(hasCover: false, hasLinked: false, postedHere: false), .accent)
        XCTAssertEqual(OfficialSpotView.postButtonStyle(hasCover: true, hasLinked: false, postedHere: false), .primary)

        var draft = PhotoDraft()
        draft.spotId = "sp_0123456789ab"
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft.saveBody(key: "k", publicUrl: "u"))) as? [String: Any]
        XCTAssertEqual(json?["spotId"] as? String, "sp_0123456789ab")
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PhotoDraft().saveBody(key: "k", publicUrl: "u"))) as? [String: Any]
        XCTAssertNil(plain?["spotId"], "普通の投稿は spotId を送らない")
    }

    /// 空の項目は送らない（api-user は「未指定＝触らない」と読む）。
    func testEmptyFieldsAreOmitted() throws {
        let body = PhotoDraft().saveBody(key: "k", publicUrl: "u")
        XCTAssertNil(body.title)
        XCTAssertNil(body.location)
        XCTAssertNil(body.tags)
    }

    /// 区切りは読点・カンマ（Web の `TAG_SEPARATOR`）。**空白では切らない。**
    /// 重複は落とす（同じタグが2つ付くと絞り込みの件数がずれる）。
    func testTagParsing() {
        XCTAssertEqual(TagInput.parse("雲海, sunrise 雲海, 雲海"), ["雲海", "sunrise 雲海"])
        XCTAssertEqual(TagInput.parse("  "), [])
        XCTAssertEqual(TagInput.parse("a、b"), ["a", "b"])
    }
}

final class InviteTokenTests: XCTestCase {

    /// **リンクをそのまま貼れること。** 受け取った人に `?t=` の後ろだけを
    /// 取り出させない（URL を貼って弾かれるのがいちばん多い失敗）。
    func testTakesTokenFromInviteURL() {
        XCTAssertEqual(
            InviteLink.token(from: "https://journey-photo.com/j?t=abc123"),
            "abc123"
        )
    }

    func testAcceptsBareToken() {
        XCTAssertEqual(InviteLink.token(from: "  abc123 "), "abc123")
    }

    /// トークンを持たない URL は「読み取れなかった」にする——
    /// URL 全体をトークンとして送ると、サーバーに無意味な問い合わせが飛ぶ。
    func testRejectsURLWithoutToken() {
        XCTAssertEqual(InviteLink.token(from: "https://journey-photo.com/"), "")
    }
}
