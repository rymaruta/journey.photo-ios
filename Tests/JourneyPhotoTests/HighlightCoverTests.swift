import XCTest
@testable import JourneyPhoto

/// ハイライトの表紙の形（`api-user/src/highlights.ts` の `resolveCover`）と、
/// プロフィールの BGM の差し替え（バグ探し 2026-09-27）。
final class HighlightCoverTests: XCTestCase {

    private func decode(_ json: String) throws -> [Highlight] {
        struct List: Decodable { let highlights: [Highlight] }
        return try JSONDecoder().decode(List.self, from: Data(json.utf8)).highlights
    }

    /// 🔴 **表紙は `{src, mediaType}`。** 文字列として読んでいたので、一覧ごと読めなかった
    func testCoverObjectFromTheServerIsRead() throws {
        let list = try decode(#"{"highlights":[{"id":"h1","title":"パリ","count":2,"cover":{"src":"https://x.test/a.jpg","mediaType":"image/jpeg"}},{"id":"h2","title":"","count":0,"cover":null}]}"#)
        XCTAssertEqual(list.map(\.id), ["h1", "h2"])
        XCTAssertEqual(list[0].coverURL?.absoluteString, "https://x.test/a.jpg")
        XCTAssertNil(list[1].coverURL)
    }

    /// 古い形（文字列）も読む
    func testLegacyStringCoverIsRead() throws {
        let list = try decode(#"{"highlights":[{"id":"h1","title":"パリ","cover":"https://x.test/a.jpg"}]}"#)
        XCTAssertEqual(list[0].coverURL?.absoluteString, "https://x.test/a.jpg")
    }

    /// 動画の表紙は絵として読まない（地の円にする）
    func testVideoCoverIsNotDrawnAsAnImage() throws {
        let list = try decode(#"{"highlights":[{"id":"h1","title":"パリ","cover":{"src":"https://x.test/a.mp4","mediaType":"video"}}]}"#)
        XCTAssertNil(list[0].coverURL)
        XCTAssertEqual(list[0].cover?.isVideo, true, "サーバーが保存する値は \"video\"（stories.ts）")
    }

    private func song(_ url: String) -> Photo.Song {
        Photo.Song(title: url, artist: nil, artwork: nil, previewUrl: url, trackUrl: nil)
    }

    /// 🔴 **「別の曲にする」は先頭を差し替える**（積み上げると5曲の人の最後の1曲が消えた）
    func testPickingAnotherSongReplacesTheFirst() {
        let five = ["a", "b", "c", "d", "e"].map(song)
        let after = ProfileSongs.replacingFirst(five, with: song("z"))
        XCTAssertEqual(after.map(\.previewUrl), ["z", "b", "c", "d", "e"], "曲が積み上がった")
        // 後ろに同じ曲があれば外す
        XCTAssertEqual(ProfileSongs.replacingFirst(five, with: song("c")).map(\.previewUrl), ["c", "b", "d", "e"])
        XCTAssertEqual(ProfileSongs.replacingFirst([], with: song("z")).map(\.previewUrl), ["z"])
    }

    /// 🔴 **選び直しても、いまの表紙が並びに残っていれば変えない。** 選ぶたびに
    /// 先頭へ替えていたので、直すだけで表紙が黙って替わった（外したら先頭）
    func testReselectingKeepsTheCoverWhileItIsStillPicked() {
        XCTAssertEqual(HighlightService.cover(keeping: "b", in: ["a", "b", "c"]), "b")
        XCTAssertEqual(HighlightService.cover(keeping: "b", in: ["a", "c"]), "a", "外したら先頭")
        XCTAssertEqual(HighlightService.cover(keeping: nil, in: ["a", "c"]), "a")
        XCTAssertNil(HighlightService.cover(keeping: "b", in: []))
    }

    /// 🔴 **「最初の1件が表紙」と言わない**——直すときはサーバーの表紙を引き継ぐ
    func testNoteNamesTheActualCover() {
        let note = HighlightService.pickedNote(picked: ["a", "b", "c"], coverId: "b")
        XCTAssertTrue(note.contains("2件目") || note.contains("#2"), note)
        XCTAssertFalse(note.contains("最初の1件") || note.contains("The first one"), note)
        let first = HighlightService.pickedNote(picked: ["a"], coverId: nil)
        XCTAssertTrue(first.contains("1件目") || first.contains("#1"), first)
    }

    /// **表紙の形が崩れていても一覧ごと落とさない**（表紙を伏せるだけ）
    func testBrokenCoverDoesNotDropTheList() throws {
        let list = try decode(#"{"highlights":[{"id":"h1","title":"a","cover":{"src":5}},{"id":"h2","title":"b"}]}"#)
        XCTAssertEqual(list.map(\.id), ["h1", "h2"])
        XCTAssertNil(list[0].cover)
    }
}
