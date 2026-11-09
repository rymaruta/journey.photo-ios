import XCTest
@testable import JourneyPhoto

/// ストーリーの描画（ペン・蛍光ペン・消しゴム・取り消し/やり直し・2026-11-09 owner「ストーリーをインスタと遜色なく」の第1弾）。
/// 線のデータ・上限・壊れた値の読み・下書きへの保存・描く判断（点を足す・上限）・座標の変換と、
/// 画面と焼き込みの配線（札を掴まない・当たり 44・読み上げ）。
/// `Canvas` と Core Graphics の描画の本物は Mac の CI と実機で確かめる。
@MainActor
final class StoryDrawingTests: XCTestCase {

    private func stroke(_ tool: StoryPenTool = .pen, points: Int = 3, hex: UInt32 = 0xFFFFFF) -> StoryStroke {
        StoryStroke(tool: tool, hex: hex, width: tool.defaultWidth,
                    points: (0..<points).map { StoryStrokePoint(x: Double($0) / 10, y: 0.5) })
    }

    // MARK: - 筆・色

    func testPaletteHasTwelveDistinctColors() async {
        let palette = StoryPen.palette
        XCTAssertEqual(palette.count, 12)
        XCTAssertEqual(Set(palette.map(\.hex)).count, 12, "色が重なっている")
        XCTAssertEqual(palette.first?.hex, 0xFFFFFF, "先頭が白でない（既定の色）")
        for swatch in palette {
            XCTAssertLessThanOrEqual(swatch.hex, 0xFFFFFF)
            XCTAssertFalse(swatch.nameJa.isEmpty)
            XCTAssertFalse(swatch.nameEn.isEmpty)
        }
    }

    func testToolsHaveSaneWidthsAndOpacity() async {
        for tool in StoryPenTool.allCases {
            XCTAssertTrue(tool.widthRange.contains(tool.defaultWidth), "\(tool) の既定の太さが幅の外")
            XCTAssertFalse(tool.label.isEmpty)
            XCTAssertFalse(tool.symbol.isEmpty)
        }
        XCTAssertLessThan(StoryPenTool.highlighter.opacity, 1, "蛍光ペンが半透明でない")
        XCTAssertEqual(StoryPenTool.pen.opacity, 1)
        XCTAssertGreaterThan(StoryPenTool.highlighter.defaultWidth, StoryPenTool.pen.defaultWidth, "蛍光ペンがペンより細い")
    }

    /// 太さ・色は筆の幅・24bit に収める
    func testStrokeClampsWidthAndColor() async {
        let thick = StoryStroke(tool: .pen, hex: 0xFFFF_FFFF, width: 9, points: [StoryStrokePoint(x: 0, y: 0)])
        XCTAssertEqual(thick.width, StoryPenTool.pen.widthRange.upperBound)
        XCTAssertEqual(thick.hex, 0xFFFFFF)
        let thin = StoryStroke(tool: .eraser, hex: 0, width: -1, points: [])
        XCTAssertEqual(thin.width, StoryPenTool.eraser.widthRange.lowerBound)
        XCTAssertEqual(StoryStroke(tool: .pen, hex: 0, width: .nan, points: []).width, StoryPenTool.pen.defaultWidth)
        XCTAssertTrue(stroke(points: 1).isDot)
        XCTAssertFalse(stroke(points: 2).isDot)
    }

    /// 筆ごとの太さを覚える。つまみ（0…1）と太さの変換が往復する
    func testPenRemembersWidthPerTool() async {
        var pen = StoryPen()
        XCTAssertEqual(pen.tool, .pen)
        XCTAssertEqual(pen.colorHex, 0xFFFFFF)
        XCTAssertEqual(pen.width, StoryPenTool.pen.defaultWidth)
        pen.setWidth(0.03)
        pen.tool = .highlighter
        XCTAssertEqual(pen.width, StoryPenTool.highlighter.defaultWidth, "筆を替えたら前の筆の太さが付いてくる")
        pen.setWidth(0.07)
        pen.tool = .pen
        XCTAssertEqual(pen.width, 0.03, accuracy: 1e-9, "ペンの太さを覚えていない")
        pen.tool = .highlighter
        XCTAssertEqual(pen.width, 0.07, accuracy: 1e-9)
        // 幅の外・NaN
        pen.setWidth(5)
        XCTAssertEqual(pen.width, StoryPenTool.highlighter.widthRange.upperBound)
        pen.setWidth(fraction: 0)
        XCTAssertEqual(pen.width, StoryPenTool.highlighter.widthRange.lowerBound, accuracy: 1e-9)
        pen.setWidth(fraction: 1)
        XCTAssertEqual(pen.widthFraction, 1, accuracy: 1e-9)
        pen.setWidth(fraction: 0.5)
        XCTAssertEqual(pen.widthFraction, 0.5, accuracy: 1e-9)
        let before = pen.width
        pen.setWidth(fraction: .nan)
        XCTAssertEqual(pen.width, before, "NaN で太さが壊れる")
    }

    func testBeginStrokeUsesThePen() async {
        var pen = StoryPen()
        pen.tool = .highlighter
        pen.colorHex = 0xFFD93D
        let begun = pen.beginStroke(at: StoryStrokePoint(x: 0.2, y: 0.8))
        XCTAssertEqual(begun.tool, .highlighter)
        XCTAssertEqual(begun.hex, 0xFFD93D)
        XCTAssertEqual(begun.width, pen.width)
        XCTAssertEqual(begun.points, [StoryStrokePoint(x: 0.2, y: 0.8)])
    }

    // MARK: - 取り消し・やり直し・上限

    func testUndoRedo() async {
        var drawing = StoryDrawing()
        XCTAssertFalse(drawing.canUndo)
        XCTAssertFalse(drawing.canRedo)
        let a = stroke(), b = stroke(.highlighter), c = stroke(.eraser)
        XCTAssertTrue(drawing.add(a))
        XCTAssertTrue(drawing.add(b))
        XCTAssertTrue(drawing.add(c))
        XCTAssertEqual(drawing.strokes, [a, b, c])
        drawing.undo()
        XCTAssertEqual(drawing.strokes, [a, b], "最後の1本が戻っていない")
        XCTAssertTrue(drawing.canRedo)
        drawing.undo()
        drawing.redo()
        XCTAssertEqual(drawing.strokes, [a, b], "やり直しが逆順でない")
        // 新しく描いたら、やり直しの分は消える
        XCTAssertTrue(drawing.add(stroke(points: 2)))
        XCTAssertFalse(drawing.canRedo, "新しい線のあとにやり直しが残っている")
        // 空で取り消し・やり直しても壊れない
        var empty = StoryDrawing()
        empty.undo()
        empty.redo()
        XCTAssertTrue(empty.isEmpty)
        drawing.clear()
        XCTAssertTrue(drawing.isEmpty)
        XCTAssertFalse(drawing.canRedo)
    }

    /// 目に見える線: 消しゴムだけ・全部取り消した後は焼き込み・書き出しで何も描かない
    func testHasInk() async {
        var drawing = StoryDrawing()
        XCTAssertFalse(drawing.hasInk)
        drawing.add(stroke(.eraser))
        XCTAssertFalse(drawing.hasInk, "消しゴムだけの描画が線ありになっている")
        drawing.add(stroke(.pen))
        XCTAssertTrue(drawing.hasInk)
        drawing.undo()
        XCTAssertFalse(drawing.hasInk)
    }

    /// 比べるのは線だけ（やり直しの控えは「変更あり」に数えない）
    func testEqualityIgnoresTheRedoStack() async {
        var a = StoryDrawing(), b = StoryDrawing()
        a.add(stroke())
        b.add(stroke())
        let s = stroke(points: 2)
        a.add(s)
        a.undo()
        XCTAssertTrue(a.canRedo)
        XCTAssertNotEqual(a, b, "別の線の並びが等しい")   // 線の id が違う
        var c = StoryDrawing()
        let shared = stroke()
        c.add(shared)
        var d = c
        d.add(stroke(points: 2))
        d.undo()
        XCTAssertEqual(c, d, "やり直しの控えが「変更あり」になる")
    }

    func testLimits() async {
        var drawing = StoryDrawing()
        // 1本の長さ
        let tooLong = StoryStroke(tool: .pen, hex: 0, width: 0.01,
                                  points: (0..<(StoryDrawing.maxPointsPerStroke + 1)).map { StoryStrokePoint(x: Double($0) / 3000, y: 0) })
        XCTAssertFalse(drawing.add(tooLong), "長すぎる1本を足している")
        XCTAssertFalse(drawing.add(StoryStroke(tool: .pen, hex: 0, width: 0.01, points: [])), "点の無い1本を足している")
        // 本数
        for _ in 0..<StoryDrawing.maxStrokes { XCTAssertTrue(drawing.add(stroke(points: 2))) }
        XCTAssertFalse(drawing.add(stroke(points: 2)), "本数の上限を超えている")
        // 点の総数（1枚）
        var many = StoryDrawing()
        let long = { (n: Int) in StoryStroke(tool: .pen, hex: 0, width: 0.01, points: (0..<n).map { StoryStrokePoint(x: Double($0) / 2000, y: 0) }) }
        for _ in 0..<(StoryDrawing.maxTotalPoints / 1000 - 1) { XCTAssertTrue(many.add(long(1000))) }
        let left = StoryDrawing.maxTotalPoints - many.totalPoints
        XCTAssertFalse(many.add(long(left + 1)), "点の総数の上限を超えている")
        XCTAssertTrue(many.add(long(left)))
        XCTAssertEqual(many.totalPoints, StoryDrawing.maxTotalPoints)
        XCTAssertEqual(many.remainingPoints(forStrokeWith: 1), 0)
        XCTAssertEqual(StoryDrawing().remainingPoints(forStrokeWith: 100), StoryDrawing.maxPointsPerStroke - 100)
    }

    /// 下書きは UserDefaults に JSON で入るので、**並び全体**の点・本数に上限を持つ。最大サイズは上限から出る
    func testSequenceLimitKeepsTheDraftSmall() async throws {
        XCTAssertLessThanOrEqual(StoryDrawing.maxSequencePoints, StoryDrawing.maxTotalPoints)
        // ほかの写真が上限まで持っていれば、この写真はもう描けない
        let others = (strokes: 10, points: StoryDrawing.maxSequencePoints)
        XCTAssertEqual(StoryDrawing().remainingPoints(forStrokeWith: 1, others: others), 0)
        XCTAssertEqual(StoryStrokeInput.step(live: nil, last: nil, location: CGPoint(x: 10, y: 10),
                                             photo: CGRect(x: 0, y: 0, width: 400, height: 800),
                                             drawing: StoryDrawing(), others: others), .limit)
        XCTAssertFalse(StoryDrawing().canStartStroke(others: (strokes: StoryDrawing.maxSequenceStrokes, points: 0)))
        // 最大に描いた1件のサイズ: 点 16B × 上限 + 1本 110B × 本数上限 が約 130KB に収まる（UserDefaults に入れてよい重さ）
        var drawing = StoryDrawing()
        for _ in 0..<(StoryDrawing.maxSequencePoints / 20) {
            drawing.add(StoryStroke(tool: .pen, hex: 0xFFFFFF, width: 0.01,
                                    points: (0..<20).map { StoryStrokePoint(x: 0.1234 + Double($0) / 1000, y: 0.5678) }))
        }
        let bytes = try JSONEncoder().encode(drawing).count
        XCTAssertLessThan(bytes, 200_000, "並び全体の描画が重い: \(bytes)B")
    }

    // MARK: - 読み書き

    func testRoundTripKeepsStrokesNotTheRedoStack() async throws {
        var drawing = StoryDrawing()
        drawing.add(stroke(.pen, hex: 0xFF5A5F))
        drawing.add(stroke(.eraser))
        drawing.add(stroke(.highlighter))
        drawing.undo()                           // やり直しの控えは書かない
        let data = try JSONEncoder().encode(drawing)
        let decoded = try JSONDecoder().decode(StoryDrawing.self, from: data)
        XCTAssertEqual(decoded.strokes, drawing.strokes)
        XCTAssertFalse(decoded.canRedo, "やり直しの控えを書いている")
    }

    /// 点は `[x, y]` の2つ組で書く（下書きを小さく保つ）
    func testPointsEncodeCompactly() async throws {
        let data = try JSONEncoder().encode(StoryStroke(tool: .pen, hex: 0xFFFFFF, width: 0.01,
                                                         points: [StoryStrokePoint(x: 0.1, y: 0.2)]))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("[[0.1,0.2]]"), text)
    }

    /// 壊れた値・欠けた鍵・知らない筆・幅の外で**落ちない**（古い下書きを壊さない）
    func testDecodingNeverThrowsAndDropsBrokenStrokes() async throws {
        func decode(_ json: String) throws -> StoryDrawing {
            try JSONDecoder().decode(StoryDrawing.self, from: Data(json.utf8))
        }
        XCTAssertTrue(try decode("{}").isEmpty)
        XCTAssertTrue(try decode("[]").isEmpty)
        XCTAssertTrue(try decode(#"{"strokes":"x"}"#).isEmpty)
        // 壊れた1本（点が文字・全体が数）だけ外れ、ほかは読める
        let json = """
        {"strokes":[
          {"tool":"pen","hex":16711680,"width":0.02,"points":[[0.1,0.2],[0.3,0.4]]},
          42,
          {"tool":"pen","points":"oops"},
          {"tool":"highlighter","hex":255,"width":0.04,"points":[[0.5,0.5]]}
        ]}
        """
        let drawing = try decode(json)
        XCTAssertEqual(drawing.strokes.count, 2, "壊れた1本で全部を読めなくしている")
        XCTAssertEqual(drawing.strokes[0].hex, 0xFF0000)
        XCTAssertEqual(drawing.strokes[1].tool, .highlighter)
        XCTAssertTrue(drawing.strokes[1].isDot)
    }

    func testDecodingFillsDefaultsAndClamps() async throws {
        let json = """
        {"strokes":[{"tool":"laser","points":[[0.1,0.1],[5,5],[0.2,0.2]],"width":99}]}
        """
        let stroke = try XCTUnwrap(try JSONDecoder().decode(StoryDrawing.self, from: Data(json.utf8)).strokes.first)
        XCTAssertEqual(stroke.tool, .pen, "知らない筆がペンにならない")
        XCTAssertEqual(stroke.hex, 0xFFFFFF, "色が無ければ白")
        XCTAssertEqual(stroke.width, StoryPenTool.pen.widthRange.upperBound, "太さを幅に収めていない")
        XCTAssertEqual(stroke.points.count, 3)
        XCTAssertEqual(stroke.points[1], StoryStrokePoint(x: 1.5, y: 1.5), "写真の外の点を収めていない")
    }

    /// 上限を超えた下書きは、超えたぶんを読まない
    func testDecodingRespectsLimits() async throws {
        let one = #"{"tool":"pen","points":[[0.1,0.1],[0.2,0.2]]}"#
        let json = #"{"strokes":["# + Array(repeating: one, count: StoryDrawing.maxStrokes + 20).joined(separator: ",") + "]}"
        let drawing = try JSONDecoder().decode(StoryDrawing.self, from: Data(json.utf8))
        XCTAssertEqual(drawing.strokes.count, StoryDrawing.maxStrokes)
    }

    // MARK: - 下書き

    func testDraftKeepsTheDrawingPerShot() async throws {
        let suite = UserDefaults(suiteName: "story-draw-\(UUID().uuidString)")!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("story-draw-\(UUID().uuidString)")
        let store = StoryDraftStore(defaults: suite, directory: dir)
        store.use(userId: "u1")
        var drawn = StoryDrawing()
        drawn.add(stroke(.pen, hex: 0x4DA3FF))
        drawn.add(stroke(.eraser))
        var eraserOnly = StoryDrawing()
        eraserOnly.add(stroke(.eraser))
        let shot = { (n: String, drawing: StoryDrawing) in
            StoryDraftStore.ShotInput(imageData: Data(n.utf8), fileName: "\(n).jpg", contentType: "image/jpeg",
                                      coords: nil, overlays: [], drawing: drawing)
        }
        XCTAssertTrue(store.save(shots: [shot("a", drawn), shot("b", StoryDrawing()), shot("c", eraserOnly)],
                                 caption: "", location: "", song: nil, durationSec: 7,
                                 savedAt: "2026-11-09T10:00:00.000Z"))
        let reopened = StoryDraftStore(defaults: suite, directory: dir)
        reopened.use(userId: "u1")
        let restored = reopened.shotImages().map(\.shot.drawing)
        XCTAssertEqual(restored.count, 3)
        XCTAssertEqual(restored[0]?.strokes, drawn.strokes, "描いた線が戻らない")
        XCTAssertNil(restored[1], "描いていない写真に空の描画を書いている")
        XCTAssertNil(restored[2], "線が見えない描画（消しゴムだけ）を書いている")
    }

    /// 複製・開き直しで描画が残る
    func testDuplicateKeepsTheDrawing() async throws {
        let suite = UserDefaults(suiteName: "story-draw-dup-\(UUID().uuidString)")!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("story-draw-dup-\(UUID().uuidString)")
        let id = UUID().uuidString
        let store = StoryDraftStore(defaults: suite, directory: dir, slot: .entry(id))
        store.bind(userId: "a")
        var drawn = StoryDrawing()
        drawn.add(stroke(.pen, hex: 0x4DA3FF))
        XCTAssertTrue(store.save(
            shots: [StoryDraftStore.ShotInput(imageData: Data([1, 2, 3]), fileName: "s.jpg", contentType: "image/jpeg",
                                              coords: nil, overlays: [], drawing: drawn)],
            caption: "", location: "", song: nil, durationSec: 5, savedAt: "2026-11-09T10:00:00.000Z"))
        let lib = DraftLibrary(defaults: suite, directory: dir)
        let copy = try XCTUnwrap(lib.duplicate(id, kind: .story, for: "a"))
        lib.remove(id, for: "a")
        let reopened = StoryDraftStore(defaults: suite, directory: dir, slot: .entry(copy))
        reopened.bind(userId: "a")
        XCTAssertEqual(reopened.shotImages().first?.shot.drawing?.strokes, drawn.strokes, "複製が描画を落とした")
    }

    func testOldDraftShotWithoutDrawingStillDecodes() async throws {
        let json = #"{"imageFile":"a","fileName":"a.jpg","contentType":"image/jpeg","overlays":[]}"#
        let shot = try JSONDecoder().decode(StoryDraftStore.Shot.self, from: Data(json.utf8))
        XCTAssertNil(shot.drawing)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(shot), as: UTF8.self).contains("drawing"))
    }

    // MARK: - 座標・命令

    /// 1点は空（丸い点を打つ）・2点は直線・3点以上はなめらかな曲線（制御点＝各点・終点＝隣との中点）で最後の点へ直線
    func testOpsFollowThePointCount() async {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        XCTAssertEqual(StoryDrawingGeometry.ops(for: []), [])
        XCTAssertEqual(StoryDrawingGeometry.ops(for: [p(1, 1)]), [])
        XCTAssertEqual(StoryDrawingGeometry.ops(for: [p(0, 0), p(10, 0)]), [.move(p(0, 0)), .line(p(10, 0))])
        XCTAssertEqual(StoryDrawingGeometry.ops(for: [p(0, 0), p(10, 0), p(10, 10)]),
                       [.move(p(0, 0)), .quad(to: p(10, 5), control: p(10, 0)), .line(p(10, 10))])
        let four = StoryDrawingGeometry.ops(for: [p(0, 0), p(10, 0), p(20, 10), p(30, 10)])
        XCTAssertEqual(four.count, 4)
        XCTAssertEqual(four[1], .quad(to: p(15, 5), control: p(10, 0)))
        XCTAssertEqual(four[2], .quad(to: p(25, 10), control: p(20, 10)))
        XCTAssertEqual(four[3], .line(p(30, 10)))
    }

    func testNormalizingAndMappingBack() async throws {
        let rect = CGRect(x: -20, y: 0, width: 440, height: 880)   // 画面より大きく敷いた写真
        let point = try XCTUnwrap(StoryDrawingGeometry.normalized(CGPoint(x: 200, y: 440), in: rect))
        XCTAssertEqual(point.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(point.y, 0.5, accuracy: 1e-9)
        let back = StoryDrawingGeometry.point(point, in: rect)
        XCTAssertEqual(back.x, 200, accuracy: 0.05)
        XCTAssertEqual(back.y, 440, accuracy: 0.05)
        // 同じ割合を別の大きさの写真（焼き込み）へ写すと同じ所に出る
        let burned = StoryDrawingGeometry.point(point, in: CGRect(x: 0, y: 0, width: 1080, height: 1920))
        XCTAssertEqual(burned.x, 540, accuracy: 0.2)
        XCTAssertEqual(burned.y, 960, accuracy: 0.2)
        XCTAssertNil(StoryDrawingGeometry.normalized(CGPoint(x: 1, y: 1), in: .zero))
        XCTAssertNil(StoryDrawingGeometry.normalized(CGPoint(x: CGFloat.nan, y: 1), in: rect))
        // 小数4桁に丸める
        let rounded = try XCTUnwrap(StoryDrawingGeometry.normalized(CGPoint(x: 1, y: 1), in: CGRect(x: 0, y: 0, width: 3, height: 3)))
        XCTAssertEqual(rounded.x, 0.3333, accuracy: 1e-12)
    }

    /// 太さは写真の短い辺に対する割合（文字の大きさと同じ決め方）
    func testLineWidthUsesTheShortSide() async {
        XCTAssertEqual(StoryDrawingGeometry.lineWidth(0.01, in: CGSize(width: 1080, height: 1920)), 10.8, accuracy: 1e-9)
        XCTAssertEqual(StoryDrawingGeometry.lineWidth(0.01, in: CGSize(width: 1920, height: 1080)), 10.8, accuracy: 1e-9)
        XCTAssertEqual(StoryDrawingGeometry.lineWidth(0.01, in: CGSize(width: 1080, height: 1920)),
                       CGFloat(TextOverlay.fontSize(0.01, in: CGSize(width: 1080, height: 1920))), accuracy: 1e-9)
    }

    func testShouldAppendNeedsRealMovement() async {
        XCTAssertFalse(StoryDrawingGeometry.shouldAppend(last: .zero, new: CGPoint(x: 1, y: 0)))
        XCTAssertTrue(StoryDrawingGeometry.shouldAppend(last: .zero, new: CGPoint(x: 1.5, y: 0)))
        XCTAssertTrue(StoryDrawingGeometry.shouldAppend(last: .zero, new: CGPoint(x: 1.1, y: 1.1)))
    }

    // MARK: - 描く判断（指の動き）

    func testStrokeInputSteps() async {
        let photo = CGRect(x: 0, y: 0, width: 400, height: 800)
        let drawing = StoryDrawing()
        // 始める
        guard case .begin(let first) = StoryStrokeInput.step(live: nil, last: nil, location: CGPoint(x: 100, y: 200),
                                                              photo: photo, drawing: drawing) else {
            return XCTFail("始めていない")
        }
        XCTAssertEqual(first, StoryStrokePoint(x: 0.25, y: 0.25))
        let live = StoryStroke(tool: .pen, hex: 0, width: 0.01, points: [first])
        // ほとんど動いていない → 何もしない
        XCTAssertEqual(StoryStrokeInput.step(live: live, last: CGPoint(x: 100, y: 200), location: CGPoint(x: 100.5, y: 200),
                                             photo: photo, drawing: drawing), .ignore)
        // 動いた → 足す
        XCTAssertEqual(StoryStrokeInput.step(live: live, last: CGPoint(x: 100, y: 200), location: CGPoint(x: 140, y: 200),
                                             photo: photo, drawing: drawing), .append(StoryStrokePoint(x: 0.35, y: 0.25)))
        // 前の点が無い・写真の大きさが 0
        XCTAssertEqual(StoryStrokeInput.step(live: live, last: nil, location: CGPoint(x: 140, y: 200), photo: photo,
                                             drawing: drawing), .ignore)
        XCTAssertEqual(StoryStrokeInput.step(live: nil, last: nil, location: CGPoint(x: 1, y: 1), photo: .zero,
                                             drawing: drawing), .ignore)
    }

    func testStrokeInputStopsAtLimits() async {
        let photo = CGRect(x: 0, y: 0, width: 400, height: 800)
        // 本数
        var full = StoryDrawing()
        for _ in 0..<StoryDrawing.maxStrokes { full.add(stroke(points: 2)) }
        XCTAssertEqual(StoryStrokeInput.step(live: nil, last: nil, location: CGPoint(x: 10, y: 10), photo: photo, drawing: full),
                       .limit, "本数の上限で始めている")
        // 1本の長さ
        let longLive = StoryStroke(tool: .pen, hex: 0, width: 0.01,
                                   points: Array(repeating: StoryStrokePoint(x: 0.1, y: 0.1), count: StoryDrawing.maxPointsPerStroke))
        XCTAssertEqual(StoryStrokeInput.step(live: longLive, last: .zero, location: CGPoint(x: 50, y: 50), photo: photo,
                                             drawing: StoryDrawing()), .limit, "1本の長さの上限を超えて足している")
    }

    // MARK: - 配線（ソース）

    private func repo(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 焼き込み: 写真 → 線 → 文字・札の順。線が無ければ飛ばし、線だけの写真でも焼く
    func testBurnDrawsLinesBetweenPhotoAndOverlays() async throws {
        let renderer = try repo("Sources/JourneyPhoto/Services/TextOverlayRenderer.swift")
        XCTAssertTrue(renderer.contains("drawing: StoryDrawing = .empty) -> Data {"))
        XCTAssertTrue(renderer.contains("!visible.isEmpty || !framing.isIdentity || !recipe.isIdentity || drawing.hasInk"),
                      "線だけの写真が焼き込みを飛ばされる")
        let burn = try XCTUnwrap(renderer.components(separatedBy: "static func burn(").dropFirst().first?
            .components(separatedBy: "static func draw(").first)
        let photo = try XCTUnwrap(burn.range(of: "image.draw(in:"))
        let lines = try XCTUnwrap(burn.range(of: "StoryDrawingPainter.draw(drawing, size: size, in: context.cgContext)"))
        let text = try XCTUnwrap(burn.range(of: "draw(overlay, on: size"))
        XCTAssertLessThan(photo.lowerBound, lines.lowerBound, "線が写真より先に描かれる")
        XCTAssertLessThan(lines.lowerBound, text.lowerBound, "線が文字・札の上に描かれる")
        // Core Graphics の本体は Linux の模型に無い口を使うので、本物の UIKit がある環境だけ
        let painter = try repo("Sources/JourneyPhoto/Services/StoryDrawingPainter.swift")
        XCTAssertTrue(painter.hasPrefix("#if !os(Linux)"))
        XCTAssertTrue(painter.contains("cg.beginTransparencyLayer(auxiliaryInfo: nil)"), "消しゴムが写真まで消す")
        XCTAssertTrue(painter.contains("cg.setBlendMode(stroke.tool == .eraser ? .clear : .normal)"))
        XCTAssertTrue(painter.contains("alpha: CGFloat(stroke.tool.opacity)"), "蛍光ペンが半透明でない")
        XCTAssertTrue(painter.contains("StoryDrawingGeometry.ops(for: points)"), "画面と同じ命令から描いていない")
    }

    /// 動画: 重ねの1枚絵に線も入れる。文字・札が無くても線があれば重ねを焼く。線は文字・札の下
    func testVideoOverlayIncludesTheDrawing() async throws {
        let pipeline = try repo("Sources/JourneyPhoto/Services/StoryVideoPipeline.swift")
        XCTAssertTrue(pipeline.contains("guard !overlays.isEmpty || drawing.hasInk else {"), "線だけの動画に重ねを焼かない")
        XCTAssertTrue(pipeline.contains("TextOverlayRenderer.overlayImage(overlays, drawing: drawing, size: renderSize,"))
        let image = try XCTUnwrap(pipeline.components(separatedBy: "static func overlayImage(").dropFirst().first)
        let lines = try XCTUnwrap(image.range(of: "StoryDrawingPainter.draw(drawing, size: size, in: context.cgContext)"))
        let text = try XCTUnwrap(image.range(of: "draw(overlay, on: size"))
        XCTAssertLessThan(lines.lowerBound, text.lowerBound)
        // 前のまま: 向き・重ねの焼き込み
        XCTAssertTrue(pipeline.contains("StoryVideoRules.renderSize(for: oriented, step: step)"))
        XCTAssertTrue(pipeline.contains("videoComposition.animationTool = AVVideoCompositionCoreAnimationTool("))
    }

    /// 画面: 描く面が下の札を受けさせない・取り消し/やり直し・✕ を隠す・下書きと書き出しに渡す
    func testComposerWiresDrawing() async throws {
        let composer = try repo("Sources/JourneyPhoto/Features/Stories/StoryComposerView.swift")
        XCTAssertTrue(composer.contains("private var sidePanelOpen: Bool { filterPanelOpen || drawMode }"), "描画中に足元が隠れない")
        XCTAssertTrue(composer.contains("@State private var liveStroke = StoryLiveStroke()"))
        XCTAssertFalse(composer.contains("@StateObject private var liveStroke"), "指が動くたびに作る画面全体が描き直される")
        XCTAssertTrue(composer.contains("drawingStrokes: shots[current].drawing.strokes,"))
        XCTAssertTrue(composer.contains("liveStroke: liveStroke)"))
        // 描く面は写真の枠（`StoryCanvas`）より後ろ＝上に重なる（指を先に受ける）
        let canvas = try XCTUnwrap(composer.range(of: "StoryCanvas(preview: preview"))
        let surface = try XCTUnwrap(composer.range(of: "StoryDrawingSurface(pen: pen"))
        XCTAssertLessThan(canvas.lowerBound, surface.lowerBound, "描く面が写真の枠の下にある（札を掴む）")
        XCTAssertTrue(composer.contains("StoryDrawPanel(pen: $pen)"))
        XCTAssertTrue(composer.contains("drawHistoryButtons"), "取り消し・やり直しが無い")
        XCTAssertTrue(composer.contains("if drawMode {\n                drawHistoryButtons\n            } else {"), "描いている間に ✕ が押せる")
        XCTAssertTrue(composer.contains("Button { drawMode = false } label: {"), "描かずに進む「完了」が無い")
        XCTAssertTrue(composer.contains("shots[current].drawing.undo()"))
        XCTAssertTrue(composer.contains("shots[current].drawing.redo()"))
        // 下書き・焼き込み・書き出し・変更の検出
        XCTAssertTrue(composer.contains("drawings: shots.map(\\.drawing))"), "描いても「変更あり」にならない")
        XCTAssertTrue(composer.contains("filter: shot.filter,\n                                      drawing: shot.drawing)"), "下書きに描画を書いていない")
        XCTAssertTrue(composer.contains("drawing: item.shot.drawing ?? StoryDrawing.empty)"), "下書きから描画を戻していない")
        XCTAssertTrue(composer.contains("song: songArt, filter: shot.filter, drawing: shot.drawing),"), "焼き込みに描画を渡していない")
        XCTAssertTrue(composer.contains("filter: filter, drawing: drawing)"), "動画の書き出しに描画を渡していない")
        XCTAssertTrue(composer.contains("done.drawings[$0.id] == $0.drawing"), "描き足しても書き出し直さない")
        // 読み上げ: 描けないことと、描かずに進めることを言う
        XCTAssertTrue(composer.contains("読み上げでは描けません。描かずに進めます"))
    }

    /// 線の層は写真と札の間（「ひとこと」の欄の下・札の下）
    func testCanvasPlacesTheLayerBetweenPhotoAndOverlays() async throws {
        let canvas = try repo("Sources/JourneyPhoto/Features/Stories/TextOverlayEditor.swift")
        let photo = try XCTUnwrap(canvas.range(of: ".accessibilityIdentifier(\"story.canvas\")"))
        let layer = try XCTUnwrap(canvas.range(of: "StoryDrawingLayer(strokes: drawingStrokes, live: liveStroke, imageSize: imageSize)"))
        let under = try XCTUnwrap(canvas.range(of: "if let underOverlays {"))
        let overlays = try XCTUnwrap(canvas.range(of: "ForEach(overlays.filter { $0.id != hiddenId }) { overlay in"))
        XCTAssertLessThan(photo.lowerBound, layer.lowerBound)
        XCTAssertLessThan(layer.lowerBound, under.lowerBound)
        XCTAssertLessThan(under.lowerBound, overlays.lowerBound)
    }

    /// 描く面・欄: 指を取りこぼさない・読み上げ・当たり 44・固定の大きさの文字なし・色は黒地の欄の上だけ真鍮
    func testSurfaceAndPanelAccessibility() async throws {
        let surface = try repo("Sources/JourneyPhoto/Features/Stories/StoryDrawingCanvas.swift")
        XCTAssertTrue(surface.contains("DragGesture(minimumDistance: 0)"), "点を打てない（動かさないと描けない）")
        XCTAssertTrue(surface.contains(".contentShape(Rectangle())"), "描く面が指を全部受けない")
        XCTAssertTrue(surface.contains("@GestureState private var touching = false"), "打ち切られた回の片付けが無い")
        XCTAssertTrue(surface.contains(".onChange(of: touching) { _, active in"))
        XCTAssertTrue(surface.contains("読み上げでは描けません"))
        XCTAssertTrue(surface.contains("StoryStrokeInput.step("))
        XCTAssertTrue(surface.contains(".allowsHitTesting(false)"), "線の層が指を受ける")
        XCTAssertFalse(surface.contains(".system(size:"))
        let panel = try repo("Sources/JourneyPhoto/Features/Stories/StoryDrawPanel.swift")
        XCTAssertTrue(panel.contains(".frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)"), "色の当たりが 44 でない")
        XCTAssertTrue(panel.contains("minHeight: 56"), "筆の当たりが 44 以上でない")
        XCTAssertTrue(panel.contains(".accessibilityValue(selected ? L(\"選択中\", \"Selected\") : \"\")"))
        XCTAssertTrue(panel.contains("strokeBorder(WebTheme.accent, lineWidth: 2)"), "選びを形（輪）で伝えていない")
        XCTAssertTrue(panel.contains("if pen.tool != .eraser { colorRow }"), "消しゴムに色を出している")
        XCTAssertTrue(panel.contains(".sensoryFeedback(.selection, trigger: pen.tool)"))
        XCTAssertFalse(panel.contains(".system(size:"))
        XCTAssertFalse(panel.contains("捨"))
        XCTAssertFalse(panel.contains("撮りどき"))
    }
}
