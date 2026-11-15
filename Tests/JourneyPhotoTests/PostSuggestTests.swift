import XCTest
@testable import JourneyPhoto

/// 投稿の題・説明・タグの候補の整え方（札 #622・2026-11-15）。AI は呼ばない（Linux でも走る）
final class PostSuggestTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: OnDeviceAI.modeKey)
        super.tearDown()
    }

    // MARK: - タグを選択肢に縛る

    func testTagsAreLimitedToChoices() {
        let result = PostSuggest.result(titles: [], caption: nil, tags: ["紅葉", "金沢", "京都旅行", "秋", "#海", "桜"])
        XCTAssertEqual(result.tags, ["紅葉", "秋", "海"], "選択肢に無い語（金沢・京都旅行）は落とし、3つまで")
        XCTAssertTrue(result.tags.allSatisfy(TagChoices.all.contains))
    }

    func testTagAliasesFoldToChoiceSpelling() {
        // 英語の別名・大小は選択肢の綴りにそろえる（同じ主題が2つのタグに割れない）
        XCTAssertEqual(PostSuggest.choices(["Autumn", "sunset", "秋"]), ["秋", "夕焼け"])
    }

    func testTagOrderPutsSuggestionsFirstWithoutAddingChips() {
        let ordered = PostSuggest.orderedChoices(suggested: ["紅葉", "金沢", "秋"])
        XCTAssertEqual(Array(ordered.prefix(2)), ["紅葉", "秋"])
        XCTAssertEqual(Set(ordered), Set(TagChoices.all), "札の数は増えない（選択肢の並べ替えだけ）")
        XCTAssertEqual(ordered.count, TagChoices.all.count)
    }

    func testTagsAcrossPhotosAreMergedUpToThree() {
        let a = PostSuggest.Result(titles: [], caption: nil, tags: ["秋", "紅葉"])
        let b = PostSuggest.Result(titles: [], caption: nil, tags: ["紅葉", "山", "空"])
        XCTAssertEqual(PostSuggest.tags([a, nil, b]), ["秋", "紅葉", "山"])
    }

    // MARK: - 候補の整え方

    func testTitlesDropBannedWordsAndMiddleDots() {
        let result = PostSuggest.result(
            titles: ["「兼六園の紅葉」", "兼六園・雪吊り", "秋の撮りどき", "捨てられない一枚", "兼六園の紅葉", "朝の庭園。"],
            caption: nil, tags: [])
        XCTAssertEqual(result.titles, ["兼六園の紅葉", "兼六園、雪吊り", "朝の庭園"],
                       "かっこと「。」を落とし、中黒は「、」に、「撮りどき」「捨て」を含むものと重なりは落とす")
        XCTAssertFalse(result.titles.contains { $0.contains("・") || $0.contains("·") })
    }

    func testSpotWordingUsesKankoSpot() {
        XCTAssertEqual(PostSuggest.tidy("撮影スポットの朝", isTitle: true), "観光スポットの朝")
    }

    func testTitleLengthAndCount() {
        let long = String(repeating: "長", count: 40)
        let result = PostSuggest.result(titles: ["a", long, "一", "二の題", "三の題", "四の題", "五の題"], caption: nil, tags: [])
        XCTAssertEqual(result.titles, ["二の題", "三の題", "四の題"], "短すぎ・長すぎは落とし、3つまで")
    }

    func testCaptionTidy() {
        let result = PostSuggest.result(titles: ["朝の庭園"], caption: "  紅葉の庭園・朝の光。\n2行目 ", tags: [])
        XCTAssertEqual(result.caption, "紅葉の庭園、朝の光。", "1行目だけ、中黒は「、」")
        XCTAssertNil(PostSuggest.result(titles: [], caption: "詳しくは https://example.com を見てください", tags: []).caption)
        XCTAssertNil(PostSuggest.result(titles: ["朝の庭園"], caption: "朝の庭園", tags: []).caption,
                     "題の候補と同じ字の説明は出さない")
    }

    // MARK: - 欄を書き換えない（空のときだけ候補を出す）

    func testCandidatesOnlyForEmptyFields() {
        let result = PostSuggest.sample
        XCTAssertEqual(PostSuggest.showsTitles(result, title: ""), result.titles)
        XCTAssertEqual(PostSuggest.showsTitles(result, title: "  "), result.titles)
        XCTAssertEqual(PostSuggest.showsTitles(result, title: "自分の題"), [], "打った題の上に候補を出さない")
        XCTAssertEqual(PostSuggest.showsCaption(result, caption: ""), result.caption)
        XCTAssertNil(PostSuggest.showsCaption(result, caption: "自分の説明"))
        XCTAssertEqual(PostSuggest.showsTitles(nil, title: ""), [], "候補が無ければ何も出さない")
    }

    // MARK: - 使えない機種では出さない

    func testUnavailableDeviceShowsNothing() async {
        UserDefaults.standard.set("off", forKey: OnDeviceAI.modeKey)
        XCTAssertFalse(OnDeviceAI.isAvailable)
        let result = await PostSuggester.live(PostSuggest.Input(place: "兼六園", takenOn: "2026-11-03"), nil)
        XCTAssertNil(result, "使えない機種・OS では候補を出さない")
    }

    func testSystemWithoutModelIsUnavailable() async {
        // 試験の切り替えが無いとき、端末の答えに従う。Linux（FoundationModels が無い）は使えない
        UserDefaults.standard.removeObject(forKey: OnDeviceAI.modeKey)
        #if !canImport(FoundationModels)
        XCTAssertEqual(OnDeviceAI.status, .unavailable("noFramework"))
        let result = await PostSuggester.live(PostSuggest.Input(place: "兼六園"), nil)
        XCTAssertNil(result)
        #endif
        if !OnDeviceAI.systemStatus.isAvailable {
            XCTAssertFalse(OnDeviceAI.isAvailable)
        }
    }

    func testSampleModeReturnsFixedCandidatesWithoutAI() async {
        UserDefaults.standard.set("sample", forKey: OnDeviceAI.modeKey)
        let result = await PostSuggester.live(PostSuggest.Input(), nil)
        XCTAssertEqual(result, PostSuggest.sample)
        XCTAssertTrue(PostSuggest.sample.tags.allSatisfy(TagChoices.all.contains))
    }

    // MARK: - 材料

    func testPromptOnlyHasKnownMaterial() {
        let prompt = PostSuggest.prompt(.init(place: "兼六園（石川県金沢市）", spotName: "兼六園",
                                              spotSeasons: ["autumn", "winter", "x"], spotTimes: ["morning", "?"],
                                              takenOn: "2026-11-03", takenHour: 16, labels: ["tree", "garden"]))
        XCTAssertTrue(prompt.contains("撮影地: 兼六園（石川県金沢市）"))
        XCTAssertTrue(prompt.contains("観光スポット: 兼六園"))
        XCTAssertTrue(prompt.contains("観光スポットの見頃の季節: 秋、冬"), "知らない季節の値は書かない")
        XCTAssertTrue(prompt.contains("撮影に向く時間帯: 朝"))
        XCTAssertTrue(prompt.contains("撮った日: 2026年11月3日 16時ごろ（秋、夕方）"))
        XCTAssertTrue(prompt.contains("写っているもの（画像の分類、英語）: tree, garden"))
        XCTAssertFalse(prompt.contains("・"))
        XCTAssertFalse(PostSuggest.instructions.contains("撮影スポット"))

        let bare = PostSuggest.prompt(.init())
        XCTAssertFalse(bare.contains("撮影地:"), "無い材料の行は書かない")
        XCTAssertFalse(bare.contains("撮った日:"))
        XCTAssertTrue(PostSuggest.Input().isEmpty)
    }

    func testHourFromExif() {
        XCTAssertEqual(PostSuggest.hour(fromExif: "2026:11:03 16:42:10"), 16)
        XCTAssertEqual(PostSuggest.hour(fromExif: "2026-11-03T07:05:00"), 7)
        XCTAssertNil(PostSuggest.hour(fromExif: "2026-11-03"))
        XCTAssertNil(PostSuggest.hour(fromExif: nil))
        XCTAssertNil(PostSuggest.takenText(on: "2026-13-01", hour: nil))
    }

    func testKeyChangesWithPlace() {
        let a = PostSuggest.key(.init(place: "兼六園"))
        XCTAssertNotEqual(a, PostSuggest.key(.init(place: "金沢城")))
        XCTAssertEqual(a, PostSuggest.key(.init(place: " 兼六園 ")))
    }
}
