import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 投稿の「撮影地の位置を付ける」（2026-10-18 判断・`UploadLocationPreference`）。
///
/// 以前は切り替えが無く、写真に位置情報があって自動で入った撮影地のまま投稿すると、聞かずに座標を送っていた。
/// オフで写真の座標を送らない・地名を問い合わせない、オンは今までどおり、選んだ値は人ごとに覚える
@MainActor
final class UploadLocationToggleTests: XCTestCase {

    private let photoCoords = Photo.Coords(lat: 34.28, lng: 133.8)
    private let spotCoords = Photo.Coords(lat: 34.29, lng: 133.81)

    override func tearDown() {
        ScriptedProtocol.reset()
        super.tearDown()
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    private func model(defaults: UserDefaults? = nil) -> UploadViewModel {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        let session = URLSession(configuration: config)
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let m = UploadViewModel(uploads: UploadService(api: api, session: session), albums: AlbumService(api: api),
                                photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        m.locationPreference = UploadLocationPreference(defaults: defaults ?? self.defaults())
        return m
    }

    /// 地名の問い合わせを「飛んでいる途中」で止められるモデル（`Gate`・`PathGates`）
    private func gatedModel(gate: Gate) -> UploadViewModel {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        let session = URLSession(configuration: config)
        let gates = PathGates(["/geocode/reverse": gate])
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session,
                            beforeRequest: { request in await gates.wait(for: request) })
        let m = UploadViewModel(uploads: UploadService(api: api, session: session), albums: AlbumService(api: api),
                                photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        m.locationPreference = UploadLocationPreference(defaults: defaults())
        return m
    }

    private func prepared(_ byte: UInt8 = 1, coords: Photo.Coords?) -> ImagePreparer.Prepared {
        ImagePreparer.Prepared(data: Data(repeating: byte, count: 16), fileName: "photo\(byte).jpg",
                               contentType: "image/jpeg", exif: nil, coords: coords, takenOn: nil)
    }

    /// 写真の位置から自動で入れた撮影地のままの1枚
    private func autoFilled() -> PendingPhoto {
        var photo = PendingPhoto(prepared: prepared(coords: photoCoords))
        photo.fillAutomatically("高松市")
        return photo
    }

    private let presign = """
    {"presignedUrl":"https://s3.example.test/put?sig=1","key":"uploads/u1/abc.jpg",
     "publicUrl":"https://cdn.example.test/uploads/u1/abc.jpg","photoId":"p1","contentType":"image/jpeg"}
    """

    private func scriptUpload() {
        ScriptedProtocol.reset()
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: presign),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#),
        ]
    }

    private func saveBodies() -> [[String: Any]] {
        ScriptedProtocol.calls.filter { $0.path == "/upload/save" }.compactMap { call in
            call.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
    }

    // MARK: - 送る中身

    /// 🔴 **オフなら、自動で入った撮影地のままでも写真の座標を送らない**（以前は聞かずに送っていた）
    func testOffSendsNoCoordinatesInTheSaveBody() async {
        scriptUpload()
        let m = model()
        m.useLocationOwner("u1")
        m.setAttachesLocation(false)
        m.items = [autoFilled()]
        await m.submit()
        let bodies = saveBodies()
        XCTAssertEqual(bodies.count, 1, "前提: 保存まで届いた")
        XCTAssertNil(bodies.first?["coords"], "オフなのに写真の座標を送った")
    }

    /// **オンは今までどおり**——自動で入った撮影地のまま、写真の座標（約1km）を送る
    func testOnSendsThePhotoCoordinatesAsBefore() async {
        scriptUpload()
        let m = model()
        m.useLocationOwner("u1")
        XCTAssertTrue(m.attachesLocation, "前提: 既定はオン（Web と同じ）")
        m.items = [autoFilled()]
        await m.submit()
        let coords = saveBodies().first?["coords"] as? [String: Double]
        XCTAssertEqual(coords?["lat"], 34.28)
        XCTAssertEqual(coords?["lng"], 133.8)
    }

    /// 1枚の決まり: オフは写真の位置を使わず、本人が候補から選んだ場所だけ
    func testOffKeepsOnlyPlacesThePersonPicked() async {
        // 自動の地名・欄が空（自動入力が間に合わなかった）: オンは送る、オフは送らない
        XCTAssertEqual(autoFilled().coordsToSend(spots: []), photoCoords)
        XCTAssertNil(autoFilled().coordsToSend(spots: [], attachesPhotoLocation: false))
        let empty = PendingPhoto(prepared: prepared(coords: photoCoords))
        XCTAssertEqual(empty.coordsToSend(spots: []), photoCoords)
        XCTAssertNil(empty.coordsToSend(spots: [], attachesPhotoLocation: false))

        // 地名の候補を選んだ: その地名の座標は送る（写真の位置ではない）
        var picked = PendingPhoto(prepared: prepared(coords: photoCoords))
        picked.location = "丸亀市"
        picked.pickedCoords = Photo.Coords(lat: 34.29, lng: 133.79)
        XCTAssertEqual(picked.coordsToSend(spots: [], attachesPhotoLocation: false),
                       Photo.Coords(lat: 34.29, lng: 133.79))

        // 撮影スポットの候補を選んだ: 写真が近いと写真の座標が入る（`coordsAfterPicking`）→ オフはスポットの座標
        var spotPick = PendingPhoto(prepared: prepared(coords: photoCoords))
        let target = UploadSpotTarget(spotId: "sp_000000000001", name: "高屋神社", coords: spotCoords)
        spotPick.pickedSpot = target
        spotPick.pickedCoords = PlaceCoordsRule.coordsForPickedSpot(spotCoords, photo: photoCoords)
        spotPick.location = "高屋神社"
        XCTAssertEqual(spotPick.pickedCoords, photoCoords, "前提: 近いスポットは写真の座標が入る")
        XCTAssertEqual(spotPick.coordsToSend(spots: []), photoCoords, "オンは今までどおり")
        XCTAssertEqual(spotPick.coordsToSend(spots: [], attachesPhotoLocation: false), spotCoords,
                       "オフで写真の座標を送った")

        // スポットの画面から開いた: オフはスポットの座標（写真が近くても写真の座標にしない）
        var fromSpot = PendingPhoto(prepared: prepared(coords: photoCoords))
        fromSpot.location = "高屋神社"
        XCTAssertEqual(fromSpot.coordsToSend(spot: target), photoCoords, "オンは今までどおり")
        XCTAssertEqual(fromSpot.coordsToSend(spot: target, attachesPhotoLocation: false), spotCoords)

        // 撮影地を空にした: どちらでも送らない（今までどおり）
        var cleared = autoFilled()
        cleared.location = ""
        XCTAssertNil(cleared.coordsToSend(spots: []))
        XCTAssertNil(cleared.coordsToSend(spots: [], attachesPhotoLocation: false))
    }

    // MARK: - 地名の問い合わせ

    /// 🔴 **オフなら、写真の座標でサーバーに地名を問い合わせない**
    func testOffDoesNotAskTheServerForThePlaceName() async {
        ScriptedProtocol.reset()
        ScriptedProtocol.script = [.init(match: "/geocode/reverse", status: 200, body: #"{"place":"高松市"}"#)]
        let m = model()
        m.useLocationOwner("u1")
        m.setAttachesLocation(false)
        m.append(prepared(coords: photoCoords))
        await m.fillPlaceName(for: m.items[0].id, lat: 34.28, lng: 133.8)
        XCTAssertFalse(ScriptedProtocol.calls.contains { $0.path.contains("/geocode/reverse") },
                       "オフなのに座標を送って地名を引いた")
        XCTAssertEqual(m.items[0].location, "", "オフなのに撮影地を自動で入れた")
    }

    /// オンは今までどおり引いて入れる
    func testOnFillsThePlaceNameAsBefore() async {
        ScriptedProtocol.reset()
        ScriptedProtocol.script = [.init(match: "/geocode/reverse", status: 200, body: #"{"place":"高松市"}"#)]
        let m = model()
        m.useLocationOwner("u1")
        m.items = [PendingPhoto(prepared: prepared(coords: photoCoords))]
        await m.fillPlaceName(for: m.items[0].id, lat: 34.28, lng: 133.8)
        XCTAssertEqual(m.items[0].location, "高松市")
    }

    /// オフにしたら、自動で入れた地名だけ外す（本人が直した地名は残す）。外しても「空にした」印は立てない
    func testTurningOffDropsOnlyTheAutomaticPlace() async {
        let m = model()
        m.useLocationOwner("u1")
        var typed = autoFilled()
        typed.location = "瀬戸内"
        m.items = [autoFilled(), typed]
        m.setAttachesLocation(false)
        XCTAssertEqual(m.items[0].location, "", "写真の位置から入れた地名が残った（公開される）")
        XCTAssertEqual(m.items[1].location, "瀬戸内", "本人が書いた地名まで消した")
        XCTAssertFalse(m.items[0].locationClearedByUser, "本人が空にしたことにした（オンに戻しても座標が落ちる）")
    }

    // MARK: - 人ごとに覚える

    /// 選んだ値を人ごとに覚える（開き直しても同じ値）
    func testChoiceIsRememberedPerPerson() async {
        let store = defaults()
        let first = model(defaults: store)
        first.useLocationOwner("a")
        first.setAttachesLocation(false)

        let reopened = model(defaults: store)
        reopened.useLocationOwner("a")
        XCTAssertFalse(reopened.attachesLocation, "選んだオフを覚えていない")

        let prefs = UploadLocationPreference(defaults: store)
        XCTAssertFalse(prefs.attachesLocation(userId: "a"))
        prefs.set(true, userId: "a")
        XCTAssertTrue(prefs.attachesLocation(userId: "a"))
    }

    /// 🔴 **人が替わったら前の人の値を使わない**（覚えが無い人はオン）。次の人が変えても前の人の値は変わらない
    func testNextPersonDoesNotGetThePreviousPersonsChoice() async {
        let store = defaults()
        let m = model(defaults: store)
        m.useLocationOwner("a")
        m.setAttachesLocation(false)

        m.useLocationOwner("b")
        XCTAssertTrue(m.attachesLocation, "前の人のオフを次の人に使った")
        m.setAttachesLocation(false)
        m.setAttachesLocation(true)

        m.useLocationOwner("a")
        XCTAssertFalse(m.attachesLocation, "次の人の操作で前の人の値が変わった")

        // 🔴 ログアウト・期限切れ（持ち主が分からない）では値を替えない（a のオフのまま・オンに戻さない）。
        // nil の間の操作は書かない
        m.useLocationOwner(nil)
        XCTAssertFalse(m.attachesLocation, "ログアウトで既定のオンに戻した")
        m.setAttachesLocation(true)
        XCTAssertNil(store.object(forKey: "journey-photo-upload-attach-location"), "持ち主の無い値を書いた")
        XCTAssertFalse(UploadLocationPreference(defaults: store).attachesLocation(userId: "a"),
                       "持ち主の無い操作が前の人の値を変えた")
    }

    /// 🔴 **写真を並べたあとで持ち主が nil・別の人に替わっても、地名を問い合わせない**（2026-10-18 の見直し）。
    /// 以前はログアウトで既定のオンに戻り、オフにしていた人の写真の座標で `/geocode/reverse` を呼んでいた
    func testOwnerChangeAfterPhotosDoesNotAskForPlaceNames() async {
        ScriptedProtocol.reset()
        ScriptedProtocol.script = [.init(match: "/geocode/reverse", status: 200, body: #"{"place":"高松市"}"#)]
        let m = model()
        m.useLocationOwner("a")
        m.setAttachesLocation(false)
        m.append(prepared(1, coords: photoCoords))
        m.append(prepared(2, coords: photoCoords))

        m.useLocationOwner(nil)                 // ログアウト・期限切れ
        XCTAssertFalse(m.attachesLocation)
        m.useLocationOwner("b")                 // 別の人（覚えが無い＝オン）
        XCTAssertTrue(m.attachesLocation, "前提: 次の人の値（オン）を読んだ")
        XCTAssertTrue(m.placeTasks.isEmpty, "人が替わっただけで地名を引き始めた")
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(ScriptedProtocol.calls.contains { $0.path.contains("/geocode/reverse") },
                       "人が替わっただけで並べた写真の座標を送った")
        XCTAssertEqual(m.items.map(\.location), ["", ""])

        // 本人が押してオンにしたときは引く（今までと同じ道）
        m.setAttachesLocation(false)
        m.setAttachesLocation(true)
        XCTAssertEqual(m.placeTasks.count, 2, "本人が押してオンにしたのに引かない")
    }

    /// 🔴 オフにしたら、引いている最中の問い合わせを取り消す
    func testTurningOffCancelsLookupsInFlight() async {
        ScriptedProtocol.reset()
        ScriptedProtocol.script = [.init(match: "/geocode/reverse", status: 200, body: #"{"place":"高松市"}"#)]
        let gate = Gate()
        let m = gatedModel(gate: gate)
        m.useLocationOwner("a")
        m.append(prepared(coords: photoCoords))
        let task = m.placeTasks[m.items[0].id]
        XCTAssertNotNil(task, "前提: オンで並べたら引き始める")
        await gate.untilWaiting()
        m.setAttachesLocation(false)
        XCTAssertTrue(task?.isCancelled ?? false, "オフにしたのに問い合わせを止めない")
        await gate.open()
        await task?.value
        XCTAssertEqual(m.items[0].location, "")
    }

    /// 🔴 問い合わせの最中にオフにしたら、届いた地名を入れない
    func testAnswerArrivingAfterTurningOffIsDropped() async {
        ScriptedProtocol.reset()
        ScriptedProtocol.script = [.init(match: "/geocode/reverse", status: 200, body: #"{"place":"高松市"}"#)]
        let gate = Gate()
        let m = gatedModel(gate: gate)
        m.useLocationOwner("a")
        m.items = [PendingPhoto(prepared: prepared(coords: photoCoords))]
        // 画面の仕事（`placeTasks`）ではなく直に引く——取り消しではなく、届いた答えの見張りを見る
        let lookup = Task { await m.fillPlaceName(for: m.items[0].id, lat: 34.28, lng: 133.8) }
        await gate.untilWaiting()
        m.setAttachesLocation(false)
        await gate.open()
        await lookup.value
        XCTAssertEqual(m.items[0].location, "", "オフにしたあとに届いた地名を入れた（公開される）")
    }

    /// 🔴 オフのまま下書きを開き直すと、写真の位置から自動で入れた地名は戻さない（オンのときに保存した下書き）
    func testRestoringADraftWhileOffDropsTheAutomaticPlace() async throws {
        let store = defaults()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = model(defaults: store)
        first.drafts = UploadDraftStore(defaults: store, directory: directory)
        first.draftOwner = "a"
        first.makeDraftThumbnail = { _ in nil }
        first.useLocationOwner("a")
        var typed = autoFilled()
        typed.location = "瀬戸内"
        first.items = [autoFilled(), typed]
        XCTAssertTrue(first.saveDraft(), "前提: 下書きに書けた")

        let next = model(defaults: store)
        next.drafts = UploadDraftStore(defaults: store, directory: directory)
        next.draftOwner = "a"
        next.makeDraftThumbnail = { _ in nil }
        next.useLocationOwner("a")
        next.setAttachesLocation(false)
        let restored = await next.restoreDraft()
        XCTAssertTrue(restored)
        XCTAssertEqual(next.items.map(\.location), ["", "瀬戸内"],
                       "オフなのに自動の地名を戻した・本人が直した地名まで消した")
    }

    /// 同じ人で呼び直しても、画面の中で選んだ値を戻さない（画面は戻るたびに持ち主を入れ直す）
    func testSameOwnerAgainKeepsTheChoice() async {
        let m = model()
        m.useLocationOwner(nil)
        m.setAttachesLocation(false)
        m.useLocationOwner(nil)
        XCTAssertFalse(m.attachesLocation)
    }

    /// 退会したら消える（`AccountLocalData`）。別の人の値は残る
    func testRemovedWithTheAccount() async {
        let store = defaults()
        let prefs = UploadLocationPreference(defaults: store)
        prefs.set(false, userId: "gone")
        prefs.set(false, userId: "stays")
        AccountLocalData.remove(userId: "gone", username: nil, defaults: store,
                                draftDirectory: FileManager.default.temporaryDirectory
                                    .appendingPathComponent(UUID().uuidString),
                                offlineTripsRoot: FileManager.default.temporaryDirectory
                                    .appendingPathComponent(UUID().uuidString),
                                passRoot: FileManager.default.temporaryDirectory
                                    .appendingPathComponent(UUID().uuidString))
        XCTAssertNil(store.object(forKey: UploadLocationPreference.key(for: "gone")!))
        XCTAssertFalse(prefs.attachesLocation(userId: "stays"))
    }

    // MARK: - 言葉

    /// 名前に「約1kmに丸めて保存」を入れる。英語もある
    func testWording() async {
        XCTAssertTrue(UploadDetails.locationToggleTitle.contains(L("約1km", "1 km")))
        XCTAssertNotEqual(UploadDetails.locationToggleNote(attaches: true),
                          UploadDetails.locationToggleNote(attaches: false))
    }
}
