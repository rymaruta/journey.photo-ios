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
}
