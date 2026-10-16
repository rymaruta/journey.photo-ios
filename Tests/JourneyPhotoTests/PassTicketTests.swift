import XCTest
@testable import JourneyPhoto

/// すれちがいのきっぷ（案C・2026-10-16 owner が選んだ）と、二度目の読み直しの直し
final class PassTicketTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    // MARK: - 種類

    /// また会えた > 遠くから > はじめて > ふつう（持ち主が分からないときは数えない）
    func testKindPrecedence() {
        XCTAssertEqual(PassTicket.kind(meetingCount: nil, km: 1200), .plain)
        XCTAssertEqual(PassTicket.kind(meetingCount: 1, km: 100), .first)
        XCTAssertEqual(PassTicket.kind(meetingCount: 1, km: nil), .first)
        XCTAssertEqual(PassTicket.kind(meetingCount: 1, km: 1047), .far(1047))
        XCTAssertEqual(PassTicket.kind(meetingCount: 3, km: 1047), .again(3))
        XCTAssertEqual(PassTicket.kind(meetingCount: 1, km: PassTicket.farKm - 1), .first)
    }

    /// 種類は縁の色だけでなく言葉でも言う（眉ラベル・裏の「回数」）
    func testKindIsAlsoSaidInWords() {
        let kinds: [PassTicket.Kind] = [.plain, .first, .again(3), .far(1047)]
        XCTAssertEqual(Set(kinds.map(PassTicket.eyebrow)).count, 4, "種類が言葉で見分けられない")
        XCTAssertNotEqual(PassTicket.countLabel(.first, meetingCount: 1), PassTicket.countLabel(.again(3), meetingCount: 3))
        XCTAssertTrue(PassTicket.countLabel(.again(3), meetingCount: 3).contains("3"))
    }

    // MARK: - 欠けたときの形

    func testMissingOriginAndPlace() {
        let somewhere = PassTicket.origin(nil)
        XCTAssertFalse(somewhere.isEmpty)
        XCTAssertNotEqual(somewhere, PassTicket.origin("北海道"))
        XCTAssertEqual(PassTicket.origin("北海道"), "北海道")
        XCTAssertEqual(PassTicket.origin("京都府"), "京都")
        XCTAssertFalse(PassTicket.destination(nil).isEmpty)
        XCTAssertEqual(PassTicket.destination("京都市"), "京都")
        XCTAssertNil(PassTicket.distanceLabel(nil))
        XCTAssertNil(PassTicket.distanceLabel(0))
        XCTAssertEqual(PassTicket.distanceLabel(1047), "1,047 km")
        XCTAssertNotEqual(PassTicket.alighting(nil), PassTicket.alighting("京都市"))
        XCTAssertEqual(PassTicket.issuer(name: "mio.k", prefecture: nil), "mio.k")
    }

    func testShortPlace() {
        XCTAssertEqual(PassTicket.shortPlace("東京都"), "東京")
        XCTAssertEqual(PassTicket.shortPlace("札幌市"), "札幌")
        XCTAssertEqual(PassTicket.shortPlace("渋谷区"), "渋谷区")
        XCTAssertEqual(PassTicket.shortPlace("北海道"), "北海道")
        XCTAssertEqual(PassTicket.shortPlace("津市"), "津市", "1字の地名にした")
    }

    /// 日時は時まで（分を出さない）
    func testDateLabelHasNoMinutes() {
        let at = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 15, minute: 42))!
        let label = PassTicket.dateLabel(at, calendar: calendar)
        XCTAssertTrue(label.hasPrefix("26.10.16 "), label)
        XCTAssertFalse(label.contains("42"), label)
        XCTAssertFalse(label.contains(":"), label)
    }

    // MARK: - 読み直しの直し

    /// ひとことの通報は、写真の通報と分かる印と本文を補足に入れる（署名が無いので写真の持ち主を罰さない）
    func testPassNoteReportCarriesMarkerAndText() {
        let note = ModerationService.passNoteReportNote("夕方の街を歩くのが好き", note: "なりすましに見える")
        XCTAssertTrue(note.hasPrefix(ModerationService.passNoteMarker))
        XCTAssertTrue(note.contains("写真の持ち主が書いたとは限らない"))
        XCTAssertTrue(note.contains("本文: 夕方の街を歩くのが好き"))
        XCTAssertTrue(note.contains("補足: なりすましに見える"))
        let long = ModerationService.passNoteReportNote(String(repeating: "あ", count: 600), note: String(repeating: "い", count: 600))
        XCTAssertLessThanOrEqual(PostLimits.length(long), ModerationService.reportNoteMax)
    }

    /// バイトで超えたときは訳を言う
    func testNoteProblemSaysWhy() {
        XCTAssertNil(PassExchange.noteProblem("霧の朝が好きです"))
        XCTAssertNotNil(PassExchange.noteProblem(String(repeating: "あ", count: 21)))
        let emoji = String(repeating: "👨‍👩‍👧", count: 10)
        XCTAssertLessThanOrEqual(emoji.count, PassExchange.noteLimit)
        let problem = PassExchange.noteProblem(emoji)
        XCTAssertNotNil(problem, "絵文字でバイトを超えても訳が出ない")
        XCTAssertNotEqual(problem, PassExchange.noteProblem(String(repeating: "あ", count: 21)))
    }

    /// 🔴 続けて2回変えたとき、前の中身の `didAdd` を後の中身の答えと取り違えない
    func testAfterAddDoesNotMixUpPayloads() {
        let a = Data([1]), b = Data([2])
        // A を足す → B に変えて足す → A の答え → B の答え
        let first = PassRadio.afterAdd(pending: [a, b], current: b, failed: false)
        XCTAssertEqual(first.published, .keep, "前の中身の答えで載せた")
        XCTAssertEqual(first.pending, [b])
        let second = PassRadio.afterAdd(pending: first.pending, current: b, failed: false)
        XCTAssertEqual(second.published, .set(b))
        XCTAssertEqual(PassRadio.afterAdd(pending: [b], current: b, failed: true).published, .clear)
        XCTAssertEqual(PassRadio.afterAdd(pending: [], current: b, failed: false).published, .keep)
        // 同じ中身をもう一度足しているなら、後の答えを待つ
        XCTAssertEqual(PassRadio.afterAdd(pending: [b, b], current: b, failed: false).published, .keep)
    }
}
