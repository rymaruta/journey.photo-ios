import XCTest
@testable import JourneyPhoto

/// 返信を受けない投稿（Web の「返信を許可」を切ったもの）。
///
/// サーバーは `allowReplies: false` のときだけ入れて返し、返信（♡ も）を 403 で断る
/// （`stories.ts` / `storyReplies.ts`）。読んでいなかった頃は返信欄と ♡ が出ていた
final class StoryAllowRepliesTests: XCTestCase {

    private func decode(_ json: String) throws -> Story {
        try JSONDecoder.api.decode(Story.self, from: Data(json.utf8))
    }

    func testClosedStoryDoesNotAcceptReplies() throws {
        let story = try decode(#"{"id":"s1","src":"https://x/s1.jpg","allowReplies":false}"#)
        XCTAssertFalse(story.acceptsReplies)
    }

    /// 既定（受ける）は保存されないので、**無いときは受ける**
    func testMissingMeansAccepts() throws {
        XCTAssertTrue(try decode(#"{"id":"s1","src":"https://x/s1.jpg"}"#).acceptsReplies)
    }

    /// 形が崩れていても一覧ごと落とさない
    func testMalformedValueDoesNotBreakTheList() throws {
        let list = try JSONDecoder.api.decode([Story].self, from: Data(
            #"[{"id":"s1","src":"https://x/s1.jpg","allowReplies":"no"},{"id":"s2","src":"https://x/s2.jpg"}]"#.utf8))
        XCTAssertEqual(list.map(\.id), ["s1", "s2"])
        XCTAssertTrue(list[0].acceptsReplies)
    }
    /// 🔴 **Web で選んだ曲の「好きな部分」から鳴らす。** `song.startSec` を読まずにいたので、
    /// アプリで見る人にはいつも曲の頭が流れていた
    func testSongStartsWhereThePosterChose() throws {
        func story(_ start: String) throws -> Story {
            try decode(#"{"id":"s1","src":"https://x/s1.jpg","song":{"title":"t","previewUrl":"https://audio-ssl.itunes.apple.com/a.m4a""# + start + "}}")
        }
        XCTAssertEqual(StoryPlayback.songStart(for: try story(#","startSec":20"#)), 20)
        XCTAssertEqual(StoryPlayback.songStart(for: try story(#","startSec":45"#)), 29, "サーバーと同じく29秒まで")
        XCTAssertEqual(StoryPlayback.songStart(for: try story("")), 0, "選んでいなければ頭から")
        // 読めない値で曲ごと落とさない
        let odd = try story(#","startSec":"abc""#)
        XCTAssertNotNil(odd.song)
        XCTAssertEqual(StoryPlayback.songStart(for: odd), 0)
    }
}

/// 送り直しで二重に出さないための照らし合わせ（`StoryService.isSameMedia`）。
/// サーバーは `src` を配信元の URL に作り直すので、**道（＝鍵）で比べる**
final class StorySameMediaTests: XCTestCase {

    private func story(src: String, userId: String = "me") throws -> Story {
        try JSONDecoder.api.decode(Story.self, from: Data(
            #"{"id":"s1","src":"\#(src)","userId":"\#(userId)"}"#.utf8))
    }

    private let media = StoryService.UploadedMedia(
        key: "uploads/me/abc.jpg", publicUrl: "https://bucket.s3.amazonaws.com/uploads/me/abc.jpg")

    func testMatchesTheSameKeyOnTheCDN() throws {
        XCTAssertTrue(StoryService.isSameMedia(try story(src: "https://cdn.example/uploads/me/abc.jpg"),
                                               media, ownerId: "me"))
    }

    func testDoesNotMatchAnotherImageOrAnotherPerson() throws {
        XCTAssertFalse(StoryService.isSameMedia(try story(src: "https://cdn.example/uploads/me/zzz.jpg"),
                                                media, ownerId: "me"))
        XCTAssertFalse(StoryService.isSameMedia(try story(src: "https://cdn.example/uploads/me/abc.jpg",
                                                          userId: "other"),
                                                media, ownerId: "me"))
    }

}
