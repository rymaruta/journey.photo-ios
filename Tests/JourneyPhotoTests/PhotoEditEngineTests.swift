import XCTest
@testable import JourneyPhoto

/// 写真の編集エンジン（Phase 1）の純粋な層: レシピ・プリセット・フィルターの並び・履歴。
/// 本物の Core Image の見た目はここでは見ない（Mac の `PhotoRendererExportTests`）
final class PhotoRecipeTests: XCTestCase {

    private func roundTrip(_ recipe: PhotoRecipe) throws -> PhotoRecipe {
        try JSONDecoder().decode(PhotoRecipe.self, from: JSONEncoder().encode(recipe))
    }

    private func decode(_ json: String) throws -> PhotoRecipe {
        try JSONDecoder().decode(PhotoRecipe.self, from: Data(json.utf8))
    }

    func testCodableRoundTripKeepsEveryField() throws {
        let recipe = PhotoRecipe(exposure: 0.7, contrast: -0.3, saturation: 0.4, temperature: -0.6,
                                 highlights: -0.5, shadows: 0.2,
                                 preset: .init(id: "dusk", strength: 0.6))
        XCTAssertEqual(try roundTrip(recipe), recipe)
    }

    func testEncodesVersion() throws {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PhotoRecipe(exposure: 1))) as? [String: Any]
        XCTAssertEqual(object?["v"] as? Int, 1, "版番号 v を書く")
    }

    func testUnknownKeysAreIgnored() throws {
        let recipe = try decode(#"{"v":1,"exposure":0.5,"grain":0.3,"vignette":{"amount":1}}"#)
        XCTAssertEqual(recipe, PhotoRecipe(exposure: 0.5))
    }

    func testMissingVersionReadsAsFirstVersion() throws {
        XCTAssertEqual(try decode(#"{"contrast":0.25}"#), PhotoRecipe(contrast: 0.25))
    }

    func testNewerVersionReadsAsNoEdit() throws {
        let recipe = try decode(#"{"v":2,"exposure":1.5,"contrast":0.5}"#)
        XCTAssertEqual(recipe, .identity, "意味の変わったかもしれない値で焼かない")
    }

    func testBrokenValuesDoNotThrow() throws {
        let recipe = try decode(#"{"v":"one","exposure":"bright","contrast":9,"preset":{"strength":"x"}}"#)
        XCTAssertEqual(recipe, PhotoRecipe(contrast: 1), "型の違う値は 0、範囲外は収める、id の無いプリセットは外す")
        XCTAssertEqual(try decode("[]"), .identity, "器が違っても落ちない")
    }

    func testEncodingNaNDoesNotThrow() throws {
        let recipe = PhotoRecipe(exposure: .nan, contrast: .infinity)
        XCTAssertEqual(try roundTrip(recipe), .identity)
    }

    func testSanitizedClampsAndZeroesNaN() {
        let recipe = PhotoRecipe(exposure: 5, contrast: -3, saturation: .nan, temperature: 2,
                                 highlights: -.infinity, shadows: 0.5,
                                 preset: .init(id: "haze", strength: 4)).sanitized
        XCTAssertEqual(recipe.exposure, 2)
        XCTAssertEqual(recipe.contrast, -1)
        XCTAssertEqual(recipe.saturation, 0)
        XCTAssertEqual(recipe.temperature, 1)
        XCTAssertEqual(recipe.highlights, 0)
        XCTAssertEqual(recipe.shadows, 0.5)
        XCTAssertEqual(recipe.preset, .init(id: "haze", strength: 1))
        XCTAssertEqual(PhotoRecipe(exposure: -9).sanitized.exposure, -2)
    }

    func testSanitizedDropsUnknownPreset() {
        XCTAssertNil(PhotoRecipe(preset: .init(id: "no-such-film")).sanitized.preset)
        XCTAssertEqual(PhotoRecipe(preset: .init(id: "sumi", strength: .nan)).sanitized.preset,
                       .init(id: "sumi", strength: 0))
    }

    func testIsIdentity() {
        XCTAssertTrue(PhotoRecipe.identity.isIdentity)
        XCTAssertTrue(PhotoRecipe(exposure: .nan).isIdentity)
        XCTAssertTrue(PhotoRecipe(preset: .init(id: "sumi", strength: 0)).isIdentity)
        XCTAssertTrue(PhotoRecipe(preset: .init(id: "unknown", strength: 1)).isIdentity)
        XCTAssertFalse(PhotoRecipe(shadows: 0.1).isIdentity)
        XCTAssertFalse(PhotoRecipe(preset: .init(id: "sumi", strength: 0.1)).isIdentity)
    }
}

final class PhotoPresetsTests: XCTestCase {

    func testThereAreSixToEightPresetsWithUniqueIds() {
        XCTAssertTrue((6...8).contains(PhotoPresets.all.count))
        XCTAssertEqual(Set(PhotoPresets.all.map(\.id)).count, PhotoPresets.all.count)
        for preset in PhotoPresets.all {
            XCTAssertFalse(preset.nameJa.isEmpty)
            XCTAssertFalse(preset.nameEn.isEmpty)
            XCTAssertNotEqual(preset.adjustments, .identity, "\(preset.id) は何かを変える")
        }
    }

    func testMonochromePresetsAreFullyDesaturated() {
        for id in ["sumi", "silver"] {
            let adjustments = PhotoRecipePlan.resolve(PhotoRecipe(preset: .init(id: id, strength: 1)))
            XCTAssertEqual(adjustments.saturation, -1, id)
            XCTAssertEqual(PhotoRecipePlan.saturationAmount(adjustments.saturation), 0, "白黒は inputSaturation 0")
        }
    }

    func testStrengthZeroIsIdentity() {
        for preset in PhotoPresets.all {
            let recipe = PhotoRecipe(preset: .init(id: preset.id, strength: 0))
            XCTAssertEqual(PhotoRecipePlan.resolve(recipe), .identity, preset.id)
            XCTAssertEqual(PhotoRecipePlan.steps(for: recipe), [], preset.id)
        }
    }

    func testStrengthOneIsTheDefinition() {
        for preset in PhotoPresets.all {
            let resolved = PhotoRecipePlan.resolve(PhotoRecipe(preset: .init(id: preset.id, strength: 1)))
            XCTAssertEqual(resolved, preset.adjustments, preset.id)
        }
    }

    func testStrengthInterpolatesLinearly() {
        let dusk = PhotoPresets.preset(id: "dusk")!.adjustments
        let half = PhotoRecipePlan.resolve(PhotoRecipe(preset: .init(id: "dusk", strength: 0.5)))
        XCTAssertEqual(half.temperature, dusk.temperature / 2, accuracy: 1e-9)
        XCTAssertEqual(half.highlights, dusk.highlights / 2, accuracy: 1e-9)
        for (i, x) in PhotoToneCurve.xs.enumerated() {
            XCTAssertEqual(half.curve.ys[i], x + (dusk.curve.ys[i] - x) / 2, accuracy: 1e-9)
        }
    }

    func testSlidersAddOnTopOfPresetAndClamp() {
        let resolved = PhotoRecipePlan.resolve(PhotoRecipe(saturation: 0.9, temperature: -0.2,
                                                           preset: .init(id: "summer", strength: 1)))
        XCTAssertEqual(resolved.saturation, 1, "0.3 + 0.9 は 1 に収める")
        XCTAssertEqual(resolved.temperature, -0.05, accuracy: 1e-9)
    }

    func testToneCurveKeepsRising() {
        let curve = PhotoToneCurve(ys: [0.2, 0.1, 0.5, .nan, 3])
        XCTAssertEqual(curve.ys, [0.2, 0.2, 0.5, 0.75, 1], "下がる点は前の点にそろえ、NaN は無変更、幅に収める")
        XCTAssertEqual(PhotoToneCurve(ys: [0, 1]), .identity, "5点でなければ無変更")
    }
}

final class PhotoRecipePlanTests: XCTestCase {

    func testIdentityHasNoFilters() {
        XCTAssertEqual(PhotoRecipePlan.steps(for: .identity), [])
    }

    func testOrderOfFilters() {
        let recipe = PhotoRecipe(exposure: 0.5, contrast: 0.4, saturation: -0.2, temperature: 0.3,
                                 highlights: -0.4, shadows: 0.3, preset: .init(id: "haze", strength: 1))
        XCTAssertEqual(PhotoRecipePlan.steps(for: recipe).map(\.filter), [
            "CITemperatureAndTint", "CIExposureAdjust", "CIHighlightShadowAdjust",
            "CIColorControls", "CIToneCurve",
        ])
    }

    func testUnchangedItemsAreSkipped() {
        XCTAssertEqual(PhotoRecipePlan.steps(for: PhotoRecipe(exposure: 0.5)).map(\.filter), ["CIExposureAdjust"])
        XCTAssertEqual(PhotoRecipePlan.steps(for: PhotoRecipe(saturation: 0.3)).map(\.filter), ["CIColorControls"])
        XCTAssertEqual(PhotoRecipePlan.steps(for: PhotoRecipe(shadows: -0.3)).map(\.filter), ["CIHighlightShadowAdjust"])
        XCTAssertEqual(PhotoRecipePlan.steps(for: PhotoRecipe(temperature: -1)).map(\.filter), ["CITemperatureAndTint"])
        // ＋の highlights は CIHighlightShadowAdjust では作れないので、曲線の上を持ち上げる
        XCTAssertEqual(PhotoRecipePlan.steps(for: PhotoRecipe(highlights: 0.5)).map(\.filter), ["CIToneCurve"])
        XCTAssertEqual(PhotoRecipePlan.steps(for: PhotoRecipe(highlights: -0.5)).map(\.filter), ["CIHighlightShadowAdjust"])
        // プリセットの値をつまみで打ち消したら、その段は足さない
        XCTAssertEqual(PhotoRecipePlan.steps(for: PhotoRecipe(exposure: -0.2, saturation: -0.3, temperature: -0.15,
                                                              shadows: -0.25,
                                                              preset: .init(id: "summer", strength: 1))), [])
    }

    func testParameterMapping() {
        let steps = PhotoRecipePlan.steps(for: PhotoRecipe(exposure: 1.5, contrast: 1, saturation: -1,
                                                           temperature: 1, highlights: -1, shadows: 1))
        let byName = Dictionary(uniqueKeysWithValues: steps.map { ($0.filter, $0.parameters) })
        XCTAssertEqual(byName["CIExposureAdjust"]?["inputEV"], .number(1.5))
        XCTAssertEqual(byName["CIColorControls"]?["inputContrast"], .number(1.25))
        XCTAssertEqual(byName["CIColorControls"]?["inputSaturation"], .number(0))
        XCTAssertEqual(byName["CIColorControls"]?["inputBrightness"], .number(0))
        XCTAssertEqual(byName["CIHighlightShadowAdjust"]?["inputHighlightAmount"], .number(0.3), accuracy: 1e-9)
        XCTAssertEqual(byName["CIHighlightShadowAdjust"]?["inputShadowAmount"], .number(0.6), accuracy: 1e-9)
        XCTAssertEqual(byName["CITemperatureAndTint"]?["inputTargetNeutral"], .vector([6500, 0]))
        guard case .vector(let neutral)? = byName["CITemperatureAndTint"]?["inputNeutral"] else {
            return XCTFail("inputNeutral が無い")
        }
        XCTAssertGreaterThan(neutral[0], 6500, "暖かく = 高い K を申告する")
    }

    func testMappingIsGentle() {
        XCTAssertEqual(PhotoRecipePlan.contrastAmount(-1), 0.75)
        XCTAssertEqual(PhotoRecipePlan.saturationAmount(1), 1.5)
        XCTAssertEqual(PhotoRecipePlan.saturationAmount(0), 1)
        XCTAssertEqual(PhotoRecipePlan.highlightAmount(0.5), 1, "＋の側はこのフィルターでは動かさない")
        let warm = PhotoRecipePlan.neutralKelvin(temperature: 1)
        let cool = PhotoRecipePlan.neutralKelvin(temperature: -1)
        XCTAssertEqual(warm, 8783, accuracy: 5)
        XCTAssertEqual(cool, 5159, accuracy: 5)
        XCTAssertEqual(PhotoRecipePlan.neutralKelvin(temperature: 0), 6500, accuracy: 1e-6)
    }

    func testToneCurvePointsAreFixedX() {
        let steps = PhotoRecipePlan.steps(for: PhotoRecipe(preset: .init(id: "sumi", strength: 1)))
        let curve = steps.first { $0.filter == "CIToneCurve" }?.parameters
        XCTAssertEqual(curve?["inputPoint0"], .vector([0, 0]))
        XCTAssertEqual(curve?["inputPoint1"], .vector([0.25, 0.18]))
        XCTAssertEqual(curve?["inputPoint4"], .vector([1, 1]))
    }

    func testHighlightLiftStacksOnPresetCurve() {
        let steps = PhotoRecipePlan.steps(for: PhotoRecipe(highlights: 1, preset: .init(id: "haze", strength: 1)))
        let curve = steps.first { $0.filter == "CIToneCurve" }?.parameters
        // haze の 0.75 の点 0.76 + 0.06（haze に highlights は無い）
        XCTAssertEqual(curve?["inputPoint3"], .vector([0.75, 0.82]), accuracy: 1e-9)
        XCTAssertFalse(steps.contains { $0.filter == "CIHighlightShadowAdjust" })
    }
}

final class PhotoEditHistoryTests: XCTestCase {

    func testDraggingIsOneStep() {
        var history = PhotoEditHistory()
        for value in stride(from: 0.1, through: 1.0, by: 0.1) {
            history.preview(PhotoRecipe(exposure: value))
        }
        history.commit()
        XCTAssertEqual(history.undoStack.count, 1, "途中の値は積まない")
        history.undo()
        XCTAssertEqual(history.current, .identity)
        XCTAssertFalse(history.canUndo)
    }

    func testCommitWithoutChangeAddsNothing() {
        var history = PhotoEditHistory()
        history.commit()
        history.preview(.identity)
        history.commit()
        XCTAssertEqual(history.undoStack.count, 0)
    }

    func testUndoRedo() {
        var history = PhotoEditHistory()
        history.apply(PhotoRecipe(contrast: 0.2))
        history.apply(PhotoRecipe(contrast: 0.2, saturation: 0.4))
        history.undo()
        XCTAssertEqual(history.current, PhotoRecipe(contrast: 0.2))
        XCTAssertTrue(history.canRedo)
        history.redo()
        XCTAssertEqual(history.current, PhotoRecipe(contrast: 0.2, saturation: 0.4))
        history.undo()
        history.apply(PhotoRecipe(shadows: 0.1))
        XCTAssertFalse(history.canRedo, "新しい手を打ったらやり直しは消える")
    }

    func testUndoWhileDraggingCommitsFirst() {
        var history = PhotoEditHistory()
        history.apply(PhotoRecipe(exposure: 0.5))
        history.preview(PhotoRecipe(exposure: 1))
        history.undo()
        XCTAssertEqual(history.current, PhotoRecipe(exposure: 0.5), "途中の値を捨てて1つ前へ")
        history.redo()
        XCTAssertEqual(history.current, PhotoRecipe(exposure: 1), "やり直しで途中の値に戻れる")
    }

    func testLimitIsFifty() {
        var history = PhotoEditHistory()
        for i in 1...60 {
            history.apply(PhotoRecipe(exposure: Double(i) / 100))
        }
        XCTAssertEqual(history.undoStack.count, PhotoEditHistory.limit)
        for _ in 0..<60 { history.undo() }
        XCTAssertEqual(history.current, PhotoRecipe(exposure: 0.1), "古い10手は捨てた")
    }

    func testResetIsOneUndoableStep() {
        var history = PhotoEditHistory(original: PhotoRecipe(saturation: 0.3))
        history.apply(PhotoRecipe(saturation: 0.3, shadows: 0.2))
        XCTAssertTrue(history.canReset)
        history.reset()
        XCTAssertEqual(history.current, .identity)
        XCTAssertFalse(history.canReset)
        XCTAssertEqual(history.undoStack.count, 2, "リセットはその場で1手になる")
        XCTAssertEqual(history.committed, .identity)
        history.undo()
        XCTAssertEqual(history.current, PhotoRecipe(saturation: 0.3, shadows: 0.2))
    }

    func testCompareShowsOriginalWithoutTouchingHistory() {
        var history = PhotoEditHistory(original: PhotoRecipe(temperature: 0.2))
        history.apply(PhotoRecipe(temperature: 0.8))
        history.setComparing(true)
        XCTAssertEqual(history.displayed, PhotoRecipe(temperature: 0.2))
        XCTAssertEqual(history.current, PhotoRecipe(temperature: 0.8))
        history.setComparing(false)
        XCTAssertEqual(history.displayed, PhotoRecipe(temperature: 0.8))
        XCTAssertTrue(history.hasChanges)
        XCTAssertEqual(history.undoStack.count, 1)
    }
}

private func XCTAssertEqual(_ value: PhotoRecipePlan.Value?, _ expected: PhotoRecipePlan.Value,
                            accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    switch (value, expected) {
    case (.number(let a)?, .number(let b)):
        XCTAssertEqual(a, b, accuracy: accuracy, file: file, line: line)
    case (.vector(let a)?, .vector(let b)) where a.count == b.count:
        for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: accuracy, file: file, line: line) }
    default:
        XCTFail("\(String(describing: value)) != \(expected)", file: file, line: line)
    }
}
