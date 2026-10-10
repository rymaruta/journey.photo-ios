import XCTest
@testable import JourneyPhoto

/// 「作例・構図を重ねて撮る」を開くまでの流れ（`ComposeGuideLauncher`・2026-10-10 に撮影スポットの頁から切り出し、
/// 投稿のシートの入口と共通にした）と、撮る画面の枠・案内の札・撮る向き。
final class ComposeGuideLauncherTests: XCTestCase {

    private static func freeLaunch() -> ComposeGuide.Launch { ComposeGuide.Launch(sample: nil, samples: []) }

    // MARK: - Pro の流れ

    @MainActor
    func testProOpensTheCamera() async {
        let launcher = ComposeGuideLauncher()
        let outcome = await launcher.open(previewUnlocked: false, signedIn: true, deliveredRevision: 0,
                                          isPro: { true }, make: Self.freeLaunch)
        XCTAssertEqual(outcome, .opened)
        XCTAssertNotNil(launcher.launch)
        XCTAssertEqual(launcher.launch?.samples.count, 0, "作例なしの入口")
        XCTAssertFalse(launcher.showPaywall)
        XCTAssertFalse(launcher.checking)
    }

    @MainActor
    func testNotProShowsThePaywallAndReopensAfterPurchase() async {
        let launcher = ComposeGuideLauncher()
        var made = 0
        let outcome = await launcher.open(previewUnlocked: false, signedIn: true, deliveredRevision: 3,
                                          isPro: { false }, make: { made += 1; return Self.freeLaunch() })
        XCTAssertEqual(outcome, .paywall)
        XCTAssertTrue(launcher.showPaywall)
        XCTAssertNil(launcher.launch)
        XCTAssertEqual(made, 0, "案内のときは撮る画面の頼みを作らない")
        // 案内で買わずに閉じた（渡し終えた回数が同じ）→ 開き直さない
        launcher.showPaywall = false
        XCTAssertNil(launcher.paywallDismissed(deliveredRevision: 3))
        // 買って閉じた（回数が増えた）→ 同じ頼みで開き直す
        let reopen = launcher.paywallDismissed(deliveredRevision: 4)
        XCTAssertNotNil(reopen)
        if let reopen {
            let again = await launcher.open(previewUnlocked: false, signedIn: true, deliveredRevision: 4,
                                            isPro: { true }, make: reopen)
            XCTAssertEqual(again, .opened)
            XCTAssertEqual(made, 1)
        }
    }

    @MainActor
    func testSignedOutGoesToPaywallWithoutAsking() async {
        let launcher = ComposeGuideLauncher()
        var asked = false
        let outcome = await launcher.open(previewUnlocked: false, signedIn: false, deliveredRevision: 0,
                                          isPro: { asked = true; return true }, make: Self.freeLaunch)
        XCTAssertEqual(outcome, .paywall)
        XCTAssertFalse(asked, "ログインしていなければプロフィールを聞きに行かない")
    }

    @MainActor
    func testUnreachableDoesNotShowPaywallToPro() async {
        let launcher = ComposeGuideLauncher()
        let outcome = await launcher.open(previewUnlocked: false, signedIn: true, deliveredRevision: 0,
                                          isPro: { nil }, make: Self.freeLaunch)
        XCTAssertEqual(outcome, .unreachable)
        XCTAssertFalse(launcher.showPaywall)
        XCTAssertNil(launcher.launch)
    }

    @MainActor
    func testDoesNotReopenWhileOpen() async {
        let launcher = ComposeGuideLauncher()
        await launcher.open(previewUnlocked: true, signedIn: false, deliveredRevision: 0,
                            isPro: { nil }, make: Self.freeLaunch)
        let first = launcher.launch?.id
        XCTAssertNotNil(first, "試験の鍵があれば Pro の確かめを飛ばす")
        // 開いている間に2回目（素早い2回押し）→ 何もしない
        let second = await launcher.open(previewUnlocked: true, signedIn: false, deliveredRevision: 0,
                                         isPro: { nil }, make: Self.freeLaunch)
        XCTAssertEqual(second, .ignored)
        XCTAssertEqual(launcher.launch?.id, first)
    }

    // MARK: - 撮る画面の枠（3:4）

    func testViewfinderFitsThreeByFour() {
        // 縦に余る（iPhone の作例なし）: 幅いっぱい・高さ 520、上下は黒い地
        let tall = ComposeGuide.viewfinderSize(width: 390, height: 600)
        XCTAssertEqual(tall.width, 390)
        XCTAssertEqual(tall.height, 520)
        // 縦が足りない（作例の行が増えた・小さい端末）: 高さいっぱい・幅を縮める
        let short = ComposeGuide.viewfinderSize(width: 375, height: 400)
        XCTAssertEqual(short.height, 400)
        XCTAssertEqual(short.width, 300)
        XCTAssertEqual(ComposeGuide.viewfinderSize(width: 0, height: 100).width, 0)
        XCTAssertEqual(ComposeGuide.viewfinderSize(width: .nan, height: 100).height, 0)
    }

    // MARK: - 案内の札（構図ごとの一言）

    func testHintUsesCompositionTip() {
        XCTAssertEqual(ComposeGuide.hint(current: nil, target: nil, tip: CompositionKind.goldenSpiral.tip),
                       CompositionKind.goldenSpiral.tip)
        XCTAssertNil(ComposeGuide.hint(current: nil, target: nil, tip: nil), "構図が「なし」なら札を出さない")
        let here = Photo.Coords(lat: 35, lng: 139)
        let north = Photo.Coords(lat: 35 + 3 / 111_195, lng: 139)
        XCTAssertEqual(ComposeGuide.hint(current: here, target: north, tip: "線に合わせる"), "あと 3 m 北へ。線に合わせる")
    }

    // MARK: - 撮る向き

    func testCaptureAngleFollowsTheDevice() {
        // 係の角度をそのまま使う（横持ち 0°・逆さの横持ち 180°）。以前は 90° 決め打ち
        XCTAssertEqual(ComposeGuide.captureAngle(coordinator: 0), 0)
        XCTAssertEqual(ComposeGuide.captureAngle(coordinator: 180), 180)
        XCTAssertEqual(ComposeGuide.captureAngle(coordinator: nil), 90)
        XCTAssertEqual(ComposeGuide.captureAngle(coordinator: .nan), 90)
    }

    func testShotBecomesACameraCaptureWithItsMetadata() {
        let data = Data([1, 2, 3])
        let shot = ComposeShot(data: data, metadata: ["{TIFF}": ["Model": "iPhone"]], capturedAt: Date(timeIntervalSince1970: 0))
        let capture = shot.cameraCapture
        XCTAssertEqual(capture.jpegData(), data)
        XCTAssertEqual(capture.metadata.count, 1, "撮影情報（機種・撮影日時）を投稿画面へ渡す")
    }

    // MARK: - 画面のつなぎ（画面の部品は Linux で動かせないので、ソースで縛る）

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 映像は撮れる範囲（3:4）の枠に切らずに敷く。撮る向きは端末の向き
    func testViewfinderMatchesThePhotoAndCaptureFollowsTheDevice() throws {
        let camera = try source("Sources/JourneyPhoto/Features/Spots/ComposeCamera.swift")
        XCTAssertTrue(camera.contains("static let gravity: AVLayerVideoGravity = .resizeAspect\n"),
                      "映像を切り抜いて敷いている（線・作例が写真とずれる）")
        XCTAssertTrue(camera.contains("videoGravity = Self.gravity"))
        XCTAssertTrue(camera.contains("rotation.map { Double($0.videoRotationAngleForHorizonLevelCapture) }"), "撮る向きが端末の向きでない")
        XCTAssertFalse(camera.contains("isVideoRotationAngleSupported(90)"), "90° 決め打ちに戻っている")
        let view = try source("Sources/JourneyPhoto/Features/Spots/ComposeGuideView.swift")
        XCTAssertTrue(view.contains("ComposeGuide.viewfinderSize(width:"), "映像の枠が 3:4 でない")
        // 重ね順: 映像 → 作例（overlay）→ 構図の線
        let preview = try XCTUnwrap(view.range(of: "CameraPreview(session: camera.session)"))
        let lines = try XCTUnwrap(view.range(of: "CompositionOverlay(kind: composition"))
        XCTAssertLessThan(preview.lowerBound, lines.lowerBound)
    }

    /// 投稿のシートの4つ目「構図を重ねて撮る」は Pro の流れ（`ComposeGuidePresenter.request`）を通り、作例なしで開く
    func testPostSheetEntryGoesThroughTheProCheck() throws {
        let sheet = try source("Sources/JourneyPhoto/Features/Upload/PostSheet.swift")
        XCTAssertTrue(sheet.contains("kind: .composition"))
        let root = try source("Sources/JourneyPhoto/App/RootView.swift")
        XCTAssertTrue(root.contains("case .composition:"))
        XCTAssertTrue(root.contains("composeLauncher, make: { ComposeGuide.Launch(sample: nil, samples: []) }"),
                      "作例なしで Pro の流れを通していない")
        XCTAssertTrue(root.contains(".composeGuidePresenter(composeLauncher, spotName: nil, onPost:"))
        XCTAssertTrue(root.contains("initialCapture: pendingCapture"), "撮った1枚を投稿画面へ渡していない")
    }

    func testPreviewLensIsOffWithoutTheLaunchArgument() {
        XCTAssertFalse(ComposeGuideAccess.previewUnlocked)
    }
}
