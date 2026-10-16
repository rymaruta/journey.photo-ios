import XCTest
@testable import JourneyPhoto

/// すれちがい（板「10 すれちがい」・2026-10-16）の、画面と電波を持たない決まり
final class PassExchangeTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    private func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    // MARK: - 電波に載せる中身

    func testPayloadRoundTrips() throws {
        let payload = PassExchange.Payload(photoId: "abc-123_XYZ", showsFrom: true, note: "霧の朝が好きです")
        let data = try XCTUnwrap(PassExchange.encode(payload))
        XCTAssertEqual(PassExchange.decode(data), payload)
        let hidden = PassExchange.Payload(photoId: "p1", showsFrom: false, note: "")
        XCTAssertEqual(PassExchange.decode(try XCTUnwrap(PassExchange.encode(hidden))), hidden)
    }

    /// 載せるのは版・印・id・ひとことだけ（id の長さを持つので、ひとことに区切りの字が要らない）
    func testPayloadLayoutIsVersionFlagsIdNote() throws {
        let data = try XCTUnwrap(PassExchange.encode(.init(photoId: "ab", showsFrom: true, note: "x")))
        XCTAssertEqual([UInt8](data), [1, 1, 2, 0x61, 0x62, 0x78])
    }

    /// 🔴 **相手の端末から来た値は信じない**: 知らない版・長さが合わない・id に使えない字・長すぎるひとこと
    func testDecodeRejectsBrokenOrForeignData() {
        XCTAssertNil(PassExchange.decode(Data([2, 0, 2, 0x61, 0x62])), "知らない版を読んだ")
        XCTAssertNil(PassExchange.decode(Data([1, 0, 9, 0x61, 0x62])), "長さの合わない id を読んだ")
        XCTAssertNil(PassExchange.decode(Data([1, 0, 0, 0x61])), "空の id を読んだ")
        XCTAssertNil(PassExchange.decode(Data([1, 0, 3, 0x2E, 0x2E, 0x2F])), "../ を id として読んだ")
        let long = [UInt8]([1, 0, 1, 0x61]) + Array(String(repeating: "あ", count: 21).utf8)
        XCTAssertNil(PassExchange.decode(Data(long)), "21 字のひとことを読んだ")
        XCTAssertNil(PassExchange.decode(Data()), "空を読んだ")
    }

    func testEncodeRefusesUnsafeIdAndCleansNote() throws {
        XCTAssertNil(PassExchange.encode(.init(photoId: "a/b", showsFrom: true, note: "")))
        XCTAssertNil(PassExchange.encode(.init(photoId: String(repeating: "a", count: 65), showsFrom: true, note: "")))
        let data = try XCTUnwrap(PassExchange.encode(.init(photoId: "p", showsFrom: true,
                                                         note: " 一行目\n二行目" + String(repeating: "あ", count: 30))))
        let note = try XCTUnwrap(PassExchange.decode(data)).note
        XCTAssertFalse(note.contains("\n"), "改行が残った")
        XCTAssertEqual(note.count, PassExchange.noteLimit)
        XCTAssertTrue(note.hasPrefix("一行目 二行目"))
    }

    // MARK: - 届く時刻

    /// 18 時より前ならその日の 18 時、18 時を過ぎたら次の日の 18 時（すぐ届けると「いま近くにいる」が分かる）
    func testDeliveryIsTheEveningOfTheDayOrTheNext() {
        XCTAssertEqual(PassExchange.deliveryDate(for: at(16, 9, 5), calendar: calendar), at(16, 18))
        XCTAssertEqual(PassExchange.deliveryDate(for: at(16, 17, 59), calendar: calendar), at(16, 18))
        XCTAssertEqual(PassExchange.deliveryDate(for: at(16, 18), calendar: calendar), at(17, 18))
        XCTAssertEqual(PassExchange.deliveryDate(for: at(16, 23, 30), calendar: calendar), at(17, 18))
        XCTAssertEqual(PassExchange.deliveryDate(for: at(16, 0, 10), calendar: calendar), at(16, 18))
    }

    /// 時刻は時の単位（分を持たない・出さない）
    func testTimeIsKeptAndShownOnlyByTheHour() {
        XCTAssertEqual(PassExchange.hourStart(at(16, 15, 42), calendar: calendar), at(16, 15))
        let label = PassExchange.timeLabel(at(16, 15, 42), calendar: calendar)
        XCTAssertTrue(label.hasPrefix("2026.10.16 · "), label)
        XCTAssertFalse(label.contains("42"), "分が出た: \(label)")
        XCTAssertFalse(label.contains(":"), "時刻の書き方で分が出た: \(label)")
    }

    func testDayKey() {
        XCTAssertEqual(PassExchange.dayKey(at(16, 23, 59), calendar: calendar), "2026-10-16")
        XCTAssertEqual(PassExchange.dayKey(at(17, 0), calendar: calendar), "2026-10-17")
    }

    // MARK: - 場所・出身・距離

    /// 場所は 0.1 度（およそ 11km）に丸める——番地の粒度を持たない
    func testPlaceIsCoarsened() {
        let c = PassExchange.coarse(Photo.Coords(lat: 34.99487, lng: 135.78503))
        XCTAssertEqual(c.lat, 35.0, accuracy: 1e-9)
        XCTAssertEqual(c.lng, 135.8, accuracy: 1e-9)
    }

    func testPlaceNamePrefersTheTown() {
        XCTAssertEqual(PassExchange.placeName(locality: "京都市", administrativeArea: "京都府"), "京都市")
        XCTAssertEqual(PassExchange.placeName(locality: " ", administrativeArea: "北海道"), "北海道")
        XCTAssertNil(PassExchange.placeName(locality: nil, administrativeArea: nil))
        XCTAssertNil(PassExchange.placeLabel(nil))
        XCTAssertNil(PassExchange.placeLabel("  "))
    }

    /// 出身は居住地の自由入力から都道府県だけ
    func testHomePrefectureFromFreeText() {
        XCTAssertEqual(PassExchange.homePrefecture("京都府京都市左京区"), "京都府")
        XCTAssertEqual(PassExchange.homePrefecture("福岡"), "福岡県")
        XCTAssertEqual(PassExchange.homePrefecture("北海道"), "北海道")
        XCTAssertNil(PassExchange.homePrefecture("Tokyo, Japan"))
        XCTAssertNil(PassExchange.homePrefecture(nil))
    }

    func testPrefectureOfficesCoverAll47() {
        XCTAssertEqual(PassExchange.prefectureOffices.count, 47)
        XCTAssertEqual(Set(PassExchange.prefectureOffices.keys), Set(RegionList.prefectures))
        for (name, c) in PassExchange.prefectureOffices {
            XCTAssertTrue(RegionList.isInJapan(c), "\(name) の庁の位置が日本の外")
        }
    }

    /// 板「札幌 → 京都 1,047km」のあたり
    func testTravelDistanceAndRoute() throws {
        let kyoto = Photo.Coords(lat: 35.0, lng: 135.8)
        let km = try XCTUnwrap(PassExchange.travelKm(fromPrefecture: "北海道", to: kyoto))
        XCTAssertTrue((1000...1100).contains(km), "\(km)")
        XCTAssertNil(PassExchange.travelKm(fromPrefecture: nil, to: kyoto))
        XCTAssertNil(PassExchange.travelKm(fromPrefecture: "北海道", to: nil))
        XCTAssertEqual(PassExchange.routeLabel(fromPrefecture: "北海道", placeName: "京都市", km: 1047),
                       "北海道 → 京都市 1,047km")
        XCTAssertNil(PassExchange.routeLabel(fromPrefecture: "京都府", placeName: "京都市", km: 0))
    }

    func testGroupedNumbers() {
        XCTAssertEqual(PassExchange.grouped(7), "7")
        XCTAssertEqual(PassExchange.grouped(128), "128")
        XCTAssertEqual(PassExchange.grouped(1284), "1,284")
        XCTAssertEqual(PassExchange.grouped(1_000_000), "1,000,000")
        XCTAssertEqual(PassExchange.kmText(1047), "1,047km")
        XCTAssertEqual(PassExchange.numberLabel(87), "No.0087")
        XCTAssertEqual(PassExchange.shortNumber(87), "0087")
    }

    // MARK: - いつ交換するか

    func testAwayFromHome() {
        let kyotoHome = "京都府"
        XCTAssertEqual(PassExchange.isAway(current: Photo.Coords(lat: 35.01, lng: 135.76), homePrefecture: kyotoHome), false)
        XCTAssertEqual(PassExchange.isAway(current: Photo.Coords(lat: 43.06, lng: 141.35), homePrefecture: kyotoHome), true)
        XCTAssertNil(PassExchange.isAway(current: nil, homePrefecture: kyotoHome))
        XCTAssertNil(PassExchange.isAway(current: Photo.Coords(lat: 43, lng: 141), homePrefecture: nil))
    }

    /// 🔴 **分からないときは交換しない**（「旅のあいだ」で家からの距離が分からない日）
    func testExchangeRules() {
        XCTAssertTrue(PassExchange.allowsExchange(mode: .always, isForeground: false, awayFromHome: nil))
        XCTAssertTrue(PassExchange.allowsExchange(mode: .foreground, isForeground: true, awayFromHome: nil))
        XCTAssertFalse(PassExchange.allowsExchange(mode: .foreground, isForeground: false, awayFromHome: true))
        XCTAssertTrue(PassExchange.allowsExchange(mode: .traveling, isForeground: false, awayFromHome: true))
        XCTAssertFalse(PassExchange.allowsExchange(mode: .traveling, isForeground: true, awayFromHome: false))
        XCTAssertFalse(PassExchange.allowsExchange(mode: .traveling, isForeground: true, awayFromHome: nil))
    }

    /// 名刺にできるのは全体に公開している写真だけ（絞った写真は相手の端末で引けない）
    func testOnlyPublicPhotosCanBeCards() throws {
        func photo(_ extra: String) throws -> Photo {
            try JSONDecoder.api.decode(Photo.self, from: Data(#"{"id":"p","src":"/u/p.jpg"\#(extra)}"#.utf8))
        }
        XCTAssertTrue(PassExchange.isPublicCard(try photo("")))
        XCTAssertTrue(PassExchange.isPublicCard(try photo(#","audience":"""#)))
        XCTAssertFalse(PassExchange.isPublicCard(try photo(#","audience":"followers""#)))
        XCTAssertFalse(PassExchange.isPublicCard(try photo(#","audience":"closeFriends""#)))
        XCTAssertFalse(PassExchange.isPublicCard(try photo(#","published":false"#)))
    }

    // MARK: - めくり・電波

    func testSwipeStep() {
        XCTAssertEqual(PassViewerMotion.step(forDrag: -120, distance: 90), 1)
        XCTAssertEqual(PassViewerMotion.step(forDrag: 120, distance: 90), -1)
        XCTAssertEqual(PassViewerMotion.step(forDrag: 40, distance: 90), 0)
    }

    /// 読めた端末には `retryInterval` の間は繋ぎ直さない・同時に繋ぐ数に上限
    func testRadioDoesNotHammerTheSamePeer() {
        let now = Date()
        typealias R = PassRadio.PeerRecord
        XCTAssertTrue(PassRadio.shouldConnect(nil, connecting: 0, now: now))
        XCTAssertFalse(PassRadio.shouldConnect(R(lastSuccess: now.addingTimeInterval(-60)), connecting: 0, now: now))
        XCTAssertTrue(PassRadio.shouldConnect(R(lastSuccess: now.addingTimeInterval(-PassRadio.retryInterval)),
                                              connecting: 0, now: now))
        XCTAssertFalse(PassRadio.shouldConnect(nil, connecting: PassRadio.maxConnections, now: now))
    }

    /// 🔴 **読めなかった相手を見捨てない**（重ねて受けない探し方では二度と知らされなかった）。
    /// 失敗は上限の回数までは試し直す
    func testRadioRetriesFailedPeersUpToALimit() {
        let now = Date()
        let once = PassRadio.PeerRecord(failures: [now.addingTimeInterval(-5)])
        XCTAssertTrue(PassRadio.shouldConnect(once, connecting: 0, now: now), "一度読めなかった相手に二度と繋がない")
        let many = PassRadio.PeerRecord(failures: Array(repeating: now.addingTimeInterval(-5), count: PassRadio.maxFailures))
        XCTAssertFalse(PassRadio.shouldConnect(many, connecting: 0, now: now), "読めない相手に繋ぎ続ける")
        let old = PassRadio.PeerRecord(failures: Array(repeating: now.addingTimeInterval(-PassRadio.retryInterval - 1),
                                                       count: PassRadio.maxFailures))
        XCTAssertTrue(PassRadio.shouldConnect(old, connecting: 0, now: now))
        XCTAssertTrue(PassRadio.pruned([UUID(): old], now: now).isEmpty, "古い記録が残る")
    }

    /// 🔴 **背景では遅らせた処理が走らない**ので、10 秒を過ぎた接続待ちは次の知らせのときに自分で切る
    func testStaleConnectionsAreFound() {
        let now = Date()
        let fresh = UUID(), stale = UUID()
        let found = PassRadio.staleConnections([fresh: now.addingTimeInterval(-2),
                                                stale: now.addingTimeInterval(-PassRadio.connectTimeout - 1)], now: now)
        XCTAssertEqual(found, [stale])
    }

    // MARK: - ひとことの形

    /// バイトの上限（送る側・受ける側とも）。字の途中で切らない
    func testNoteByteLimit() throws {
        let emoji = String(repeating: "👨‍👩‍👧", count: 20)
        let clean = PassExchange.cleanNote(emoji)
        XCTAssertLessThanOrEqual(clean.utf8.count, PassExchange.noteByteLimit)
        XCTAssertTrue(clean.allSatisfy { $0 == "👨‍👩‍👧" }, "絵文字の途中で切った")
        let tooBig = [UInt8]([1, 0, 1, 0x61]) + Array(String(repeating: "👍", count: 21).utf8)
        XCTAssertNil(PassExchange.decode(Data(tooBig)))
        let big = [UInt8]([1, 0, 1, 0x61]) + Array(String(repeating: "あ", count: 27).utf8) // 81 バイト
        XCTAssertNil(PassExchange.decode(Data(big)), "80 バイトを超えたひとことを読んだ")
        let ok = PassExchange.Payload(photoId: String(repeating: "a", count: 64), showsFrom: true, note: emoji)
        XCTAssertLessThanOrEqual(try XCTUnwrap(PassExchange.encode(ok)).count, PassExchange.payloadByteLimit)
    }

    /// ZWJ・異体字セレクタは残し、向きの制御・ゼロ幅の空白は落とす。重ね書きの結合文字は上限まで
    func testNoteKeepsEmojiAndDropsTricks() {
        XCTAssertEqual(PassExchange.cleanNote("❤️👨‍👩‍👧"), "❤️👨‍👩‍👧", "ZWJ・異体字セレクタを落とした")
        XCTAssertEqual(PassExchange.cleanNote("a\u{202E}bc\u{200B}d"), "abcd", "向きの制御・ゼロ幅の空白が残った")
        let zalgo = "e" + String(repeating: "\u{0301}", count: 30)
        let clean = PassExchange.cleanNote(zalgo)
        let marks = clean.unicodeScalars.filter { $0.properties.generalCategory == .nonspacingMark }.count
        XCTAssertEqual(marks, PassExchange.marksPerCharacterLimit, "重ね書きの結合文字が残った")
        XCTAssertEqual(PassExchange.cleanNote("é"), "é")
    }

    // MARK: - 説明の文

    /// 🔴 **仕組みが守っていない約束を書かない**（暗号化なし・誰でも読める・ブロックした人にも届きうる）
    func testPrivacyTextMatchesTheMechanism() {
        let all = ([PassPrivacyText.noteTitle, PassPrivacyText.noteBody] + PassPrivacyText.introPoints.map(\.text))
            .joined(separator: "\n")
        for banned in ["いま近くに誰がいるか", "誰にも分かりません", "ブロックした人のカードは届きません。",
                       "who is nearby right now", "No one can tell"] {
            XCTAssertFalse(all.contains(banned), "守れない約束が残っている: \(banned)")
        }
        let ja = PassPrivacyText.noteBody + PassPrivacyText.noteTitle
        if ja.contains("暗号化") {
            XCTAssertTrue(ja.contains("暗号化していません"))
            XCTAssertTrue(ja.contains("ブロックした人にも"))
            XCTAssertTrue(ja.contains("名刺の写真とひとことが読めます"))
        } else {
            XCTAssertTrue(ja.contains("isn\u{2019}t encrypted"))
            XCTAssertTrue(ja.contains("blocked may still receive"))
        }
    }
}
