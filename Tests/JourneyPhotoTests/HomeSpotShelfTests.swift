import XCTest
@testable import JourneyPhoto

/// ホームの「いまの季節のスポット」の段（`HomeSpotShelf`・2026-10-03）。
/// 候補は季節の札と同じ・週替わり・都道府県で散らす・上の札と今日の一問の選択肢は除く。
/// 写真は作例 → 索引の代表写真 → 無し。作例は小さい縮小版で出す
final class HomeSpotShelfTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!
    /// 2026-09-27 12:00 UTC（秋）
    private let now = Date(timeIntervalSince1970: 1_790_510_400)

    private var today: Date { HomeTopCard.today(now, in: utc)! }

    /// 索引の1行。`prefecture` を変えて散らし方を見る
    private func spot(_ id: String, stage: String = "published", image: Bool = false,
                      prefecture: String? = nil,
                      seasons: [(String, String)] = [("autumn", "秋は紅葉")]) throws -> OfficialSpot {
        var fields = ["\"spotId\":\"\(id)\"", "\"slug\":\"\(id)\"", "\"name\":\"[\(id)]\"", "\"stage\":\"\(stage)\""]
        if image {
            fields.append("\"image\":{\"url\":\"https://journey-photo.com/images/spots/\(id).jpg\",\"author\":\"A\",\"license\":\"CC BY 4.0\"}")
        }
        if let prefecture {
            fields.append("\"region\":{\"prefecture\":\"\(prefecture)\"}")
        }
        if !seasons.isEmpty {
            let list = seasons.map { "{\"season\":\"\($0.0)\",\"text\":\"\($0.1)\"}" }.joined(separator: ",")
            fields.append("\"seasonalGuide\":[\(list)]")
        }
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    /// 違う県の `n` 件（`sp_00`〜）
    private func spots(_ n: Int) throws -> [OfficialSpot] {
        try (0..<n).map { try spot(String(format: "sp_%02d", $0), prefecture: "県\($0)") }
    }

    private func ids(_ shelf: HomeSpotShelf.Shelf?) -> [String] {
        shelf?.entries.map(\.spot.spotId) ?? []
    }

    // MARK: - 何を出すか

    /// 公開済み・いまの季節の案内を持つ行だけ。**写真の無い行も出す**（作例は本文にしか無い）
    func testPicksPublishedSpotsWithThisSeasonRegardlessOfPhoto() throws {
        let ok = try spot("sp_ok", prefecture: "京都府")
        let noImage = try spot("sp_noimage", image: false, prefecture: "奈良県")
        let draft = try spot("sp_draft", stage: "review", prefecture: "大阪府")
        let spring = try spot("sp_spring", prefecture: "兵庫県", seasons: [("spring", "春は桜")])
        let shelf = HomeSpotShelf.shelf(today: today, spots: [draft, spring, ok, noImage])
        XCTAssertEqual(Set(ids(shelf)), ["sp_ok", "sp_noimage"])
        XCTAssertEqual(shelf?.season, "autumn")
        XCTAssertEqual(shelf?.entries.first { $0.id == "sp_ok" }?.guide, "秋は紅葉")
    }

    /// 候補が無ければ段ごと出さない（空き地を作らない）
    func testNoCandidatesMeansNoShelf() throws {
        XCTAssertNil(HomeSpotShelf.shelf(today: today, spots: []))
        XCTAssertNil(HomeSpotShelf.shelf(today: today, spots: [try spot("sp_s", seasons: [("spring", "春")])]))
        let only = try spot("sp_only")
        XCTAssertNil(HomeSpotShelf.shelf(today: today, spots: [only], excluding: ["sp_only"]))
    }

    /// 出すのは `count`（5）件まで＝本文を取りに行くのも5件まで
    func testShowsAtMostCountSpots() throws {
        XCTAssertEqual(HomeSpotShelf.count, 5)
        XCTAssertEqual(ids(HomeSpotShelf.shelf(today: today, spots: try spots(40))).count, 5)
        XCTAssertEqual(ids(HomeSpotShelf.shelf(today: today, spots: try spots(3))).count, 3)
    }

    /// **週替わり**: 同じ週は同じ並び、次の週は `count` 件先から
    func testRotatesWeekly() throws {
        let list = try spots(40)
        let thisWeek = ids(HomeSpotShelf.shelf(today: today, spots: list))
        // 9/27 は日曜。前の日（土曜）は同じ週（週は月曜はじまり）
        let sameWeek = ids(HomeSpotShelf.shelf(today: today.addingTimeInterval(-86_400), spots: list))
        XCTAssertEqual(thisWeek, sameWeek, "同じ週で並びが変わった")
        let week = HomeTopCard.weekNumber(today)
        let start = (week * 5) % 40
        XCTAssertEqual(thisWeek, (0..<5).map { String(format: "sp_%02d", (start + $0) % 40) })
        let nextWeek = ids(HomeSpotShelf.shelf(today: today.addingTimeInterval(7 * 86_400), spots: list))
        XCTAssertEqual(nextWeek, (0..<5).map { String(format: "sp_%02d", (start + 5 + $0) % 40) })
    }

    /// **都道府県で散らす**: 同じ県は1周目で飛ばし、足りなければ飛ばした行で埋める
    func testSpreadsAcrossPrefectures() throws {
        // 回しの起点に関係なく見るため、候補を5件だけにする（全部が段に入る数）
        let kyoto = try (0..<4).map { try spot("sp_k\($0)", prefecture: "京都府") }
        let nara = try spot("sp_n", prefecture: "奈良県")
        let shelf = HomeSpotShelf.shelf(today: today, spots: kyoto + [nara], limit: 2)
        let picked = ids(shelf)
        XCTAssertEqual(picked.count, 2)
        XCTAssertTrue(picked.contains("sp_n"), "京都府が2件並んだ: \(picked)")
        // 県が1つしか無ければ、飛ばした行で埋める（数を減らさない）
        XCTAssertEqual(ids(HomeSpotShelf.shelf(today: today, spots: kyoto, limit: 3)).count, 3)
        // 地域の分からない行は散らす対象にしない
        let unknown = try (0..<3).map { try spot("sp_u\($0)") }
        XCTAssertEqual(ids(HomeSpotShelf.shelf(today: today, spots: unknown, limit: 3)).count, 3)
    }

    /// **除く前に回す**: 1件を除いても、残りの並びはずれない
    func testExcludingDoesNotShiftTheRest() throws {
        let list = try spots(40)
        let all = ids(HomeSpotShelf.shelf(today: today, spots: list))
        let without = ids(HomeSpotShelf.shelf(today: today, spots: list, excluding: [all[0]]))
        XCTAssertFalse(without.contains(all[0]))
        XCTAssertEqual(Array(without.prefix(4)), Array(all.dropFirst()))
    }

    // MARK: - 除くもの

    /// 上の札（季節・行きたい場所）の場所と、今日の一問の選択肢を集める
    func testExcludedCollectsTopCardSpotsAndQuizChoices() throws {
        let a = try spot("sp_a", image: true)
        let b = try spot("sp_b")
        let choices: [HomeTopCard.Choice] = [
            .inSeason(spot: a, season: "autumn", guide: "x"),
            .wishlistSeason(spot: b, season: "autumn", guide: "y"),
            .theme,
        ]
        XCTAssertEqual(HomeSpotShelf.excluded(by: choices, quizSpots: ["sp_q1", "", "sp_q2"]),
                       ["sp_a", "sp_b", "sp_q1", "sp_q2"])
        XCTAssertEqual(HomeSpotShelf.excluded(by: [.theme], quizSpots: []), [])
    }

    /// 上の季節の札に出た場所は、段に二度出ない（並びと段を通して）
    func testTopSeasonCardSpotIsNotRepeatedInTheShelf() throws {
        let list = try (0..<6).map { try spot(String(format: "sp_%02d", $0), image: true, prefecture: "県\($0)") }
        let cards = HomeTopCard.cards(now: now, plans: [], myPhotos: [], openedBookDays: [],
                                      spots: list, timeZone: utc)
        guard case .inSeason(let top, _, _)? = cards.first(where: { $0.slot == "inSeason" }) else {
            return XCTFail("季節の札が出ていない")
        }
        let shelf = HomeSpotShelf.shelf(today: today, spots: list,
                                        excluding: HomeSpotShelf.excluded(by: cards, quizSpots: []))
        XCTAssertFalse(ids(shelf).contains(top.spotId))
        XCTAssertEqual(ids(shelf).count, 5)
    }

    /// 今日の一問の選択肢（答えを含む）は段に出さない
    func testQuizChoicesAreNotShown() throws {
        let q = try XCTUnwrap(DailyQuiz.parse(Data(DailyQuizTests.json(date: "2026-09-27").utf8), date: "2026-09-27"))
        let quizSpots = q.choices.map(\.spotId)
        let list = try quizSpots.map { try spot($0) } + [try spot("sp_other")]
        let shelf = HomeSpotShelf.shelf(today: today, spots: list,
                                        excluding: HomeSpotShelf.excluded(by: [], quizSpots: quizSpots))
        XCTAssertEqual(ids(shelf), ["sp_other"])
    }

    // MARK: - 札の写真

    private func body(samples: [String]) throws -> SpotBody {
        let json = #"{"slug":"a","check":{"kind":"human","verifiedAt":"2026-09-25"},"samples":["#
            + samples.joined(separator: ",") + "]}"
        return try JSONDecoder.api.decode(SpotBody.self, from: Data(json.utf8))
    }

    private func sample(_ name: String, width: Int = 1280) -> String {
        """
        {"src":"https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/\(name).jpg/\(width)px-\(name).jpg",\
        "width":\(width),"height":853,"title":"\(name)","author":"Taro","license":"CC BY-SA 4.0",\
        "licenseUrl":"https://creativecommons.org/licenses/by-sa/4.0",\
        "sourceUrl":"https://commons.wikimedia.org/wiki/File:\(name).jpg"}
        """
    }

    /// 作例が先・読めなかった作例は次の作例・作例が無ければ索引の代表写真・どちらも無ければ nil
    func testPicturePrefersSampleThenCover() throws {
        let withCover = try spot("sp_c", image: true)
        let bare = try spot("sp_b")
        let b = try body(samples: [sample("One"), sample("Two")])
        guard case .sample(let first)? = HomeSpotShelf.picture(for: withCover, body: b) else {
            return XCTFail("作例が先に出ない")
        }
        XCTAssertEqual(first.title, "One")
        let firstURL = HomeSpotShelf.Picture.sample(first).url
        guard case .sample(let second)? = HomeSpotShelf.picture(for: withCover, body: b, broken: [firstURL]) else {
            return XCTFail("読めなかった1枚の次の作例に進まない")
        }
        XCTAssertEqual(second.title, "Two")
        let allBroken: Set<URL> = Set(b.samples.map { HomeSpotShelf.Picture.sample($0).url })
        XCTAssertEqual(HomeSpotShelf.picture(for: withCover, body: b, broken: allBroken), .cover(try XCTUnwrap(withCover.photo)))
        XCTAssertEqual(HomeSpotShelf.picture(for: withCover, body: nil), .cover(try XCTUnwrap(withCover.photo)))
        XCTAssertNil(HomeSpotShelf.picture(for: bare, body: nil))
        XCTAssertNil(HomeSpotShelf.picture(for: bare, body: try body(samples: [])))
    }

    /// 🔴 作例の出典は「題 / 写真: 作者 / ライセンス / Wikimedia Commons」のまま（表示の条件）
    func testSampleCreditKeepsAllFourParts() throws {
        let b = try body(samples: [sample("One")])
        let picture = try XCTUnwrap(HomeSpotShelf.picture(for: try spot("sp_x"), body: b))
        XCTAssertEqual(picture.credit, "One / 写真: Taro / CC BY-SA 4.0 / Wikimedia Commons")
        XCTAssertEqual(picture.creditLinks.count, 2)
    }

    // MARK: - 小さい縮小版

    private func decodedSample(src: String, width: Int) throws -> SpotSample {
        let raw = """
        {"src":"\(src)","width":\(width),"height":800,"title":"T","author":"Taro","license":"CC BY-SA 4.0",\
        "licenseUrl":"https://creativecommons.org/licenses/by-sa/4.0",\
        "sourceUrl":"https://commons.wikimedia.org/wiki/File:T.jpg"}
        """
        return try XCTUnwrap(try body(samples: [raw]).samples.first)
    }

    /// 1280px・960px の縮小版は 500px に替える（同じ Commons の縮小版。標準の幅だけ）
    func testThumbnailShrinksToStandardWidth() throws {
        let base = "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Kinkaku.jpg/"
        let big = try decodedSample(src: base + "1280px-Kinkaku.jpg", width: 1280)
        XCTAssertEqual(big.thumbnail(maxWidth: 500).absoluteString, base + "500px-Kinkaku.jpg")
        let mid = try decodedSample(src: base + "960px-Kinkaku.jpg", width: 960)
        XCTAssertEqual(mid.thumbnail(maxWidth: 500).absoluteString, base + "500px-Kinkaku.jpg")
        XCTAssertEqual(HomeSpotShelf.Picture.sample(big).url.absoluteString, base + "500px-Kinkaku.jpg",
                       "札は小さい縮小版を使う")
    }

    /// もう小さい・形が違うときはそのまま。**%xx の綴りは変えない**
    func testThumbnailKeepsSmallOrUnknownShapes() throws {
        let base = "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/"
        let small = try decodedSample(src: base + "K.jpg/500px-K.jpg", width: 500)
        XCTAssertEqual(small.thumbnail(maxWidth: 500), small.src)
        let narrow = try decodedSample(src: base + "K.jpg/330px-K.jpg", width: 330)
        XCTAssertEqual(narrow.thumbnail(maxWidth: 500), narrow.src)
        let odd = try decodedSample(src: base + "K.jpg/K-large.jpg", width: 1280)
        XCTAssertEqual(odd.thumbnail(maxWidth: 500), odd.src)
        let encoded = "%E9%87%91%E9%96%A3%E5%AF%BA_(1).jpg"
        let jp = try decodedSample(src: base + "\(encoded)/1280px-\(encoded)", width: 1280)
        XCTAssertEqual(jp.thumbnail(maxWidth: 500).absoluteString, base + "\(encoded)/500px-\(encoded)")
    }

    // MARK: - 言葉

    func testEyebrowNamesTheSeason() {
        XCTAssertEqual(HomeSpotShelf.eyebrow("autumn"), "THIS SEASON · 秋")
        XCTAssertEqual(HomeSpotShelf.eyebrow("???"), "THIS SEASON")
        XCTAssertTrue(HomeSpotShelf.note.contains("利用者ではありません"), "作例の撮影者は利用者ではないと添える")
    }

    /// 札の地域は県（国外は国）。空なら出さない
    func testEntryRegionLabel() throws {
        XCTAssertEqual(HomeSpotShelf.Entry(spot: try spot("a", prefecture: "岡山県"), guide: "").regionLabel, "岡山県")
        XCTAssertNil(HomeSpotShelf.Entry(spot: try spot("b"), guide: "").regionLabel)
        XCTAssertNil(HomeSpotShelf.Entry(spot: try spot("c", prefecture: " "), guide: "").regionLabel)
    }
}
