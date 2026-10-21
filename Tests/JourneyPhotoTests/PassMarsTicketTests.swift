import XCTest
@testable import JourneyPhoto

/// すれちがいのカードの表と裏を「マルス券」の形にした（**2026-10-17 owner「マルス券いいね」**・候補の板
/// `Plain.dc.html` の「1. マルス券」と「裏」）。表の欄・経由・発／着・読み上げ・種類の名と、表と裏を同じ部品で描くことを見張る
final class PassMarsTicketTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/JourneyPhoto")
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    private func content(placeName: String?, meetingCount: Int = 1, ownerId: String? = "u1",
                         prefecture: String? = "東京都") throws -> PassCardContent {
        let photo = try JSONDecoder.api.decode(Photo.self, from: Data(
            "{\"id\":\"p1\",\"src\":\"/uploads/p1.jpg\",\"userId\":\"u1\"}".utf8))
        let met = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 14, minute: 5))!
        let card = PassEncounter(id: "c", photoId: "p1", note: "", showsFrom: true, metHour: met,
                                 deliverAt: met, placeName: placeName, placeLat: nil, placeLng: nil, number: 87,
                                 opened: false, ownerId: ownerId)
        return PassCardContent(card: card, photo: photo, owner: nil, fromPrefecture: prefecture,
                               meetingCount: meetingCount)
    }

    // MARK: - 表の欄

    /// 日付・区間・回数の3つ（この順）。値が無い欄は「—」で、欄は抜かない
    func testFrontFieldsKeepThreeColumns() {
        let full = PassTicket.frontFields(date: "10.17 14時", distance: "9,712 km", count: "はじめて")
        XCTAssertEqual(full.map(\.label), ["日付", "区間", "回数"])
        XCTAssertEqual(full.map(\.value), ["10.17 14時", "9,712 km", "はじめて"])
        let empty = PassTicket.frontFields(date: nil, distance: nil, count: "")
        XCTAssertEqual(empty.count, 3, "値が無い欄を抜いた（格子が崩れる）")
        XCTAssertEqual(Set(empty.map(\.value)), [PassTicket.blank])
    }

    /// 届いたカードの表: 日付は「10.17 14時」・回数は数えた回・No. は帳の順
    func testReceivedFrontFields() throws {
        let face = try content(placeName: "京都市").face(calendar: calendar)
        XCTAssertEqual(face.fields.map(\.label), ["日付", "区間", "回数"])
        XCTAssertEqual(face.fields[0].value, "10.17 14時")
        XCTAssertEqual(face.fields[2].value, "はじめて")
        XCTAssertEqual(face.number, "No.0087")
        XCTAssertEqual(face.headline, "はじめての乗車券", "種類の名が「乗車券」の位置に出ない")
        // 持ち主が分からない → 数えない（「—」）・種類はふつう＝「乗車券」
        let unknown = try content(placeName: "京都市", ownerId: nil).face(calendar: calendar)
        XCTAssertEqual(unknown.fields[2].value, PassTicket.blank)
        XCTAssertEqual(unknown.headline, "乗車券")
    }

    /// 表と裏の「回数」は同じ値
    func testFrontAndBackShareCount() throws {
        let c = try content(placeName: "京都市", meetingCount: 3)
        XCTAssertEqual(c.face(calendar: calendar).count, c.backFace().count)
        XCTAssertEqual(c.face(calendar: calendar).fields[2].value, "3 度目")
    }

    // MARK: - 経由

    /// 「経由 〇〇のあたり」。場所の記録が無ければ行ごと出さない（nil）
    func testViaLineAppearsOnlyWithPlace() throws {
        XCTAssertEqual(PassTicket.via("清水寺"), "経由 清水寺のあたり")
        XCTAssertNil(PassTicket.via(nil))
        XCTAssertNil(PassTicket.via("  "))
        XCTAssertEqual(try content(placeName: "京都市").face(calendar: calendar).via, "経由 京都市のあたり")
        XCTAssertNil(try content(placeName: nil).face(calendar: calendar).via, "記録が無いのに経由の行を出す")
        // 前の「〇〇のあたり 下車」の行は無くなった
        XCTAssertFalse(try source("Features/Pass/PassCards.swift").contains("下車"))
    }

    // MARK: - 区間の発・着

    /// 「東京発、フランス着」と読む（札の字と同じ）
    func testSpokenRouteSaysDepartureAndArrival() {
        XCTAssertEqual(PassTicket.spokenRoute(origin: "東京", destination: "フランス"), "東京発、フランス着")
        XCTAssertEqual(PassTicket.originMark, "発")
        XCTAssertEqual(PassTicket.destinationMark, "着")
        XCTAssertFalse(PassTicket.marksLead, "日本語で「発」「着」を名の前に置く")
        // 出身が無いときは「どこか」（「どこかから発」と重ねない）
        XCTAssertEqual(PassTicket.origin(nil), "どこか")
    }

    /// 🔴 「発」「着」を添えても、発・着は同じ大きさ・矢印は中央・名と「発」が欄からはみ出さない
    func testMarksDoNotBreakSharedRouteSize() {
        let route = PassCardStyle.routeLayout(origin: "東京", destination: "フランス")
        XCTAssertGreaterThan(route.markWidth, 0, "「発」「着」の幅を数えていない（欄からはみ出す）")
        XCTAssertEqual(route.markWidth, PassCardStyle.markSize + PassCardStyle.markGap, accuracy: 1e-9)
        XCTAssertEqual(route, PassCardStyle.routeLayout(origin: "フランス", destination: "東京"), "左右で大きさが変わる")
        XCTAssertEqual(route.arrowCenter, PassCardStyle.routeWidth / 2, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(PassCardStyle.routeEms("フランス") * route.fontSize + route.markWidth,
                                 route.columnWidth + 1e-9, "「フランス着」が欄からはみ出す")
        // 英語は from / to（幅を数える）。発・着とも同じ大きさ
        let en = PassCardStyle.routeLayout(origin: "Tokyo", destination: "France", marks: ("from", "to"))
        XCTAssertGreaterThan(en.markWidth, route.markWidth)
        XCTAssertLessThanOrEqual(PassCardStyle.routeEms("France") * en.fontSize + en.markWidth, en.columnWidth + 1e-9)
        // 区間の字は本文系の 12 を割らない・「発」「着」も 12
        XCTAssertGreaterThanOrEqual(PassCardStyle.routeMinSize, 12)
        XCTAssertGreaterThanOrEqual(PassCardStyle.markSize, 12)
    }

    /// 表の区間は、名の後ろに「発」「着」を同じ並びの線（下）でそろえて描く
    func testFrontDrawsMarksBesideNames() throws {
        let cards = try source("Features/Pass/PassCards.swift")
        for part in ["routeColumn(face.origin, mark: PassTicket.originMark, route)",
                     "routeColumn(face.destination, mark: PassTicket.destinationMark, route)",
                     "HStack(alignment: .firstTextBaseline, spacing: CGFloat(PassCardStyle.markGap))",
                     ".font(.custom(JPFont.displayName, fixedSize: CGFloat(PassCardStyle.markSize)))"] {
            XCTAssertTrue(cards.contains(part), "区間の発・着の描き方が違う: \(part)")
        }
    }

    // MARK: - 種類の名

    /// 種類は「乗車券」の位置の言葉でも分かる（4つとも違う・どれも「乗車券」の名）
    func testHeadlineTellsKindInWords() {
        let kinds: [PassTicket.Kind] = [.plain, .first, .again(2), .far(900)]
        XCTAssertEqual(Set(kinds.map(PassTicket.headline)).count, 4, "種類が言葉で見分けられない")
        XCTAssertEqual(PassTicket.headline(.plain), "乗車券")
        XCTAssertTrue(kinds.allSatisfy { PassTicket.headline($0).hasSuffix("乗車券") })
    }

    // MARK: - 裏

    /// 裏の欄は 発行・有効・区間・回数（2×2）。届いたカードは No. と「届きました」、見本は No. なしで「届きます」
    func testBackFieldsAndFootnote() throws {
        let back = try content(placeName: "京都市").backFace()
        XCTAssertEqual(back.fields.map(\.label), ["発行", "有効", "区間", "回数"])
        XCTAssertEqual(back.number, "No.0087")
        XCTAssertEqual(back.footnote, PassTicket.receivedFootnote)
        XCTAssertTrue(back.footnote.contains("届きました"))
        let own = PassTicketBackFace.preview(photoTitle: "霧の朝", note: "", name: "mio", origin: .hidden,
                                             homePrefecture: nil)
        XCTAssertNil(own.number, "自分のカードの見本に番号を出した（番号は受け取った側で決まる）")
        XCTAssertEqual(own.footnote, PassTicket.ownFootnote)
        XCTAssertTrue(own.footnote.contains("届きます"))
        XCTAssertEqual(own.fields[2].value, PassTicket.blank)
        XCTAssertEqual(own.fields[3].value, PassTicket.blank)
    }

    /// 裏は板の帯（高さ 44・案内の帯の地・下に真鍮の線）・欄は `face.fields`・裾に一行
    func testBackShape() throws {
        let cards = try source("Features/Pass/PassCards.swift")
        guard let start = cards.range(of: "struct PassCardBack"),
              let end = cards.range(of: "/// 帳の綴じの小さなきっぷ") else { return XCTFail("裏が無い") }
        let back = String(cards[start.lowerBound..<end.lowerBound])
        for part in [".frame(height: PassCardStyle.bandHeight)", ".background(WebTheme.accentSoft)",
                     "PassTicketRule(opacity: PassCardStyle.bandRuleOpacity, shine: shine)",
                     "let fields = PassTicket.shown(face.fields)", "PassTicketDash(shine: shine)", "Text(face.footnote)"] {
            XCTAssertTrue(back.contains(part), "裏に \(part) が無い")
        }
        XCTAssertEqual(PassCardStyle.bandHeight, 44)
        XCTAssertFalse(back.contains("LinearGradient"), "前の案C の帯（傾きの地）が残っている")
    }

    // MARK: - 寸法

    /// 板の寸法（札 300×430・角 14・写真 214）と、本文系 12 以上（眉ラベルの類だけ 11）
    func testMarsDimensions() {
        XCTAssertEqual(PassCardStyle.deckSize, CGSize(width: 300, height: 430))
        XCTAssertEqual(PassCardStyle.deckCorner, 14)
        XCTAssertEqual(PassCardStyle.photoHeight, 214)
        XCTAssertEqual(PassCardStyle.photoRuleOpacity, 0.55, accuracy: 1e-9)
        // 文（「すれちがいの日から ずっと有効」・裏の裾）は本文系なので 12 以上（2026-10-17: 11 だったのを直した）
        for size in [PassCardStyle.metaSize, PassCardStyle.fieldValueSize, PassCardStyle.backLabelSize,
                     PassCardStyle.backValueSize, PassCardStyle.headSize, PassCardStyle.validitySize,
                     PassCardStyle.footnoteSize] {
            XCTAssertGreaterThanOrEqual(size, 12, "本文系が 12 を割る")
        }
        // 11 でよいのは眉ラベルの類（番号・欄の小さな見出し）だけ
        for size in [PassCardStyle.numberSize, PassCardStyle.fieldLabelSize] {
            XCTAssertGreaterThanOrEqual(size, 11, "眉ラベルの類でも 11 を割る")
        }
        // 裾を 12 にした分の縦は上の余白から取る（下と左右は板の 18 のまま）
        XCTAssertLessThan(PassCardStyle.backTop, PassCardStyle.backPadding)
    }

    /// 表は写真の下端に真鍮の線・欄の格子・名前と「ずっと有効」。前の改札の穴は無い
    func testFrontShape() throws {
        let cards = try source("Features/Pass/PassCards.swift")
        guard let start = cards.range(of: "struct PassCardFront"),
              let end = cards.range(of: "struct PassTicketHead") else { return XCTFail("表が無い") }
        let front = String(cards[start.lowerBound..<end.lowerBound])
        for part in ["PassTicketRule(opacity: PassCardStyle.photoRuleOpacity, shine: shine)",
                     "PassTicketHead(text: face.headline)", "if let via = face.via",
                     "ForEach(Array(PassTicket.shown(face.fields).enumerated())", "Text(PassTicket.frontValidity)",
                     "PassTicketEdge(kind: face.kind, corner: corner, shine: shine)",
                     "PassTicketGlow(kind: face.kind, corner: corner)"] {
            XCTAssertTrue(front.contains(part), "表に \(part) が無い")
        }
        XCTAssertFalse(front.contains("PassTicketPunch"), "表に前の改札の穴が残っている")
        XCTAssertFalse(front.contains("minimumScaleFactor(PassCardStyle.route"), "区間が別々に縮む")
    }

    /// 自分のカードの見本も同じ表（経由は「旅先のあたり」・日付と区間と回数は「—」）
    func testOwnPreviewUsesSameFace() throws {
        let pick = try source("Features/Pass/PassCardPickView.swift")
        XCTAssertTrue(pick.contains("via: PassTicket.via(L(\"旅先\", \"your trip\"))"))
        XCTAssertTrue(pick.contains("count: PassTicket.countLabel(.plain, meetingCount: nil)"))
        XCTAssertEqual(PassTicket.via("旅先"), "経由 旅先のあたり")
    }

    // MARK: - 2026-10-17 の読み直し

    /// 回る札: 裏を見ている間は表を読ませない・表を見ている間は裏を読ませない（どちらかを消すと両面が読まれる）
    func testSpinHidesOtherSideFromVoiceOver() throws {
        let spin = try source("Features/Pass/PassSpinCard.swift")
        let front = try XCTUnwrap(spin.range(of: "PassCardFront(face: front"))
        let back = try XCTUnwrap(spin.range(of: "PassCardBack(face: self.back"))
        let end = try XCTUnwrap(spin.range(of: ".rotation3DEffect(.radians(reduceMotion ? 0 : yaw)"))
        let frontPart = spin[front.upperBound..<back.lowerBound]
        let backPart = spin[back.upperBound..<end.lowerBound]
        XCTAssertTrue(frontPart.contains(".accessibilityHidden(back)"), "裏を見ている間も表が読まれる")
        XCTAssertTrue(backPart.contains(".accessibilityHidden(!back)"), "表を見ている間も裏が読まれる")
    }

    /// 英語の「また会えた」の名は、右上の番号（No.0002）と数字が並ばない言い方
    func testAgainHeadlineEnglishAvoidsNumberClash() throws {
        let text = try source("Core/Text/PassTicket.swift")
        XCTAssertFalse(text.contains("PASS NO."), "英語の名が「PASS NO. 2」で右上の No.0002 と紛れる")
        XCTAssertTrue(text.contains("\"AGAIN ×\\(n)\""))
    }

    /// 空の欄「—」は、読み上げだけ「なし」（「ダッシュ」と読ませない）。値のある欄はそのまま
    func testBlankFieldSpokenAsNone() throws {
        let empty = PassTicket.Field(label: PassTicket.dateTitle, value: PassTicket.blank)
        XCTAssertEqual(PassTicket.spokenField(empty), "\(PassTicket.dateTitle) \(L("なし", "none"))")
        XCTAssertFalse(PassTicket.spokenField(empty).contains(PassTicket.blank))
        let filled = PassTicket.Field(label: PassTicket.countTitle, value: "はじめて")
        XCTAssertEqual(PassTicket.spokenField(filled), "\(PassTicket.countTitle) はじめて")
        let cards = try source("Features/Pass/PassCards.swift")
        XCTAssertEqual(cards.components(separatedBy: ".accessibilityLabel(PassTicket.spokenField(field))").count - 1, 2,
                       "表と裏の欄の読み上げに「なし」を当てていない")
    }
}
