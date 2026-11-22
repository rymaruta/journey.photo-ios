import XCTest
import MapKit
@testable import JourneyPhoto

/// AI の答えの地図の範囲（2026-11-22・owner「AIの答えで謎の枠あった。地図のスポットかな？周り見えないから全然わからないな」）。
/// ピンが1つでも周りの街が見える広さにする（前は `.automatic` で最大まで寄り、一色の面にピンだけだった）
final class AskMapFrameTests: XCTestCase {

    /// 金沢駅のあたり（実機で見えていた「金沢駅 鼓門ともてなしドーム」）
    private let kanazawa = CLLocationCoordinate2D(latitude: 36.578, longitude: 136.648)

    func testNoCoordinatesHasNoRegion() {
        XCTAssertNil(AskMapFrame.region(for: []))
    }

    /// ピンが1つ: その場所が真ん中で、南北に約 3km（半径 1.5km）。東西も同じメートル（経度は緯度の分だけ広い）
    func testSinglePinShowsSurroundingTown() throws {
        let r = try XCTUnwrap(AskMapFrame.region(for: [kanazawa]))
        XCTAssertEqual(r.center.latitude, kanazawa.latitude, accuracy: 1e-9)
        XCTAssertEqual(r.center.longitude, kanazawa.longitude, accuracy: 1e-9)
        let northSouthMeters = r.span.latitudeDelta * 111_000
        XCTAssertEqual(northSouthMeters, 3_000, accuracy: 1)
        // 半径 1〜2km の範囲（寄りすぎて道が消えない・引きすぎて場所がぼけない）
        XCTAssertGreaterThanOrEqual(northSouthMeters / 2, 1_000)
        XCTAssertLessThanOrEqual(northSouthMeters / 2, 2_000)
        let eastWestMeters = r.span.longitudeDelta * 111_000 * cos(kanazawa.latitude * .pi / 180)
        XCTAssertEqual(eastWestMeters, northSouthMeters, accuracy: 1)
    }

    /// ピンが2つ以上: 全部の外枠より広く、端のピンが縁にかからない（上下左右に余白）
    func testManyPinsKeepEdgePinsInside() throws {
        let kenrokuen = CLLocationCoordinate2D(latitude: 36.562, longitude: 136.662)
        let higashi = CLLocationCoordinate2D(latitude: 36.572, longitude: 136.667)
        let kanazawaPort = CLLocationCoordinate2D(latitude: 36.611, longitude: 136.611)
        let pins = [kanazawa, kenrokuen, higashi, kanazawaPort]
        let r = try XCTUnwrap(AskMapFrame.region(for: pins))
        let halfLat = r.span.latitudeDelta / 2
        let halfLng = r.span.longitudeDelta / 2
        for p in pins {
            // 中心から縁までの 8 割より内側（縁に 1 割以上の余白）
            XCTAssertLessThan(abs(p.latitude - r.center.latitude), halfLat * 0.8)
            XCTAssertLessThan(abs(p.longitude - r.center.longitude), halfLng * 0.8)
        }
        XCTAssertEqual(r.center.latitude, (36.562 + 36.611) / 2, accuracy: 1e-9)
    }

    /// 近い2か所（同じ建物の中など）は、1つのときより寄せない
    func testClosePinsNeverZoomPastSingle() throws {
        let near = CLLocationCoordinate2D(latitude: kanazawa.latitude + 0.0005, longitude: kanazawa.longitude)
        let single = try XCTUnwrap(AskMapFrame.region(for: [kanazawa]))
        let two = try XCTUnwrap(AskMapFrame.region(for: [kanazawa, near]))
        XCTAssertGreaterThanOrEqual(two.span.latitudeDelta, single.span.latitudeDelta - 1e-9)
    }

    /// 地図の上にピンの名前の字を出さない（大きな字が左下の「法律に基づく情報」に重なっていた）、
    /// 範囲は `AskMapFrame` で決める（`.automatic` のままだとピン1つで最大まで寄る）。
    /// 地図は Linux で描けないので、`AskPinsMap` の書いてあるもので見る
    func testPinsMapHidesTitlesAndUsesFrame() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto/Features/Search/AskThreadView.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "struct AskPinsMap: View {"))
        let end = try XCTUnwrap(source.range(of: "struct AskSendButton", range: start.upperBound..<source.endIndex))
        let body = String(source[start.upperBound..<end.lowerBound])
        XCTAssertTrue(body.contains(".annotationTitles(.hidden)"), "ピンの名前の字が地図に出る")
        XCTAssertTrue(body.contains("AskMapFrame.region(for:"), "地図の範囲を AskMapFrame で決めていない")
        // 読み上げの名前はピンのボタンに残す
        XCTAssertTrue(body.contains(".accessibilityLabel(pin.spot.name)"))
    }

    /// 広い札の地図は札の並びの地図と同じ高さ（細い 76 では周りが読めなかった）
    @MainActor
    func testWideCardMapIsTallEnough() async {
        XCTAssertEqual(AskWideSpotCard.mapHeight, AskSpotCarousel.mapHeight)
        XCTAssertGreaterThanOrEqual(AskWideSpotCard.mapHeight, 160)
    }
}
