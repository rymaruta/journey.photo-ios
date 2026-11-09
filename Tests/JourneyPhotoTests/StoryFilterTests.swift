import XCTest
@testable import JourneyPhoto

/// ストーリーのフィルター（2026-11-09 owner「ストーリーをインスタと遜色なく」の第1弾・段 2a は写真）。
/// 一覧・強さ・選びの読み書き（壊れた値・古い下書きで落ちない）・下書きへの保存・焼き込みと画面の配線。
/// Core Image の描画の本物（色・速さ）は Mac の CI と実機で確かめる。
@MainActor
final class StoryFilterTests: XCTestCase {

    // MARK: - 一覧

    /// 約10種。id は重ならず、名前は日本語中心（英語も持つ）。「なし」は一覧に含めない（列の先頭は画面が足す）
    func testListShape() {
        let all = StoryFilters.all
        XCTAssertTrue((10...12).contains(all.count), "約10種でない: \(all.count)")
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "id が重なっている")
        XCTAssertFalse(all.contains { $0.id == StoryFilterChoice.noneId }, "「なし」が一覧に入っている")
        for filter in all {
            XCTAssertFalse(filter.nameJa.isEmpty)
            XCTAssertFalse(filter.nameEn.isEmpty)
            XCTAssertTrue(filter.nameJa.unicodeScalars.contains { $0.value > 0x2FFF }, "\(filter.id) の名前が日本語でない")
            XCTAssertFalse(filter.recipe.isIdentity, "\(filter.id) は何も変えない")
        }
    }

    /// 写真の編集のプリセットを使い回すものは、実在する id を指す。写真の編集の一覧は増やさない
    func testReusedPresetsExistAndEditListIsUntouched() {
        let reused = StoryFilters.all.compactMap { $0.recipe.preset?.id }
        XCTAssertGreaterThanOrEqual(reused.count, 6)
        for id in reused {
            XCTAssertNotNil(PhotoPresets.preset(id: id), "\(id) が写真の編集のプリセットに無い")
        }
        XCTAssertTrue((6...8).contains(PhotoPresets.all.count), "写真の編集のプリセットを増やした（画面は 6〜8 を前提）")
    }

    /// 禁止の言い回しを名前に使わない
    func testNamesAvoidBannedWords() {
        for filter in StoryFilters.all {
            for banned in ["撮りどき", "捨", "注目スポット", "撮影地ガイド", "ガイドを見る", "この場所"] {
                XCTAssertFalse(filter.nameJa.contains(banned))
            }
        }
    }

    // MARK: - 強さ

    /// 強さ 0 は無編集、強さ 1 はそのまま、間は線形（つまみの値もプリセットの強さも）
    func testStrengthScalesEveryFilter() throws {
        for filter in StoryFilters.all {
            XCTAssertTrue(filter.recipe(strength: 0).isIdentity, "\(filter.id) は強さ 0 でも変わる")
            XCTAssertEqual(filter.recipe(strength: 1), filter.recipe, "\(filter.id) の強さ 1 が元と違う")
        }
        let vivid = try XCTUnwrap(StoryFilters.filter(id: "story-vivid"))
        XCTAssertEqual(vivid.recipe(strength: 0.5).saturation, vivid.recipe.saturation * 0.5, accuracy: 1e-9)
        let dusk = try XCTUnwrap(StoryFilters.filter(id: "dusk"))
        XCTAssertEqual(try XCTUnwrap(dusk.recipe(strength: 0.4).preset).strength, 0.4, accuracy: 1e-9)
        // 幅の外・NaN
        XCTAssertEqual(vivid.recipe(strength: 9), vivid.recipe)
        XCTAssertTrue(vivid.recipe(strength: -3).isIdentity)
        XCTAssertTrue(vivid.recipe(strength: .nan).isIdentity, "NaN の強さで色が壊れる")
    }

    // MARK: - 選び

    func testChoiceOffAndUnknown() {
        XCTAssertTrue(StoryFilterChoice.off.isNone)
        XCTAssertTrue(StoryFilterChoice.off.recipe.isIdentity)
        XCTAssertEqual(StoryFilterChoice(id: "no-such-filter").sanitized, .off, "知らない id が「なし」にならない")
        XCTAssertTrue(StoryFilterChoice(id: "no-such-filter").recipe.isIdentity)
        XCTAssertFalse(StoryFilterChoice(id: "dusk").isNone)
        XCTAssertTrue(StoryFilterChoice(id: "dusk", strength: 0).isNone, "強さ 0 は何も変えない")
    }

    /// 選び直したら強さは 1 に戻る（前のフィルターの強さを引き継がない）。つまみは 0.05 刻み
    func testSelectingAndStrengthSteps() {
        var choice = StoryFilterChoice(id: "dusk", strength: 0.3)
        choice = choice.selecting("harbor")
        XCTAssertEqual(choice.id, "harbor")
        XCTAssertEqual(choice.strength, 1)
        XCTAssertEqual(choice.selecting(StoryFilterChoice.noneId), .off)
        XCTAssertEqual(choice.selecting("no-such-filter"), .off)
        XCTAssertEqual(choice.withStrength(0.62).strength, 0.6, accuracy: 1e-9)
        XCTAssertEqual(choice.withStrength(0.63).strength, 0.65, accuracy: 1e-9)
        XCTAssertEqual(choice.withStrength(7).strength, 1)
        XCTAssertEqual(choice.withStrength(-1).strength, 0)
        XCTAssertEqual(choice.withStrength(.nan), choice, "NaN で選びが壊れる")
    }

    // MARK: - 読み書き

    func testChoiceRoundTrip() throws {
        let choice = StoryFilterChoice(id: "story-mono", strength: 0.75)
        let data = try JSONEncoder().encode(choice)
        XCTAssertEqual(try JSONDecoder().decode(StoryFilterChoice.self, from: data), choice)
    }

    /// 壊れた値・欠けた鍵・知らない id・幅の外で**落ちない**（古い下書きを壊さない）
    func testChoiceDecodingNeverThrows() throws {
        func decode(_ json: String) throws -> StoryFilterChoice {
            try JSONDecoder().decode(StoryFilterChoice.self, from: Data(json.utf8))
        }
        XCTAssertEqual(try decode("{}"), .off)
        XCTAssertEqual(try decode(#"{"id":"gone"}"#), .off)
        XCTAssertEqual(try decode(#"{"id":7,"strength":"x"}"#), .off)
        XCTAssertEqual(try decode(#"{"id":"dusk"}"#), StoryFilterChoice(id: "dusk", strength: 1), "強さが無ければ 1")
        XCTAssertEqual(try decode(#"{"id":"dusk","strength":2.5}"#).strength, 1, "幅の外を収めていない")
        XCTAssertEqual(try decode(#"{"id":"dusk","strength":-1}"#).strength, 0)
        XCTAssertEqual(try decode("[]"), .off)
    }

    // MARK: - 下書き

    /// 古い下書き（フィルターの鍵が無い）はそのまま読め、フィルターは nil（なし）
    func testOldDraftShotWithoutFilterStillDecodes() throws {
        let json = #"{"imageFile":"a","fileName":"a.jpg","contentType":"image/jpeg","overlays":[]}"#
        let shot = try JSONDecoder().decode(StoryDraftStore.Shot.self, from: Data(json.utf8))
        XCTAssertNil(shot.filter)
        let encoded = try JSONEncoder().encode(shot)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("filter"), "かけていないのに鍵を書いている")
    }

    /// 並びの写真ごとに、フィルターを残して戻す。かけていない写真は nil
    func testDraftKeepsTheFilterPerShot() throws {
        let suite = UserDefaults(suiteName: "story-filter-\(UUID().uuidString)")!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("story-filter-\(UUID().uuidString)")
        let store = StoryDraftStore(defaults: suite, directory: dir)
        store.use(userId: "u1")
        let shot = { (n: String, filter: StoryFilterChoice) in
            StoryDraftStore.ShotInput(imageData: Data(n.utf8), fileName: "\(n).jpg", contentType: "image/jpeg",
                                      coords: nil, overlays: [], filter: filter)
        }
        XCTAssertTrue(store.save(shots: [shot("a", StoryFilterChoice(id: "dusk", strength: 0.5)),
                                         shot("b", .off),
                                         shot("c", StoryFilterChoice(id: "story-mono"))],
                                 caption: "", location: "", song: nil, durationSec: 7,
                                 savedAt: "2026-11-09T10:00:00.000Z"))
        let reopened = StoryDraftStore(defaults: suite, directory: dir)
        reopened.use(userId: "u1")
        XCTAssertEqual(reopened.shotImages().map(\.shot.filter),
                       [StoryFilterChoice(id: "dusk", strength: 0.5), nil, StoryFilterChoice(id: "story-mono")])
    }

    // MARK: - 画面と焼き込みの配線（ソース）

    private func repo(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 焼き込みは写真の画素にだけ当て、文字・札は上に重ねる。当てなかった写真は元のデータをそのまま返す
    func testBurnAppliesTheFilterToThePhotoOnly() throws {
        let renderer = try repo("Sources/JourneyPhoto/Services/TextOverlayRenderer.swift")
        XCTAssertTrue(renderer.contains("filter: StoryFilterChoice = .off,"), "焼き込みがフィルターを受けない")
        XCTAssertTrue(renderer.contains("!visible.isEmpty || !framing.isIdentity || !recipe.isIdentity"),
                      "フィルターだけの写真が焼き込みを飛ばされる")
        XCTAssertTrue(renderer.contains("StoryFilterRenderer.image(data: data, recipe: recipe, maxPixelSize: ImagePreparer.maxPixelSize)"))
        XCTAssertTrue(renderer.contains("            ?? original"), "当てられなかったとき元の絵で出さない")
        // 文字は当てた絵のあとに描く
        let burnBody = try XCTUnwrap(renderer.components(separatedBy: "static func burn(").dropFirst().first?
            .components(separatedBy: "static func draw(").first)
        let drawImage = try XCTUnwrap(burnBody.range(of: "image.draw(in:"))
        let drawText = try XCTUnwrap(burnBody.range(of: "draw(overlay, on: size"))
        XCTAssertLessThan(drawImage.lowerBound, drawText.lowerBound)
    }

    func testComposerWiresTheFilter() throws {
        let composer = try repo("Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(composer.contains("song: songArt, filter: shot.filter),"), "投稿の焼き込みにフィルターを渡していない")
        XCTAssertTrue(composer.contains("vote: shot.vote,\n                                      filter: shot.filter)"), "下書きにフィルターを書いていない")
        XCTAssertTrue(composer.contains("filter: (item.shot.filter ?? StoryFilterChoice.off).sanitized)"), "下書きからフィルターを戻していない")
        XCTAssertTrue(composer.contains("filters: shots.map(\\.filter))"), "フィルターを変えても「変更あり」にならない")
        XCTAssertTrue(composer.contains("shots.indices.contains(current) ? shots[current].shownPreview : nil"),
                      "作る画面がフィルターをかけた絵を出さない")
        XCTAssertFalse(composer.contains("if currentClip == nil { filterButton }"), "動画（段 2b）にフィルターの口が出ない")
        XCTAssertTrue(composer.contains("                    filterButton\n                    drawButton\n                    moreMenu"))
        XCTAssertTrue(composer.contains("if !votePanelOpen && !sidePanelOpen {"), "欄を開いても足元が隠れない")
        // `Optional.none` と取り違える書き方を持ち込まない
        XCTAssertFalse(composer.contains("?? .none"))
    }

    func testPanelTargetsAndAccessibility() throws {
        let panel = try repo("Sources/JourneyPhoto/Features/Stories/StoryFilterPanel.swift")
        XCTAssertTrue(panel.contains(".accessibilityValue(selected ? L(\"選択中\", \"Selected\") : \"\")"), "選びを読み上げない")
        XCTAssertTrue(panel.contains("strokeBorder(WebTheme.accent, lineWidth: 2)"), "選びを形（輪）で伝えていない")
        XCTAssertTrue(panel.contains(".frame(minHeight: WebTheme.minTapTarget)"), "強さの行が 44 でない")
        XCTAssertTrue(panel.contains(".sensoryFeedback(.selection, trigger: selectedId)"), "選んだときの触覚が無い")
        XCTAssertFalse(panel.contains(".system(size:"), "固定の大きさの文字")
        XCTAssertFalse(panel.contains("捨"))
    }
}
