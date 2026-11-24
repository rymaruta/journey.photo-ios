import XCTest
@testable import JourneyPhoto

/// 主要な行き先で旅行プランを組めるか（2026-11-24・owner「メジャーなところで旅行プラン組みたいのに組めなかった」・TestFlight 1.2.1）。
///
/// 台帳は 2026-11-24 の本番の索引（`spot-feed/index.json`）から、主要な行き先の県の国内の公開の観光スポットだけを抜いたもの
/// （`Tests/Fixtures/trip-ai-major-spots.json`・1264件）。AI は使わない（読み取り・候補・AI なしの組み方だけを見る）
@MainActor
final class TripAIMajorPlacesTests: XCTestCase {

    private static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/trip-ai-major-spots.json")

    private static var cached: [OfficialSpot]?
    private func ledger() throws -> [OfficialSpot] {
        if let cached = Self.cached { return cached }
        let data = try Data(contentsOf: Self.fixtureURL)
        var rows = try JSONDecoder.api.decode([OfficialSpot].self, from: data)
        for i in rows.indices { rows[i].isIndexOnly = true }
        Self.cached = rows
        return rows
    }

    /// 頼みの文 → 期待する県（最初の県）と日数
    private static let cases: [(text: String, prefecture: String, days: Int)] = [
        ("東京 2泊3日", "東京都", 3),
        ("東京都で1泊2日", "東京都", 2),
        ("京都旅行 1泊2日", "京都府", 2),
        ("京都市 日帰り", "京都府", 1),
        ("京都 2泊3日 紅葉", "京都府", 3),
        ("大阪 日帰り", "大阪府", 1),
        ("札幌 2泊3日", "北海道", 3),
        ("北海道 3泊4日", "北海道", 4),
        ("沖縄 3泊4日", "沖縄県", 4),
        ("金沢 1泊2日", "石川県", 2),
        ("箱根 日帰り", "神奈川県", 1),
        ("日光 日帰り", "栃木県", 1),
        ("福岡 1泊2日", "福岡県", 2),
        ("広島と宮島 1泊2日", "広島県", 2),
        ("奈良 日帰り", "奈良県", 1),
        ("横浜 日帰り", "神奈川県", 1),
        ("鎌倉 日帰り", "神奈川県", 1),
        ("名古屋 1泊2日", "愛知県", 2),
        ("仙台 1泊2日", "宮城県", 2),
        ("函館 1泊2日", "北海道", 2),
        ("長崎 1泊2日", "長崎県", 2),
        ("神戸 日帰り", "兵庫県", 1),
        ("伊勢 1泊2日", "三重県", 2),
        ("別府 1泊2日", "大分県", 2),
    ]

    /// 行き先と日数が読め、候補が日数に足り、AI なしの組み方でも日ごとに分かれる
    func testMajorDestinationsCanBePlanned() async throws {
        let rows = try ledger()
        var failures: [String] = []
        for c in Self.cases {
            let ask = TripAIAsk.reading(c.text, spots: rows)
            guard ask.prefectures.first == c.prefecture else {
                failures.append("\(c.text): 行き先 \(ask.prefectures)（期待 \(c.prefecture)）")
                continue
            }
            XCTAssertEqual(ask.days, c.days, c.text)
            let cands = TripAIRunner.candidates(for: ask, index: rows, wishlist: [])
            // 1日2か所以上は組めるだけの候補（AI の決まり「1日に2〜5か所」）
            if cands.count < c.days * 2 { failures.append("\(c.text): 候補 \(cands.count)") }
            // 候補は行き先の県の中だけ
            XCTAssertTrue(cands.allSatisfy { ask.prefectures.contains($0.region?.prefecture ?? "") }, c.text)
            let plan = TripAIFallback.plan(candidates: cands, days: c.days, title: "")
            let days = plan.dayLists(cands, keepEmpty: true)
            if days.count != c.days || days.contains(where: \.isEmpty) {
                failures.append("\(c.text): 日ごと \(days.map(\.count))")
            }
        }
        XCTAssertEqual(failures, [], "組めない行き先")
    }

    /// 「東京都」の字の中の「京都」で京都府を拾わない（前は「東京都で1泊2日」が東京都と京都府の両方になり、候補が2つの県に割れた）
    func testTokyoToDoesNotReadKyoto() async throws {
        let rows = try ledger()
        XCTAssertEqual(TripAIDestination.match("東京都で1泊2日", spots: rows)?.prefectures, ["東京都"])
        XCTAssertEqual(TripAIDestination.match("東京都", spots: rows)?.prefectures, ["東京都"])
        XCTAssertEqual(TripAIDestination.match("京都", spots: rows)?.prefectures, ["京都府"])
    }

    /// 県の名前だけの「沖縄」は沖縄市に寄せない。市で読めない「沖縄旅行」「東京旅行」でも、離れた島から選ばない
    /// （前は「沖縄旅行 3泊4日」の候補の上が新城島・与那国島、「東京旅行」が三宅島だった）
    func testPrefectureNameDoesNotNarrowToSameNamedCity() async throws {
        let rows = try ledger()
        for text in ["沖縄 3泊4日", "沖縄旅行 3泊4日"] {
            let ask = TripAIAsk.reading(text, spots: rows)
            XCTAssertEqual(ask.place, "沖縄", text)
            XCTAssertFalse(ask.cities.contains("沖縄市"), "\(text): 沖縄市に寄せている")
            let cands = TripAIRunner.candidates(for: ask, index: rows, wishlist: [])
            // 沖縄本島（北緯 26.0〜26.9・東経 127.5〜128.4。慶伊瀬島など那覇の沖は入れる）の中だけ
            let off = cands.filter { c in
                guard let p = c.coords else { return false }
                return !(26.0...26.9).contains(p.lat) || !(127.5...128.4).contains(p.lng)
            }
            XCTAssertEqual(off.map(\.name), [], "\(text): 本島の外の島が候補にある")
        }
        let tokyo = TripAIAsk.reading("東京旅行", spots: rows)
        let far = TripAIRunner.candidates(for: tokyo, index: rows, wishlist: []).filter { ($0.coords?.lat ?? 35.7) < 35.2 }
        XCTAssertEqual(far.map(\.name), [], "東京旅行で伊豆諸島が候補にある")
        // 京都・大阪のように県と同じ名前の市が旅の中心なら、市で読む
        let kyoto = TripAIAsk.reading("京都 1泊2日", spots: rows)
        XCTAssertTrue(kyoto.cities.contains("京都市") && kyoto.cities.allSatisfy { $0.hasPrefix("京都市") }, "\(kyoto.cities)")
        // 区がいくつかでも同じ市なら市の名前（前は「札幌」が「北海道」、「名古屋」が「愛知」になった）
        XCTAssertEqual(TripAIAsk.reading("札幌 2泊3日", spots: rows).place, "札幌")
        XCTAssertEqual(TripAIAsk.reading("名古屋", spots: rows).place, "名古屋")
        // 「大阪」で、名前に大阪を含む所のある遠い町（能勢町）を行き先の市にしない
        XCTAssertFalse(TripAIAsk.reading("大阪 日帰り", spots: rows).cities.contains("豊能郡能勢町"))
    }

    /// 行き先の札に、行きたい場所が無くても主要な行き先が並ぶ（前は台帳の多い県 島根・熊本・宮崎・山形 などで埋まっていた）
    func testPlaceChoicesListMajorDestinations() async throws {
        let rows = try ledger()
        let labels = TripAIPlaceChoices.make(first: [], spots: rows).map(\.label)
        for name in ["東京", "京都", "大阪", "北海道", "沖縄", "福岡", "金沢", "箱根"] {
            XCTAssertTrue(labels.contains(name), "\(name) が札に無い: \(labels)")
        }
        // 手がかりの県が先
        XCTAssertEqual(TripAIPlaceChoices.make(first: ["長崎県"], spots: rows).first?.label, "長崎")
        // 京都の札は京都市の周りで組む
        let kyoto = try XCTUnwrap(TripAIPlaceChoices.make(first: [], spots: rows).first { $0.label == "京都" })
        XCTAssertEqual(kyoto.prefectures, ["京都府"])
        XCTAssertTrue(kyoto.cities.contains("京都市") && kyoto.cities.allSatisfy { $0.hasPrefix("京都市") })
        // 台帳に無い県の手がかりは札にしない（選んでも組めない）
        XCTAssertFalse(TripAIPlaceChoices.make(first: ["島根県"], spots: rows).contains { $0.label == "島根" })
    }

    /// 旅の計画の言い方は旅行プランの AI へ（前は「作って」「組んで」「泊」が無いと観光スポットの答えになった）
    func testTripWordingsRouteToTripPlan() async {
        for text in ["京都旅行のプラン", "東京 3日間", "大阪のモデルコース", "京都観光のルート", "札幌旅行の計画",
                     "沖縄 2泊3日", "箱根 日帰り", "金沢の観光コース"] {
            XCTAssertEqual(AskEntry.route(text), .tripPlan, text)
        }
        for text in ["Pro プランでできること", "旅行プランの共有のやり方", "今週末、紅葉が見頃の所は？",
                     "11月3日に紅葉が見頃の所", "ストーリーに曲を付けるには", "京都の紅葉の名所"] {
            XCTAssertEqual(AskEntry.route(text), .ask, text)
        }
    }
}
