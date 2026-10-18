import XCTest
@testable import JourneyPhoto

/// 手荷物タグ（2026-10-18 owner「hnd hel がデフォルトでついてるのなんで？」）: 行き先と日付は、その人自身のラベルから作る。
/// モックの固定の行き先（HND→HEL・KIX→BCN・CTS）と日付を、誰にでも貼らない
final class TrunkTagTests: XCTestCase {

    private func label(_ id: String, _ name: String, latin: String? = nil, at: String = "2025-06-20T10:00:00Z",
                       kind: TrunkLabel.Kind = .place) -> TrunkLabel {
        TrunkLabel(id: id, photoId: id, kind: kind, place: .init(name: name, latin: latin, country: nil), seed: 1, at: at)
    }

    /// ラベルの地名（ローマ字があれば大文字）と日付がタグに出る。新しい順に、違う撮影地を投稿の数ぶんまで
    func testTagsComeFromTheOwnersLabels() {
        let stuck = [label("a", "京都", latin: "Kyoto", at: "2026-04-03T09:00:00Z"),
                     label("b", "京都", latin: "Kyoto", at: "2026-03-01T09:00:00Z"),
                     label("c", "高屋神社", at: "2024-10-30T06:00:00Z"),
                     label("d", "パリ", latin: "Paris", at: "2024-02-11T10:00:00Z")]
        let tags = TrunkLooks.tags(stuck: stuck, posts: 120)
        XCTAssertEqual(tags.map(\.code), ["KYOTO", "高屋神社", "PARIS"], "同じ撮影地を2枚・新しい順でない")
        XCTAssertEqual(tags.map(\.printedDay), ["2026.04.03", "2024.10.30", "2024.02.11"])
        XCTAssertEqual(tags.map(\.x), TrunkLooks.tagSlots.map(\.x), "吊るす場所がモックの位置でない")
        XCTAssertEqual(TrunkLooks.tags(stuck: stuck, posts: 20).count, 1)
        XCTAssertEqual(TrunkLooks.tags(stuck: stuck, posts: 19).count, 0, "投稿 20 より前にタグを出す")
    }

    /// 使える地名が足りなければ、足りない枚数ぶん出さない（偽の行き先で埋めない）。地名の無いラベルは使わない
    func testNoPlaceMeansNoTag() {
        XCTAssertTrue(TrunkLooks.tags(stuck: [], posts: 120).isEmpty, "ラベルが無いのにタグが付く")
        let sealed = [label("s1", ""), label("s2", "", kind: .season), label("s3", "  ")]
        XCTAssertTrue(TrunkLooks.tags(stuck: sealed, posts: 120).isEmpty, "地名の無いラベルでタグを作る")
        let one = TrunkLooks.tags(stuck: sealed + [label("k", "札幌", latin: "Sapporo")], posts: 120)
        XCTAssertEqual(one.map(\.code), ["SAPPORO"], "足りない枚数を偽の行き先で埋める")
    }

    /// 人のトランク: 伏せたラベル（人の口が地名を空で返したもの）は使わない
    func testTheirTrunkSkipsHiddenLabels() throws {
        let json = #"""
        {"stuck":[{"id":"s2","kind":"season","seed":1,"place":{"name":""},"where":null},
                  {"id":"s1","kind":"place","seed":2,"place":{"name":"パリ","latin":"Paris"},"at":"2024-02-11","where":{"location":"パリ"}},
                  {"id":"s0","kind":"timeslot","seed":3,"place":{"name":""},"where":null}],"posts":120}
        """#
        let trunk = try JSONDecoder.api.decode(TheirTrunk.self, from: Data(json.utf8))
        let tags = TrunkLooks.tags(stuck: trunk.stuck, posts: trunk.agingPosts)
        XCTAssertEqual(tags.map(\.code), ["PARIS"])
        XCTAssertEqual(tags.first?.printedDay, "2024.02.11")
        // 画面写真の見本の人のトランクでも、地名のあるラベルからタグが出る
        let sample = TheirTrunkSample.trunk(userId: "u")
        let sampleTags = TrunkLooks.tags(stuck: sample.stuck, posts: sample.agingPosts)
        XCTAssertFalse(sampleTags.isEmpty, "見本の人のトランクにタグが出ない")
        let hiddenIds = Set(sample.stuck.filter { $0.place.name.isEmpty }.map(\.id))
        XCTAssertFalse(hiddenIds.isEmpty)
        XCTAssertFalse(sampleTags.contains { $0.code.isEmpty })
    }

    /// 自分のトランクの見本（`-JPPreviewTrunk`）でも、見本のラベルの地名からタグが出る
    func testPreviewSampleHasTags() {
        let state = TrunkSample.state(isPro: false)
        let tags = TrunkLooks.tags(stuck: state.stuck, posts: state.posts ?? 0)
        XCTAssertFalse(tags.isEmpty, "見本でタグが出ない（画面写真で確かめられない）")
        XCTAssertEqual(tags.first?.code, TrunkLooks.tagCode(state.stuck[0]))
    }

    /// 長い地名は字の切れ目で省く（板のタグの幅に収める）
    func testLongNamesAreTrimmed() {
        let long = TrunkLooks.tagCode(label("a", "x", latin: "Saint-Jean-Pied-de-Port"))
        XCTAssertEqual(long, "SAINT-JEAN", "ローマ字の長い地名を省いていない")
        let kanji = TrunkLooks.tagCode(label("b", "日本平夢テラス展望台"))
        XCTAssertEqual(kanji, "日本平夢テ", "かな・漢字の長い地名を省いていない")
        XCTAssertEqual(TrunkLooks.tagCode(label("c", "函館")), "函館")
    }

    /// 偽の行き先の字（モックの HND・HEL・KIX・BCN・CTS と固定の日付）がどこにも残っていない
    func testNoFakeDestinationsAnywhere() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 100)
        let fakes = ["HND→HEL", "KIX→BCN", "\"CTS\"", "2025.06.20", "2023.08.02", "2019.02.08"]
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for fake in fakes { XCTAssertFalse(text.contains(fake), "\(file.lastPathComponent) に偽の行き先 \(fake)") }
        }
        // カプセルの部品「空の便」も行き先の無い字
        let tag = try XCTUnwrap(TrunkPartCatalog.parts(of: .tag).first { $0.name == "空の便" })
        if case .tag(let look) = tag.look {
            XCTAssertEqual(look.t1, "BY AIR")
        } else {
            XCTFail("空の便が札の部品でない")
        }
    }

    /// 5回目の見直し 1: 型を選ぶ画面は絵のラベルを減らすが、手荷物タグは本体と同じ（全部のラベルから）
    func testModelsPreviewKeepsTheSameTags() throws {
        let stuck = [label("a", "京都", latin: "Kyoto", at: "2026-04-03T09:00:00Z"),
                     label("b", "京都", latin: "Kyoto", at: "2026-03-01T09:00:00Z"),
                     label("c", "高屋神社", at: "2024-10-30T06:00:00Z"),
                     label("d", "パリ", latin: "Paris", at: "2024-02-11T10:00:00Z")]
        let main = TrunkLooks.tags(stuck: TrunkLooks.tagSource(stuck: stuck, tagsFrom: nil), posts: 120)
        for count in [2, 3] {
            let preview = TrunkLooks.modelsPreview(stuck, count: count)
            XCTAssertEqual(preview.stuck.count, count, "絵に描くラベルの数が板と違う")
            let tags = TrunkLooks.tags(stuck: TrunkLooks.tagSource(stuck: preview.stuck, tagsFrom: preview.tagsFrom), posts: 120)
            XCTAssertEqual(tags, main, "型を選ぶ画面と本体でタグが割れる（\(count) 枚）")
        }
        XCTAssertEqual(main.count, 3)
        // 型を選ぶ画面はこの形で渡している（ラベルを切って渡す所がほかに無い）
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
        let models = try String(contentsOf: root.appendingPathComponent("Features/Trunk/TrunkModelsView.swift"), encoding: .utf8)
        XCTAssertEqual(models.components(separatedBy: "tagsFrom: preview.tagsFrom").count - 1, 2)
        XCTAssertFalse(models.contains("stuck.prefix("), "型を選ぶ画面がラベルを切って渡している")
    }
}
