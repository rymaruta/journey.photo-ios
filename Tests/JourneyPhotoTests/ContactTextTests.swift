import XCTest
@testable import JourneyPhoto

/// すれちがいの自分で書く字に、連絡先の形（URL・メール・電話番号・ID）を受け付けない（2026-10-16 owner の決定）
final class ContactTextTests: XCTestCase {

    /// 拾う形
    func testCatchesContacts() {
        let caught = [
            // URL
            "https://example.com", "http://a.b", "見てね www.kiri", "abc.com", "kiri.jp", "kiri.co.jp",
            // 全角・空白・言い換えの抜け道
            "ａｂｃ．ｃｏｍ", "abc . com", "abc。com", "abcドットcom", "abc dot jp", "abc(dot)net", "abcdotcom",
            // メール
            "kiri@example", "kiri＠example", "kiri アット example", "kiri (at) mail",
            // ID
            "@kiri_photo", "ラインは @kirikiri", "LINE ID: kiri", "ID：kiri",
            // 電話番号（区切り・全角・漢数字）
            "09012345678", "090-1234-5678", "090 1234 5678", "０９０ー１２３４ー５６７８", "〇九〇一二三四五六七八",
            "03(1234)5678", "+81 90 1234 5678",
            // 日付に見えて日付ではない並び（2026-10-16 の読み直し）
            "+81-90-1234-5678", "090-12-34-5678", "2026.10.16.1234",
            // 空白なしの弱い終わり
            "kiri.me", "kiri.to", "abc.shop",
        ]
        for text in caught {
            XCTAssertTrue(PassExchange.containsContact(text), "拾えない: \(text)")
        }
    }

    /// 通す形（誤って止めない）
    func testLetsOrdinaryTextThrough() {
        let passed = [
            "霧の朝が好きです", "北陸ひとり旅", "2026.10.16", "26.10.16 15時", "2026-10-16", "10/16",
            "1,047km", "1,284 km", "No.0087", "e.g. 雪国", "Mt.Fuji", "あっという間", "3泊4日", "1234567",
            "Hokuriku", "雪国", "夕方の街を歩くのが好き", "ID なし", "",
            // 英語の文（点の後に空白がある弱い終わり・2026-10-16 の読み直し）
            "Loved it. So good", "Kyoto. To Osaka", "Hi. Me too", "you vs. me", "Kyoto. Work trip", "Osaka.Tokyo",
            // 年の範囲・日付と時刻
            "2016-2026", "2016〜2026", "2026/10/16 18時",
        ]
        for text in passed {
            XCTAssertFalse(PassExchange.containsContact(text), "通さない: \(text)")
        }
    }

    /// 入力側: 訳を出す（打っている途中では切らない・保存を押せなくするのは訳があるかで決める）
    func testInputProblems() {
        XCTAssertEqual(PassExchange.noteProblem("連絡は kiri@example"), PassExchange.contactProblem)
        XCTAssertEqual(PassExchange.labelProblem("abc.jp"), PassExchange.contactProblem)
        XCTAssertNil(PassExchange.noteProblem("霧の朝"))
        XCTAssertNil(PassExchange.labelProblem("金沢"))
    }

    /// 受け取る側: 該当した字は伏せた扱い（区間は自動の形・ひとことは出さない）
    func testReceivedContactsAreHidden() {
        let card = PassEncounter(id: "c", photoId: "p", note: "電話 090-1234-5678", showsFrom: true, metHour: Date(),
                                 deliverAt: Date(), placeName: "京都市", placeLat: nil, placeLng: nil, number: 1,
                                 opened: false, ownerId: "a", originLabel: "abc.com", destinationLabel: "金沢")
        XCTAssertEqual(card.shownNote, "", "連絡先の形のひとことが出た")
        XCTAssertNil(card.shownOrigin, "連絡先の形の発が区間に出た")
        XCTAssertEqual(card.shownDestination, "金沢", "ふつうの着まで伏せた")
        XCTAssertEqual(PassTicket.origin("北海道", written: card.shownOrigin), "北海道", "自動の形に戻らない")
        // 通報には元の字のまま入る
        XCTAssertTrue(card.writtenText.contains("abc.com"))
    }

    /// 長く貼り付けても頭の 200 字ほどだけを見る（重くしない）
    func testScanIsBounded() {
        let long = String(repeating: "霧", count: 5000) + " kiri@example"
        XCTAssertFalse(PassExchange.containsContact(long), "頭より後ろまで見ている")
        XCTAssertTrue(PassExchange.containsContact("kiri@example" + String(repeating: "霧", count: 5000)))
    }

    /// 受け取った時に判定した印を使う（描くたびに判定し直さない）
    func testRecordedFlagsWin() {
        var card = PassEncounter(id: "c", photoId: "p", note: "ふつうの字", showsFrom: true, metHour: Date(),
                                 deliverAt: Date(), placeName: nil, placeLat: nil, placeLng: nil, number: 1,
                                 opened: false, ownerId: "a", originLabel: "雪国")
        card.noteContact = true
        card.originContact = true
        XCTAssertEqual(card.shownNote, "", "持っている印を使わない")
        XCTAssertNil(card.shownOrigin)
    }
}
