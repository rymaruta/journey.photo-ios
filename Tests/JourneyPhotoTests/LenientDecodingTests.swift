import XCTest
@testable import JourneyPhoto

/// **1行の型違いで一覧が丸ごと消えないこと。**
///
/// 公開の写真一覧は30枚を1本の JSON で受け取る。まとめて復号すると、
/// 古い形の行が1つ混ざっただけで**ギャラリーが空になる**。
/// Web 側も「おかしい項目だけを落とし、読める項目は出す」に倒している
/// （`lib/utils/apiRows.ts` の `usablePhotoRows`）。
final class LenientDecodingTests: XCTestCase {

    private func decode(_ json: String) throws -> LenientPhotoList {
        try JSONDecoder.api.decode(LenientPhotoList.self, from: Data(json.utf8))
    }

    func testDropsOnlyTheBadRow() throws {
        let list = try decode("""
        [
          {"id":"good1","src":"https://x/1.jpg"},
          {"id":"bad","src":12345},
          {"id":"good2","src":"https://x/2.jpg"}
        ]
        """)
        XCTAssertEqual(list.photos.map(\.id), ["good1", "good2"])
        XCTAssertEqual(list.dropped, 1)
    }

    /// `src` が無い行も落とす（画像を出しようがない）。
    func testDropsRowWithoutSource() throws {
        let list = try decode(#"[{"id":"a"},{"id":"b","src":"https://x/b.jpg"}]"#)
        XCTAssertEqual(list.photos.map(\.id), ["b"])
        XCTAssertEqual(list.dropped, 1)
    }

    /// **落とすのは1行だけ。** 失敗時に添字が進んだかどうかを実装に
    /// 委ねる書き方だと、隣の良い行まで巻き添えになりうる。
    func testAdjacentGoodRowSurvivesTwoBadRows() throws {
        let list = try decode("""
        [
          {"id":"bad1","src":1},
          {"id":"bad2","src":2},
          {"id":"good","src":"https://x/g.jpg"}
        ]
        """)
        XCTAssertEqual(list.photos.map(\.id), ["good"])
        XCTAssertEqual(list.dropped, 2)
    }

    /// 説明が `{ ja: "一行" }`（配列でない）形でも読める。
    /// 保存する入口が3つあり、段落に割っているのは1つだけだった。
    func testDescriptionAcceptsPlainStringPerLocale() throws {
        let list = try decode(#"[{"id":"a","src":"https://x/a.jpg","description":{"ja":"一行目\n二行目"}}]"#)
        XCTAssertEqual(list.dropped, 0)
        XCTAssertEqual(list.photos.first?.paragraphs, ["一行目", "二行目"])
    }

    // MARK: - 撮影スポットの索引（同じ判断）

    private func decodeSpots(_ json: String) throws -> LenientOfficialSpotList {
        try JSONDecoder.api.decode(LenientOfficialSpotList.self, from: Data(json.utf8))
    }

    /// 索引も1件の型違いで丸ごと消さない。**知らない項目は読み飛ばす**
    func testSpotIndexDropsOnlyTheBadItem() throws {
        let list = try decodeSpots("""
        [
          {"spotId":"sp_1","slug":"a","name":"A","stage":"review","future":"unknown"},
          {"spotId":"sp_2","slug":"b","name":"B","stage":"review","coords":{"lat":"x","lng":1}},
          {"spotId":"sp_3","slug":"c","name":"C","stage":"published"}
        ]
        """)
        XCTAssertEqual(list.spots.map(\.slug), ["a", "c"])
        XCTAssertEqual(list.dropped, 1)
    }

    /// **鍵になる3つが無い行は落とす。** `slug` が空だと「行きたい」の鍵が
    /// `SPOT-` だけになり、名前が空だと札に何も出ない
    func testSpotIndexRequiresIdSlugAndName() throws {
        let list = try decodeSpots("""
        [
          {"spotId":"sp_1","slug":"","name":"A","stage":"review"},
          {"spotId":"sp_2","slug":"b","name":" ","stage":"review"},
          {"slug":"c","name":"C","stage":"review"},
          {"spotId":"sp_4","slug":"d","name":"D","stage":"review"}
        ]
        """)
        XCTAssertEqual(list.spots.map(\.slug), ["d"])
        XCTAssertEqual(list.dropped, 3)
    }

    /// `stage` が知らない値なら**下書きとして扱う**（確かめたと言えるのは published だけ）
    func testUnknownStageIsTreatedAsDraft() throws {
        let list = try decodeSpots(#"[{"spotId":"sp_1","slug":"a","name":"A","stage":"whatever"}]"#)
        XCTAssertEqual(list.spots.first?.isDraft, true)
    }
}

/// ストーリーの返信。
///
/// 投稿者が選んだ表示秒数（`stories.ts` が 3〜15 で保存）。
/// **復号していない頃は、投稿画面で選んだ秒数が閲覧で一度も効いていなかった。**
final class StoryDurationDecodingTests: XCTestCase {

    private func story(_ json: String) throws -> Story {
        try JSONDecoder.api.decode(Story.self, from: Data(json.utf8))
    }

    func testDurationSecIsDecoded() throws {
        let s = try story(#"{"id":"story-1","src":"https://x.test/1.jpg","durationSec":7}"#)
        XCTAssertEqual(s.durationSec, 7)
    }

    /// 既定の5はサーバーが保存しないので、無ければ `nil`（画面側が 5 にする）。
    func testMissingDurationIsNil() throws {
        let s = try story(#"{"id":"story-1","src":"https://x.test/1.jpg"}"#)
        XCTAssertNil(s.durationSec)
    }

    /// 付けた曲を読む（閲覧画面の「曲名 · アーティスト」の行）
    func testSongIsDecoded() throws {
        let s = try story(#"{"id":"story-1","src":"https://x.test/1.jpg","song":{"title":"夜に駆ける","artist":"YOASOBI","previewUrl":"https://audio.test/p.m4a"}}"#)
        XCTAssertEqual(s.songLine, "夜に駆ける · YOASOBI")
    }

    /// アーティストが無ければ曲名だけ
    func testSongWithoutArtist() throws {
        let s = try story(#"{"id":"story-1","src":"https://x.test/1.jpg","song":{"title":"雨","previewUrl":"https://audio.test/p.m4a"}}"#)
        XCTAssertEqual(s.songLine, "雨")
    }

    /// 🔴 **曲の形が崩れていても、ストーリーは読める。** 一覧は配列1本で
    /// 復号するので、ここで落ちると全員のストーリーが消える
    func testBrokenSongDoesNotDropTheStory() throws {
        let s = try story(#"{"id":"story-1","src":"https://x.test/1.jpg","durationSec":7,"song":{"artist":"題が無い"}}"#)
        XCTAssertNil(s.song)
        XCTAssertEqual(s.durationSec, 7)
    }
}

/// **定型の反応は `text` ではなく `emoji` に入って返る**
/// （`api-user/src/storyReplies.ts` の `REACTIONS`）。見ていないと、
/// 返信の一覧に**名前だけの空行**が並ぶ。
final class StoryReplyDecodingTests: XCTestCase {

    private func reply(_ json: String) throws -> StoryReply {
        try JSONDecoder.api.decode(StoryReply.self, from: Data(json.utf8))
    }

    func testEmojiReactionIsShown() throws {
        let r = try reply(#"{"id":"1","uid":"u","name":"だれか","emoji":"❤️","t":"2026-09-20T00:00:00Z"}"#)
        XCTAssertEqual(r.body, "❤️")
    }

    func testTextReplyIsShown() throws {
        let r = try reply(#"{"id":"1","uid":"u","text":"いいね","t":"2026-09-20T00:00:00Z"}"#)
        XCTAssertEqual(r.body, "いいね")
    }

    /// 両方あれば本文を出す（サーバーは片方しか入れないが、決めておく）。
    func testTextWinsWhenBothArePresent() throws {
        let r = try reply(#"{"id":"1","text":"いいね","emoji":"❤️"}"#)
        XCTAssertEqual(r.body, "いいね")
    }

    /// `id` を持たない回がある——相手と時刻で作る（無いと `ForEach` が壊れる）。
    func testMissingIdFallsBackToSenderAndTime() throws {
        let r = try reply(#"{"uid":"u1","t":"2026-09-20T00:00:00Z","text":"やあ"}"#)
        XCTAssertEqual(r.id, "u1|2026-09-20T00:00:00Z")
    }
}
