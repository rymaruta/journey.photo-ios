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

    func testPartTitlesExist() {
        for part in CompositionLesson.Part.allCases {
            XCTAssertFalse(part.title.isEmpty)
        }
    }
}
