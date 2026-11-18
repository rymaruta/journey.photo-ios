import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// **何枚か選んだら「1つの投稿」が既定。撮影地・題・説明は1組だけ書く**（2026-11-18 owner 採用・案 B3）。
///
/// 送るときに先頭の写真の値を全部の写真に写す。サーバーは1枚ずつの行のまま（保存は写真の数だけ・同じ束の印）。
/// 「写真ごとに書く ›」で写真ごとに書ける。「それぞれ別の投稿」の切り替えは残す
@MainActor
final class UploadSharedFieldsTests: XCTestCase {

    override func tearDown() {
        ScriptedProtocol.reset()
        super.tearDown()
    }

    private func model() -> UploadViewModel {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        let session = URLSession(configuration: config)
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let m = UploadViewModel(uploads: UploadService(api: api, session: session), albums: AlbumService(api: api),
                                photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        m.locationPreference = UploadLocationPreference(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        return m
    }

    private func photo(_ byte: UInt8, coords: Photo.Coords? = nil) -> PendingPhoto {
        PendingPhoto(prepared: ImagePreparer.Prepared(data: Data(repeating: byte, count: 16), fileName: "p\(byte).jpg",
                                                      contentType: "image/jpeg", exif: nil, coords: coords, takenOn: nil))
    }

    private func scriptUpload() {
        ScriptedProtocol.reset()
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 200, body: """
            {"presignedUrl":"https://s3.example.test/put?sig=1","key":"uploads/u1/abc.jpg",
             "publicUrl":"https://cdn.example.test/uploads/u1/abc.jpg","photoId":"p1","contentType":"image/jpeg"}
            """),
            .init(match: "/put", status: 200, body: ""),
            .init(match: "/upload/save", status: 200, body: #"{"success":true,"photo":{"id":"p1","src":"https://x/p1.jpg"}}"#),
        ]
    }

    private func saveBodies() -> [[String: Any]] {
        ScriptedProtocol.calls.filter { $0.path == "/upload/save" }.compactMap { call in
            call.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
    }

    // MARK: - 既定

    /// 既定は「1つの投稿」。2枚以上で欄は1組、1枚なら写真ごとの欄（1組と同じ）
    func testDefaultIsOnePostWithOneSetOfFields() async {
        let m = model()
        XCTAssertTrue(m.groupsAsOnePost, "既定が「1つの投稿」でない")
        m.items = [photo(1)]
        XCTAssertFalse(m.sharesFields, "1枚で1組の扱いになった（何枚目の見出しが出ないだけで同じ欄）")
        m.items = [photo(1), photo(2), photo(3)]
        XCTAssertTrue(m.sharesFields)
        m.groupsAsOnePost = false
        XCTAssertFalse(m.sharesFields, "「それぞれ別の投稿」でも1組のまま")
        XCTAssertEqual(UploadSharedFields.tapsBefore, 9)
        XCTAssertEqual(UploadSharedFields.tapsShared, 8)
    }

    // MARK: - 送る

    /// 🔴 1組だけ書けば、全部の写真に同じ題・説明・撮影地（選んだ場所の座標も）が付く。保存は写真の数だけ・同じ束
    func testOneSetIsCopiedToEveryPhotoOnSubmit() async {
        scriptUpload()
        let m = model()
        m.items = [photo(1), photo(2), photo(3)]
        m.items[0].title = "高屋神社の雲海"
        m.items[0].caption = "朝五時の雲"
        m.items[0].location = "高屋神社"
        m.items[0].pickedCoords = Photo.Coords(lat: 34.15, lng: 133.68)
        await m.submit()
        let bodies = saveBodies()
        XCTAssertEqual(bodies.count, 3, "サーバーは1枚ずつの行のまま（保存は写真の数だけ）")
        XCTAssertEqual(bodies.compactMap { $0["title"] as? String }, Array(repeating: "高屋神社の雲海", count: 3),
                       "2枚目より後に題が写っていない")
        XCTAssertEqual(bodies.compactMap { $0["description"] as? String }, Array(repeating: "朝五時の雲", count: 3))
        XCTAssertEqual(bodies.compactMap { $0["location"] as? String }, Array(repeating: "高屋神社", count: 3))
        let groups = Set(bodies.compactMap { $0["groupId"] as? String })
        XCTAssertEqual(groups.count, 1, "1つの投稿の束に入っていない")
        XCTAssertEqual(bodies.compactMap { ($0["coords"] as? [String: Any])?["lat"] as? Double }.count, 3,
                       "選んだ場所の座標が2枚目より後に付いていない")
        XCTAssertTrue(m.didPostAll)
    }

    /// 写真の位置から入れた撮影地を写すと、ほかの写真では「自動の地名」のまま（その写真の座標を送る・`PlaceCoordsRule` の (a)）
    func testAutomaticPlaceKeepsEachPhotosOwnCoords() async {
        var first = photo(1, coords: Photo.Coords(lat: 34.1, lng: 133.6))
        first.fillAutomatically("観音寺市")
        var second = photo(2, coords: Photo.Coords(lat: 34.2, lng: 133.7))
        second.copySharedFields(from: first)
        XCTAssertEqual(second.location, "観音寺市")
        XCTAssertEqual(second.coordsToSend(spots: []), Photo.Coords(lat: 34.2, lng: 133.7),
                       "写した自動の地名で、その写真の座標が落ちた（手で書いた地名の扱いになった）")
        // 空にした撮影地を写したら、ほかの写真の座標も送らない
        var cleared = photo(3, coords: Photo.Coords(lat: 35, lng: 135))
        cleared.fillAutomatically("京都市")
        cleared.location = ""
        var third = photo(4, coords: Photo.Coords(lat: 36, lng: 136))
        third.copySharedFields(from: cleared)
        XCTAssertNil(third.coordsToSend(spots: []), "空にした撮影地を写したのに座標を送る")
    }

    /// 「それぞれ別の投稿」は前と同じ（写さない・束にしない）
    func testSeparatePostsKeepEachPhotosFields() async {
        scriptUpload()
        let m = model()
        m.groupsAsOnePost = false
        m.items = [photo(1), photo(2)]
        m.items[0].title = "一枚目"
        await m.submit()
        let bodies = saveBodies()
        XCTAssertEqual(bodies.compactMap { $0["title"] as? String }, ["一枚目"], "別々の投稿で題を写した")
        XCTAssertTrue(bodies.allSatisfy { $0["groupId"] == nil }, "別々の投稿に束の印が付いた")
    }

    // MARK: - 写真ごとに書く

    /// 「写真ごとに書く ›」を開くと、先頭の値を写してから写真ごとの欄。そのあと直した値はそのまま送る
    func testOpeningPerPhotoCopiesThenKeepsEdits() async {
        scriptUpload()
        let m = model()
        m.items = [photo(1), photo(2)]
        m.items[0].title = "雲海"
        m.openPerPhotoFields()
        XCTAssertTrue(m.writesPerPhoto)
        XCTAssertFalse(m.sharesFields)
        XCTAssertEqual(m.items[1].title, "雲海", "開いた先の2枚目が空のまま（1組で書いた値が消えて見える）")
        m.items[1].title = "鳥居"
        await m.submit()
        XCTAssertEqual(saveBodies().compactMap { $0["title"] as? String }, ["雲海", "鳥居"], "写真ごとに直した値が上書きされた")
    }

    /// 🔴 2枚目より後に本人が書いた値があれば、1組に畳まない（畳むと隠れて、送るときに先頭の値で上書きされる）
    func testOwnTextOnLaterPhotosIsNeverHiddenOrOverwritten() async {
        scriptUpload()
        let m = model()
        m.groupsAsOnePost = false
        m.items = [photo(1), photo(2)]
        m.items[0].title = "一枚目"
        m.items[1].title = "二枚目"
        m.groupsAsOnePost = true
        XCTAssertTrue(m.writesPerPhoto, "別々で書いてから「1つの投稿」に戻したら畳まれた")
        XCTAssertFalse(m.sharesFields)
        // 「写真ごとに書く」を閉じる道が無くても、どの道から来ても上書きしない
        m.writesPerPhoto = false
        XCTAssertFalse(m.sharesFields, "書いた値があるのに1組にした")
        await m.submit()
        XCTAssertEqual(saveBodies().compactMap { $0["title"] as? String }, ["一枚目", "二枚目"])
        // 自動で入れた撮影地は本人が書いた値に数えない
        var auto = photo(3)
        auto.fillAutomatically("白石市")
        XCTAssertFalse(UploadSharedFields.hasOwnText([photo(4), auto]))
    }

    /// 送れなかったら、写した値が残る（やり直しで2枚目より後の題が空にならない）
    func testFailedSendKeepsTheCopiedFields() async {
        ScriptedProtocol.reset()
        ScriptedProtocol.script = [
            .init(match: "/upload/presigned-url", status: 500, body: #"{"error":"x"}"#),
        ]
        let m = model()
        m.items = [photo(1), photo(2)]
        m.items[0].title = "雲海"
        await m.submit()
        XCTAssertEqual(m.items.count, 2, "送れなかった写真が消えた")
        XCTAssertEqual(m.items.map(\.title), ["雲海", "雲海"], "送れなかった2枚目に題が写っていない")
        XCTAssertNotNil(m.errorMessage)
    }

    // MARK: - 確かめ役の指摘（2026-11-18）

    /// 🔴 1組で書いた題・説明・撮影地は、先頭の写真を外しても消えない（次の写真へ移してから外す）
    func testRemovingTheLeadKeepsTheSharedText() async {
        let m = model()
        m.items = [photo(1), photo(2), photo(3)]
        m.items[0].title = "雲海"
        m.items[0].caption = "朝五時"
        m.items[0].location = "高屋神社"
        let lead = m.items[0].id
        m.remove(lead)
        XCTAssertEqual(m.items.count, 2)
        XCTAssertEqual(m.items[0].title, "雲海", "先頭を外したら1組で書いた題が消えた")
        XCTAssertEqual(m.items[0].caption, "朝五時")
        XCTAssertEqual(m.items[0].location, "高屋神社")
        XCTAssertTrue(m.sharesFields)
    }

    /// 🔴 写す元の写真の位置を、ほかの写真に載せない（位置の切り替えがオフでも載る道があった）
    func testLeadPhotosOwnCoordsAreNeverCopied() async {
        let leadSpot = Photo.Coords(lat: 34.10, lng: 133.60)
        // 写真の近くの撮影スポットを選んだが、下書き・控えから戻してスポットが分からない（座標は元の写真の位置と同じ）
        var lead = photo(1, coords: leadSpot)
        lead.location = "高屋神社"
        lead.pickedCoords = leadSpot
        var other = photo(2, coords: Photo.Coords(lat: 35.0, lng: 135.0))
        other.copySharedFields(from: lead)
        XCTAssertNil(other.pickedCoords, "1枚目の写真の位置を2枚目に写した")
        XCTAssertNil(other.coordsToSend(spots: [], attachesPhotoLocation: false), "位置の切り替えがオフでも1枚目の位置が載る")
        // 撮影スポットを選んでいたら、写す先の写真ごとに作り直す（遠い写真はスポットの位置・写真の位置は使わない）
        lead.pickedSpot = UploadSpotTarget(spotId: "sp_takaya", name: "高屋神社", coords: Photo.Coords(lat: 34.15, lng: 133.68))
        var far = photo(3, coords: Photo.Coords(lat: 35.0, lng: 135.0))
        far.copySharedFields(from: lead)
        XCTAssertEqual(far.pickedCoords, Photo.Coords(lat: 34.15, lng: 133.68), "遠い写真にスポットの位置が付かない")
        XCTAssertNotEqual(far.pickedCoords, leadSpot)
        // 地名の候補を選んだ（写真の位置ではない）ならそのまま写す
        var named = photo(4, coords: leadSpot)
        named.pickedCoords = Photo.Coords(lat: 33.0, lng: 131.0)
        var target = photo(5)
        target.copySharedFields(from: named)
        XCTAssertEqual(target.pickedCoords, Photo.Coords(lat: 33.0, lng: 131.0))
    }

    /// 旅の写真からの投稿は1組に畳まない（何か所も回った旅が全部1枚目の撮影地になる）
    func testTripImportKeepsPerPhotoFields() async {
        let m = model()
        m.applyInitialPhotos([photo(1).prepared, photo(2).prepared], startPrivate: true)
        XCTAssertTrue(m.fromTripImport)
        XCTAssertEqual(m.items.count, 2)
        XCTAssertFalse(m.sharesFields, "旅の写真からの投稿を1組に畳んだ")
    }

    // MARK: - 画面

    func testScreenShowsOneSetAndFoldedLink() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let view = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Upload/UploadView.swift"),
                              encoding: .utf8)
        XCTAssertTrue(view.contains("detailFields(model.sharesFields ? Array(model.items.prefix(1)) : model.items)"),
                      "1つの投稿でも写真の数だけ欄を出している")
        XCTAssertTrue(view.contains("Text(L(\"写真ごとに書く\", \"Write for each photo\"))"))
        XCTAssertTrue(view.contains("Button { model.openPerPhotoFields() } label: {"))
        // 切り替えは残す（左が別々、右が1つの投稿）
        let choice = try XCTUnwrap(view.range(of: "private var groupChoice: some View {"))
        let body = String(view[choice.upperBound...].prefix(900))
        let separate = try XCTUnwrap(body.range(of: "L(\"それぞれ別の投稿\""))
        let one = try XCTUnwrap(body.range(of: "L(\"1つの投稿\""))
        XCTAssertLessThan(separate.lowerBound, one.lowerBound, "模型の並び（左が別々）でない")
        // プレビューも送るときと同じ値を見せる
        let preview = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Upload/PostPreviewSheet.swift"),
                                 encoding: .utf8)
        XCTAssertTrue(preview.contains("let fields = shares ? (lead ?? item) : item"))
    }
}
