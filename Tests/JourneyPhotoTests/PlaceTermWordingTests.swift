import XCTest
@testable import JourneyPhoto

/// 場所の呼び名をそろえる（2026-10-11 owner 承認、2026-11-12 に「観光スポット」へ変更・CLAUDE.md「呼び名の決まり」）。
///
/// 同じものが「撮影地・撮影スポット・スポット・注目スポット・撮影地ガイド・この場所」と
/// 最大7通りで呼ばれていた。決まりは:
/// - 公式の頁・一覧（`OfficialSpot`） → 「観光スポット」（チップ・タブ・切り替えだけ「スポット」）。
///   2026-11-12 まで「撮影スポット」だった（1.1.84 で表の言葉を一度に替えた。識別子・URL・サーバーの欄はそのまま）
/// - 写真が撮られた所（写真から導く撮影地の頁も） → 「撮影地」
/// - 保存の機能 → 「行きたい場所」
///
/// 画面は Linux で描けないので、`L("…")` の日本語を書いてあるもので見る（`NoDiscardWordingTests` と同じ形）
final class PlaceTermWordingTests: XCTestCase {

    private var sourcesRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
    }

    /// `L("日本語"` の日本語の部分だけを、ファイル:行 と一緒に返す
    private func japaneseStrings(in file: URL) throws -> [(at: String, text: String)] {
        let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
        let pattern = try NSRegularExpression(pattern: #"L\("((?:[^"\\]|\\.)*)""#)
        var out: [(String, String)] = []
        for (i, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            for match in pattern.matches(in: line, range: range) {
                guard let r = Range(match.range(at: 1), in: line) else { continue }
                out.append(("\(file.lastPathComponent):\(i + 1)", String(line[r])))
            }
        }
        return out
    }

    private func allJapaneseStrings() throws -> [(at: String, text: String)] {
        let files = FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        return try files.flatMap { try japaneseStrings(in: $0) }
    }

    /// 公式の頁・一覧の古い呼び名「撮影スポット」が、画面の文（コードの文字列）に戻ってこない（1.1.84 で替えた）
    func testOldOfficialSpotNameIsGone() throws {
        let files = FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        var left: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for literal in NoMiddleDotSweepTests.literals(text) where literal.contains("撮影スポット") {
                left.append("\(file.lastPathComponent): \(literal)")
            }
        }
        XCTAssertEqual(left, [], "「撮影スポット」は「観光スポット」に替えた")
        let strings = try allJapaneseStrings()
        XCTAssertGreaterThan(strings.filter { $0.text.contains("観光スポット") }.count, 50)
    }

    /// 消した呼び名が戻ってこない
    func testRemovedVariantsDoNotComeBack() throws {
        let strings = try allJapaneseStrings()
        XCTAssertGreaterThan(strings.count, 500, "前提: `L(` を読めていない")
        let removed = ["注目スポット", "撮影地ガイド", "この場所", "スポットのガイド", "ガイドを見る"]
        let bad = strings.filter { s in removed.contains { s.text.contains($0) } }.map { "\($0.at) \($0.text)" }
        XCTAssertEqual(bad, [], "使わないと決めた呼び名が画面の言葉にある")
    }

    /// 写真から導く撮影地の頁（`SpotDetailView`）は「撮影地」と呼ぶ。公式の撮影スポットと混ぜない
    func testDerivedPlacePageSaysSatsueichi() throws {
        let derived = try japaneseStrings(in: sourcesRoot.appendingPathComponent("Features/Spots/SpotDetailView.swift"))
        XCTAssertFalse(derived.isEmpty)
        XCTAssertEqual(derived.filter { $0.text.contains("スポット") }.map(\.at), [],
                       "撮影地の頁が「スポット」と名乗っている")
        XCTAssertTrue(derived.contains { $0.text.hasPrefix("この撮影地の写真") })
        XCTAssertTrue(derived.contains { $0.text == "近くの撮影地" })
    }

    /// 公式の撮影スポットの頁（`OfficialSpotView`）は「撮影スポット」と呼ぶ
    func testOfficialSpotPageSaysSatsueiSpot() throws {
        let official = try japaneseStrings(in: sourcesRoot.appendingPathComponent("Features/Spots/OfficialSpotView.swift"))
        for text in ["この観光スポットの魅力", "この観光スポットの写真を投稿", "近くの観光スポット",
                     "この観光スポットから、次の一枚へ"] {
            XCTAssertTrue(official.contains { $0.text == text }, "公式の頁に「\(text)」が無い")
        }
        XCTAssertTrue(official.contains { $0.text.hasPrefix("この観光スポットの写真（") })
        XCTAssertEqual(official.filter { $0.text.contains("このスポット") }.map(\.at), [],
                       "公式の頁が「このスポット」と短く呼んでいる")
    }

    /// 地図の札・光の知らせ・クイズから公式の頁へ行くボタンは「撮影スポットを見る」。
    /// 写真の撮影地の頁へ行くボタンは「撮影地を見る」
    func testOpenButtonsNameTheirDestination() throws {
        let map = try japaneseStrings(in: sourcesRoot.appendingPathComponent("Features/Map/PhotoMapView.swift"))
        XCTAssertTrue(map.contains { $0.text == "観光スポットを見る" })
        XCTAssertTrue(map.contains { $0.text == "撮影地を見る" })
        let bare = try allJapaneseStrings().filter { $0.text == "スポットを見る" }.map(\.at)
        XCTAssertEqual(bare, [], "行き先が分からない「スポットを見る」が残っている")
    }

    /// 延ばした「撮影スポットを見る」は横に並ぶボタンなので、幅 375pt ではみ出さないよう
    /// **1行に収めて縮める。縮めるのは 0.8 まで**（15pt × 0.8 = 12pt。板の本文の最小・2026-10-11 のレビュー）
    func testLongSpotButtonsFitOnOneLine() throws {
        for path in ["Features/Map/PhotoMapView.swift", "Features/Gallery/DailyQuizView.swift"] {
            let text = try String(contentsOf: sourcesRoot.appendingPathComponent(path), encoding: .utf8)
            guard let start = text.range(of: #"L("観光スポットを見る""#) else {
                XCTFail("\(path) に「観光スポットを見る」が無い"); continue
            }
            let after = String(text[start.upperBound...].prefix(400))
            XCTAssertTrue(after.contains(".lineLimit(1)"), "\(path) の「観光スポットを見る」が折り返す")
            XCTAssertTrue(after.contains(".minimumScaleFactor(0.8)"),
                          "\(path) の「観光スポットを見る」が縮まない、または 12pt より小さく縮む")
        }
    }

    /// 文で書く所は「撮影スポット」。「スポット」だけで呼んでよいのはチップ・タブ・切り替え
    func testShelfAndWishlistTextsSayTheFullName() {
        XCTAssertEqual(HomeSpotShelf.heading, L("いまの季節の観光スポット", "Photo spots for this season"))
        XCTAssertTrue(HomeSpotShelf.note.contains(L("各観光スポットの作例", "examples for each spot")))
    }
}
