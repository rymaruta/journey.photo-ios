import XCTest
@testable import JourneyPhoto

/// 旅をストーリーに（`TravelStory`・第9章・1.1.83）。
///
/// 固定したいのは:
///  1. 場所は写真の撮影地から、**既定は県まで（海外は国まで）**。県より細かいかもしれない1つの欠片は県までに出さない
///  2. 日付の既定は「今日」。**今日撮った写真でなければ日付**（「今日」と偽らない）。撮影日の無い写真は日付を出さない
///  3. 家からの距離・時刻（分まで）・作り話（座席）を載せない。ただいまの数は旅の一冊の数だけ
///  4. 型・形・場所・日付は次も使う。場面は覚えない
///  5. 文字はインスタの上の帯（11%）と下の送る欄（12%）に隠れない
final class TravelStoryTests: XCTestCase {

    private func photo(_ id: String, location: String? = nil, date: String? = nil,
                       createdAt: String? = nil, published: Bool? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\""]
        if let published { fields.append("\"published\":\(published)") }
        if let location { fields.append("\"location\":\"\(location)\"") }
        if let date { fields.append("\"date\":\"\(date)\"") }
        if let createdAt { fields.append("\"createdAt\":\"\(createdAt)\"") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    /// 2026-11-11 12:00 JST
    private let now = Date(timeIntervalSince1970: 1_794_366_000)

    private func freshDefaults() -> UserDefaults {
        let name = "TravelStoryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: - 既定と覚える

    func testDefaultsAreStampOnPhotoPrefectureToday() {
        let choice = TravelStory.load(phase: .now, defaults: freshDefaults())
        XCTAssertEqual(choice.kind, .stamp, "初めは推奨 1 の切手と消印")
        XCTAssertEqual(choice.mode, .photo)
        XCTAssertEqual(choice.placeLevel, .prefecture, "場所の既定は県まで")
        XCTAssertEqual(choice.dateLevel, .today, "日付の既定は「今日」")
        XCTAssertEqual(choice.phase, .now)
    }

    func testRemembersEverythingButThePhase() {
        let defaults = freshDefaults()
        var choice = TravelStory.Choice()
        choice.kind = .film
        choice.mode = .sticker
        choice.placeLevel = .city
        choice.dateLevel = .none
        choice.phase = .go
        TravelStory.save(choice, defaults: defaults)
        let back = TravelStory.load(phase: .home, defaults: defaults)
        XCTAssertEqual(back.kind, .film)
        XCTAssertEqual(back.mode, .sticker)
        XCTAssertEqual(back.placeLevel, .city)
        XCTAssertEqual(back.dateLevel, .none)
        XCTAssertEqual(back.phase, .home, "場面は入口で決める（覚えない）")
    }

    func testFilmIsNeverASticker() {
        var choice = TravelStory.Choice()
        choice.mode = .sticker
        XCTAssertEqual(choice.with(kind: .stamp).effectiveMode, .sticker)
        XCTAssertEqual(choice.with(kind: .pass).effectiveMode, .sticker)
        XCTAssertEqual(choice.with(kind: .film).effectiveMode, .photo, "フィルムの帯はステッカーにしない")
        // 使わない選び（フィルムの形・場面）では描き直さない
        var other = choice
        other.mode = .photo
        other.phase = .home
        XCTAssertEqual(choice.with(kind: .film).renderKey, other.with(kind: .film).renderKey)
        XCTAssertNotEqual(choice.with(kind: .pass).renderKey, other.with(kind: .pass).renderKey)
    }

    // MARK: - 場所

    func testPlaceIsPrefectureByDefaultAndCityOnlyWhenChosen() {
        let raw = "輪島市, 石川県, 日本"
        XCTAssertEqual(TravelStory.placeText(raw, level: .prefecture), "石川県")
        XCTAssertEqual(TravelStory.placeText(raw, level: .city), "輪島市")
        XCTAssertNil(TravelStory.placeText(raw, level: .none))
        XCTAssertEqual(TravelStory.placeLatin(raw), "ISHIKAWA")
    }

    func testAbroadIsCountryByDefault() {
        XCTAssertEqual(TravelStory.placeText("パリ, フランス", level: .prefecture), "フランス")
        XCTAssertEqual(TravelStory.placeText("パリ, フランス", level: .city), "フランス", "市と見なせないので国（2026-11-12）")
        XCTAssertEqual(TravelStory.placeLatin("Paris, France"), "FRANCE")
        XCTAssertNil(TravelStory.placeLatin("パリ, フランス"), "ラテン文字でない国名は大きな字にしない")
    }

    /// 1つの欠片（「山中湖」）は県より細かいかもしれない。県までには出さない
    func testSinglePieceIsNotShownAtPrefectureLevel() {
        XCTAssertNil(TravelStory.placeText("山中湖", level: .prefecture))
        XCTAssertNil(TravelStory.placeLatin("山中湖"))
        XCTAssertEqual(TravelStory.placeText("山梨県", level: .prefecture), "山梨県")
    }

    /// 最後が日本なのに1行目が都道府県でない住所は、県までに出さない（確かめ役の実測・2026-11-12）。
    /// 国とみなすのは最後の欠片が日本でないときだけ
    func testJapanWithoutPrefectureShowsNothingAtPrefectureLevel() {
        for raw in ["富士山, 日本", "富士吉田市, 日本", "Kyoto City, Japan", "Mt Fuji, Japan"] {
            XCTAssertNil(TravelStory.placeText(raw, level: .prefecture), raw)
            XCTAssertNil(TravelStory.placeLatin(raw), raw)
        }
        // 英文の県があれば県まで（"Kyoto Prefecture" → Kyoto）
        XCTAssertEqual(TravelStory.placeText("Higashiyama Ward, Kyoto, Kyoto Prefecture, Japan", level: .prefecture), "Kyoto")
        XCTAssertEqual(TravelStory.placeLatin("Higashiyama Ward, Kyoto, Kyoto Prefecture, Japan"), "KYOTO")
    }

    /// 海外の市まで: 市と見なせるとき（「市, 州, 国」の自動入力の形）だけ。見なせなければ国にとどめる（2026-11-12 確かめ役）
    func testAbroadCityOnlyWhenItIsSurelyACity() {
        // 市と見なせる: 座標からの自動入力の形
        XCTAssertEqual(TravelStory.placeText("ニューヨーク, ニューヨーク州, アメリカ合衆国", level: .city), "ニューヨーク")
        XCTAssertEqual(TravelStory.placeText("ローマ, ラツィオ州, イタリア", level: .city), "ローマ")
        XCTAssertEqual(TravelStory.placeText("Lyon, Auvergne-Rhône-Alpes Region, France", level: .city), "Lyon")
        // 見なせない: 施設・地方が出るので国
        XCTAssertEqual(TravelStory.placeText("Eiffel Tower, France", level: .city), "France", "欠片2つの1つ目は施設かもしれない")
        XCTAssertEqual(TravelStory.placeText("パリ, フランス", level: .city), "フランス")
        XCTAssertEqual(TravelStory.placeText(
            "ヴェルサイユ, Versailles, Yvelines, イル＝ド＝フランス地域圏, フランス・メトロポリテーヌ, 78000, フランス",
            level: .city), "フランス", "Nominatim の長い形で国の手前（地方）を出した")
        XCTAssertEqual(TravelStory.placeText("エッフェル塔, シャン・ド・マルス, パリ, フランス", level: .city), "フランス")
        XCTAssertEqual(TravelStory.placeText("Eiffel Tower, Champ de Mars, 75007 Paris, France", level: .city), "France")
        XCTAssertEqual(TravelStory.placeText("エッフェル塔, パリ, フランス", level: .city), "フランス", "真ん中が州でない")
        // 日本は今までどおり市区町村
        XCTAssertEqual(TravelStory.placeText("輪島市, 石川県, 日本", level: .city), "輪島市")
    }

    func testHiddenPlaceLeavesNoLatinEither() {
        let facts = TravelStory.Facts(location: "輪島市, 石川県, 日本", takenDay: nil, name: "mika")
        var choice = TravelStory.Choice()
        choice.placeLevel = .none
        let texts = TravelStory.texts(facts, choice: choice, now: now, timeZone: tokyo)
        XCTAssertNil(texts.place)
        XCTAssertNil(texts.placeLatin, "出さないを選んだのに県の英名が残る")
        XCTAssertEqual(TravelStory.pass(facts, choice: choice, texts: texts).big, "ON THE ROAD")
        XCTAssertEqual(TravelStory.from(texts), L("旅先より", "From the road"))
    }

    // MARK: - 日付

    func testTodayOnlyForAPhotoTakenToday() throws {
        let today = TravelStory.facts(of: try photo("a", location: "石川県", date: "2026-11-11"), name: "mika")
        let old = TravelStory.facts(of: try photo("b", location: "石川県", date: "2026-11-09"), name: "mika")
        let choice = TravelStory.Choice()
        XCTAssertEqual(TravelStory.texts(today, choice: choice, now: now, timeZone: tokyo).date, L("今日", "Today"))
        XCTAssertEqual(TravelStory.texts(old, choice: choice, now: now, timeZone: tokyo).date, "2026.11.09",
                       "今日撮っていない写真を「今日」と言っている")
        var dated = choice
        dated.dateLevel = .date
        XCTAssertEqual(TravelStory.texts(today, choice: dated, now: now, timeZone: tokyo).date, "2026.11.11")
        XCTAssertEqual(TravelStory.texts(today, choice: dated, now: now, timeZone: tokyo).postmark, "26.11.11")
        var hidden = choice
        hidden.dateLevel = .none
        let texts = TravelStory.texts(today, choice: hidden, now: now, timeZone: tokyo)
        XCTAssertNil(texts.date)
        XCTAssertNil(texts.postmark, "出さないを選んだのに消印に日付が残る")
    }

    /// 撮影日の無い写真は、投稿した日を「今日」と言わない（日付を出さない）
    func testNoTakenDayMeansNoDate() throws {
        let facts = TravelStory.facts(of: try photo("a", location: "石川県", createdAt: "2026-11-11T03:00:00Z"),
                                      name: "mika")
        XCTAssertNil(facts.takenDay)
        let texts = TravelStory.texts(facts, choice: TravelStory.Choice(), now: now, timeZone: tokyo)
        XCTAssertNil(texts.date)
        XCTAssertNil(texts.postmark)
    }

    func testNoClockTimeAnywhere() throws {
        let facts = TravelStory.facts(of: try photo("a", location: "輪島市, 石川県, 日本", date: "2026-11-11T18:24:00"),
                                      name: "mika")
        for level in TravelStory.DateLevel.allCases {
            var choice = TravelStory.Choice()
            choice.dateLevel = level
            let texts = TravelStory.texts(facts, choice: choice, now: now, timeZone: tokyo)
            for value in [texts.date, texts.postmark].compactMap({ $0 }) {
                XCTAssertFalse(value.contains(":"), "分までの時刻を出している: \(value)")
            }
        }
    }

    // MARK: - 搭乗券

    func testPassForAPhotoHasNoMadeUpFields() throws {
        let facts = TravelStory.facts(of: try photo("a", location: "輪島市, 石川県, 日本", date: "2026-11-11"),
                                      name: "mika")
        var choice = TravelStory.Choice()
        choice.kind = .pass
        choice.phase = .now
        let texts = TravelStory.texts(facts, choice: choice, now: now, timeZone: tokyo)
        let pass = TravelStory.pass(facts, choice: choice, texts: texts)
        XCTAssertEqual(pass.head, "NOW")
        XCTAssertEqual(pass.big, "ISHIKAWA")
        XCTAssertEqual(pass.local, "石川県")
        XCTAssertNil(pass.day, "旅の何日目か分からない写真に DAY を出している")
        XCTAssertEqual(pass.foot.map(\.key), ["DATE", "PASSENGER"])
        XCTAssertFalse(pass.foot.contains { $0.key == "SEAT" }, "座席は作り話")
        choice.phase = .go
        XCTAssertEqual(TravelStory.pass(facts, choice: choice, texts: texts).day, 1)
    }

    func testBackHomeUsesTheTripBookNumbers() throws {
        let start = Date(timeIntervalSince1970: 1_794_182_400) // 2026-11-09 UTC
        let photos = [try photo("a", location: "金沢市, 石川県, 日本", date: "2026-11-09"),
                      try photo("b", location: "輪島市, 石川県, 日本", date: "2026-11-10"),
                      try photo("c", location: "射水市, 富山県, 日本", date: "2026-11-11")]
        let trip = TripBook.Trip(id: "t", place: "石川県", start: start, end: start.addingTimeInterval(2 * 86_400),
                                 photos: photos, timeZone: TimeZone(identifier: "UTC")!)
        let facts = TravelStory.facts(of: trip, lead: photos[1], name: "mika", distance: 312.4)
        XCTAssertEqual(facts.location, "輪島市, 石川県, 日本", "場所は渡した先頭の1枚からだけ")
        XCTAssertEqual(facts.trip?.leadDay, 2)
        var choice = TravelStory.Choice()
        choice.kind = .pass
        choice.phase = .home
        let texts = TravelStory.texts(facts, choice: choice, now: now, timeZone: tokyo)
        let pass = TravelStory.pass(facts, choice: choice, texts: texts)
        XCTAssertEqual(pass.head, "FROM")
        XCTAssertEqual(pass.day, 3)
        XCTAssertEqual(pass.foot, [.init(key: "PHOTOS", value: "3"),
                                   .init(key: "DISTANCE", value: "\(TravelDistance.formatted(312.4)) km")])
        XCTAssertEqual(TravelStory.stampCaption(texts), L("2日目", "Day 2"))
        // 数えられない・0 km の移動は載せない（旅の一冊の画面と同じ）
        let noDistance = TravelStory.facts(of: trip, lead: photos[1], name: "mika", distance: nil)
        XCTAssertEqual(TravelStory.pass(noDistance, choice: choice, texts: texts).foot.map(\.key), ["PHOTOS"])
    }

    // MARK: - 入口の条件（2026-11-12 確かめ役「入口の条件を試験で縛る」）

    /// 写真の詳細: 絞った写真（全体に公開でない）はフィルムの帯に入れない。上の1枚が絞った写真なら何も出さない
    func testPhotoDetailFilmUsesOnlyShareablePhotos() throws {
        let target = try photo("a")
        let group = [target, try photo("b", published: false), try photo("c"), try photo("d", published: false)]
        XCTAssertEqual(TravelStory.filmPicks(target: target, group: group).map(\.id), ["a", "c"])
        XCTAssertTrue(TravelStory.filmPicks(target: try photo("x", published: false), group: group).isEmpty)
    }

    /// 旅の一冊: 先頭（ただいまの場所）は最後の配ってよい1枚。絞った写真の撮影地・画像を使わない。
    /// 配ってよい写真が無ければ入口を出さない（nil）
    func testTripBookSourceUsesOnlyShareablePhotos() throws {
        let start = Date(timeIntervalSince1970: 1_794_182_400)
        let photos = [try photo("a", location: "金沢市, 石川県, 日本", date: "2026-11-09"),
                      try photo("b", location: "輪島市, 石川県, 日本", date: "2026-11-10", published: false),
                      try photo("c", location: "射水市, 富山県, 日本", date: "2026-11-11"),
                      try photo("d", location: "高山市, 岐阜県, 日本", date: "2026-11-11", published: false)]
        let trip = TripBook.Trip(id: "t", place: "石川県", start: start, end: start.addingTimeInterval(2 * 86_400),
                                 photos: photos, timeZone: TimeZone(identifier: "UTC")!)
        let source = try XCTUnwrap(TravelStory.source(of: trip, name: "mika", distance: nil))
        XCTAssertEqual(source.facts.location, "射水市, 富山県, 日本", "絞った写真（高山市）の撮影地を使った")
        XCTAssertEqual(source.lead, photos[2].detailImageURL)
        XCTAssertEqual(source.film, [photos[0].detailImageURL, photos[2].detailImageURL].compactMap { $0 })
        let hidden = TripBook.Trip(id: "h", place: "", start: start, end: start,
                                   photos: [photos[1], photos[3]], timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertNil(TravelStory.source(of: hidden, name: "mika", distance: nil))
    }

    /// 写真の詳細の ⋯: 「SNS に載せる」（ストーリーはこの中）は自分の、全体に公開した写真のときだけ。
    /// ⋯ に「ストーリーに」の行を足さない（2026-11-12 秘書室の判断）
    func testPhotoDetailMenuShowsSocialShareOnlyForShareablePhotos() throws {
        let detail = try source("Sources/JourneyPhoto/Features/PhotoDetail/PhotoDetailView.swift")
        let gate = try XCTUnwrap(detail.range(of: "if CollectionScreen.isShareable(shown) {"))
        let row = try XCTUnwrap(detail.range(of: "L(\"SNS に載せる\", \"Share to social apps\")"))
        XCTAssertLessThan(gate.lowerBound, row.lowerBound)
        // 条件の `{` に対応する `}` を数えて探し、行がその中にあることを確かめる
        var depth = 1
        var end = gate.upperBound
        while depth > 0, end < detail.endIndex {
            if detail[end] == "{" { depth += 1 } else if detail[end] == "}" { depth -= 1 }
            end = detail.index(after: end)
        }
        XCTAssertLessThan(row.lowerBound, end, "「SNS に載せる」が全体に公開した写真の条件の外にある")
        XCTAssertFalse(detail.contains("photo.travelStory"), "⋯ に「ストーリーに」の行を足している（1行にまとめる）")
        XCTAssertTrue(detail.contains("SocialShareSheet("), "「SNS に載せる」の画面に投稿とストーリーの切り替えが無い")
        XCTAssertTrue(detail.contains("TravelStory.filmPicks(target: target, group:"), "写真の詳細が絞り込みを通さずに帯を作っている")
        let book = try source("Sources/JourneyPhoto/Features/Trips/TripBookView.swift")
        XCTAssertTrue(book.contains("TravelStory.source(of: book"), "旅の一冊が絞り込みを通さずに元を作っている")
    }

    /// 「SNS に載せる」の画面: はじめは投稿（今までどおり）、前に選んだ側から始まる
    func testSocialShareStartsAtPostAndRemembers() {
        let name = "TravelStoryTests-mode-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(SocialShareSheet.Mode.load(defaults), .post)
        SocialShareSheet.Mode.save(.story, defaults)
        XCTAssertEqual(SocialShareSheet.Mode.load(defaults), .story)
        XCTAssertEqual(SocialShareSheet.Mode.allCases.map(\.label), [L("投稿", "Post"), L("ストーリー", "Story")])
    }

    /// 共有シートに空の文を渡さない（2026-11-12 確かめ役・`ShareSheet`）
    func testShareSheetDoesNotPassAnEmptyText() throws {
        let sheet = try source("Sources/JourneyPhoto/Features/Common/ShareSheet.swift")
        XCTAssertFalse(sheet.contains("+ [text]"), "空の文も項目として渡している")
        XCTAssertTrue(sheet.contains("if !text.isEmpty { items.append(text) }"))
    }

    // MARK: - 描いて置いておく型（2026-11-12 確かめ役「今の選び＋両隣」）

    func testKeepsOnlyTheCurrentKindAndItsNeighbours() {
        XCTAssertEqual(TravelStory.nearby(.pass), [.pass, .stamp])
        XCTAssertEqual(TravelStory.nearby(.stamp), [.stamp, .pass, .film])
        XCTAssertEqual(TravelStory.nearby(.film), [.film, .stamp])
        let sheet = try? source("Sources/JourneyPhoto/Features/Common/TravelStorySheet.swift")
        XCTAssertTrue(sheet?.contains("outputs = outputs.filter { keys.contains($0.key) }") == true, "置き場を絞っていない")
        XCTAssertTrue(sheet?.contains("onCancel: { job.cancel() }") == true, "取り消した描画を止めていない")
        XCTAssertFalse(sheet?.contains("UIImage(data: output.data)") == true, "払うたびに 1080×1920 を開いている")
    }

    // MARK: - フィルムの帯

    func testFilmPicksStartMiddleEnd() {
        XCTAssertEqual(TravelStory.filmPicks([1, 2, 3, 4, 5, 6, 7]), [1, 4, 7])
        XCTAssertEqual(TravelStory.filmPicks([1, 2, 3]), [1, 2, 3])
        XCTAssertEqual(TravelStory.filmPicks([1, 2]), [1, 2], "足りないときに同じ写真を繰り返さない")
    }

    func testFilmCaption() {
        let texts = TravelStory.Texts(place: "石川県", placeLatin: "ISHIKAWA", date: "今日", postmark: "26.11.11", tripDay: 2)
        let caption = TravelStory.filmCaption(texts)
        XCTAssertEqual(caption.title, "石川県")
        // 中黒でつながない（2026-11-12 owner の好み「・」「·」で区切らない）。欠片のまま描く側へ
        XCTAssertEqual(caption.sub, ["今日", L("2日目", "Day 2")])
        let bare = TravelStory.filmCaption(.init(place: nil, placeLatin: nil, date: nil, postmark: nil, tripDay: nil))
        XCTAssertEqual(bare.title, L("旅の三枚", "Three from the trip"))
        XCTAssertEqual(bare.sub, [])
    }

    /// 絵に載せる文字に「・」「·」の区切りを作らない（2026-11-12 owner の好み）。
    /// 文字を作る所（`TravelStory`）と描く所（`TravelStoryRenderer`）のコードに、中黒でつなぐ書き方が無いこと
    func testNoMiddleDotSeparatorsInTheImage() throws {
        let texts = TravelStory.Texts(place: "石川県", placeLatin: "ISHIKAWA", date: "2026.11.11",
                                      postmark: "26.11.11", tripDay: 3)
        let facts = TravelStory.Facts(location: "輪島市, 石川県, 日本", takenDay: nil, name: "mika")
        var choice = TravelStory.Choice()
        choice.kind = .pass
        var all = [TravelStory.filmCaption(texts).title] + TravelStory.filmCaption(texts).sub
        all += [TravelStory.from(texts), TravelStory.stampCaption(texts) ?? ""]
        for phase in TravelStory.Phase.allCases {
            choice.phase = phase
            let pass = TravelStory.pass(facts, choice: choice, texts: texts)
            all += [pass.phaseLabel, pass.head, pass.big, pass.local] + pass.foot.flatMap { [$0.key, $0.value] }
        }
        for value in all {
            XCTAssertFalse(value.contains("·") || value.contains("・"), "絵の文字に中黒がある: \(value)")
        }
        for path in ["Sources/JourneyPhoto/Core/Text/TravelStory.swift", "Sources/JourneyPhoto/Services/TravelStoryRenderer.swift"] {
            let code = try source(path).components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            XCTAssertFalse(code.contains("separator: \" · \"") || code.contains("separator: \"・\""),
                           "\(path) が中黒でつないでいる")
        }
    }

    // MARK: - 寸法（インスタの上の帯・下の送る欄に隠れない）

    func testEverythingSitsInsideTheSafeArea() {
        typealias Lay = TravelStory.Layout
        let safe = Lay.safeRect
        XCTAssertEqual(safe.minY, 1920 * 0.11, accuracy: 0.5)
        XCTAssertEqual(safe.maxY, 1920 * 0.88, accuracy: 0.5)
        XCTAssertTrue(safe.contains(Lay.passRect), "搭乗券が送る欄に掛かる: \(Lay.passRect)")
        let stamp = Lay.rotatedBounds(Lay.stampRect, degrees: Lay.stampAngle)
        XCTAssertTrue(safe.contains(stamp), "切手が上の帯か下の欄に掛かる: \(stamp)")
        // 消印（切手の右上に掛ける）も上の帯に掛けない
        let postmark = Lay.postmarkRect.offsetBy(dx: Lay.stampRect.minX, dy: Lay.stampRect.minY)
        XCTAssertGreaterThanOrEqual(postmark.minY, safe.minY)
        XCTAssertLessThanOrEqual(postmark.maxX, Lay.canvas.width)
        XCTAssertLessThanOrEqual(Lay.canvas.height - Lay.fromBottom, safe.maxY)
        for frames in 1...3 {
            XCTAssertTrue(safe.contains(Lay.filmRect(frames: frames)), "帯（\(frames)コマ）が隠れる")
            XCTAssertTrue(safe.contains(Lay.filmCaptionRect(frames: frames)), "帯の下の字（\(frames)コマ）が隠れる")
        }
    }

    func testMeasuresFollowTheMock() {
        typealias Lay = TravelStory.Layout
        XCTAssertEqual(Lay.u(100), Lay.canvas.width, "1cqw は幅の 1%")
        XCTAssertEqual(Lay.canvas.width / Lay.canvas.height, 9.0 / 16.0, accuracy: 0.0001, "比率は 9:16 に決め打ち")
        XCTAssertEqual(Lay.filmFrameHeight / Lay.filmFrameWidth, 0.75, accuracy: 0.0001, "コマは 4:3")
        XCTAssertEqual(Lay.passRect.minX, Lay.u(6))
        XCTAssertEqual(Lay.canvas.height - Lay.passRect.maxY, Lay.u(25))
    }
}
