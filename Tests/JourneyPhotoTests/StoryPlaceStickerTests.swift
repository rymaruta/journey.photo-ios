import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 札 #499（owner 2026-11-08・TestFlight 1.1.72「場所などを入力した後、自由に場所を動かせない」）。
///
/// 原因: 場所ツールで決めた撮影地は固定の札（`photoChip`）で、動かす操作を持たなかった
/// （曲の札・文字の札は `StoryCanvas` の操作で動く）。直し: 撮影地を `.place` の札にして写真に焼き込み、
/// 送るとき `locationOnPhoto` を立てる。`location`・`coords` は今までどおり送る（スポットへのひも付け）。
final class StoryPlaceStickerTests: XCTestCase {

    // MARK: - 札

    func testMakeBuildsAMovablePlaceOverlay() throws {
        let sticker = try XCTUnwrap(PlaceSticker.make(for: " 高屋神社 "))
        XCTAssertEqual(sticker.kind, .place)
        XCTAssertEqual(sticker.text, "高屋神社", "前後の空白を札に入れている")
        XCTAssertNil(PlaceSticker.make(for: "  "), "空の撮影地で札を作っている")
    }

    /// 曲の札と同じ高さ（0.6）に重ねて置かない
    func testMakeAvoidsAnOverlayAtTheSameHeight() throws {
        let song = TextOverlay(text: "♪", x: 0.5, y: 0.6, kind: .song)
        let sticker = try XCTUnwrap(PlaceSticker.make(for: "高屋神社", avoiding: [song]))
        XCTAssertGreaterThanOrEqual(abs(sticker.y - 0.6), PlaceSticker.rowGap)
        XCTAssertEqual(try XCTUnwrap(PlaceSticker.make(for: "高屋神社")).y, 0.6, accuracy: 0.001)
    }

    /// 札は文字で見分ける。自分で打った別の「撮影地」の札・文字の札・文字を消した札では立たない
    func testIsOnPhotoMatchesTheCurrentLocationOnly() throws {
        let sticker = try XCTUnwrap(PlaceSticker.make(for: "高屋神社"))
        XCTAssertTrue(PlaceSticker.isOnPhoto([sticker], location: "高屋神社"))
        XCTAssertTrue(PlaceSticker.isOnPhoto([sticker], location: " 高屋神社 "))
        var other = sticker; other.text = "別の場所"
        XCTAssertFalse(PlaceSticker.isOnPhoto([other], location: "高屋神社"))
        var emptied = sticker; emptied.text = ""
        XCTAssertFalse(PlaceSticker.isOnPhoto([emptied], location: ""), "空の撮影地で立てている")
        let asText = TextOverlay(text: "高屋神社", kind: .text)
        XCTAssertFalse(PlaceSticker.isOnPhoto([asText], location: "高屋神社"), "文字の札で立てている")
        XCTAssertFalse(PlaceSticker.isOnPhoto([], location: "高屋神社"))
    }

    /// 撮影地を直すと札の文字だけ替わり、動かした位置は残る。外すと札も消える
    func testRetextKeepsThePositionAndRemovesOnClear() throws {
        var sticker = try XCTUnwrap(PlaceSticker.make(for: "高屋神社"))
        sticker.x = 0.2; sticker.y = 0.9
        let edited = PlaceSticker.retext([sticker], from: "高屋神社", to: "観音寺")
        XCTAssertTrue(edited.found)
        XCTAssertEqual(edited.overlays.first?.text, "観音寺")
        XCTAssertEqual(edited.overlays.first?.x ?? 0, 0.2, accuracy: 0.001, "直したら動かした位置が戻った")
        XCTAssertEqual(edited.overlays.first?.y ?? 0, 0.9, accuracy: 0.001)

        let cleared = PlaceSticker.retext([sticker], from: "高屋神社", to: "")
        XCTAssertTrue(cleared.found)
        XCTAssertTrue(cleared.overlays.isEmpty, "外したのに札が残っている")

        XCTAssertFalse(PlaceSticker.retext([], from: "高屋神社", to: "観音寺").found, "札が無いのに見つけたことにしている")
        XCTAssertFalse(PlaceSticker.retext([sticker], from: "", to: "観音寺").found)
    }

    /// 付けた札を消したら撮影地も外す。別の写真に残っていれば外さない
    func testShouldDetach() throws {
        let sticker = try XCTUnwrap(PlaceSticker.make(for: "高屋神社"))
        XCTAssertTrue(PlaceSticker.shouldDetach(removedSticker: true, remaining: [[], []], location: "高屋神社"))
        XCTAssertFalse(PlaceSticker.shouldDetach(removedSticker: true, remaining: [[], [sticker]], location: "高屋神社"))
        XCTAssertFalse(PlaceSticker.shouldDetach(removedSticker: false, remaining: [[]], location: "高屋神社"))
        XCTAssertFalse(PlaceSticker.shouldDetach(removedSticker: true, remaining: [[]], location: ""))
    }

    /// 札は他の札と同じ動かし方で動く
    func testStickerMovesLikeAnyOverlay() throws {
        let sticker = try XCTUnwrap(PlaceSticker.make(for: "高屋神社"))
        let moved = sticker.moved(by: CGSize(width: 0, height: -90), in: CGSize(width: 300, height: 400))
        XCTAssertLessThan(moved.y, sticker.y - 0.2, "札が動かない")
    }

    // MARK: - 送る・読む

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
        StubProtocol.reset()
    }

    override func tearDown() {
        StubProtocol.reset()
        super.tearDown()
    }

    private func service() -> StoryService {
        StoryService(api: APIClient(baseURL: URL(string: "https://api.example.test")!,
                                    tokenProvider: StubTokenProvider(token: "t"), session: session))
    }

    private let media = StoryService.UploadedMedia(
        key: "uploads/me/abc.jpg", publicUrl: "https://bucket.example/uploads/me/abc.jpg", uploadedAt: Date())

    private func sentBody() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(StubProtocol.lastBody)) as? [String: Any])
    }

    /// 撮影地の札を置いたときだけ立てる。`location`・`coords` は札があっても送る
    func testLocationOnPhotoIsSentOnlyWithAPlaceAndASticker() async throws {
        StubProtocol.respond(status: 201, body: #"{"success":true}"#)
        _ = try await service().createRecord(media, caption: nil, location: "高屋神社",
                                             coords: Photo.Coords(lat: 34.1, lng: 133.6), locationOnPhoto: true)
        var body = try sentBody()
        XCTAssertEqual(body["locationOnPhoto"] as? Bool, true)
        XCTAssertEqual(body["location"] as? String, "高屋神社", "ひも付けの撮影地を送っていない")
        XCTAssertNotNil(body["coords"], "ひも付けの座標を送っていない")

        StubProtocol.respond(status: 201, body: #"{"success":true}"#)
        _ = try await service().createRecord(media, caption: nil, location: "高屋神社", coords: nil)
        body = try sentBody()
        XCTAssertNil(body["locationOnPhoto"], "札を置いていないのに立てている")

        StubProtocol.respond(status: 201, body: #"{"success":true}"#)
        _ = try await service().createRecord(media, caption: nil, location: nil, coords: nil, locationOnPhoto: true)
        body = try sentBody()
        XCTAssertNil(body["locationOnPhoto"], "撮影地が無いのに立てている")
    }

    private func story(_ extra: String) throws -> Story {
        let json = #"{"id":"s1","src":"https://cdn.example/a.jpg","userId":"u1","location":"高屋神社""# + extra + "}"
        return try JSONDecoder().decode(Story.self, from: Data(json.utf8))
    }

    /// 見る画面: 印のある1本は固定の撮影地の札を出さない。旧版のストーリー・形の崩れた印は今までどおり出す
    func testViewerHidesTheFixedCardOnlyWhenBurned() throws {
        let burned = try story(#","locationOnPhoto":true"#)
        XCTAssertEqual(burned.locationOnPhoto, true)
        XCTAssertFalse(burned.showsLocationCard, "札を焼き込んだのに固定の札も出している（二重）")
        XCTAssertEqual(burned.location, "高屋神社", "ひも付けの撮影地まで消している")
        XCTAssertTrue(try story("").showsLocationCard, "印の無い（旧版・Web の）ストーリーの撮影地を消している")
        XCTAssertTrue(try story(#","locationOnPhoto":"yes""#).showsLocationCard, "形の崩れた印で消している")
        XCTAssertTrue(try story(#","locationOnPhoto":false"#).showsLocationCard)
    }
}

/// 札 #499 の直し: 焼き込み済みの1本の撮影スポットへの導線と、写真ごとの判定
final class StoryPlaceLinkTests: XCTestCase {
    func testEntryOnlyWhenBakedAndLinked() {
        XCTAssertEqual(StoryPlaceLink.entry(showsCard: false, location: "高屋神社", spotLinked: true), "高屋神社")
        XCTAssertNil(StoryPlaceLink.entry(showsCard: false, location: "高屋神社", spotLinked: false), "結べないのに導線を出している")
        XCTAssertNil(StoryPlaceLink.entry(showsCard: true, location: "高屋神社", spotLinked: true), "固定の札と二重に導線を出している")
        XCTAssertNil(StoryPlaceLink.entry(showsCard: false, location: nil, spotLinked: true))
        XCTAssertNil(StoryPlaceLink.entry(showsCard: false, location: "", spotLinked: true))
    }

    private func repo(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 作る画面・送信・見る画面が同じ規則（写真ごと）。作る画面は見ている1枚で判定する
    func testComposerDecidesPerShot() throws {
        let composer = try repo("Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(composer.contains("PlaceSticker.isOnPhoto(shots[current].overlays, location: place.location)"))
        XCTAssertFalse(composer.contains("private var placeOnPhoto: Bool {\n        PlaceSticker.isOnAnyPhoto"),
                       "どれかの写真に札があれば全部の写真で固定の札を消している")
        XCTAssertTrue(composer.contains("locationOnPhoto: PlaceSticker.isOnPhoto(shot.overlays, location: placeText)"))
    }

    /// 禁止語（PlaceTermWordingTests）を使わない
    func testEntryWordingAvoidsBannedTerms() throws {
        let viewer = try repo("Sources/JourneyPhoto/Features/Stories/StoryViewerView.swift")
        XCTAssertTrue(viewer.contains("撮影スポットを見る"))
        for banned in ["注目スポット", "撮影地ガイド", "ガイドを見る"] {
            XCTAssertFalse(viewer.contains("L(\"\(banned)"), banned)
        }
    }
}
