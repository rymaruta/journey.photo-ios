import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 投稿画面の「撮影スポット「◯◯」に結ぶ」（2026-10-31・journey.photo-ios#425・Web の `spotUploadAuto.ts`）。
///
/// 🔴 自動の候補は `spotId` に書かない（Web の静的な生成が結ぶ）。書くのは本人が切った写真の
/// `spotAuto: "off"` だけ。**本人が触っていない写真には何も書かない**。撮影スポットの画面から来た
/// 明示の `spotId` は今までどおり
@MainActor
final class UploadSpotAutoTests: XCTestCase {

    override func tearDown() {
        ScriptedProtocol.reset()
        super.tearDown()
    }

    private func model(withIndex: Bool = true) -> UploadViewModel {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedProtocol.self]
        let session = URLSession(configuration: config)
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "t"), session: session)
        let m = UploadViewModel(uploads: UploadService(api: api, session: session), albums: AlbumService(api: api),
                                photos: PhotoService(api: api), discovery: DiscoveryService(api: api))
        m.locationPreference = UploadLocationPreference(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        if withIndex { m.useAutoSpotIndex(Self.index) }
        return m
    }

    /// 蔵王キツネ村（白石市・宮城県）と高屋神社（観音寺市・香川県）
    nonisolated static let index: SpotMatchIndex = {
        let json = """
        {"v":1,"spots":[
          {"i":"sp_fox","d":"蔵王キツネ村","n":"蔵王キツネ村","c":[38.02,140.55],"p":"宮城県"},
          {"i":"sp_takaya","d":"高屋神社 本宮","n":"高屋神社本宮","a":["高屋神社"],"c":[34.15,133.68],"p":"香川県"}
        ]}
        """
        return SpotMatchIndex.decode(Data(json.utf8))!
    }()

    private func shot(_ byte: UInt8, coords: Photo.Coords? = nil) -> ImagePreparer.Prepared {
        ImagePreparer.Prepared(data: Data(repeating: byte, count: 16), fileName: "photo\(byte).jpg",
                               contentType: "image/jpeg", exif: nil, coords: coords, takenOn: nil)
    }

    private func item(_ byte: UInt8, location: String = "", title: String = "") -> PendingPhoto {
        var p = PendingPhoto(prepared: shot(byte))
        p.location = location
        p.title = title
        return p
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

    // MARK: - 切り替えの出し方

    func testRowAppearsWithTheCandidateAndStartsOn() async {
        let m = model()
        let fox = item(1, location: "蔵王キツネ村, 白石市")
        m.items = [fox, item(2, location: "東京")]
        XCTAssertEqual(m.autoSpotRow(for: m.items[0]), .init(spotId: "sp_fox", name: "蔵王キツネ村", on: true))
        XCTAssertNil(m.autoSpotRow(for: m.items[1]), "候補の無い写真に切り替えを出した")
        XCTAssertEqual(SpotUploadAuto.title(spotName: "蔵王キツネ村"), L("撮影スポット「蔵王キツネ村」に結ぶ", "Link to “蔵王キツネ村”"))
    }

    /// 撮影スポットの画面から来て、その `spotId` を送る写真には出さない（帯が受け持つ）
    func testNoRowWhenTheSpotScreenAlreadyLinks() async {
        let m = model()
        m.spot = UploadSpotTarget(spotId: "sp_takaya", name: "高屋神社", coords: nil)
        m.items = [item(1, location: "高屋神社, 観音寺市")]
        XCTAssertNil(m.autoSpotRow(for: m.items[0]))
    }

    /// 索引が読めなければ自動では選ばない（投稿はできる）
    func testNoIndexNoRow() async {
        let bare = model(withIndex: false)
        bare.items = [item(1, location: "蔵王キツネ村")]
        XCTAssertTrue(bare.wantsAutoSpotIndex)
        // 既定の口は読まない（nil）＝索引が読めなかった回
        await bare.loadAutoSpotIndexIfNeeded()
        XCTAssertNil(bare.autoSpotIndex)
        XCTAssertNil(bare.autoSpotRow(for: bare.items[0]))
    }

    /// 読めたら1回だけ（読めなかった回も読み直さない）
    func testIndexIsAskedOnce() async {
        let m = model(withIndex: false)
        let counter = Counter()
        let index = Self.index
        m.fetchSpotMatchIndex = { await counter.bump(); return index }
        await m.loadAutoSpotIndexIfNeeded()
        let before = await counter.value
        XCTAssertEqual(before, 0, "何も入っていないのに読んだ")
        m.items = [item(1, location: "蔵王キツネ村")]
        await m.loadAutoSpotIndexIfNeeded()
        await m.loadAutoSpotIndexIfNeeded()
        let after = await counter.value
        XCTAssertEqual(after, 1)
        XCTAssertEqual(m.autoSpotRow(for: m.items[0])?.spotId, "sp_fox")
    }

    private actor Counter {
        var value = 0
        func bump() { value += 1 }
    }

    /// 撮影地・題・説明のどれかが入ってから読む
    func testWantsIndexOnlyAfterSomethingIsTyped() async {
        let m = model()
        m.items = [item(1)]
        XCTAssertFalse(m.wantsAutoSpotIndex)
        m.items[0].caption = "蔵王で"
        XCTAssertTrue(m.wantsAutoSpotIndex)
    }

    // MARK: - 送る中身

    /// 🔴 触っていない写真は何も書かない（`spotId` も外した印も）——静的な生成が同じ決まりで結ぶ
    func testUntouchedCandidateWritesNothing() async {
        scriptUpload()
        let m = model()
        m.items = [item(1, location: "蔵王キツネ村, 白石市")]
        await m.submit()
        let body = saveBodies().first
        XCTAssertEqual(saveBodies().count, 1, "前提: 保存まで届いた")
        XCTAssertNil(body?["spotId"], "自動の候補を spotId に書いた")
        XCTAssertNil(body?["spotAuto"])
    }

    /// 切った写真だけ `spotAuto: "off"`。入れ直したら何も書かない
    func testTurningOffWritesOffOnlyForThatPhoto() async {
        scriptUpload()
        let m = model()
        m.items = [item(1, location: "蔵王キツネ村"), item(2, title: "蔵王キツネ村で")]
        XCTAssertEqual(m.autoSpotRow(for: m.items[1])?.spotId, "sp_fox", "前提: 2枚目にも候補がある")
        m.setAutoSpot(false, for: m.items[0].id)
        XCTAssertEqual(m.autoSpotRow(for: m.items[0])?.on, false)
        await m.submit()
        let bodies = saveBodies()
        XCTAssertEqual(bodies.count, 2)
        XCTAssertEqual(bodies[0]["spotAuto"] as? String, "off")
        XCTAssertNil(bodies[1]["spotAuto"], "本人が見ていない（触っていない）写真に外した印を書いた")
        XCTAssertNil(bodies[0]["spotId"])
        XCTAssertNil(bodies[1]["spotId"])
    }

    func testTurningBackOnWritesNothing() async {
        scriptUpload()
        let m = model()
        m.items = [item(1, location: "蔵王キツネ村")]
        m.setAutoSpot(false, for: m.items[0].id)
        m.setAutoSpot(true, for: m.items[0].id)
        await m.submit()
        XCTAssertNil(saveBodies().first?["spotAuto"])
    }

    /// 撮影スポットの画面から来た明示の `spotId` は今までどおり（外した印は書かない）
    func testExplicitSpotIdFromTheSpotScreenStays() async {
        scriptUpload()
        let m = model()
        m.spot = UploadSpotTarget(spotId: "sp_takaya", name: "高屋神社", coords: nil)
        m.items = [item(1, location: "高屋神社, 観音寺市")]
        await m.submit()
        XCTAssertEqual(saveBodies().first?["spotId"] as? String, "sp_takaya")
        XCTAssertNil(saveBodies().first?["spotAuto"])
    }

    /// 帯の「外す」は明示の操作: 帯が受け持っていた写真で、候補が同じ撮影スポットなら外した印。
    /// 帯の付いていなかった写真（撮影地から名前を消していた）には書かない
    func testRemovingTheSpotBannerTurnsOffThePhotosItCovered() async {
        scriptUpload()
        let m = model()
        m.spot = UploadSpotTarget(spotId: "sp_takaya", name: "高屋神社", coords: nil)
        m.items = [item(1, location: "高屋神社, 観音寺市"), item(2, location: "観音寺市", title: "高屋神社本宮へ")]
        m.removeSpot()
        XCTAssertEqual(m.autoSpotRow(for: m.items[0])?.on, false, "外した帯の撮影スポットを入りで出した")
        XCTAssertEqual(m.autoSpotRow(for: m.items[1])?.on, true, "帯の付いていなかった写真まで切った")
        await m.submit()
        let bodies = saveBodies()
        XCTAssertEqual(bodies.count, 2)
        XCTAssertEqual(bodies[0]["spotAuto"] as? String, "off")
        XCTAssertNil(bodies[0]["spotId"])
        XCTAssertNil(bodies[1]["spotAuto"])
    }

    /// 切り・外した印の決まり（値）
    func testOffForRules() async {
        XCTAssertEqual(SpotUploadAuto.offFor(choice: false, dismissedSpotId: nil, candidate: "a"), true)
        XCTAssertEqual(SpotUploadAuto.offFor(choice: true, dismissedSpotId: "a", candidate: "a"), false, "本人の切り替えが先")
        XCTAssertEqual(SpotUploadAuto.offFor(choice: nil, dismissedSpotId: "a", candidate: "a"), true)
        XCTAssertNil(SpotUploadAuto.offFor(choice: nil, dismissedSpotId: "a", candidate: "b"))
        XCTAssertNil(SpotUploadAuto.offFor(choice: nil, dismissedSpotId: nil, candidate: "a"))
        XCTAssertNil(SpotUploadAuto.spotAutoToSend(explicitSpotId: "sp_x", candidate: "a", off: true))
        XCTAssertNil(SpotUploadAuto.spotAutoToSend(explicitSpotId: nil, candidate: nil, off: true))
        XCTAssertEqual(SpotUploadAuto.spotAutoToSend(explicitSpotId: nil, candidate: "a", off: true), "off")
    }
}
