import XCTest
@testable import JourneyPhoto

/// 「作例を重ねて撮る」（Pro・板 ComposeGuide・2026-10-09）の画面を持たない決まり（`ComposeGuide`）。
/// 濃さの範囲・作例の順・上の札と案内の札の文・距離と方角・入口の行き先・カメラが使えないときの文
final class ComposeGuideTests: XCTestCase {

    // MARK: - 濃さ

    func testOpacityRangeMatchesBoard() {
        // 板: 0〜0.8、既定は 0.35〜0.45 の間
        XCTAssertEqual(ComposeGuide.opacityRange, 0...0.8)
        XCTAssertTrue((0.35...0.45).contains(ComposeGuide.defaultOpacity))
    }

    func testClampedOpacityStaysInRange() {
        XCTAssertEqual(ComposeGuide.clampedOpacity(-0.2), 0)
        XCTAssertEqual(ComposeGuide.clampedOpacity(0.5), 0.5)
        XCTAssertEqual(ComposeGuide.clampedOpacity(1), 0.8)
        XCTAssertEqual(ComposeGuide.clampedOpacity(.nan), ComposeGuide.defaultOpacity)
        XCTAssertEqual(ComposeGuide.clampedOpacity(.infinity), ComposeGuide.defaultOpacity)
    }

    func testOpacityPercentForVoiceOver() {
        XCTAssertEqual(ComposeGuide.opacityPercent(0.4), "40%")
        XCTAssertEqual(ComposeGuide.opacityPercent(0), "0%")
        // 範囲の外は上限で読む
        XCTAssertEqual(ComposeGuide.opacityPercent(2), "80%")
    }

    // MARK: - 作例の順

    func testNextAndPreviousWrapAround() {
        XCTAssertEqual(ComposeGuide.next(after: 0, count: 3), 1)
        XCTAssertEqual(ComposeGuide.next(after: 2, count: 3), 0)
        XCTAssertEqual(ComposeGuide.previous(before: 0, count: 3), 2)
        XCTAssertEqual(ComposeGuide.previous(before: 2, count: 3), 1)
        // 1枚だけ・0枚
        XCTAssertEqual(ComposeGuide.next(after: 0, count: 1), 0)
        XCTAssertEqual(ComposeGuide.next(after: 0, count: 0), 0)
        XCTAssertEqual(ComposeGuide.previous(before: 0, count: 0), 0)
    }

    func testOutOfRangeIndexIsPulledBackIn() {
        // 作例が壊れて隠れた・減ったとき
        XCTAssertEqual(ComposeGuide.normalized(5, count: 3), 2)
        XCTAssertEqual(ComposeGuide.normalized(-1, count: 3), 0)
        XCTAssertEqual(ComposeGuide.next(after: 9, count: 3), 0)
    }

    func testSwipeLeftIsNextAndRightIsPrevious() {
        XCTAssertEqual(ComposeGuide.swiped(index: 1, count: 6, translationWidth: -120), 2)
        XCTAssertEqual(ComposeGuide.swiped(index: 1, count: 6, translationWidth: 120), 0)
        XCTAssertEqual(ComposeGuide.swiped(index: 0, count: 6, translationWidth: 120), 5)
    }

    func testShortSwipeOrSingleSampleDoesNotSwitch() {
        XCTAssertEqual(ComposeGuide.swiped(index: 1, count: 6, translationWidth: -30), 1)
        XCTAssertEqual(ComposeGuide.swiped(index: 0, count: 1, translationWidth: -200), 0)
    }

    // MARK: - 上の札

    func testCounterMatchesBoard() {
        // 板: 「[撮影地の名前] · 作例 [2] / [6]」（番号は 1 から）
        XCTAssertEqual(ComposeGuide.counter(spotName: "鍋ヶ滝", index: 1, count: 6), "鍋ヶ滝 · 作例 2 / 6")
        XCTAssertEqual(ComposeGuide.counter(spotName: "鍋ヶ滝", index: 9, count: 6), "鍋ヶ滝 · 作例 6 / 6")
        XCTAssertEqual(ComposeGuide.counterAccessibility(spotName: "鍋ヶ滝", index: 0, count: 6),
                       "鍋ヶ滝、作例 1 枚目、全 6 枚")
    }

    // MARK: - 案内の札

    private let here = Photo.Coords(lat: 35.0, lng: 139.0)

    /// `here` から北へ `meters` 進んだ点
    private func north(_ meters: Double) -> Photo.Coords {
        Photo.Coords(lat: here.lat + meters / 111_195, lng: here.lng)
    }

    func testHintWithoutPositionsIsHorizonOnly() {
        // 作例に撮った位置が無い・いまの位置が無い → 距離の文は出さない（ありもしない数を出さない）
        XCTAssertEqual(ComposeGuide.hint(current: nil, target: nil), "地平線を下の線に合わせる")
        XCTAssertEqual(ComposeGuide.hint(current: here, target: nil), "地平線を下の線に合わせる")
        XCTAssertEqual(ComposeGuide.hint(current: nil, target: here), "地平線を下の線に合わせる")
        XCTAssertNil(ComposeGuide.movement(current: here, target: nil))
    }

    func testHintWithPositionsMatchesBoard() {
        // 板: 「あと 3 m 北へ。地平線を下の線に合わせる」
        XCTAssertEqual(ComposeGuide.hint(current: here, target: north(3)), "あと 3 m 北へ。地平線を下の線に合わせる")
    }

    func testArrivedOrTooFarIsHorizonOnly() {
        XCTAssertEqual(ComposeGuide.hint(current: here, target: north(1)), "地平線を下の線に合わせる")
        XCTAssertEqual(ComposeGuide.hint(current: here, target: north(5_000)), "地平線を下の線に合わせる")
    }

    func testBrokenCoordinatesAreIgnored() {
        let broken = Photo.Coords(lat: .nan, lng: 139)
        XCTAssertNil(ComposeGuide.movement(current: broken, target: here))
        XCTAssertNil(ComposeGuide.movement(current: here, target: Photo.Coords(lat: 120, lng: 0)))
    }

    func testDistanceLabel() {
        XCTAssertEqual(ComposeGuide.distanceLabel(meters: 3.4), "3 m")
        XCTAssertEqual(ComposeGuide.distanceLabel(meters: 999), "999 m")
        XCTAssertEqual(ComposeGuide.distanceLabel(meters: 1_000), "1.0 km")
        XCTAssertEqual(ComposeGuide.distanceLabel(meters: 1_234), "1.2 km")
    }

    func testDistanceMeters() {
        XCTAssertEqual(ComposeGuide.distanceMeters(from: here, to: north(100)), 100, accuracy: 0.5)
        XCTAssertEqual(ComposeGuide.distanceMeters(from: here, to: here), 0, accuracy: 0.001)
    }

    func testBearingAndCompass() {
        XCTAssertEqual(ComposeGuide.bearingDegrees(from: here, to: north(50)), 0, accuracy: 0.5)
        let east = Photo.Coords(lat: here.lat, lng: here.lng + 0.001)
        XCTAssertEqual(ComposeGuide.bearingDegrees(from: here, to: east), 90, accuracy: 0.5)
        let south = Photo.Coords(lat: here.lat - 0.001, lng: here.lng)
        XCTAssertEqual(ComposeGuide.bearingDegrees(from: here, to: south), 180, accuracy: 0.5)
        let west = Photo.Coords(lat: here.lat, lng: here.lng - 0.001)
        XCTAssertEqual(ComposeGuide.bearingDegrees(from: here, to: west), 270, accuracy: 0.5)

        XCTAssertEqual(ComposeGuide.Compass(bearing: 0), .north)
        XCTAssertEqual(ComposeGuide.Compass(bearing: 22), .north)
        XCTAssertEqual(ComposeGuide.Compass(bearing: 23), .northEast)
        XCTAssertEqual(ComposeGuide.Compass(bearing: 90), .east)
        XCTAssertEqual(ComposeGuide.Compass(bearing: 225), .southWest)
        XCTAssertEqual(ComposeGuide.Compass(bearing: 350), .north)
        XCTAssertEqual(ComposeGuide.Compass(bearing: -90), .west)
        XCTAssertEqual(ComposeGuide.Compass(bearing: .nan), .north)
        XCTAssertEqual(ComposeGuide.Compass.southEast.ja, "南東")
    }

    func testHintNamesDirection() {
        let east = Photo.Coords(lat: here.lat, lng: here.lng + 20 / (111_195 * cos(35 * .pi / 180)))
        XCTAssertEqual(ComposeGuide.hint(current: here, target: east), "あと 20 m 東へ。地平線を下の線に合わせる")
    }

    // MARK: - 入口

    func testEntryOnlyWithSamples() {
        XCTAssertFalse(ComposeGuide.showsEntry(sampleCount: 0))
        XCTAssertTrue(ComposeGuide.showsEntry(sampleCount: 1))
    }

    func testDestination() {
        XCTAssertEqual(ComposeGuide.destination(signedIn: true, isPro: true), .camera)
        XCTAssertEqual(ComposeGuide.destination(signedIn: true, isPro: false), .paywall)
        XCTAssertEqual(ComposeGuide.destination(signedIn: false, isPro: nil), .paywall)
        // Pro かを確かめられなかった（圏外）→ Pro の人に案内を出さない
        XCTAssertEqual(ComposeGuide.destination(signedIn: true, isPro: nil), .unreachable)
    }

    func testPreviewKeyIsOffByDefault() {
        UserDefaults.standard.removeObject(forKey: ComposeGuideAccess.defaultsKey)
        XCTAssertFalse(ComposeGuideAccess.previewUnlocked)
    }

    // MARK: - 撮ったあと・カメラが使えないとき

    func testSaveMessages() {
        XCTAssertEqual(ComposeGuide.message(for: .saved), "保存しました")
        XCTAssertTrue(ComposeGuide.message(for: .denied).contains("設定"))
        XCTAssertEqual(ComposeGuide.message(for: .failed), "保存できませんでした")
    }

    func testBlockedTextAndSettings() {
        XCTAssertNil(ComposeGuide.blockedText(.ready))
        XCTAssertNil(ComposeGuide.blockedText(.preparing))
        XCTAssertNotNil(ComposeGuide.blockedText(.denied))
        XCTAssertNotNil(ComposeGuide.blockedText(.restricted))
        XCTAssertNotNil(ComposeGuide.blockedText(.unavailable))
        // 設定アプリへの誘導は、断ったときだけ（制限・カメラ無しは設定で直らない）
        XCTAssertTrue(ComposeGuide.offersSettings(.denied))
        XCTAssertFalse(ComposeGuide.offersSettings(.restricted))
        XCTAssertFalse(ComposeGuide.offersSettings(.unavailable))
    }
}
