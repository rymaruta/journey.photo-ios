import XCTest
@testable import JourneyPhoto

final class ColorFamiliesTests: XCTestCase {

    private func photo(_ id: String, color: String?, likes: Int? = nil,
                       category: String? = "landscape") throws -> Photo {
        let c = color.map { ",\"dominantColor\":\"\($0)\"" } ?? ""
        let l = likes.map { ",\"likes\":\($0)" } ?? ""
        let k = category.map { ",\"category\":\"\($0)\"" } ?? ""
        return try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"\(id)\",\"src\":\"/uploads/\(id).jpg\"\(c)\(l)\(k)}".utf8))
    }

    func testReadsHex() {
        XCTAssertNil(ColorFamilies.rgb(nil))
        XCTAssertNil(ColorFamilies.rgb("#abc"))
        XCTAssertNil(ColorFamilies.rgb("みどり"))
        let rgb = ColorFamilies.rgb("#ff8000")
        XCTAssertEqual(rgb?.r, 1)
        XCTAssertEqual(rgb?.b, 0)
    }

    func testFamilies() {
        XCTAssertEqual(ColorFamilies.family(ofHex: "#2f6fd0"), .blue)
        XCTAssertEqual(ColorFamilies.family(ofHex: "#2f8f3f"), .green)
        XCTAssertEqual(ColorFamilies.family(ofHex: "#e2761b"), .orange)
        XCTAssertEqual(ColorFamilies.family(ofHex: "#d94f8a"), .pink)
    }

    /// **彩度が低くて明るいものは白。** 桜の淡い色は色相だけ見ると
    /// ピンクにも赤にも転ぶが、人は「白」と呼ぶ
    func testPaleColoursAreWhite() {
        XCTAssertEqual(ColorFamilies.family(ofHex: "#f2eef0"), .white)
        XCTAssertEqual(ColorFamilies.family(ofHex: "#ffffff"), .white)
    }

    /// **暗すぎるものはどの札にも入れない**（夜の写真を「青」に混ぜない）
    func testVeryDarkColoursHaveNoFamily() {
        XCTAssertNil(ColorFamilies.family(ofHex: "#0a0b0d"))
        XCTAssertNil(ColorFamilies.family(ofHex: "#333333"))
    }

    /// 色を持たない写真は振り分けない（「分からない」であって「黒」ではない）
    func testPhotosWithoutAColourAreSkipped() throws {
        XCTAssertNil(ColorFamilies.family(ofHex: nil))
        let sections = ColorFamilies.sections(in: [try photo("a", color: nil)])
        XCTAssertTrue(sections.isEmpty)
    }

    /// 1枚も無い色味は札にしない。並びは決まった順
    func testSectionsSkipEmptyFamiliesAndKeepOrder() throws {
        let sections = ColorFamilies.sections(in: [
            try photo("o", color: "#e2761b"),
            try photo("b1", color: "#2f6fd0", likes: 1),
            try photo("b2", color: "#3a7ad9", likes: 9),
        ])
        XCTAssertEqual(sections.map(\.family), [.blue, .orange])
        XCTAssertEqual(sections.first?.photos.map(\.id), ["b2", "b1"])
    }

    /// **色の丸の読み上げに色の名前を入れる。** 丸の下の字は「空・海」だけなので、
    /// 読み上げでは何色か分からなかった
    func testAccessibilityLabelSaysTheColourName() {
        let label = ColorFamilies.accessibilityLabel(.blue, count: 5)
        XCTAssertTrue(label.contains(ColorFamilies.Family.blue.label), label)
        XCTAssertTrue(label.contains(ColorFamilies.Family.blue.note), label)
        XCTAssertTrue(label.contains("5"), label)
    }

    /// **札は景色を約束している。** 白い器の料理が「雪・冬景色」に、分類の無い写真が
    /// 色だけで札に入っていた（owner の指摘・2026-10-07）
    func testFoodAndUncategorisedPhotosStayOutOfSceneFamilies() throws {
        let sections = ColorFamilies.sections(in: [
            try photo("snow", color: "#eef0f2", category: "風景"),
            try photo("plate", color: "#f1efe9", category: "食べ物"),
            try photo("unknown", color: "#f0f0f0", category: nil),
            try photo("curry", color: "#e2761b", category: "food"),
            try photo("sunset", color: "#e2761b", category: "自然"),
        ])
        let byFamily = Dictionary(uniqueKeysWithValues: sections.map { ($0.family, $0.photos.map(\.id)) })
        XCTAssertEqual(byFamily[.white], ["snow"], "料理・分類の無い写真が雪・冬景色に入った")
        XCTAssertEqual(byFamily[.orange], ["sunset"], "料理が夕日に入った")
    }

    /// 白い建物・街は雪ではない。ほかの色味（青い空の建物など）には入れてよい
    func testWhiteIsOnlyForLandscapeAndNature() throws {
        let sections = ColorFamilies.sections(in: [
            try photo("cathedral", color: "#ededed", category: "建築"),
            try photo("bluebuilding", color: "#2f6fd0", category: "architecture"),
        ])
        XCTAssertEqual(sections.map(\.family), [.blue], "白い建物が雪・冬景色に入った")
    }
}
