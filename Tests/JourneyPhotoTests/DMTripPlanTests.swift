import XCTest
@testable import JourneyPhoto

/// DM の会話から旅行プランを作る（2026-11-12・資料「SNS をもっと SNS に」2a の段①と段②）。
///
/// 固定したいのは:
///  1. 段①: 写真の札の撮影地を集める。頭の語が撮影スポットと同じなら撮影スポット、ほかは撮影地。
///     公開の写真の行があれば座標を使い、非公開は文字だけ。見られない札・ブロックした相手の写真は数えない
///  2. 段②: 文の中の撮影スポットの名前を拾う（長い名前が勝つ・短い名前と下書きは拾わない）。
///     拾えなければ候補（続けて同じ字の長い順・3件まで）
///  3. 休みの組: 祝日の計算（振替休日・国民の休日・春分秋分）と、押すと2日入る組の選び方
///  4. 画面のつなぎ: 帯・長押しの「旅行プランに入れる」・日付の段で保存・共有の口を出さない
final class DMTripPlanTests: XCTestCase {

    private func spot(_ slug: String, name: String, reading: String? = nil, stage: String = "published",
                      lat: Double? = 36.56, lng: Double? = 136.66, prefecture: String? = "石川県") throws -> OfficialSpot {
        var fields = ["\"spotId\":\"sp_\(slug)\"", "\"slug\":\"\(slug)\"", "\"name\":\"\(name)\"", "\"stage\":\"\(stage)\""]
        if let reading { fields.append("\"reading\":\"\(reading)\"") }
        if let lat, let lng { fields.append("\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}") }
        if let prefecture { fields.append("\"region\":{\"prefecture\":\"\(prefecture)\"}") }
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func photo(_ id: String, location: String, coords: String?) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"", "\"location\":\"\(location)\""]
        if let coords { fields.append("\"coords\":\(coords)") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func message(_ id: String, mine: Bool, quote: DMPhotoQuote?) -> DMMessage {
        DMMessage(id: id, from: mine ? "me" : "you", mine: mine, text: "写真を送りました", t: "2026-11-11T00:00:0\(id.count).000Z",
                  photoId: quote?.id ?? id, photoOnly: true, photo: quote)
    }

    private func live(_ id: String, location: String?, owner: String = "you") -> DMPhotoQuote {
        DMPhotoQuote(id: id, state: "live", src: "https://x/\(id).jpg", title: nil, location: location, ownerId: owner)
    }

    // MARK: - 1. 段①: 写真から

    func testPhotoPlacesFromConversation() throws {
        let kenroku = try spot("kenrokuen", name: "兼六園", reading: "けんろくえん")
        let messages = [
            message("1", mine: false, quote: live("p1", location: "兼六園, 金沢市, 石川県")),
            message("2", mine: true, quote: live("p2", location: "ひがし茶屋街, 金沢市", owner: "me")),
            message("3", mine: false, quote: live("p3", location: "兼六園")),                        // 同じ撮影スポット
            message("4", mine: false, quote: DMPhotoQuote(id: "p4", state: "gone")),                // 見られない
            message("5", mine: false, quote: live("p5", location: "  ")),                           // 撮影地なし
            message("6", mine: false, quote: nil),                                                  // 札が分からない
            message("7", mine: false, quote: live("p7", location: "非公開の滝")),                     // 公開の一覧に無い
            message("8", mine: false, quote: live("p8", location: "ブロックした人の場所", owner: "bad")),
        ]
        let photos = [try photo("p2", location: "ひがし茶屋街, 金沢市", coords: "{\"lat\":36.57,\"lng\":136.67}")]
        let found = DMTripPlaces.photoPlaces(messages, index: [kenroku], photos: photos, blocked: ["bad"])
        XCTAssertEqual(found.map(\.place.name), ["兼六園", "ひがし茶屋街, 金沢市", "非公開の滝"])
        XCTAssertEqual(found.map(\.source), [.receivedPhoto, .sentPhoto, .receivedPhoto])
        XCTAssertTrue(found[0].place.isSpot, "頭の語が撮影スポットの名前と同じなら撮影スポット")
        XCTAssertFalse(found[1].place.isSpot)
        XCTAssertEqual(found[1].place.coords, Photo.Coords(lat: 36.57, lng: 136.67), "公開の写真の行から座標を引く")
        XCTAssertNil(found[2].place.coords, "非公開は文字だけ")
        XCTAssertEqual(found[0].detail, "撮影スポット · 送られた写真から")
        XCTAssertEqual(found[1].detail, "撮影地 · 送った写真から")
    }

    /// 名前の一部が同じだけでは撮影スポットにしない（違う場所を入れない）・下書きの行は使わない
    func testPhotoLocationNeedsExactSpotName() throws {
        let kenroku = try spot("kenrokuen", name: "兼六園")
        let draft = try spot("draft", name: "金沢城", stage: "review")
        XCTAssertFalse(DMTripPlaces.place(forLocation: "兼六園の近く, 金沢市", coords: nil, index: [kenroku]).isSpot)
        XCTAssertFalse(DMTripPlaces.place(forLocation: "金沢城, 金沢市", coords: nil, index: [draft]).isSpot)
        XCTAssertTrue(DMTripPlaces.place(forLocation: "兼六園、金沢市", coords: nil, index: [kenroku]).isSpot)
    }

    func testMergedPutsPhotosFirstAndDropsDuplicates() throws {
        let a = DMTripPlaces.Found(place: TripDraft.place(spot: try spot("a", name: "兼六園")), source: .receivedPhoto)
        let b = DMTripPlaces.Found(place: TripDraft.place(spot: try spot("b", name: "金沢21世紀美術館")), source: .text)
        let again = DMTripPlaces.Found(place: a.place, source: .text)
        XCTAssertEqual(DMTripPlaces.merged(photos: [a], added: [again, b]).map(\.id), [a.id, b.id])
        XCTAssertEqual(DMTripPlaces.merged(photos: [a], added: [again, b]).map(\.source), [.receivedPhoto, .text])
    }

    // MARK: - 2. 段②: 文から

    func testSpotsInTextPicksWholeNamesInOrder() throws {
        let kenroku = try spot("kenrokuen", name: "兼六園", reading: "けんろくえん")
        let kiyomizu = try spot("kiyomizudera", name: "清水寺")
        let shimizu = try spot("shimizu", name: "清水港")
        let short = try spot("umi", name: "海岸")
        let draft = try spot("draft", name: "ひがし茶屋街", stage: "review")
        let index = [kiyomizu, kenroku, shimizu, short, draft]
        XCTAssertEqual(DMTripPlaces.spotsInText("兼六園のあと清水寺も行きたい", index: index).map(\.slug),
                       ["kenrokuen", "kiyomizudera"], "文に出た順")
        XCTAssertEqual(DMTripPlaces.spotsInText("けんろくえん いこう", index: index).map(\.slug), ["kenrokuen"], "読みでも拾う")
        XCTAssertTrue(DMTripPlaces.spotsInText("海岸を歩こう", index: index).isEmpty, "2字の名前は拾わない")
        XCTAssertTrue(DMTripPlaces.spotsInText("ひがし茶屋街に行こう", index: index).isEmpty, "下書きの行は拾わない")
        // 別名でも拾う
        let aliases = ["shimizu": ["清水港の"], "kiyomizudera": ["清水の舞台"]]
        XCTAssertEqual(DMTripPlaces.spotsInText("清水の舞台から", index: index, aliases: aliases).map(\.slug), ["kiyomizudera"])
    }

    func testLongerNameWinsOverItsPart() throws {
        let long = try spot("kiyomizudera", name: "清水寺")
        let part = try spot("kiyomizu", name: "清水寺の")   // 長い方が文に入っているときだけ
        XCTAssertEqual(DMTripPlaces.spotsInText("清水寺の紅葉", index: [long, part]).map(\.slug), ["kiyomizu"])
    }

    func testCandidatesWhenNoNameMatches() throws {
        let museum = try spot("21seiki", name: "金沢21世紀美術館")
        let other = try spot("kenrokuen", name: "兼六園")
        let noCoords = try spot("nc", name: "21世紀美術館分館", lat: nil, lng: nil)
        let index = [other, museum, noCoords]
        XCTAssertTrue(DMTripPlaces.spotsInText("21世紀美術館も行きたい", index: index).isEmpty)
        XCTAssertEqual(DMTripPlaces.candidates(for: "21世紀美術館も行きたい", index: index).map(\.slug), ["21seiki"],
                       "続けて同じ字が名前の 6 割以上・座標のある行だけ")
        XCTAssertTrue(DMTripPlaces.candidates(for: "おやすみ", index: index).isEmpty)
        XCTAssertEqual(DMTripPlaces.longestCommonRun(Array("abcde".unicodeScalars), Array("xbcdy".unicodeScalars)), 3)
    }

    func testLabels() {
        XCTAssertEqual(DMTripPlaces.countLabel(2), "2 か所")
        XCTAssertEqual(DMTripPlaces.nextTitle(count: 2), "2 か所で 日付を選ぶ")
        XCTAssertEqual(DMTripPlaces.bandTitle, "この会話から旅行プランを作る")
    }

    // MARK: - 3. 休みの組

    func testJapaneseHolidays2026() {
        for day in ["2026-01-01", "2026-01-12", "2026-02-11", "2026-02-23", "2026-03-20", "2026-04-29",
                    "2026-05-03", "2026-05-04", "2026-05-05", "2026-05-06", "2026-07-20", "2026-08-11",
                    "2026-09-21", "2026-09-22", "2026-09-23", "2026-10-12", "2026-11-03", "2026-11-23"] {
            XCTAssertTrue(TripHolidays.isHoliday(day), day)
        }
        for day in ["2026-01-13", "2026-05-07", "2026-11-22", "2026-11-24", "2026-12-23"] {
            XCTAssertFalse(TripHolidays.isHoliday(day), day)
        }
        XCTAssertEqual(TripHolidays.vernalEquinox(2027), 21)
        XCTAssertEqual(TripHolidays.autumnalEquinox(2025), 23)
        XCTAssertTrue(TripHolidays.isOff("2026-11-14"), "土曜")
        XCTAssertFalse(TripHolidays.isOff("2026-11-11"), "水曜")
    }

    func testHolidayPairsFromTheMockDay() {
        let pairs = TripHolidays.pairs(from: "2026-11-11")
        XCTAssertEqual(pairs.map(\.start), ["2026-11-14", "2026-11-22"], "いちばん近い組と、祝日を含むいちばん近い組")
        XCTAssertEqual(pairs.map(\.end), ["2026-11-15", "2026-11-23"])
        XCTAssertEqual(pairs.map(\.label), ["11/14 · 15（土日）", "11/22 · 23（日・祝）"])
        XCTAssertEqual(TripHolidays.pair(of: ["2026-05-02", "2026-05-03", "2026-05-04", "2026-05-05", "2026-05-06"]).start,
                       "2026-05-03", "平日の祝日とその隣の休み")
        XCTAssertEqual(TripHolidays.label("2026-12-31", "2027-01-01"), "12/31 · 1/1（木・祝）")
    }

    @MainActor
    func testChoosingAPairFillsBothDays() async throws {
        let model = TripCreateModel(initial: [TripDraft.place(spot: try spot("a", name: "兼六園"))])
        model.undated = true
        model.choose(TripHolidays.Pair(start: "2026-11-22", end: "2026-11-23", label: "", hasHoliday: true))
        XCTAssertFalse(model.undated)
        XCTAssertEqual(model.sendDates.start, "2026-11-22")
        XCTAssertEqual(model.sendDates.end, "2026-11-23")
        XCTAssertTrue(model.datesReady)
    }

    // MARK: - 4. 画面のつなぎ

    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
    }

    func testConversationWiresBandMenuAndCreateFlow() throws {
        let conversation = try source("Features/Messages/DMConversationView.swift")
        XCTAssertTrue(conversation.contains("DMTripBand(count: tripFound.count)"), "場所の出た会話に帯")
        XCTAssertTrue(conversation.contains(".contextMenu { bubbleMenu(text) }"), "吹き出しの長押し")
        XCTAssertTrue(conversation.contains("L(\"旅行プランに入れる\", \"Add to a trip\")"))
        XCTAssertTrue(conversation.contains("TripPlanDetailView(planId: planId, model: tripPlans)"), "作ったら日程の画面")
        let views = try source("Features/Messages/DMTripViews.swift")
        XCTAssertTrue(views.contains("TripCreateDatesStep(model: model, next: save, finishTitle:"), "日付の段で保存（押す回数 4 回）")
        XCTAssertTrue(views.contains("WebTheme.accentSoft") && views.contains("strokeBorder(WebTheme.accent"),
                      "帯は案内の帯（真鍮 8% の地・真鍮の縁）")
        XCTAssertNil(views.range(of: #"L\("[^"]*(共有|仲間)"#, options: .regularExpression),
                     "相手と共有する口・仲間の文は出さない（2b は DB の変更が要る）")
        let create = try source("Features/Trips/TripCreateView.swift")
        XCTAssertTrue(create.contains("TripHolidays.pairs(from:"), "日付の段に休みの組")
    }
}
