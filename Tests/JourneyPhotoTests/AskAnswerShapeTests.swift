import XCTest
@testable import JourneyPhoto

/// AI の答えを短い文と札の理由に分ける（札 #663・2026-11-20 判断）。owner「結果が見づらいな。。」（1.1.107 の実機）
final class AskAnswerShapeTests: XCTestCase {

    /// 1.1.107 の実機の画面写真と同じ8行の答え（「おすすめの」で頼んだ回）
    static let photoAnswer = """
    - 愛知県庁本庁舎: 秋や冬の朝に訪れると、名古屋城の大天守を思わせる屋根が美しく映えます。
    - 熱田神宮: 冬や夏に訪れると、織田信長が奉納した信長塀が歴史を感じさせます。
    - 中部国際空港 スカイデッキ: 冬の訪問で、伊勢湾の向こうに鈴鹿山脈の景色を楽しめます。
    - 茶臼山高原: 冬に訪れると、愛知県唯一のスキー場を楽しめます。
    - 蒲郡 竹島: 竹島橋を渡って訪れると、八百富神社の境内を散策できます。
    - 半田運河と黒壁の蔵: 春に訪れると、黒板張りの醸造蔵が水辺に並ぶ美しい景色が見られます。
    - 日間賀島: 夏や冬に訪れると、「タコとフグの島」として知られる独特の雰囲気を味わえます。
    - 鳳来寺山: 夕方の斜光に照らされた石段と寺を訪れると、国の名勝の美しさを堪能できます。
    """

    private func spots() throws -> [OfficialSpot] {
        [
            try AskSamples.spot("aichi", name: "愛知県庁本庁舎", prefecture: "愛知県", city: "名古屋市", lat: 35.18, lng: 136.90),
            try AskSamples.spot("atsuta", name: "熱田神宮", prefecture: "愛知県", city: "名古屋市", lat: 35.12, lng: 136.90),
            try AskSamples.spot("centrair", name: "中部国際空港スカイデッキ", prefecture: "愛知県", city: "常滑市", lat: 34.85, lng: 136.81),
            try AskSamples.spot("takeshima", name: "蒲郡 竹島", prefecture: "愛知県", city: "蒲郡市", lat: 34.81, lng: 137.22),
        ]
    }

    /// 写真の8行: 文は1〜2文、理由は札に付き、札に無い名前は消える
    func testPhotoAnswerSplitsIntoLeadAndSpotReasons() throws {
        let rows = try spots()
        let shaped = AskAnswerShape.shape("愛知県で季節の案内がある所を選びました。どこも写真に向きます。季節を変えると、ほかの所も出ます。\n"
                                          + Self.photoAnswer, spots: rows)
        XCTAssertEqual(shaped.lead, "愛知県で季節の案内がある所を選びました。どこも写真に向きます。", "文がはじめの1〜2文にならない")
        XCTAssertLessThanOrEqual(shaped.lead.count, AskAnswerShape.leadLimit)
        XCTAssertFalse(shaped.lead.contains("- "), "箇条の行が文に残った")
        XCTAssertEqual(shaped.reasons["sp_aichi"], "秋や冬の朝に訪れると、名古屋城の大天守を思わせる屋根が美しく映えます。")
        XCTAssertEqual(shaped.reasons["sp_atsuta"], "冬や夏に訪れると、織田信長が奉納した信長塀が歴史を感じさせます。")
        // 空白の違い（「中部国際空港 スカイデッキ」と台帳の「中部国際空港スカイデッキ」）でも当てる
        XCTAssertEqual(shaped.reasons["sp_centrair"], "冬の訪問で、伊勢湾の向こうに鈴鹿山脈の景色を楽しめます。")
        XCTAssertEqual(shaped.reasons["sp_takeshima"], "竹島橋を渡って訪れると、八百富神社の境内を散策できます。")
        // 札に無い名前（茶臼山高原、半田運河と黒壁の蔵、日間賀島、鳳来寺山）は文にも理由にも出さない
        XCTAssertEqual(shaped.reasons.count, 4)
        for gone in ["茶臼山高原", "半田運河", "日間賀島", "鳳来寺山"] {
            XCTAssertFalse(shaped.lead.contains(gone), "札に無い名前が文に出た: \(gone)")
            XCTAssertFalse(shaped.reasons.values.contains { $0.contains(gone) }, gone)
        }
    }

    /// 箇条だけの答え（写真の形そのまま）は文が空になり、札の理由だけが残る
    func testListOnlyAnswerHasNoLead() throws {
        let shaped = AskAnswerShape.shape(Self.photoAnswer, spots: try spots())
        XCTAssertEqual(shaped.lead, "")
        XCTAssertEqual(shaped.reasons.count, 4)
    }

    /// 「・」「1.」「**名前**：」の形も読み分ける
    func testOtherListMarks() throws {
        let rows = try spots()
        let text = "おすすめは次の通りです:\n・熱田神宮：朝の参道が静かです\n2. **愛知県庁本庁舎**: 屋根が映えます\n* 架空の岬: 無い所"
        let shaped = AskAnswerShape.shape(text, spots: rows)
        XCTAssertEqual(shaped.lead, "おすすめは次の通りです。")
        XCTAssertEqual(shaped.reasons["sp_atsuta"], "朝の参道が静かです")
        XCTAssertEqual(shaped.reasons["sp_aichi"], "屋根が映えます")
        XCTAssertEqual(shaped.reasons.count, 2)
    }

    /// 1文が80字を超えたら文の切れ目で切る
    func testLongSentenceIsCut() {
        let long = String(repeating: "瀬戸内の島々を望む展望台から", count: 6) + "、夕日がきれいに見えます。次の文。"
        let lead = AskAnswerShape.lead(long)
        XCTAssertLessThanOrEqual(lead.count, AskAnswerShape.leadLimit)
        XCTAssertTrue(lead.hasSuffix("…"))
        XCTAssertEqual(AskAnswerShape.lead("短い文です。2つ目です。3つ目です。"), "短い文です。2つ目です。")
    }

    /// 「観光スポットの情報から」の1行（「台帳」は見せない。前の版の控えの label も言い替える）
    func testSourcesLineHidesLedgerWord() {
        let line = AskText.sourcesLine([.init(kind: .spots, label: "観光スポットの台帳"), .init(kind: .spots, label: AskText.spotsSource)])
        XCTAssertEqual(line, "観光スポットの情報から")
        XCTAssertFalse(line.contains("台帳"))
        XCTAssertEqual(AskText.sourcesLine([.init(kind: .spots, label: "x"), .init(kind: .photos, label: "公開の写真")]),
                       "観光スポットの情報、公開の写真から")
    }

    /// 端末の AI の決まった形の答えも同じ道で札に振り分ける
    func testDeviceStructuredReplyJoinsIntoParsableText() throws {
        let text = AskDevice.joined(lead: "愛知の2か所を選びました。", reasons: [("熱田神宮", "朝の参道が静かです。"), ("架空の岬", "無い所")])
        let shaped = AskAnswerShape.shape(text, spots: try spots())
        XCTAssertEqual(shaped.lead, "愛知の2か所を選びました。")
        XCTAssertEqual(shaped.reasons, ["sp_atsuta": "朝の参道が静かです。"])
    }

    // MARK: - 手順（AskEngine）を通した答え

    /// 端末の AI が写真と同じ形で答えても、答えの文は1〜2文、理由は札、札に無い名前は消える
    @MainActor
    func testEngineShapesDeviceAnswer() async throws {
        let rows = try AskSamples.ledger()
        let picks = rows.filter { ["屋島", "父母ヶ浜"].contains($0.name) }.map { AskLibrary.Pick(spot: $0) }
        let text = """
        香川で夕日がきれいな所を2つ選びました。どちらも夕方の案内があります。海に沈む夕日を撮れます。
        - 屋島: 山上の展望台から、瀬戸内の島へ沈む夕日が見えます。
        - 父母ヶ浜: 潮だまりに空が映ります。
        - 架空の岬: 台帳に無い所です。
        """
        let backend = AskEngine.Backend(
            signedIn: { true }, offline: { false }, deviceAI: { true },
            library: { _ in AskLibrary(spots: rows, photos: []) },
            reserve: { kind, _ in
                AskUsage(tier: "free", kind: kind.rawValue, day: .init(used: 1, limit: 3, remaining: 2),
                         month: .init(used: 1, limit: 10, remaining: 9, resetsOn: "2026-12-01"), serverAllowed: false)
            },
            serverAsk: { _, _, _ in AskService.ServerAnswer(answer: "", general: false) },
            deviceAsk: { _, _, _ in AskDevice.Result(text: text, general: false, picks: picks, photoIds: [],
                                                     sources: [.init(kind: .spots, label: AskText.spotsSource)]) },
            details: { $0 }, userId: { "u1" })
        let engine = AskEngine(history: AskHistoryStore(defaults: UserDefaults(suiteName: "AskAnswerShapeTests.\(UUID().uuidString)")!))
        await engine.start("香川で夕日がきれいな所を教えて", backend: backend)
        let a = try XCTUnwrap(engine.thread.first?.answer)
        XCTAssertEqual(a.text, "香川で夕日がきれいな所を2つ選びました。どちらも夕方の案内があります。")
        XCTAssertEqual(a.reasons?["sp_yashima"], "山上の展望台から、瀬戸内の島へ沈む夕日が見えます。")
        XCTAssertEqual(a.reasons?["sp_chichibugahama"], "潮だまりに空が映ります。")
        XCTAssertEqual(a.reasons?.count, 2)
        XCTAssertFalse(a.text.contains("架空の岬"))
    }

    // MARK: - 案A（2026-11-20 owner 承認）の頭の1〜2文と札のチップ

    /// 頭の文は明朝 20pt。20pt で4行を超える長さ（68字より長い）なら 18pt。断り、使い切った、圏外は 18pt
    func testLeadSizeAndLine() throws {
        XCTAssertEqual(AskAnswerShape.leadPointSize("香川で夕日がきれいな所を2つ選びました。"), 20)
        XCTAssertEqual(AskAnswerShape.leadPointSize(String(repeating: "あ", count: 69)), 18)
        XCTAssertEqual(AskAnswerShape.leadPointSize(String(repeating: "あ", count: 68)), 20)
        XCTAssertEqual(AskAnswerShape.leadPointSize("短い", small: true), 18)
        var ai = AskAnswer(engine: .device)
        ai.text = "愛知の2か所を選びました。"
        ai.spotIds = ["sp_a", "sp_b"]
        ai.heading = "観光スポット（2か所）"
        XCTAssertEqual(AskAnswerShape.leadLine(ai)?.text, "愛知の2か所を選びました。")
        XCTAssertEqual(AskAnswerShape.leadLine(ai)?.small, false)
        var table = AskAnswer(engine: .table)
        table.spotIds = ["sp_a"]
        table.heading = "冬の案内がある観光スポット（6か所）"
        // 2026-11-21 判断（札 #675 の答えの形・版3）: AI を使わずに札を選んだ答えの頭の文は決まり文
        XCTAssertEqual(AskAnswerShape.leadLine(table)?.text, "合う所を1つ選びました。")
        table.chips = ["香川", "冬"]
        XCTAssertEqual(AskAnswerShape.leadLine(table)?.text, "冬に向く所を1つ選びました。")
        XCTAssertEqual(AskAnswerShape.leadLine(table)?.small, true)
        var offline = AskAnswer(engine: .table, state: .offline)
        offline.spotIds = ["a", "b", "c", "d", "e"]
        XCTAssertEqual(AskAnswerShape.leadLine(offline)?.text, "合う所を5つ選びました。")
    }

    /// 札のチップは台帳に欄がある所だけ。季節を先に、時間帯は1つ、3つまで
    func testSpotTagsOnlyFromLedger() throws {
        let rows = try AskSamples.ledger()
        let kenrokuen = try XCTUnwrap(rows.first { $0.name == "兼六園" })
        XCTAssertEqual(AskSpotTags.labels(kenrokuen).map(\.text), ["秋", "冬", "朝"])
        XCTAssertEqual(AskSpotTags.labels(kenrokuen).map(\.time), [false, false, true])
        let plain = try AskSamples.spot("x", name: "欄の無い所", prefecture: "香川県", city: "高松市", lat: 34, lng: 134)
        XCTAssertTrue(AskSpotTags.labels(plain).isEmpty, "台帳に欄が無いのにチップを出す")
    }

    /// 札の並びは、どの札も左から 16 に止まる（札の幅＋12 ごと。端を越えない）。ピンで送るときも左から 16（回 1619、1626 の絵で約 6pt だった）
    func testCardSnapKeepsLeftGutter() {
        let step: CGFloat = 268 + 12
        XCTAssertEqual(AskCardSnap.snapped(0, step: step, maxOffset: 1000), 0)
        XCTAssertEqual(AskCardSnap.snapped(150, step: step, maxOffset: 1000), 280)
        XCTAssertEqual(AskCardSnap.snapped(130, step: step, maxOffset: 1000), 0)
        XCTAssertEqual(AskCardSnap.snapped(900, step: step, maxOffset: 700), 700, "端を越えて送った")
        // 札の左 = 割合 ×（並びの幅 − 札の幅）= 16
        XCTAssertEqual(AskCardSnap.anchorX(container: 402, card: 268) * (402 - 268), 16, accuracy: 0.001)
    }

    /// 前の版の控え（reasons の無い答え）も読める
    func testOldCachedAnswerDecodes() throws {
        let old = #"{"engine":"device","state":"answered","text":"屋島です。","general":false,"spotIds":["sp_yashima"],"distances":{},"photoIds":[],"sources":[],"chips":[],"offersPlan":true}"#
        let a = try JSONDecoder().decode(AskAnswer.self, from: Data(old.utf8))
        XCTAssertNil(a.reasons)
        XCTAssertEqual(a.text, "屋島です。")
    }
}
