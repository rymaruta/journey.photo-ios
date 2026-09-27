import XCTest
@testable import JourneyPhoto

/// 🔴 読み込みの途中で書いた・消したコメントを、後から届いた一覧で失わない。
final class CommentMergeTests: XCTestCase {

    private func comment(_ id: String) throws -> PhotoComment {
        try JSONDecoder.api.decode(PhotoComment.self, from: Data(
            #"{"id":"\#(id)","uid":"u","name":"n","text":"t"}"#.utf8))
    }

    /// 投稿の前に読んだ一覧が後から届いても、書いたコメントを残す
    /// （既にある他の人のコメントも出す）
    func testPostedDuringLoadIsKept() throws {
        let merged = CommentMerge.merge(loaded: [try comment("old")], count: 1,
                                        posted: [try comment("mine")], deleted: [])
        XCTAssertEqual(merged.items.map(\.id), ["mine", "old"])
        XCTAssertEqual(merged.count, 2)
    }

    /// 一覧に既に載っていれば二重にしない
    func testPostedAlreadyInListIsNotDuplicated() throws {
        let merged = CommentMerge.merge(loaded: [try comment("mine"), try comment("old")], count: 2,
                                        posted: [try comment("mine")], deleted: [])
        XCTAssertEqual(merged.items.map(\.id), ["mine", "old"])
        XCTAssertEqual(merged.count, 2)
    }

    /// 消したコメントは戻さない
    func testDeletedDuringLoadStaysGone() throws {
        let merged = CommentMerge.merge(loaded: [try comment("a"), try comment("b")], count: 5,
                                        posted: [try comment("b")], deleted: ["b"])
        XCTAssertEqual(merged.items.map(\.id), ["a"])
        XCTAssertEqual(merged.count, 4)
        XCTAssertNil(CommentMerge.merge(loaded: [], count: nil, posted: [], deleted: []).count)
    }
}
