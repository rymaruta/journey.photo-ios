import XCTest
@testable import JourneyPhoto

/// ホームの札 `HomeFeedTile` の等しさ（2026-11-07・札 #435 / #429）。入力が同じなら `.equatable()` で `body` を評価し直さない。
/// 親（`GalleryView`）の `body` が撮影スポットの索引の到着などで評価し直されるたびに、札を約10枚作り直していた
final class HomeFeedTileEqualityTests: XCTestCase {

    private func photo(_ id: String, userId: String? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\""]
        if let userId { fields.append("\"userId\":\"\(userId)\"") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    /// 写真・同じ投稿の写真・段の大きさが同じなら等しい。通報の閉包は比べない（作り口は閉包を空にする）
    func testEqualWhenInputsMatchRegardlessOfClosure() throws {
        let a = try photo("p1")
        let first = HomeFeedTile.forEquality(photo: a, siblings: [a], large: true)
        let second = HomeFeedTile.forEquality(photo: a, siblings: [a], large: true)
        XCTAssertEqual(first, second)
    }

    /// 見た目を決める入力が1つでも違えば等しくない（描き直される）
    func testNotEqualWhenAnyVisibleInputDiffers() throws {
        let a = try photo("p1")
        let b = try photo("p2")
        let base = HomeFeedTile.forEquality(photo: a, siblings: [a], large: false)
        XCTAssertNotEqual(base, HomeFeedTile.forEquality(photo: b, siblings: [a], large: false), "写真が違う")
        XCTAssertNotEqual(base, HomeFeedTile.forEquality(photo: a, siblings: [a, b], large: false), "同じ投稿の写真が違う")
        XCTAssertNotEqual(base, HomeFeedTile.forEquality(photo: a, siblings: [a], large: true), "段の大きさが違う")
        let changed = try photo("p1", userId: "u9")
        XCTAssertNotEqual(base, HomeFeedTile.forEquality(photo: changed, siblings: [a], large: false), "写真の中身が変わった")
    }

    /// 札を作る場所は `.equatable()` を付けている（付け忘れると評価し直しが戻る）
    func testMosaicAppliesEquatable() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/Gallery/HomeMosaic.swift"),
                              encoding: .utf8)
        let code = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertTrue(code.contains("large: large, onReport: onReport)\n            .equatable()"),
                      "HomeMosaic.tile が HomeFeedTile に .equatable() を付けていない")
    }
}
