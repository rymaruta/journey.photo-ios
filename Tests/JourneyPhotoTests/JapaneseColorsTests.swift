import XCTest
@testable import JourneyPhoto

/// 写真の色に、日本の色の名前（札 #710 の案10）
final class JapaneseColorsTests: XCTestCase {

    /// 表は約100色。名前・読み・ローマ字・由来（日本語と英語）がそろい、名前とローマ字は重ならない
    func testTable() {
        let all = JapaneseColors.all
        XCTAssertGreaterThanOrEqual(all.count, 95)
        XCTAssertLessThanOrEqual(all.count, 110)
        XCTAssertEqual(Set(all.map(\.name)).count, all.count, "同じ名前が2つある")
        XCTAssertEqual(Set(all.map(\.romaji)).count, all.count)
        XCTAssertEqual(Set(all.map(\.hex)).count, all.count, "同じ色の値が2つある")
        for color in all {
            XCTAssertFalse(color.reading.isEmpty || color.origin.isEmpty || color.originEn.isEmpty, color.name)
            XCTAssertFalse(color.origin.contains("・"), "中黒で区切らない: \(color.name)")
            XCTAssertLessThanOrEqual(color.origin.count, 30, "由来は短い1行: \(color.name)")
        }
    }

    /// 表の色そのものは、その名前になる
    func testExactColorsNameThemselves() {
        for color in JapaneseColors.all where color.lab.chroma >= JapaneseColors.minChroma {
            XCTAssertEqual(JapaneseColors.name(forHex: color.hexString), color, color.name)
        }
    }

    /// Lab の距離でいちばん近い色（紅葉の赤は赤の名前）
    func testNearestInLab() {
        XCTAssertEqual(JapaneseColors.name(forHex: "#e63a2a")?.name, "紅緋")
        XCTAssertEqual(JapaneseColors.name(forHex: "#176086")?.name, "藍色")
        XCTAssertEqual(JapaneseColors.lab(hex: 0xFFFFFF).l, 100, accuracy: 0.1)
        XCTAssertEqual(JapaneseColors.lab(hex: 0x000000).l, 0, accuracy: 0.1)
    }

    /// 灰色に近い写真・代表色の無い写真には出さない
    func testGrayAndMissingGetNoName() {
        XCTAssertNil(JapaneseColors.name(forHex: "#808080"))
        XCTAssertNil(JapaneseColors.name(forHex: "#7a7d80"), "わずかに青い灰色に名前を付けた")
        XCTAssertNil(JapaneseColors.name(forHex: nil))
        XCTAssertNil(JapaneseColors.name(forHex: "zzz"))
    }

    /// 表のどの色からも遠い写真には出さない
    func testFarColorGetsNoName() {
        // 表のどの色からも `maxDistance` より遠い色を1つ探して確かめる（無ければ線が広すぎる）
        var found = false
        for r in stride(from: 0, through: 255, by: 51) {
            for g in stride(from: 0, through: 255, by: 51) {
                for b in stride(from: 0, through: 255, by: 51) {
                    let hex = (r << 16) | (g << 8) | b
                    let lab = JapaneseColors.lab(hex: hex)
                    guard lab.chroma >= JapaneseColors.minChroma else { continue }
                    let nearest = JapaneseColors.all.map { $0.lab.distance(to: lab) }.min() ?? 0
                    if nearest > JapaneseColors.maxDistance {
                        XCTAssertNil(JapaneseColors.name(forHex: String(format: "#%06x", hex)))
                        found = true
                    }
                }
            }
        }
        XCTAssertTrue(found, "遠い色が1つも無い（線が広すぎて外れた名前を出す）")
    }

    /// 「この色の写真」: 同じ名前の写真。少ない色は近い色の写真も混ぜる
    func testPhotosForColor() throws {
        func photo(_ id: String, _ color: String?) throws -> Photo {
            var obj: [String: Any] = ["id": id, "src": "https://example.com/\(id).jpg"]
            if let color { obj["dominantColor"] = color }
            return try JSONDecoder.api.decode(Photo.self, from: JSONSerialization.data(withJSONObject: obj))
        }
        let benihi = try XCTUnwrap(JapaneseColors.all.first { $0.name == "紅緋" })
        let near = try XCTUnwrap(JapaneseColors.neighbors(of: benihi).first)
        let photos = [try photo("a", "#e83929"), try photo("b", near.hexString), try photo("c", "#165e83"), try photo("d", nil)]
        let shown = JapaneseColors.photos(for: benihi, in: photos).map(\.id)
        XCTAssertEqual(shown.first, "a")
        XCTAssertTrue(shown.contains("b"), "少ない色に近い色を混ぜていない")
        XCTAssertFalse(shown.contains("c"))
        let many = (0..<6).map { try? photo("p\($0)", "#e83929") }.compactMap { $0 } + [try photo("b", near.hexString)]
        XCTAssertFalse(JapaneseColors.photos(for: benihi, in: many).contains { $0.id == "b" }, "多い色に近い色を混ぜた")
        XCTAssertEqual(JapaneseColors.neighbors(of: benihi).count, 3)
    }

    /// 英語の画面はローマ字と英語の1行（読みは出さない）
    func testEnglishShowsRomaji() throws {
        let color = try XCTUnwrap(JapaneseColors.all.first { $0.name == "藍色" })
        XCTAssertEqual(color.shownName, L("藍色", "Ai-iro"))
        XCTAssertEqual(color.shownOrigin, L(color.origin, color.originEn))
    }

    /// Lab は表の色を作るときに1回だけ計算して持つ（比べるたびに pow を計算し直さない・2026-11-23 確かめ役の指摘）
    func testLabIsStoredNotRecomputed() throws {
        let color = try XCTUnwrap(JapaneseColors.all.first)
        let stored = Mirror(reflecting: color).children.compactMap(\.label)
        XCTAssertTrue(stored.contains("lab"), "Lab を計算型で持っている（比べるたびに計算し直す）")
        XCTAssertEqual(color.lab, JapaneseColors.lab(hex: color.hex))
    }

    /// 「この色の写真」は、名前を写真の id ごとに控えた表で選ぶ（body のたびに全部の写真の名前を引かない）。
    /// 控えで選んでも、毎回引くのと同じ並び
    func testPhotosUseTheCachedNames() throws {
        func photo(_ id: String, _ color: String?) throws -> Photo {
            var obj: [String: Any] = ["id": id, "src": "https://example.com/\(id).jpg"]
            if let color { obj["dominantColor"] = color }
            return try JSONDecoder.api.decode(Photo.self, from: JSONSerialization.data(withJSONObject: obj))
        }
        let benihi = try XCTUnwrap(JapaneseColors.all.first { $0.name == "紅緋" })
        let photos = [try photo("a", "#e83929"), try photo("c", "#165e83"), try photo("d", nil), try photo("g", "#808080")]
        let names = JapaneseColors.names(of: photos)
        XCTAssertEqual(names["a"], benihi.id)
        XCTAssertNil(names["d"])
        XCTAssertNil(names["g"], "灰色に名前を控えた")
        XCTAssertEqual(JapaneseColors.photos(for: benihi, in: photos, names: names).map(\.id),
                       JapaneseColors.photos(for: benihi, in: photos).map(\.id))
        // 控えに無い写真は、代表色があっても並べない（控えだけを見る）
        XCTAssertTrue(JapaneseColors.photos(for: benihi, in: photos, names: [:]).isEmpty)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let view = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Features/PhotoDetail/JapaneseColorViews.swift"),
                              encoding: .utf8)
        XCTAssertTrue(view.contains("JapaneseColors.photos(for: color, in: all, names: colorIds)"), "body の中で全部の写真の名前を引いている")
        XCTAssertTrue(view.contains("colorIds = JapaneseColors.names(of: photos)"))
    }
}
