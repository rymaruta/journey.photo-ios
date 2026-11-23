import XCTest
import UIKit
@testable import JourneyPhoto

/// 見た目が少し変わる重さの直し（2026-10-28・owner 承認）:
/// ホームの札のガラスの丸を外し、札が見る store を絞る／地図のピンの影を外す／
/// とおまわり号の中の形の使い回し・影・MSAA（とおまわり号は 2026-11-23 に消した・札 #709。その試験も外した）
final class PerfBatch2Tests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto").appendingPathComponent(path),
                          encoding: .utf8)
    }

    /// 注記の行を除いたコード（注記に `.ultraThinMaterial` と書いてあっても数えない）
    private func code(_ path: String) throws -> String {
        try source(path).components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func between(_ text: String, _ from: String, _ to: String) throws -> String {
        let a = try XCTUnwrap(text.range(of: from), "見つからない: \(from)")
        let b = try XCTUnwrap(text.range(of: to, range: a.upperBound..<text.endIndex), "見つからない: \(to)")
        return String(text[a.lowerBound..<b.lowerBound])
    }

    // MARK: - ホームの札

    /// ガラス（ぼかし）を外し、黒 55% の丸だけにする（いいね・「…」の両方）
    func testHomeTileCirclesHaveNoGlass() throws {
        let mosaic = try code("Features/Gallery/HomeMosaic.swift")
        XCTAssertFalse(mosaic.contains("Material"), "ホームの札にぼかしの材質が残っている")
        XCTAssertTrue(mosaic.contains(".background(Color.black.opacity(0.55), in: Capsule())"), "いいねの丸の地が無い")
        XCTAssertTrue(mosaic.contains(".background(Color.black.opacity(0.55), in: Circle())"), "「…」の丸の地が無い")
    }

    /// 札そのものはログインだけを見る。いいね・ブロックの store は、それを使う小さな部品だけが見る
    func testHomeTileObservesOnlyWhatItNeeds() throws {
        let mosaic = try code("Features/Gallery/HomeMosaic.swift")
        let tile = try between(mosaic, "struct HomeFeedTile: View {", "struct HomeTileMoreMenu: View {")
        XCTAssertEqual(tile.components(separatedBy: "@EnvironmentObject").count - 1, 1, "札が見る store が増えている")
        XCTAssertTrue(tile.contains("@EnvironmentObject private var auth: AuthStore"))
        for store in ["FavoritesStore", "LikeCountStore", "ModerationStore", "ToastCenter", "AppEnvironment"] {
            XCTAssertFalse(tile.contains(store), "札が \(store) を見ている（♥やブロックのたびに札が全部描き直される）")
        }
        XCTAssertTrue(tile.contains("HomeTileLikeButton(photo: photo)"))
        XCTAssertTrue(tile.contains("HomeTileMoreMenu(photo: photo, ownerId: ownerId, onReport: onReport)"))

        let menu = try between(mosaic, "struct HomeTileMoreMenu: View {", "struct HomeTileLikeButton: View {")
        XCTAssertTrue(menu.contains("@EnvironmentObject private var hidden: ModerationStore"))
        XCTAssertFalse(menu.contains("FavoritesStore") || menu.contains("LikeCountStore"))

        let like = try between(mosaic, "struct HomeTileLikeButton: View {", "enum HomeTileText")
        XCTAssertTrue(like.contains("@EnvironmentObject private var favorites: FavoritesStore"))
        XCTAssertTrue(like.contains("@EnvironmentObject private var likeCounts: LikeCountStore"))
        XCTAssertFalse(like.contains("ModerationStore"))
    }

    // MARK: - 地図のピン

    /// 撮影スポットの印・みんなの写真のピンに影を付けない
    func testMapPinsHaveNoShadow() throws {
        XCTAssertFalse(try code("Features/Map/SpotMapMarker.swift").contains(".shadow("), "観光スポットのピンに影が残っている")
        let map = try code("Features/Map/PhotoMapView.swift")
        let frame = try between(map, "private static func photoPinFrame<", "private func cameraChanged(")
        XCTAssertFalse(frame.contains(".shadow("), "みんなの写真のピンに影が残っている")
        XCTAssertTrue(frame.contains(".background(Color.white, in: RoundedRectangle(cornerRadius: photoPinRadius))"),
                      "白い札の縁が無い（影を外した代わりの見分け）")
    }
}
