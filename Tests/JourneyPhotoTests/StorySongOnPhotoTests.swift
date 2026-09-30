import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 曲名が2か所に出ない（2026-09-30・owner「曲選択したときに表示されるのが2か所あってやだ」）。
///
/// 作る画面は曲の札を写真に置いて焼き込むので、見る画面の左下の ♪ の行と2度出ていた。
/// 札を焼き込んだ1本は `songOnPhoto` を立てて送り、見る画面はその行を出さない。
/// **曲は鳴らす**（`songLine` は鳴らす判定にも使うので触らない）
final class StorySongOnPhotoTests: XCTestCase {

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
    private let song = Photo.Song(title: "海", artist: "誰か", artwork: nil,
                                  previewUrl: "https://audio-ssl.itunes.apple.com/a.m4a", trackUrl: nil)

    private func sentBody() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(StubProtocol.lastBody)) as? [String: Any])
    }

    private func story(_ extra: String) throws -> Story {
        let json = #"{"id":"s1","src":"https://cdn.example/a.jpg","userId":"u1","song":{"title":"海","artist":"誰か","previewUrl":"https://audio-ssl.itunes.apple.com/a.m4a"}"# + extra + "}"
        return try JSONDecoder().decode(Story.self, from: Data(json.utf8))
    }

    func testSentOnlyWhenTheStickerIsOnThePhoto() async throws {
        StubProtocol.respond(status: 201, body: #"{"success":true}"#)
        _ = try await service().createRecord(media, caption: nil, location: nil, coords: nil,
                                             song: song, songOnPhoto: true)
        XCTAssertEqual(try sentBody()["songOnPhoto"] as? Bool, true)

        StubProtocol.respond(status: 201, body: #"{"success":true}"#)
        _ = try await service().createRecord(media, caption: nil, location: nil, coords: nil, song: song)
        XCTAssertNil(try sentBody()["songOnPhoto"], "札を置いていないのに立てている")
    }

    /// 曲が無ければ立てない（札だけ残った・曲を外した）
    func testNotSentWithoutASong() async throws {
        StubProtocol.respond(status: 201, body: #"{"success":true}"#)
        _ = try await service().createRecord(media, caption: nil, location: nil, coords: nil, songOnPhoto: true)
        XCTAssertNil(try sentBody()["songOnPhoto"])
    }

    /// 見る画面: 札を焼き込んだ1本は ♪ の行を出さない。**鳴らす判定（`songLine`）は残す**
    func testViewerHidesTheLineButKeepsTheSong() throws {
        let burned = try story(#","songOnPhoto":true"#)
        XCTAssertNil(burned.songLineShown)
        XCTAssertNotNil(burned.songLine, "曲まで消している（鳴らなくなる）")
        let plain = try story("")
        XCTAssertEqual(plain.songLineShown, plain.songLine)
        XCTAssertNotNil(plain.songLineShown, "Web で出した曲（札なし）の行まで消している")
    }

    /// 形の崩れた印で一覧ごと落とさない（読めなければ無いものとして読む）
    func testMalformedFlagIsIgnored() throws {
        let odd = try story(#","songOnPhoto":"yes""#)
        XCTAssertNotNil(odd.songLineShown)
    }

    /// 表示秒数の選択肢は 5・10・15（owner の判断）。**受けて読む幅（3〜15）の中に収まる**
    func testDurationChoices() {
        XCTAssertEqual(StoryService.durationChoices, [5, 10, 15])
        XCTAssertTrue(StoryService.durationChoices.allSatisfy(StoryService.durationRange.contains))
        XCTAssertTrue(StoryService.durationChoices.contains(StoryService.defaultDurationSec))
    }

    // MARK: - 686566d のレビュー

    /// いまの曲の札が文字どおり置いてあるときだけ立つ（空の札・前の曲の札・自分で打った「曲」の札では立たない）
    func testIsOnPhotoMatchesTheCurrentSongSticker() throws {
        let sticker = try XCTUnwrap(SongSticker.make(for: song))
        XCTAssertTrue(SongSticker.isOnPhoto([sticker], song: song))
        var emptied = sticker; emptied.text = ""
        XCTAssertFalse(SongSticker.isOnPhoto([emptied], song: song), "焼き込まれない空の札で立てている")
        var free = sticker; free.text = "旅のBGM"
        XCTAssertFalse(SongSticker.isOnPhoto([free], song: song), "曲名でない札で立てている")
        let other = Photo.Song(title: "山", artist: nil, artwork: nil,
                               previewUrl: "https://audio-ssl.itunes.apple.com/b.m4a", trackUrl: nil)
        XCTAssertFalse(SongSticker.isOnPhoto([sticker], song: other), "前の曲の札で立てている")
        XCTAssertFalse(SongSticker.isOnPhoto([sticker], song: nil))
    }

    /// 前に選べた秒数の下書きは、いま選べる近い秒数へ寄せる
    func testNearestDurationChoice() {
        XCTAssertEqual(StoryService.nearestDurationChoice(3), 5)
        XCTAssertEqual(StoryService.nearestDurationChoice(7), 5)
        XCTAssertEqual(StoryService.nearestDurationChoice(8), 10)
        XCTAssertEqual(StoryService.nearestDurationChoice(15), 15)
        XCTAssertEqual(StoryService.nearestDurationChoice(10), 10)
    }
}

