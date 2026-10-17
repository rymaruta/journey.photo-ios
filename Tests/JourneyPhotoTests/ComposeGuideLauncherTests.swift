import XCTest
@testable import JourneyPhoto

/// 「作例・構図を重ねて撮る」を開くまでの流れ（`ComposeGuideLauncher`・2026-10-10 に撮影スポットの頁から切り出し、
/// 投稿のシートの入口と共通にした）と、撮る画面の枠・案内の札・撮る向き。
final class ComposeGuideLauncherTests: XCTestCase {

    private static func freeLaunch() -> ComposeGuide.Launch { ComposeGuide.Launch(sample: nil, samples: []) }

    // MARK: - 開く流れ（2026-10-17 判断: 全員無料）

    /// Pro でなくても・ログインしていなくても・圏外でも、押せば撮る画面へ進む。
    /// `open` は Pro もログインも受け取らない——Pro の確かめを戻すと、この呼び方が通らない
    @MainActor
    func testAnyoneOpensTheCamera() async {
        let launcher = ComposeGuideLauncher()
        var made = 0
        let outcome = launcher.open(make: { made += 1; return Self.freeLaunch() })
        XCTAssertEqual(outcome, .opened)
        XCTAssertNotNil(launcher.launch)
        XCTAssertEqual(launcher.launch?.samples.count, 0, "作例なしの入口")
        XCTAssertEqual(made, 1, "頼みは開く時点で1回だけ作る")
    }

    @MainActor
    func testDoesNotReopenWhileOpen() async {
        let launcher = ComposeGuideLauncher()
        launcher.open(make: Self.freeLaunch)
        let first = launcher.launch?.id
        XCTAssertNotNil(first)
        // 開いている間に2回目（素早い2回押し）→ 何もしない
        var made = 0
        let second = launcher.open(make: { made += 1; return Self.freeLaunch() })
        XCTAssertEqual(second, .ignored)
        XCTAssertEqual(made, 0)
        XCTAssertEqual(launcher.launch?.id, first)
        // 閉じたら、また開ける
        launcher.launch = nil
        XCTAssertEqual(launcher.open(make: Self.freeLaunch), .opened)
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
        let lines = try XCTUnwrap(view.range(of: "CompositionLines(kind: composition"))
        XCTAssertLessThan(preview.lowerBound, lines.lowerBound)
    }

    /// 傾き（30 回/秒）で撮る画面全体を描き直さない。裏に回ったら傾きの見張りも止める
    func testLevelDoesNotRedrawTheWholeScreenAndStopsInBackground() throws {
        let view = try source("Sources/JourneyPhoto/Features/Spots/ComposeGuideView.swift")
        XCTAssertTrue(view.contains("@State private var level = LevelMotion()"), "撮る画面が傾きを見張っている")
        XCTAssertFalse(view.contains("@StateObject private var level"), "撮る画面が傾きを見張っている")
        XCTAssertFalse(view.contains("level.degrees"), "撮る画面の本体が角度を読んでいる")
        let background = try XCTUnwrap(view.components(separatedBy: "} else if phase == .background {").dropFirst().first)
        XCTAssertTrue(background.prefix(300).contains("level.stop()"), "裏に回っても傾きの見張りが止まらない")
        let overlay = try source("Sources/JourneyPhoto/Features/Spots/CompositionOverlay.swift")
        XCTAssertTrue(overlay.contains("@ObservedObject var level: LevelMotion"), "線の子の View が傾きを見ていない")
    }

    /// 投稿のシートの4つ目「構図を重ねて撮る」は、Pro の確かめを通らずに作例なしで開く（2026-10-17 判断: 全員無料）
    func testPostSheetEntryOpensWithoutTheProCheck() throws {
        let sheet = try source("Sources/JourneyPhoto/Features/Upload/PostSheet.swift")
        XCTAssertTrue(sheet.contains("kind: .composition"))
        let root = try source("Sources/JourneyPhoto/App/RootView.swift")
        XCTAssertTrue(root.contains("case .composition:"))
        XCTAssertTrue(root.contains("composeLauncher.open(make: { ComposeGuide.Launch(sample: nil, samples: []) })"),
                      "作例なしで、そのまま開いていない")
        XCTAssertTrue(root.contains(".composeGuidePresenter(composeLauncher, spotName: nil,"))
        XCTAssertTrue(root.contains("onPost: { capture in pendingCapture = capture }"))
        XCTAssertTrue(root.contains("initialCapture: pendingCapture"), "撮った1枚を投稿画面へ渡していない")
        // 投稿のシートが閉じきってから開く（閉じている途中に全画面を重ねない）
        XCTAssertTrue(root.contains(".sheet(isPresented: $showPostChoice, onDismiss: postChoiceDismissed)"),
                      "投稿選択シートの閉じ完了ハンドラーを通していない")
        XCTAssertTrue(root.contains("private func postChoiceDismissed()"),
                      "投稿選択シートを閉じた後の処理がない")
        XCTAssertTrue(root.contains("if let kind = pendingPostChoice"),
                      "選択した投稿種別を閉じた後に処理していない")
        XCTAssertTrue(root.contains("openCompositionIfRequested()"),
                      "構図ガイドの要求を閉じた後に処理していない")
    }

    /// 2026-10-17 判断（owner）: 全員無料。**開く前にサーバーへ何も聞かない**（プロフィールの `pro` を読まない）・
    /// Pro の案内も「つながりません」の知らせも出さない。入口（投稿のシート・撮影スポット）も同じ
    func testOpeningDoesNotAskTheServerOrShowThePaywall() throws {
        let launcher = try source("Sources/JourneyPhoto/Features/Spots/ComposeGuideLauncher.swift")
        let code = launcher.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        for banned in ["myProfile", "isPro", "PaywallView", "showPaywall", "unreachable", "profiles", "StoreService",
                       "async"] {
            XCTAssertFalse(code.contains(banned), "開く流れに Pro の確かめ・問い合わせが戻っている: \(banned)")
        }
        XCTAssertTrue(code.contains("func open(make: () -> ComposeGuide.Launch) -> Outcome {"))
        let root = try source("Sources/JourneyPhoto/App/RootView.swift")
        let spot = try source("Sources/JourneyPhoto/Features/Spots/OfficialSpotView.swift")
        for (name, text) in [("RootView", root), ("OfficialSpotView", spot)] {
            XCTAssertFalse(text.contains("ComposeGuidePresenter.request"), "\(name) が Pro の流れを通している")
            XCTAssertFalse(text.contains("composeLauncher.checking"), "\(name) が確かめ中の回転を待っている")
        }
        XCTAssertTrue(spot.contains("composeLauncher.open(make: { ComposeGuide.Launch(sample: sample, samples: shownSamples) })"))
        // 撮影スポットの入口から PRO の札と「Pro の機能です」の読み上げを外した
        let entry = try XCTUnwrap(spot.components(separatedBy: "private var composeEntry: some View {").dropFirst().first)
        let card = try XCTUnwrap(entry.components(separatedBy: "private func sampleCreditLink").first)
        XCTAssertFalse(card.contains("Text(\"PRO\")"), "撮影スポットの入口に PRO の札が残っている")
        XCTAssertFalse(card.contains("Pro の機能"), "撮影スポットの入口に Pro の読み上げが残っている")
    }

    /// Pro の案内の利点から「作例を重ねて撮る」を外した（2026-10-17）。残りは3つで空にならない
    func testPaywallNoLongerSellsTheComposeGuide() {
        let titles = ProBenefit.all.map(\.title)
        XCTAssertEqual(titles, ["光と天気の知らせ", "電波なしで使える旅", "Pro マークと Pro 限定の章", "特別な乗車券"])
        XCTAssertFalse(ProBenefit.all.contains { $0.title.contains("重ねて撮る") || $0.body.contains("重ねて") })
    }

    func testPreviewLensIsOffWithoutTheLaunchArgument() {
        XCTAssertFalse(ComposeGuideAccess.previewUnlocked)
    }
}
