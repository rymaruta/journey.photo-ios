import XCTest
@testable import JourneyPhoto

/// ホームの撮影スポットの日替わり（`HomeDailySpots`・2026-10-18）。
/// 画面の「今日」を進める判定（端末の時刻帯の暦日・0 時の待ち）と、候補の少ない季節の選び方
final class HomeDailySpotsTests: XCTestCase {

    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    private let paris = TimeZone(identifier: "Europe/Paris")!
    private let utc = TimeZone(identifier: "UTC")!

    // MARK: - 画面の「今日」を進める

    /// **端末の時刻帯の暦日**で進める。今日の一問は日本時間で替わるが、札と段はパリならパリの 0 時
    /// （96e499b7 のレビュー: 日本の外では一問が早抜けし、札が昨日のまま残った）
    func testAdvancesAtLocalMidnightNotAtJapanMidnight() {
        // 2026-10-17 21:30 UTC ＝ パリ 23:30 ／ 東京 10/18 06:30
        let parisBefore = Date(timeIntervalSince1970: 1_792_272_600)
        // 2026-10-17 22:30 UTC ＝ パリ 10/18 00:30 ／ 東京 10/18 07:30
        let parisAfter = Date(timeIntervalSince1970: 1_792_276_200)
        XCTAssertTrue(HomeDailySpots.shouldAdvance(shown: parisBefore, now: parisAfter, in: paris), "パリの 0 時で進まない")
        XCTAssertFalse(HomeDailySpots.shouldAdvance(shown: parisBefore, now: parisAfter, in: tokyo))
        // 一問（日本時間）はこの間ずっと 10/18 のまま＝一問の読み直しでは気づけない
        XCTAssertEqual(DailyQuiz.today(parisBefore), DailyQuiz.today(parisAfter))

        // 2026-10-17 14:30 UTC ＝ 東京 23:30 ／ パリ 16:30。15:30 UTC ＝ 東京 10/18 00:30 ／ パリ 17:30
        let tokyoBefore = Date(timeIntervalSince1970: 1_792_247_400)
        let tokyoAfter = Date(timeIntervalSince1970: 1_792_251_000)
        XCTAssertTrue(HomeDailySpots.shouldAdvance(shown: tokyoBefore, now: tokyoAfter, in: tokyo))
        XCTAssertFalse(HomeDailySpots.shouldAdvance(shown: tokyoBefore, now: tokyoAfter, in: paris), "パリはまだ同じ日")
        // 同じ時刻は進めない・時計が戻って前の日になっても今の日に合わせる
        XCTAssertFalse(HomeDailySpots.shouldAdvance(shown: parisAfter, now: parisAfter, in: paris))
        XCTAssertTrue(HomeDailySpots.shouldAdvance(shown: parisAfter, now: parisBefore, in: paris))
    }

    /// 0 時の待ちは**次の 0 時（端末の時刻帯）の1秒後**まで、ただし15分を超えない（起きるたびに壁時計で確かめ直す）
    func testRecheckWaitsUntilLocalMidnightButAtMostFifteenMinutes() {
        // 2026-10-17 21:59 UTC ＝ パリ 23:59 → 0 時まで 60 秒 ＋ 1
        let parisLate = Date(timeIntervalSince1970: 1_792_274_340)
        XCTAssertEqual(HomeDailySpots.secondsUntilRecheck(now: parisLate, in: paris), 61, accuracy: 0.001)
        // 同じ時刻の東京（10/18 06:59）は 0 時が遠いので15分で起きる
        XCTAssertEqual(HomeDailySpots.secondsUntilRecheck(now: parisLate, in: tokyo), 15 * 60, accuracy: 0.001)
        XCTAssertEqual(HomeDailySpots.secondsUntilRecheck(now: parisLate, in: tokyo, maxWait: 30), 30, accuracy: 0.001)
        // 夏時間の終わる前の晩（パリ 10/24 23:50 CEST）も、その晩の 0 時まで
        let beforeDST = Date(timeIntervalSince1970: 1_792_878_600)
        XCTAssertEqual(HomeDailySpots.secondsUntilRecheck(now: beforeDST, in: paris), 601, accuracy: 0.001)
    }

    // MARK: - 候補の少ない季節

    private func spot(_ id: String, image: Bool = true) throws -> OfficialSpot {
        var fields = ["\"spotId\":\"\(id)\"", "\"slug\":\"\(id)\"", "\"name\":\"[\(id)]\"", "\"stage\":\"published\"",
                      "\"region\":{\"prefecture\":\"県\(id)\"}",
                      "\"seasonalGuide\":[{\"season\":\"autumn\",\"text\":\"秋\"}]"]
        if image {
            fields.append("\"image\":{\"url\":\"https://journey-photo.com/images/spots/\(id).jpg\",\"author\":\"A\",\"license\":\"CC BY 4.0\"}")
        }
        return try JSONDecoder.api.decode(OfficialSpot.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    /// 🔴 写真のある候補の無い組がある季節（候補が少ない）も、**昨日・一昨日の札は出さない**——組を使わず、
    /// 写真のある候補を1日1件ずつ回す（96e499b7 のレビュー: ほかの組から借りた札が翌日の札と同じになる道があった）
    func testBorrowedTopCardDoesNotRepeatTheLastTwoDays() throws {
        // 6件。0番・3番（同じ組）は写真が無い＝その組の日は、ほかの組から借りる
        let list = try (0..<6).map { try spot(String(format: "sp_%02d", $0), image: $0 % 3 != 0) }
        // 2026-09-27 12:00 UTC から60日
        let start = Date(timeIntervalSince1970: 1_790_510_400)
        var picks: [String] = []
        for offset in 0..<60 {
            let at = start.addingTimeInterval(Double(offset) * 86_400)
            let cards = HomeTopCard.cards(now: at, plans: [], myPhotos: [], openedBookDays: [], spots: list, timeZone: utc)
            guard case .inSeason(let card, _, _)? = cards.first(where: { $0.slot == "inSeason" }) else {
                return XCTFail("\(offset)日目に季節の札が無い")
            }
            for (back, past) in picks.suffix(2).reversed().enumerated() {
                XCTAssertNotEqual(card.spotId, past, "\(offset)日目の札が\(back + 1)日前と同じ: \(picks.suffix(2)) → \(card.spotId)")
            }
            picks.append(card.spotId)
        }
        XCTAssertEqual(Set(picks), ["sp_01", "sp_02", "sp_04", "sp_05"], "写真のある4件を回す")
    }

    /// 候補が1件だけなら毎日それ（出せる物がそれしか無い・注記の例外）。2件なら毎日入れ替わる
    func testOneCandidateRepeatsTwoAlternate() throws {
        let start = Date(timeIntervalSince1970: 1_790_510_400)
        let one = [try spot("sp_only")]
        for offset in 0..<5 {
            let cards = HomeTopCard.cards(now: start.addingTimeInterval(Double(offset) * 86_400), plans: [], myPhotos: [],
                                          openedBookDays: [], spots: one, timeZone: utc)
            XCTAssertEqual(cards.map(\.slot), ["inSeason", "theme"])
        }
    }
}
