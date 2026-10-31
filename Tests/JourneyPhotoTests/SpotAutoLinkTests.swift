import XCTest
@testable import JourneyPhoto

/// **写真を撮影スポットに自動で結ぶ**（2026-10-31・journey.photo-ios#425）。
///
/// 前半は Swift の突き合わせ（`SpotMatcher`）が **Web の決まり（`lib/utils/spotAutoLink.ts`）と同じ答え**を
/// 出すことを縛る。答えの表 `Tests/Fixtures/spot-auto-link.json` は Web の決まりそのもので作ったもの
/// （`Tools/gen-spot-auto-fixture.ts`）: 本物の台帳の索引（2,689 行）と本番の48枚、Web の試験の
/// 結ばない例・結ぶ例の全部。決まりを Web で直したら、作り直してから Swift を直す。
///
/// 後半は表（`SpotPhotoLinks`）の読み方: `spotId` → 無ければ表 → 外した写真は結ばない。
final class SpotAutoLinkTests: XCTestCase {

    // MARK: - Web と同じ答え

    private struct Fixture: Decodable {
        struct Group: Decodable {
            let name: String
            let cases: [Case]
        }
        struct Case: Decodable {
            let note: String
            let location: String?
            let texts: [String]
            let coords: Photo.Coords?
            let geoApprox: Bool
            let expect: String?
        }
        let from: String
        let groups: [Group]
    }

    private static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/spot-auto-link.json")

    /// 組ごとの索引（`index` はそのまま Web の `SpotMatchIndex` の JSON）
    private static func indexes() throws -> [SpotMatchIndex] {
        let data = try Data(contentsOf: fixtureURL)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let groups = try XCTUnwrap(object["groups"] as? [[String: Any]])
        return try groups.map { group in
            let raw = try JSONSerialization.data(withJSONObject: try XCTUnwrap(group["index"]))
            return try XCTUnwrap(SpotMatchIndex.decode(raw))
        }
    }

    func testSwiftAnswersMatchWebForEveryCase() throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: Self.fixtureURL))
        let indexes = try Self.indexes()
        XCTAssertEqual(fixture.groups.count, indexes.count)
        var total = 0, linked = 0
        for (group, index) in zip(fixture.groups, indexes) {
            let matcher = SpotMatcher(index: index)
            for c in group.cases {
                let got = matcher.match(location: c.location, texts: c.texts, coords: c.coords, geoApprox: c.geoApprox)
                XCTAssertEqual(got, c.expect, "\(group.name) / \(c.note)")
                total += 1
                if c.expect != nil { linked += 1 }
            }
        }
        // 表が減っていないこと（作り直しで例が消えたら気づく）
        XCTAssertEqual(total, 113)
        XCTAssertEqual(linked, 44)
    }

    /// 写真の形（題・説明が言語ごと・段落の配列）から `Photo` に読んで突き合わせても、同じ答え
    /// （`SpotMatcher.texts` の並び。境目をまたぐ一致の例を含む）
    func testSwiftAnswersMatchWebFromPhotoRows() throws {
        let data = try Data(contentsOf: Self.fixtureURL)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let groups = try XCTUnwrap(object["groups"] as? [[String: Any]])
        let indexes = try Self.indexes()
        var checked = 0
        for (group, index) in zip(groups, indexes) {
            let matcher = SpotMatcher(index: index)
            for c in try XCTUnwrap(group["cases"] as? [[String: Any]]) {
                var row: [String: Any] = ["id": "p", "src": "s"]
                let raw = c["photo"] as? [String: Any] ?? [:]
                if let title = raw["title"], !(title is NSNull) { row["title"] = title }
                if let description = raw["description"], !(description is NSNull) { row["description"] = description }
                if let location = c["location"] as? String { row["location"] = location }
                if let coords = c["coords"] as? [String: Any] { row["coords"] = coords }
                if c["geoApprox"] as? Bool == true { row["geoApprox"] = true }
                let photo = try JSONDecoder().decode(Photo.self, from: JSONSerialization.data(withJSONObject: row))
                XCTAssertEqual(matcher.match(photo), c["expect"] as? String, "\(c["note"] ?? "")")
                checked += 1
            }
        }
        XCTAssertEqual(checked, 113)
    }

    /// 本番の48枚: 正しく16・ほかの32枚は結ばない（案の表・Web の `spotAutoLink.test.ts` と同じ数）
    func testProduction48LinksSixteen() throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: Self.fixtureURL))
        let matcher = SpotMatcher(index: try Self.indexes()[0])
        let prod = fixture.groups[0].cases.filter { $0.note.hasPrefix("本番48枚") }
        XCTAssertEqual(prod.count, 48)
        let hits = prod.filter {
            matcher.match(location: $0.location, texts: $0.texts, coords: $0.coords, geoApprox: $0.geoApprox) != nil
        }
        XCTAssertEqual(hits.count, 16)
    }

    // MARK: - 突き合わせの1行ずつ（作った索引で）

    private func index(_ rows: [[String: Any]]) -> SpotMatchIndex {
        let data = try! JSONSerialization.data(withJSONObject: ["v": 1, "spots": rows])
        return SpotMatchIndex.decode(data)!
    }

    private var fox: [String: Any] {
        ["i": "sp_fox", "d": "蔵王キツネ村", "n": "蔵王キツネ村", "a": ["宮城蔵王キツネ村"], "c": [38.02, 140.55], "p": "宮城県"]
    }

    func testPhotoTitleByLocaleIsRead() throws {
        let matcher = SpotMatcher(index: index([fox]))
        let photo = try Self.photo(["id": "p1", "title": ["ja": "夢の中", "en": "Dream"],
                                    "description": ["ja": ["蔵王キツネ村での一枚"]]])
        XCTAssertEqual(matcher.match(photo), "sp_fox")
    }

    func testGeoApproxFromPhotoIsUsed() throws {
        // 撮影地「山形県」・補った位置: 県が食い違うので結ばない（本物の位置なら 5km 以内で結ぶ）
        let matcher = SpotMatcher(index: index([fox]))
        let approx = try Self.photo(["id": "p1", "title": "蔵王キツネ村", "location": "山形県",
                                     "coords": ["lat": 38.02, "lng": 140.55], "geoApprox": true])
        XCTAssertNil(matcher.match(approx))
        let real = try Self.photo(["id": "p1", "title": "蔵王キツネ村", "location": "山形県",
                                   "coords": ["lat": 38.02, "lng": 140.55]])
        XCTAssertEqual(matcher.match(real), "sp_fox")
    }

    func testIndexDecodeDropsBrokenRowsOnly() {
        let data = try! JSONSerialization.data(withJSONObject: ["v": 1, "spots": [fox, ["i": 1, "d": "x", "n": "x"], ["i": "sp_x"]]])
        XCTAssertEqual(SpotMatchIndex.decode(data)?.rows.map(\.id), ["sp_fox"])
        XCTAssertNil(SpotMatchIndex.decode(Data(#"{"v":2,"spots":[]}"#.utf8)))
        XCTAssertNil(SpotMatchIndex.decode(Data("<html>".utf8)))
        XCTAssertEqual(index([fox]).name(of: "sp_fox"), "蔵王キツネ村")
    }

    func testNormalizeMatchesWebNormalizeSpotName() {
        XCTAssertEqual(SpotMatcher.normalize("オペラ・ガルニエ （パリ）"), "オペラ・ガルニエパリ")
        XCTAssertEqual(SpotMatcher.normalize("ＴＯＫＹＯ　Tower, 「港区」"), "tokyotower港区")
    }

    // MARK: - 表（`/app/data/spot-photo-links.json`）

    static func photo(_ fields: [String: Any]) throws -> Photo {
        var row: [String: Any] = ["src": "https://example.com/a.jpg"]
        row.merge(fields) { _, new in new }
        return try JSONDecoder().decode(Photo.self, from: JSONSerialization.data(withJSONObject: row))
    }

    func testLinksDecode() {
        let links = SpotPhotoLinks.decode(Data(#"{"v":1,"links":{"p1":"sp_a","p2":3,"":"sp_b","p3":""}}"#.utf8))
        XCTAssertEqual(links?.links, ["p1": "sp_a"])
        XCTAssertNil(SpotPhotoLinks.decode(Data(#"{"v":2,"links":{}}"#.utf8)), "知らない版は読まない")
        XCTAssertNil(SpotPhotoLinks.decode(Data(#"{"v":1}"#.utf8)))
        XCTAssertNil(SpotPhotoLinks.decode(Data("<html>login</html>".utf8)))
    }

    /// 読む順: 写真の `spotId` → 無ければ表 → 外した写真（`spotAuto: "off"`）は表にあっても結ばない
    func testSpotIdFirstThenTableAndOffWins() throws {
        let links = SpotPhotoLinks(links: ["auto": "sp_a", "mine": "sp_a", "off": "sp_a"])
        XCTAssertEqual(links.spotId(for: try Self.photo(["id": "auto"])), "sp_a")
        XCTAssertEqual(links.spotId(for: try Self.photo(["id": "mine", "spotId": "sp_me"])), "sp_me")
        XCTAssertNil(links.spotId(for: try Self.photo(["id": "off", "spotAuto": "off"])))
        XCTAssertNil(links.spotId(for: try Self.photo(["id": "none"])))
        // 本人が選んだ `spotId` は外した印に負けない（Web と同じ）
        XCTAssertEqual(links.spotId(for: try Self.photo(["id": "x", "spotId": "sp_me", "spotAuto": "off"])), "sp_me")
        XCTAssertNil(links.autoSpotId(for: try Self.photo(["id": "mine", "spotId": "sp_me"])))
    }

    /// 形の違う `spotAuto`・`geoApprox` で写真の行ごと落とさない
    func testOddSpotAutoDoesNotDropPhoto() throws {
        let photo = try Self.photo(["id": "p1", "spotAuto": 1, "geoApprox": "yes"])
        XCTAssertNil(photo.spotAutoMark)
        XCTAssertFalse(photo.isGeoApprox)
        let list = try JSONDecoder().decode(LenientPhotoList.self, from: Data(#"[{"id":"a","src":"s","spotAuto":{"x":1}}]"#.utf8))
        XCTAssertEqual(list.photos.count, 1)
    }

    /// この端末で外した・戻した分は、サイトの作り直しまで表と写真の印より先
    func testOverridesBeatTableUntilRebuild() throws {
        let table = SpotPhotoLinks(links: ["p1": "sp_a"])
        let photo = try Self.photo(["id": "p1"])
        XCTAssertNil(table.with(["p1": .off(spotId: "sp_a")]).spotId(for: photo))
        XCTAssertTrue(table.with(["p1": .off(spotId: "sp_a")]).isOff(photo))
        // 外した写真（表に無い・印が付いている）を戻すと、すぐ結ぶ
        let offPhoto = try Self.photo(["id": "p2", "spotAuto": "off"])
        let restored = SpotPhotoLinks.empty.with(["p2": .on(spotId: "sp_b")])
        XCTAssertEqual(restored.spotId(for: offPhoto), "sp_b")
        XCTAssertFalse(restored.isOff(offPhoto))
    }

    /// 本人に出す先（外していても）。`spotId` を持つ・非公開の写真は出さない
    func testCandidateForOwnerNotice() throws {
        let links = SpotPhotoLinks(links: ["p1": "sp_a"])
        XCTAssertEqual(links.candidate(for: try Self.photo(["id": "p1"])), "sp_a")
        XCTAssertEqual(links.candidate(for: try Self.photo(["id": "p2", "spotAuto": "off"]), rule: "sp_r"), "sp_r")
        XCTAssertNil(links.candidate(for: try Self.photo(["id": "p1", "spotId": "sp_me"])))
        XCTAssertNil(links.candidate(for: try Self.photo(["id": "p1", "published": false])))
        XCTAssertTrue(links.needsRule(for: try Self.photo(["id": "p2", "spotAuto": "off"])))
        XCTAssertFalse(links.needsRule(for: try Self.photo(["id": "p1", "spotAuto": "off"])), "表にあれば求め直さない")
        XCTAssertFalse(links.needsRule(for: try Self.photo(["id": "p3"])), "外していない写真は求め直さない")
    }
}
