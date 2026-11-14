import XCTest
@testable import JourneyPhoto

/// ホームの上の札の出典の行（`TopCardCredit`・`TopCardFace.creditLine`・2026-11-14 判断）。
/// 札の背（116）と1行のまま、**出典の頭（「写真: 作者」の頭）を必ず見せる**。
/// 前は「地域　写真: 作者 / ライセンス」の1本の字を真ん中で切り、ちょうど「写真: 作者」が消えていた
final class TopCardCreditTests: XCTestCase {

    private let url = URL(string: "https://journey-photo.com/images/spots/a.jpg")!

    private func photo(_ author: String, _ license: String = "CC BY-SA 4.0") -> SpotImage {
        SpotImage(url: url, author: author, license: license, pageUrl: nil)
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path),
                              encoding: .utf8)
        return text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func slice(_ text: String, from start: String, to end: String) -> String {
        guard let a = text.range(of: start), let b = text.range(of: end, range: a.upperBound..<text.endIndex) else {
            return ""
        }
        return String(text[a.lowerBound..<b.upperBound])
    }

    // MARK: - 形の並び

    /// 入る最初の形を出す: 地域＋出典 → 県＋出典 → 出典だけ。削るのは地域だけで、**どの形も出典の全文を含む**
    func testWholeLinesDropTheRegionNotTheCredit() {
        let p = photo("Maarten Heerlien from Voorschoten, The Netherlands")
        let c = TopCardCredit(region: "高知県\u{2002}高知市", prefecture: "高知県", photo: p)
        XCTAssertEqual(c.wholeLines, ["高知県\u{2002}高知市\u{2002}" + p.credit, "高知県\u{2002}" + p.credit, p.credit])
        for line in c.wholeLines {
            XCTAssertTrue(line.hasSuffix(p.credit), "形から出典の全文が欠けている: \(line)")
        }
        // 前の形（1本の字を真ん中で切る）に戻すと、この並びが無くなる
        XCTAssertEqual(c.credit, p.credit, "出典の字が写真の詳細（`SpotImage.credit`）と違う")
    }

    /// 地域が無い・県だけの地域では、同じ字の形を1つにまとめる（同じ形を2度試さない）
    func testWholeLinesAreDistinct() {
        let p = photo("Σ64", "CC BY 4.0")
        XCTAssertEqual(TopCardCredit(photo: p).wholeLines, [p.credit])
        XCTAssertEqual(TopCardCredit(region: "東京都", prefecture: "東京都", photo: p).wholeLines,
                       ["東京都\u{2002}" + p.credit, p.credit])
        XCTAssertEqual(TopCardCredit(region: "  ", prefecture: nil, photo: p).wholeLines, [p.credit])
    }

    /// どれも入らないとき: 作者の後ろだけを切り、「 / ライセンス」は残す。頭は「写真: 」と作者の初めの4文字
    func testCutFormKeepsTheHeadAndTheLicense() {
        let p = photo("No machine-readable author provided. Marubatsu assumed (based on copyright claims).")
        let c = TopCardCredit(photo: p)
        XCTAssertEqual(c.author, p.creditAuthor)
        XCTAssertEqual(c.licenseTail, " / CC BY-SA 4.0")
        XCTAssertEqual(c.author + c.licenseTail, p.credit, "作者とライセンスを合わせると出典の全文にならない")
        XCTAssertEqual(c.head, L("写真: No m", "Photo: No m"))
        XCTAssertTrue(c.author.hasPrefix(c.head))
        // 短い作者は全部が頭
        XCTAssertEqual(TopCardCredit(photo: photo("A")).head, L("写真: A", "Photo: A"))
    }

    /// 読み上げは形にかかわらず全文（地域と出典）
    func testSpokenIsTheWholeText() {
        let p = photo("663highland", "CC BY 2.5")
        let c = TopCardCredit(region: "石川県\u{2002}金沢市", prefecture: "石川県", photo: p)
        XCTAssertEqual(c.spoken, "石川県\u{2002}金沢市\u{2002}" + p.credit)
        XCTAssertEqual(c.spoken, c.wholeLines.first)
    }

    // MARK: - 札の面

    /// 札の面は出典の行を `ViewThatFits` で組み、最後の形は作者を末尾で切ってライセンス名に先に幅を渡す。
    /// 読み上げは全文。**真ん中で切る1本の字に戻すと落ちる**
    func testCardFaceKeepsTheCreditHead() throws {
        let face = try source("Features/Gallery/TopCardFace.swift")
        let line = slice(face, from: "private func creditLine(_ credit: TopCardCredit)", to: ".modifier(TopCardCreditProbe")
        XCTAssertFalse(line.isEmpty, "札の面に出典の行（creditLine）が無い")
        XCTAssertTrue(line.contains("ViewThatFits(in: .horizontal)"), "入る形を選んでいない")
        XCTAssertTrue(line.contains("ForEach(credit.wholeLines"), "地域から削る形の並びを使っていない")
        XCTAssertTrue(line.contains("TopCardCreditCutLine(credit: credit)"), "最後の形（作者の後ろを切る）が無い")
        XCTAssertFalse(line.contains(".truncationMode(.middle)"), "出典を真ん中で切っている（出典の頭が消える）")
        let cut = slice(face, from: "struct TopCardCreditCutLine", to: ".truncationMode(.tail)")
        XCTAssertTrue(cut.contains("Text(credit.licenseTail)"))
        XCTAssertTrue(cut.contains(".layoutPriority(1)"), "ライセンス名に先に幅を渡していない")
        XCTAssertTrue(cut.contains("Text(credit.author)"))
        XCTAssertTrue(cut.hasSuffix(".truncationMode(.tail)"), "作者を末尾で切っていない（頭が消える）")
        XCTAssertFalse(line.contains(".lineLimit(2)"), "出典の行を2行にしている（札の背が伸びる）")
        XCTAssertTrue(line.contains(".accessibilityLabel(credit.spoken)"), "読み上げが全文でない")
        XCTAssertTrue(face.contains("if let credit {\n                        creditLine(credit)"), "出典があっても出典の行を使っていない")
    }

    /// 写真のある札（季節・行きたい場所・払う入口・今日の一問）は、出典を1本の字（`detail`）でなく `credit` で渡す
    func testPhotoCardsPassTheCredit() throws {
        let home = try source("Features/Gallery/HomeTopCardView.swift")
        XCTAssertEqual(home.components(separatedBy: "credit: Self.spotCredit(spot)").count - 1, 2, "季節・行きたい場所の札")
        XCTAssertTrue(home.contains("credit: cover.flatMap(Self.spotCredit)"), "払う入口の札")
        XCTAssertTrue(home.contains("credit: TopCardCredit(photo: quiz.photo)"), "今日の一問の札")
        XCTAssertFalse(home.contains("detail: quiz.photo.credit"), "今日の一問の出典を1本の字で渡している")
        XCTAssertFalse(home.contains("spot.photo?.credit"), "出典を地域と1本の字にしている")
        let search = try source("Features/Search/SearchView.swift")
        XCTAssertTrue(search.contains("credit: TopCardCredit(photo: quiz.photo)"), "探すの今日の一問の札")
        XCTAssertFalse(search.contains("detail: quiz.photo.credit"))
    }

    /// 札の背は変えない（板の 116・1行）
    func testCardHeightUnchanged() {
        XCTAssertEqual(HomeTopCardView.cardHeight, 116)
        XCTAssertEqual(HomeTopCardView.lineLimit, 1)
    }
}
