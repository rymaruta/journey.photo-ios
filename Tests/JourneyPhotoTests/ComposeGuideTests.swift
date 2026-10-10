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

    private func sample(_ n: Int) -> SpotSample {
        SpotSample(src: URL(string: "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/\(n).jpg/1280px-\(n).jpg")!,
                   width: 1280, height: 853, title: "T\(n)", author: "A", license: "CC0", licenseUrl: nil,
                   sourceUrl: URL(string: "https://commons.wikimedia.org/wiki/File:\(n).jpg")!)
    }

    func testStartIndexIsTheTappedSample() {
        // owner の報告（2026-10-10・1.0.84）「作例の1枚目しか重ねられない」: 帯で押した1枚から始める
        let samples = (0..<5).map(sample)
        XCTAssertEqual(ComposeGuide.startIndex(of: samples[2].sourceUrl, in: samples), 2)
        XCTAssertEqual(ComposeGuide.startIndex(of: samples[4].sourceUrl, in: samples), 4)
        // 入口のボタン（nil）は1枚目
        XCTAssertEqual(ComposeGuide.startIndex(of: nil, in: samples), 0)
    }

    func testStartIndexFollowsTheSampleWhenAnEarlierOneIsHidden() {
        // 案内を経るあいだに前の1枚が読めずに隠れても、押した1枚から始める（番号ではなく出典で探す）
        let samples = (0..<5).map(sample)
        let shown = samples.filter { $0 != samples[1] }
        XCTAssertEqual(ComposeGuide.startIndex(of: samples[3].sourceUrl, in: shown), 2)
        // 押した1枚が消えていたら1枚目
        XCTAssertEqual(ComposeGuide.startIndex(of: samples[1].sourceUrl, in: shown), 0)
        XCTAssertEqual(ComposeGuide.startIndex(of: samples[0].sourceUrl, in: []), 0)
    }

    func testEachLaunchIsANewRequest() {
        // 同じ1枚を続けて開いても、撮る画面を作り直す（前の作例の番号を持ち越さない）
        let samples = (0..<3).map(sample)
        let url = samples[1].sourceUrl
        XCTAssertNotEqual(ComposeGuide.Launch(sample: url, samples: samples),
                          ComposeGuide.Launch(sample: url, samples: samples))
    }

    func testLaunchStartsAtTheTappedSampleAndKeepsTheOrder() {
        let samples = (0..<5).map(sample)
        let launch = ComposeGuide.Launch(sample: samples[3].sourceUrl, samples: samples)
        XCTAssertEqual(launch.start, 3)
        // 開いた時点の並びを持つ（開いている間に帯が縮んでも、撮る画面の作例はずれない）
        XCTAssertEqual(launch.samples, samples)
        // 入口のボタンは1枚目
        XCTAssertEqual(ComposeGuide.Launch(sample: nil, samples: samples).start, 0)
    }

    // MARK: - 画面のつなぎ（画面の部品は Linux で動かせないので、ソースで縛る・2026-10-10）

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 撮る画面へは、頼み（`Launch`）が持つ並びと始める番号をそのまま渡す。
    /// `startIndex: 0` や今の帯の並び（`samples:` に `samples`）に戻すと、押した作例から始まらない・ずれる。
    /// 2026-10-10: 撮る画面を開く口は共通の部品（`ComposeGuidePresenter`）1か所に移した
    func testSpotScreenPassesTheLaunchToTheCamera() throws {
        let spot = try source("Sources/JourneyPhoto/Features/Spots/OfficialSpotView.swift")
        let launcher = try source("Sources/JourneyPhoto/Features/Spots/ComposeGuideLauncher.swift")
        XCTAssertTrue(launcher.contains("ComposeGuideView(spotName: spotName, samples: launch.samples, startIndex: launch.start"),
                      "撮る画面に Launch の並びと始める番号を渡していない")
        XCTAssertEqual(launcher.components(separatedBy: "ComposeGuideView(").count - 1, 1, "撮る画面を開く口が増えた")
        XCTAssertEqual(spot.components(separatedBy: "ComposeGuideView(").count - 1, 0, "撮影スポットの頁が直に開いている")
        XCTAssertTrue(spot.contains(".composeGuidePresenter(composeLauncher, spotName: spot.name)"),
                      "撮影スポットの頁が共通の部品で開いていない")
        // 頼みは開く時点の帯の並びで作る
        XCTAssertTrue(spot.contains("ComposeGuide.Launch(sample: sample, samples: shownSamples)"), "帯の並びで開いていない")
        // 帯の写真は押した1枚の出典で開く。入口のボタンは1枚目
        XCTAssertTrue(spot.contains("openComposeGuide(from: sample.sourceUrl)"), "帯の写真から開いていない")
        XCTAssertTrue(spot.contains("openComposeGuide(from: nil)"), "入口のボタンが1枚目から開いていない")
        // 開いている間は開き直さない（素早い2回押し・`ComposeGuideLauncherTests.testDoesNotReopenWhileOpen`）
        XCTAssertTrue(launcher.contains("guard !checking, launch == nil, !showPaywall"), "開いている間の2回押しを止めていない")
    }

    /// 撮る画面は渡された番号から始め、映像に指を取らせない
    func testComposeScreenStartsAtTheGivenIndexAndPreviewIgnoresTouches() throws {
        let view = try source("Sources/JourneyPhoto/Features/Spots/ComposeGuideView.swift")
        XCTAssertTrue(view.contains("_index = State(initialValue: ComposeGuide.normalized(startIndex, count: samples.count))"),
                      "撮る画面が startIndex から始めていない")
        // `CameraPreview(...)` の次の部品（`overlay`）までの修飾に `.allowsHitTesting(false)` がある
        let afterPreview = try XCTUnwrap(view.components(separatedBy: "CameraPreview(session: camera.session)").dropFirst().first)
        let chain = try XCTUnwrap(afterPreview.components(separatedBy: "\n                overlay\n").first)
        XCTAssertTrue(chain.contains(".allowsHitTesting(false)"), "映像が指を取る（枠の左右の払いが届かない恐れ）")
    }

    @MainActor
    func testCameraPreviewDoesNotTakeTouches() async {
        // 映像が指を取ると、枠の左右の払い（作例の切り替え）が届かない（2026-10-10）
        XCTAssertFalse(CameraPreview.preparedView().isUserInteractionEnabled)
    }

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
