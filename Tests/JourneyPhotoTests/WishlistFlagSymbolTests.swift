import XCTest
@testable import JourneyPhoto

/// 「行きたい」（行きたい場所に保存する操作と、その一覧）の印は旗にそろえる（2026-11-14 owner 承認・#593）。
///
/// 旗（マイページのタブ・写真の詳細・行きたい場所の一覧）とハート（スポットの頁の「行きたい」・ホームの棚・
/// 地図の「行きたい場所 N」・旅行プランのめくり）に割れていて、いいねのハートと紛れていた。
/// 保存済み・決める操作は塗りの旗（`flag.fill`）、まだのときは線の旗（`flag`）。いいねのハートは変えない。
///
/// 画面は Linux で描けないので、ソースの印の名前で見る（`PlaceTermWordingTests` と同じ形）
final class WishlistFlagSymbolTests: XCTestCase {

    private var sourcesRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
    }

    /// 「行きたい」の文脈と見なす言葉（印の行と、その前4行・後1行で探す）
    private static let wishMarkers = ["行きたい", "wanted", "wishlist", "Wishlist", "choose(.want)", "Want to go"]

    /// ハートの印（`"heart"`・`"heart.fill"`・`"heart.circle"` など）の行の近くに「行きたい」の言葉が無い
    func testWishlistNeverUsesHeartSymbol() throws {
        let files = FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 100, "前提: ソースを読めていない")
        let heart = try NSRegularExpression(pattern: #""heart(\.[a-z.]+)?""#)
        var hearts = 0
        var bad: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (i, line) in lines.enumerated()
            where heart.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                hearts += 1
                let window = lines[max(0, i - 4)...min(lines.count - 1, i + 1)].joined(separator: "\n")
                if Self.wishMarkers.contains(where: { window.contains($0) }) {
                    bad.append("\(file.lastPathComponent):\(i + 1) \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        XCTAssertGreaterThan(hearts, 5, "前提: いいねのハートを見つけられていない")
        XCTAssertEqual(bad, [], "「行きたい」の印にハートを使っている（旗にそろえる・#593）")
    }

    /// 「行きたい」の印のある所は、どれも旗（保存済みは塗り・まだは線）
    func testWishlistSitesUseFlag() throws {
        let sites: [(String, String)] = [
            ("Features/Spots/SpotDetailView.swift", #".actionLabel(icon: wanted ? "flag.fill" : "flag","#),
            ("Features/Spots/OfficialSpotView.swift", #".actionLabel(icon: wanted ? "flag.fill" : "flag","#),
            ("Features/PhotoDetail/PhotoTripSection.swift", #".actionLabel(icon: wanted ? "flag.fill" : "flag","#),
            ("Features/Gallery/HomeSpotShelfView.swift", #"Image(systemName: wanted ? "flag.fill" : "flag")"#),
            ("Features/Map/PhotoMapView.swift", #"Image(systemName: "flag.fill")"#),
            ("Features/Trips/TripPickerView.swift", #"stamp(L("行きたい", "Want to go"), icon: "flag.fill")"#),
            ("Features/Trips/TripPickerView.swift", #"Label(L("行きたい", "Want to go"), systemImage: "flag.fill")"#),
        ]
        for (path, needle) in sites {
            let text = try String(contentsOf: sourcesRoot.appendingPathComponent(path), encoding: .utf8)
            XCTAssertTrue(text.contains(needle), "\(path) の「行きたい」が旗でない: \(needle)")
        }
        XCTAssertEqual(ProfileTab.wishlist.systemImage, "flag", "マイページの「行きたい場所」のタブが旗でない")
    }
}
