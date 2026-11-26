import XCTest
@testable import JourneyPhoto

/// ホームの札を、並び（`HomeMosaic`）が描き直されただけでは描き直さない直し（2026-11-26・Mac run 1804 の
/// `chg.HomeFeedTile.@self` 172・154・56 回）の試験。札そのものは Linux の模型では描けないので、比べる値と配線を見る
@MainActor
final class HomeFeedTileEquatableTests: XCTestCase {

    private func photo(_ id: String, location: String = "京都") throws -> Photo {
        let json = "{\"id\":\"\(id)\",\"src\":\"https://journey-photo.com/images/\(id).jpg\",\"title\":\"t\(id)\",\"location\":\"\(location)\"}"
        return try JSONDecoder.api.decode(Photo.self, from: Data(json.utf8))
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func tile(_ p: Photo, siblings: [Photo]? = nil, large: Bool = false, first: Bool = false,
                      yours: Bool = false) -> HomeFeedTile {
        HomeFeedTile(photo: p, siblings: siblings ?? [p], large: large, isFirstPost: first,
                     onReport: { _ in }, marksAsYours: yours)
    }

    /// 🔴 毎回新しい `onReport` だけが違う札は同じ。描く値（写真・同じ投稿の写真・大きさ・印）が違えば違う
    func testTilesCompareOnlyWhatTheyDraw() throws {
        let a = try photo("a"), b = try photo("b")
        XCTAssertTrue(tile(a) == tile(a), "閉じた処理が新しくなっただけで描き直す")
        XCTAssertFalse(tile(a) == tile(b), "写真が替わったのに描き直さない")
        XCTAssertFalse(tile(a) == tile(try photo("a", location: "大阪")), "写真の中身（撮影地）が替わったのに描き直さない")
        XCTAssertFalse(tile(a) == tile(a, siblings: [a, b]), "複数枚の印が変わったのに描き直さない")
        XCTAssertFalse(tile(a) == tile(a, large: true))
        XCTAssertFalse(tile(a) == tile(a, first: true))
        XCTAssertFalse(tile(a) == tile(a, yours: true))
    }

    /// 🔴 並びが札を `.equatable()` で包む。札が親から受け取る値が増えたら、比べる値も見直す
    func testMosaicWrapsTilesAndInputsAreComplete() throws {
        let file = try source("Sources/JourneyPhoto/Features/Gallery/HomeMosaic.swift")
        guard let range = file.range(of: "HomeFeedTile(photo: photo, siblings:") else { return XCTFail("並びに札が無い") }
        XCTAssertTrue(file[range.upperBound...].prefix(400).contains(".equatable()"), "並びが札を .equatable() で包んでいない")
        guard let head = file.range(of: "struct HomeFeedTile: View {") else { return XCTFail("HomeFeedTile が無い") }
        let body = file[head.upperBound...].components(separatedBy: "\n}\n").first ?? ""
        let passed = body.components(separatedBy: "\n")
            .filter { $0.hasPrefix("    let ") || ($0.hasPrefix("    var ") && !$0.hasSuffix("{")) }
            .map { $0.trimmingCharacters(in: .whitespaces).split(separator: " ").prefix(2).joined(separator: " ")
                .components(separatedBy: ":").first ?? "" }
        XCTAssertEqual(passed, ["let photo", "var siblings", "var large", "var isFirstPost", "var onReport", "var marksAsYours"],
                       "HomeFeedTile が親から受け取る値が変わった。HomeFeedTileInputs も見直す")
    }
}
