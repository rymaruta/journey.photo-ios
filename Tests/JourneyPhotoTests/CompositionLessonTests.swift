import XCTest
@testable import JourneyPhoto

/// 構図の詳しい解説（2026-10-16 owner「構図の説明が軽いので、詳しくしたい」・`CompositionLessons`）。
/// 全37種類に6つの段（どういう構図か・なぜ効くのか・撮り方の手順・合う場面・よくある失敗・似た構図との違い）が
/// 日本語と英語の両方であるか。
final class CompositionLessonTests: XCTestCase {

    private func hasJapanese(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }
    }

    func testEveryKindHasEveryPartInJapaneseAndEnglish() {
        XCTAssertEqual(CompositionLesson.Part.allCases.count, 6)
        for kind in CompositionKind.allCases {
            for english in [false, true] {
                let l = CompositionLessons.lesson(for: kind, english: english)
                let lang = english ? "en" : "ja"
                for (name, text) in [("what", l.what), ("why", l.why), ("scenes", l.scenes),
                                     ("mistakes", l.mistakes), ("versus", l.versus)] {
                    XCTAssertGreaterThanOrEqual(text.count, english ? 40 : 20, "\(kind) \(lang) の \(name) が短い・空")
                    XCTAssertEqual(hasJapanese(text), !english, "\(kind) \(lang) の \(name) の言語が違う: \(text)")
                }
                XCTAssertTrue((3...4).contains(l.steps.count), "\(kind) \(lang) の手順は 3〜4 段: \(l.steps.count)")
                for step in l.steps {
                    XCTAssertFalse(step.isEmpty, "\(kind) \(lang) の手順に空の段")
                    XCTAssertEqual(hasJapanese(step), !english, "\(kind) \(lang) の手順の言語が違う: \(step)")
                }
                // 失敗の段は「失敗 → 直し方」の形
                XCTAssertTrue(l.mistakes.contains("→"), "\(kind) \(lang) の失敗の段に直し方が無い")
            }
            let ja = CompositionLessons.lesson(for: kind, english: false)
            let en = CompositionLessons.lesson(for: kind, english: true)
            XCTAssertEqual(ja.steps.count, en.steps.count, "\(kind) の手順の段数が日本語と英語で違う")
        }
    }

    /// 構図ごとに違う解説になっている（写しで埋めていない）
    func testLessonsAreNotCopiedBetweenKinds() {
        for english in [false, true] {
            let whats = CompositionKind.allCases.map { CompositionLessons.lesson(for: $0, english: english).what }
            XCTAssertEqual(Set(whats).count, whats.count, "どういう構図かの段が別の構図と同じ")
        }
    }

    /// 根拠の弱い断言を書かない（「黄金比は人が最も美しいと感じる」など）
    func testNoUnfoundedBeautyClaims() {
        let banned = ["最も美しい", "一番美しい", "必ず美しく", "人間が本能的", "most beautiful", "naturally pleasing", "always beautiful"]
        for kind in CompositionKind.allCases {
            for english in [false, true] {
                let l = CompositionLessons.lesson(for: kind, english: english)
                let all = ([l.what, l.why, l.scenes, l.mistakes, l.versus] + l.steps).joined(separator: " ")
                for word in banned {
                    XCTAssertFalse(all.contains(word), "\(kind) に根拠の弱い断言「\(word)」")
                }
            }
        }
    }

    /// 解説の数字が線の計算と食い違わない（黄金螺旋の目・ファイグリッドの線・余白の四角・額縁の内側）
    func testNumbersMatchTheGuideLines() {
        let eye = CompositionGuide.spiralEye(variant: 0)
        let spiral = CompositionLessons.lesson(for: .goldenSpiral, english: false).what
        XCTAssertTrue(spiral.contains("\(Int((eye.x * 100).rounded()))%"), spiral)
        XCTAssertTrue(spiral.contains("\(Int((eye.y * 100).rounded()))%"), spiral)
        let phi = CompositionLessons.lesson(for: .phiGrid, english: false).what
        XCTAssertTrue(phi.contains("\(Int((100 / (CompositionGuide.phi * CompositionGuide.phi)).rounded()))%"), phi)
        XCTAssertTrue(phi.contains("\(Int((100 / CompositionGuide.phi).rounded()))%"), phi)
        XCTAssertTrue(CompositionLessons.lesson(for: .frameWithin, english: false).what.contains("12%"))
        XCTAssertTrue(CompositionLessons.lesson(for: .tunnel, english: false).what.contains("12%"))
        // 縦持ちの 6×4 は 4 列×6 段（`rawMarks` の grid(columns: 4, rows: 6)）
        XCTAssertTrue(CompositionLessons.lesson(for: .grid6x4, english: false).what.contains("縦4列・横6段"))
    }

    /// 2026-10-16（確かめ役の指摘）: 対角線の向きの名前が逆だった。一般的な呼び名は
    /// **バロック＝左下→右上・シニスター＝左上→右下**。線と番号は動かさず（向き 0＝左上→右下）、名前だけ入れ替えた
    func testDiagonalNamesMatchTheLines() throws {
        func onlySegment(_ v: Int) throws -> (GuidePoint, GuidePoint) {
            let marks = CompositionGuide.marks(.diagonals, variant: v, aspect: 0.75)
            XCTAssertEqual(marks.count, 1)
            guard case .segment(let a, let b) = try XCTUnwrap(marks.first).shape else {
                XCTFail("線分ではない"); return (GuidePoint(x: 0, y: 0), GuidePoint(x: 0, y: 0))
            }
            return a.x < b.x ? (a, b) : (b, a)
        }
        let names = (0..<CompositionKind.diagonals.variantCount).map { CompositionKind.diagonals.variantEnglishName($0) }
        let baroque = try XCTUnwrap(names.firstIndex(of: "Baroque"))
        let sinister = try XCTUnwrap(names.firstIndex(of: "Sinister"))
        // バロック: 左下 (0,1) → 右上 (1,0)
        let b = try onlySegment(baroque)
        XCTAssertEqual(b.0, GuidePoint(x: 0, y: 1)); XCTAssertEqual(b.1, GuidePoint(x: 1, y: 0))
        // シニスター: 左上 (0,0) → 右下 (1,1)
        let s = try onlySegment(sinister)
        XCTAssertEqual(s.0, GuidePoint(x: 0, y: 0)); XCTAssertEqual(s.1, GuidePoint(x: 1, y: 1))
        // 向き 0 は左上→右下のまま（覚えてある番号・作例写真が合わせてある）
        XCTAssertEqual(sinister, 0)
        XCTAssertEqual(CompositionKind.diagonals.variantName(baroque), "バロック")
        // 解説も同じ対応で書く
        XCTAssertTrue(CompositionLessons.lesson(for: .diagonals, english: false).what.contains("バロック（左下→右上）"))
        XCTAssertTrue(CompositionLessons.lesson(for: .diagonals, english: true).what.contains("baroque (bottom-left to top-right)"))
    }

    /// 縦持ちの 6×4 のマスはほぼ正方形で少し横長（約 9:8）。4×4 は縦長（3:4）。解説の言い方が形と食い違わない
    func testGridCellShapesMatchTheText() {
        let r = 0.75
        func cellAspect(_ kind: CompositionKind) -> Double {
            let marks = CompositionGuide.marks(kind, variant: 0, aspect: r)
            var vertical = 0, horizontal = 0
            for m in marks {
                if case .segment(let a, let b) = m.shape {
                    if a.x == b.x { vertical += 1 } else if a.y == b.y { horizontal += 1 }
                }
            }
            // 幅 r・高さ 1 の面で、列の幅 ÷ 段の高さ
            return (r / Double(vertical + 1)) / (1 / Double(horizontal + 1))
        }
        XCTAssertEqual(cellAspect(.grid6x4), 9.0 / 8, accuracy: 0.001)
        XCTAssertEqual(cellAspect(.grid4), 0.75, accuracy: 0.001)
        for kind in CompositionKind.allCases {
            for english in [false, true] {
                let l = CompositionLessons.lesson(for: kind, english: english)
                let all = ([l.what, l.why, l.scenes, l.mistakes, l.versus] + l.steps).joined(separator: " ")
                XCTAssertFalse(all.contains("6×4 は縦長"), "\(kind) が 6×4 のマスを縦長と書いている")
                XCTAssertFalse(all.contains("4×4 and 6×4 use tall"), "\(kind) が 6×4 のマスを縦長と書いている")
                XCTAssertFalse(all.contains("6×4 uses taller"), "\(kind) が 6×4 のマスを縦長と書いている")
            }
        }
    }

    /// 書き方の見張り: 構図の詳細の画面に、詳しい解説の段が実際に出る（Linux では SwiftUI の画面を動かせないので、
    /// ソースで見る）。`lessonSection` を body から外すとここで落ちる
    func testExplanationScreenShowsTheLesson() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto/Features/Settings/CompositionCatalogView.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "struct CompositionExplanationView"))
        let bodyStart = try XCTUnwrap(source.range(of: "var body: some View", range: start.upperBound..<source.endIndex))
        let bodyEnd = try XCTUnwrap(source.range(of: ".webScreen()", range: bodyStart.upperBound..<source.endIndex))
        let body = source[bodyStart.upperBound..<bodyEnd.lowerBound]
        XCTAssertTrue(body.contains("lessonSection"), "詳細の画面の body に解説の段が無い")
        XCTAssertTrue(source.contains("CompositionLessons.lesson(for: kind)"), "解説を構図から取り出していない")
        XCTAssertTrue(source.contains("ForEach(CompositionLesson.Part.allCases"), "6つの段を全部並べていない")
        // 段の見出しは明朝・押せる高さ 44
        XCTAssertTrue(source.contains(".font(JPFont.rowTitle)"))
        XCTAssertTrue(source.contains(".frame(minHeight: WebTheme.minTapTarget)"))
    }

    func testPartTitlesExist() {
        for part in CompositionLesson.Part.allCases {
            XCTAssertFalse(part.title.isEmpty)
        }
    }
}
