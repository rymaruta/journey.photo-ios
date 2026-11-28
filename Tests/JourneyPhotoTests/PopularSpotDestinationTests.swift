import XCTest
@testable import JourneyPhoto

/// 探すの「人気の撮影地」の札の行き先を、押したときだけ決める直し（2026-11-28・札 #594 の2回目）の試験。
/// 前は札の `NavigationLink { … }` の中で `DerivedSpot.openable` を呼び、探すの body のたびに札の数だけ全部の写真をなめていた
@MainActor
final class PopularSpotDestinationTests: XCTestCase {

    private func photo(_ id: String, place: String?) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"", "\"createdAt\":\"2026-01-0\(id.count % 9 + 1)\""]
        if let place { fields.append("\"location\":\"\(place)\"") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 🔴 行き先は今までと同じ: 2枚以上ある地点はスポットの画面、1枚だけなら集約
    func testSameTargetAsBefore() throws {
        let photos = [try photo("a", place: "京都"), try photo("bb", place: "京都"), try photo("c", place: "金沢")]
        guard case .spot(let place) = PopularSpotDestination.target("京都", in: photos) else {
            return XCTFail("2枚ある地点がスポットの画面にならない")
        }
        XCTAssertEqual(place, DerivedSpot.openable("京都", in: photos))
        XCTAssertEqual(PopularSpotDestination.target("金沢", in: photos), .tag("金沢"), "1枚だけの地点が集約にならない")
        XCTAssertEqual(PopularSpotDestination.target("パリ", in: photos), .tag("パリ"))
    }

    /// 🔴 札の行き先は名前と写真だけを持つ。探すの札は計算を呼ばない（戻すと落ちる）
    func testSearchCardsDoNotResolveTheTargetInBody() throws {
        let view = try source("Sources/JourneyPhoto/Features/Search/SearchView.swift")
        XCTAssertFalse(view.contains("DerivedSpot.openable("), "探すの body の中で行き先を計算している")
        guard let range = view.range(of: "private func spotLink<Label: View>") else { return XCTFail("札の行き先が無い") }
        XCTAssertTrue(view[range.upperBound...].prefix(600).contains("PopularSpotDestination(label: spot.id, photos: model.everything)"),
                      "札の行き先が PopularSpotDestination ではない")
    }

    /// 探すの body 1回あたりの行き先の計算の時間（前: 札 6 枚ぶん `openable`・後: 行き先を作るだけ）。数をログに残す
    func testBuildingLinksIsCheap() throws {
        var photos: [Photo] = []
        let places = ["京都", "金沢", "富士山", "那覇市, 沖縄県", "パリ, フランス", "東京都 渋谷区", "ソウル 韓国", "台北, 台湾"]
        for copy in 0..<75 {
            for (index, place) in places.enumerated() { photos.append(try photo("p\(copy)-\(index)", place: place)) }
        }
        let spots = DiscoverySections.popularSpots(in: photos, limit: 6)
        XCTAssertEqual(spots.count, 6)
        func best(_ work: () -> Void) -> TimeInterval {
            (0..<3).map { _ in
                let start = Date()
                work()
                return Date().timeIntervalSince(start)
            }.min() ?? 0
        }
        let before = best { for spot in spots { _ = DerivedSpot.openable(spot.id, in: photos) } }
        let after = best { for spot in spots { _ = PopularSpotDestination(label: spot.id, photos: photos) } }
        print("measured [popular-spot-links] photos=\(photos.count) spots=\(spots.count) before=\(Int(before * 1000))ms after=\(Int(after * 1000))ms")
        XCTAssertLessThan(after, before, "行き先を作るだけなのに計算と同じくらいかかる")
    }
}
