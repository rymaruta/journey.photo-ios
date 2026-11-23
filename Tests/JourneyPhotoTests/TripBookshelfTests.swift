import XCTest
@testable import JourneyPhoto

/// 旅の記録の本棚と荷札の道具の列（札 #714・2026-11-23 owner 決定・案の頁「旅の道具の入口」）。
///
/// 画面は Linux では描けないので、寸法と並べ方は数で、部品の作りは元のファイルを読んで見張る
final class TripBookshelfTests: XCTestCase {

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/JourneyPhoto")
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func photo(_ id: String, date: String, color: String? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"", "\"userId\":\"owner\"", "\"date\":\"\(date)\"",
                      "\"location\":\"金沢\""]
        if let color { fields.append("\"dominantColor\":\"\(color)\"") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func trip(_ id: String, year: Int, month: Int, photos: Int = 2, days: Int = 1,
                      color: String? = nil, isPrivate: Bool = false) throws -> TripBook.Trip {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(from: DateComponents(year: year, month: month, day: 10))!
        let end = calendar.date(byAdding: .day, value: days - 1, to: start)!
        let list = try (0..<photos).map { try photo("\(id)-\($0)", date: "\(year)-\(String(format: "%02d", month))-10", color: color) }
        return TripBook.Trip(id: id, place: "金沢", start: start, end: end, photos: list, isPrivate: isPrivate)
    }

    // MARK: - 背表紙の寸法

    /// 厚さは写真の枚数（22〜36）、高さは日数（118 + 日数 × 5、5日まで）
    func testSpineSizeFollowsPhotosAndDays() {
        XCTAssertEqual(TripBookshelf.spineWidth(photos: 0), 22)
        XCTAssertEqual(TripBookshelf.spineWidth(photos: 2), 22)
        XCTAssertEqual(TripBookshelf.spineWidth(photos: 30), 29)
        XCTAssertEqual(TripBookshelf.spineWidth(photos: 60), 36)
        XCTAssertEqual(TripBookshelf.spineWidth(photos: 400), 36, "厚さに上限が無い")
        XCTAssertEqual(TripBookshelf.spineHeight(days: 1), 123)
        XCTAssertEqual(TripBookshelf.spineHeight(days: 3), 133)
        XCTAssertEqual(TripBookshelf.spineHeight(days: 30), 143, "高さに上限が無い")
        XCTAssertLessThanOrEqual(TripBookshelf.spineHeight(days: 99), TripBookshelf.rowHeight, "いちばん高い背が段に入らない")
        XCTAssertEqual(TripBookshelf.tapWidth, 44, "押せる幅は 44pt（CLAUDE.md）")
        XCTAssertEqual(TripBookshelf.windowHeight, 30)
        XCTAssertGreaterThanOrEqual(TripBookshelf.monthSize, 12, "本文系の最小 12pt")
    }

    /// 背の題は縦に1字ずつ。入らない分は縦の「︙」で切る
    func testSpineTitleIsCutToFit() {
        XCTAssertEqual(TripBookshelf.spineTitle("金沢", maxCharacters: 4), ["金", "沢"])
        XCTAssertEqual(TripBookshelf.spineTitle("屋久島町宮之浦", maxCharacters: 4), ["屋", "久", "島", "︙"])
        XCTAssertEqual(TripBookshelf.spineTitle("金沢", maxCharacters: 0), [])
        // 低い背ほど入る字が少ない。印が付くと減る
        let short = TripBookshelf.spineTitleCapacity(height: TripBookshelf.spineHeight(days: 1), marks: 0)
        let tall = TripBookshelf.spineTitleCapacity(height: TripBookshelf.spineHeight(days: 5), marks: 0)
        XCTAssertGreaterThan(tall, short)
        XCTAssertLessThan(TripBookshelf.spineTitleCapacity(height: TripBookshelf.spineHeight(days: 1), marks: 2), short)
        XCTAssertGreaterThanOrEqual(short, 2, "いちばん低い背に2字の地名が入らない")
    }

    // MARK: - 並べ方

    /// 年ごとの段。新しい年が上、段の中は新しい旅が先
    func testShelvesAreYearsNewestFirst() throws {
        let books = try [trip("a", year: 2025, month: 4), trip("b", year: 2026, month: 2),
                         trip("c", year: 2026, month: 9), trip("d", year: 2024, month: 12)].map(TripBookshelf.book)
        let shelves = TripBookshelf.shelves(books)
        XCTAssertEqual(shelves.map(\.year), [2026, 2025, 2024])
        XCTAssertEqual(shelves[0].books.map(\.id), ["posted-c", "posted-b"])
        XCTAssertEqual(shelves[0].books.map(\.month), [9, 2])
    }

    /// 幅に入るだけ並べて折り返す（30冊でも段からはみ出さない）
    func testRowsWrapToTheWidth() {
        XCTAssertEqual(TripBookshelf.rows(widths: [30, 30, 30], available: 100, gap: 3), [[0, 1, 2]])
        XCTAssertEqual(TripBookshelf.rows(widths: [30, 30, 30, 30], available: 100, gap: 3), [[0, 1, 2], [3]])
        XCTAssertEqual(TripBookshelf.rows(widths: [], available: 100), [])
        // 1冊が幅より太くても、その1冊で1段（消えない）
        XCTAssertEqual(TripBookshelf.rows(widths: [120, 20], available: 100), [[0], [1]])
        let widths = (0..<30).map { TripBookshelf.spineWidth(photos: $0 * 3) }
        let rows = TripBookshelf.rows(widths: widths, available: 358)
        XCTAssertEqual(rows.flatMap { $0 }, Array(0..<30), "並びが崩れた")
        for row in rows {
            let used = row.map { widths[$0] }.reduce(0, +) + Double(row.count - 1) * TripBookshelf.spineGap
            XCTAssertLessThanOrEqual(used, 358)
        }
    }

    /// 投稿の旅と端末の旅は別の id（同じ id の旅があっても棚で重ならない）
    func testPostedAndDeviceBooksHaveDistinctIds() throws {
        let posted = TripBookshelf.book(try trip("x", year: 2026, month: 1))
        XCTAssertEqual(posted.id, "posted-x")
        XCTAssertFalse(posted.isDevice)
        XCTAssertNil(posted.name)
    }

    // MARK: - 地の色・読み上げ

    /// 背の地は写真の色みを残して暗くする。色が無い写真は id で決まる布の色（起動ごとに変わらない）
    func testClothIsADarkenedPhotoColor() {
        let cloth = TripBookshelf.clothColor(hex: "#FF8000", seed: "a")
        XCTAssertEqual(cloth >> 16 & 0xFF, 77, "いちばん明るい色を 30% に")
        XCTAssertEqual(cloth >> 8 & 0xFF, 38)
        XCTAssertEqual(cloth & 0xFF, 0)
        XCTAssertEqual(TripBookshelf.clothColor(hex: "zz", seed: "a"), TripBookshelf.clothColor(hex: nil, seed: "a"))
        XCTAssertEqual(TripBookshelf.clothColor(hex: nil, seed: "trip-1"), TripBookshelf.clothColor(hex: nil, seed: "trip-1"))
        XCTAssertTrue(TripBookshelf.cloths.contains(TripBookshelf.clothColor(hex: "#000000", seed: "b")), "黒の写真で真っ黒の背になる")
        for hex in ["#FFFFFF", "#00FF00", "#C9A66B"] {
            let c = TripBookshelf.clothColor(hex: hex, seed: "s")
            XCTAssertLessThanOrEqual(max(c >> 16 & 0xFF, c >> 8 & 0xFF, c & 0xFF), 77, "\(hex) の背が明るすぎて白い字が読めない")
        }
    }

    /// 読み上げは「旅、題、年月、枚数」と印（色だけで言わない）。中黒で区切らない
    func testSpokenLabelSaysTheMarks() throws {
        let book = TripBookshelf.book(try trip("p", year: 2026, month: 9, photos: 3, isPrivate: true))
        let label = TripBookshelf.spokenLabel(book)
        XCTAssertTrue(label.hasPrefix(L("旅、金沢、2026年9月", "Trip, 金沢, September 2026")), label)
        XCTAssertTrue(label.contains(L("自分だけ", "Only you")))
        XCTAssertFalse(label.contains(L("端末の中だけ", "On this iPhone only")))
        XCTAssertFalse(label.contains("・") || label.contains("·"), label)
    }

    /// 写真の代表色が背の地に入る
    func testPostedBookUsesTheCoverColor() throws {
        let book = TripBookshelf.book(try trip("c", year: 2026, month: 3, color: "#FF8000"))
        XCTAssertEqual(book.cloth, TripBookshelf.clothColor(hex: "#FF8000", seed: "c"))
    }

    // MARK: - 本を開く動き

    /// 秒と角度は案の頁の値（合わせて約 0.55 秒、閉じるのは約 0.45 秒）
    func testOpeningMotionMatchesTheProposal() {
        XCTAssertEqual(TripBookMotion.coverFlipDelay, 0.12)
        XCTAssertEqual(TripBookMotion.coverFlipDuration, 0.26)
        XCTAssertEqual(TripBookMotion.coverFlipAngle, -165)
        XCTAssertEqual(TripBookMotion.bounceAt, 0.54)
        XCTAssertEqual(TripBookMotion.bounceScale, 1.012, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(TripBookMotion.coverFlipDelay + TripBookMotion.coverFlipDuration, TripBookMotion.bounceAt)
        XCTAssertEqual(TripBookMotion.openTotal, 0.55)
        XCTAssertEqual(TripBookMotion.closeTotal, 0.45)
    }

    /// 🔴 動かすのは位置・向き・透明度だけ。表紙は1枚の絵にまとめて回し、押せない。動きを減らす設定ではすぐ開く。
    /// 詳しい頁から戻っても、もう一度めくらない
    func testOpeningIsLightAndSafe() throws {
        let shelf = try source("Features/Trips/TripShelf.swift")
        let opening = try XCTUnwrap(shelf.range(of: "struct TripBookOpening: ViewModifier {"))
        let body = String(shelf[opening.lowerBound...].prefix(4000))
        XCTAssertTrue(body.contains(".drawingGroup()"), "表紙を1枚の絵にまとめていない")
        XCTAssertTrue(body.contains(".allowsHitTesting(false)"), "動いている間に表紙が押せる")
        XCTAssertTrue(body.contains("guard animated, !started else { return }"), "戻るたびにめくり直す")
        XCTAssertTrue(body.contains("anchor: .leading, perspective: TripBookMotion.perspective"), "左の辺を軸にめくっていない")
        XCTAssertTrue(body.contains(".bookZoomTransition(id: book.id, in: namespace, enabled: animated)"))
        XCTAssertFalse(body.contains(".frame(width: flipped") || body.contains(".blur("), "大きさ・ぼかしを動かしている")
        XCTAssertTrue(shelf.contains("TripBookOpening(book: book, namespace: bookSpace, animated: !reduceMotion)"),
                      "動きを減らす設定でも本を開く動きをしている")
        // 表紙は縮めた画像（256px・端末の旅は辺の 3 倍）
        let cover = try XCTUnwrap(shelf.range(of: "struct BookCoverImage: View {"))
        XCTAssertTrue(shelf[cover.lowerBound...].prefix(800).contains("cover.pinImageURL"), "表紙に大きい画像を読んでいる")
    }

    // MARK: - 日のページを左右でめくる

    /// 横に払うと日をめくる。縦のスクロール・短い払い・左の端からの「戻る」ではめくらない
    func testPageFlipDirection() {
        XCTAssertEqual(TripBookPageFlip.direction(dx: -80, dy: 10, startX: 200), 1, "左へ払うと次の日")
        XCTAssertEqual(TripBookPageFlip.direction(dx: 80, dy: -10, startX: 200), -1, "右へ払うと前の日")
        XCTAssertNil(TripBookPageFlip.direction(dx: -40, dy: 0, startX: 200), "短い払いでめくった")
        XCTAssertNil(TripBookPageFlip.direction(dx: -80, dy: 60, startX: 200), "縦のスクロールでめくった")
        XCTAssertNil(TripBookPageFlip.direction(dx: 120, dy: 0, startX: 10), "左の端からの「戻る」でめくった")
    }

    /// めくる先は、いま読んでいる日の次と前。表紙を読んでいる間に左へ払うと 1 日目。端では何もしない
    func testPageFlipTarget() {
        let ids = ["day-1", "day-2", "day-4"]
        XCTAssertEqual(TripBookPageFlip.current(dayIDs: ids, passed: []), 0)
        XCTAssertEqual(TripBookPageFlip.targetID(dayIDs: ids, passed: [], direction: 1), "day-1")
        XCTAssertNil(TripBookPageFlip.targetID(dayIDs: ids, passed: [], direction: -1))
        XCTAssertEqual(TripBookPageFlip.targetID(dayIDs: ids, passed: ["day-1", "day-2"], direction: 1), "day-4",
                       "撮らなかった日を飛ばして次の見出しへ")
        XCTAssertEqual(TripBookPageFlip.targetID(dayIDs: ids, passed: ["day-1", "day-2"], direction: -1), "day-1")
        XCTAssertNil(TripBookPageFlip.targetID(dayIDs: ids, passed: Set(ids), direction: 1), "最後の日の先へめくった")
        XCTAssertNil(TripBookPageFlip.targetID(dayIDs: [], passed: [], direction: 1))
        XCTAssertEqual(TripBookPageFlip.headerID(day: 3), "day-3")
    }

    /// 🔴 めくる id は一冊の行の id と同じ（違うと送れない）。投稿した一冊と端末の一冊の両方に付ける
    func testPageFlipIsWiredToBothBooks() throws {
        let rows = TripBook.pageRows(of: TripBook.days(of: try trip("t", year: 2026, month: 9, photos: 2)))
        XCTAssertEqual(rows.first?.id, TripBookPageFlip.headerID(day: 1))
        let book = try source("Features/Trips/TripBookView.swift")
        XCTAssertTrue(book.contains(".modifier(TripDayFlip(dayIDs: TripBook.days(of: book).map { TripBookPageFlip.headerID(day: $0.number) },"))
        XCTAssertTrue(book.contains(".tripDayMark(id: TripBookPageFlip.headerID(day: day.number), passed: $passedDays)"))
        let device = try source("Features/Trips/DeviceTripShelf.swift")
        XCTAssertTrue(device.contains(".modifier(TripDayFlip(dayIDs: shown.days.map(\\.id), passed: passedDays))"))
        XCTAssertTrue(device.contains(".tripDayMark(id: day.id, passed: $passedDays)"))
        let flip = try source("Features/Trips/TripDayFlip.swift")
        XCTAssertTrue(flip.contains("if reduceMotion {"), "動きを減らす設定でも動かしている")
        XCTAssertTrue(flip.contains(".simultaneousGesture("), "縦のスクロールを止めている")
    }

    // MARK: - 荷札の道具の列

    /// 並びは決まった順、新しい道具は最後。スタンプ帳（#712）は場所だけで出さない。トランクは口のある人だけ
    func testToolOrderAndGating() {
        XCTAssertEqual(TripTool.allCases, [.plans, .albums, .trunk, .stampBook, .passBook])
        XCTAssertEqual(TripTool.shown(trunkAvailable: true), [.plans, .albums, .trunk, .passBook])
        XCTAssertEqual(TripTool.shown(trunkAvailable: false), [.plans, .albums, .passBook])
        XCTAssertEqual(TripTool.shown(trunkAvailable: true, stampBookReady: true), TripTool.allCases)
        // 今までの目印は変えない（UI テスト）
        XCTAssertEqual(TripTool.allCases.map(\.identifier),
                       ["trips.plans", "trips.albums", "trips.trunk", "trips.stampBook", "trips.passBook"])
        for tool in TripTool.allCases {
            XCTAssertFalse(tool.title.contains("・") || tool.title.contains("·"), tool.title)
        }
    }

    /// 荷札の寸法（案の頁）。押せる高さ 44、字の地の差は濃い灰の面の段から読む
    func testTagMetrics() throws {
        XCTAssertEqual(TripToolTag.height, 44)
        XCTAssertEqual(TripToolTag.spacing, 10)
        XCTAssertEqual(TripToolTag.edgeFade, 18)
        XCTAssertEqual(TripToolTag.chamfer, 8)
        XCTAssertEqual(TripToolTag.cornerRadius, 7)
        XCTAssertEqual(TripToolTag.holeDiameter, 7)
        XCTAssertEqual(TripToolTag.holeCenterX, 11)
        XCTAssertEqual(TripToolTag.leadingInset, 24)
        XCTAssertEqual(TripToolTag.trailingInset, 13)
        XCTAssertEqual(TripToolTag.faceTop, 0x1C1C1E)
        XCTAssertEqual(TripToolTag.faceBottom, 0x161617)
        XCTAssertEqual(TripToolTagStyle.pressedAngle, -1)
        XCTAssertEqual(TripToolTagStyle.pressedScale, 0.98)
        let tag = try source("Features/Profile/TripToolTag.swift")
        // 真鍮は件数バッジだけ
        XCTAssertFalse(tag.contains("WebTheme.accent"), "荷札に件数バッジ以外の真鍮がある")
        XCTAssertTrue(tag.contains("CountBadge(count: badge, maximum: 99)"))
        // 動きを減らす設定では明るくなるだけ
        XCTAssertTrue(tag.contains("pressed && !reduceMotion ? Self.pressedAngle : 0"))
        XCTAssertTrue(tag.contains("pressed && !reduceMotion ? Self.pressedScale : 1"))
    }

    /// 🔴 道具の列は旅の記録のタブの頭（旅の棚より上）。旅が増えても道具の位置は変わらない。入口は今までと同じ4つ
    func testToolStripSitsAboveTheShelf() throws {
        let page = try source("Features/Profile/MyPageView.swift")
        let area = try XCTUnwrap(page.range(of: "private var tripsArea: some View {"))
        let rest = page[area.upperBound...]
        let tools = try XCTUnwrap(rest.range(of: "tripToolsCard"))
        let shelf = try XCTUnwrap(rest.range(of: "MyPageTripsShelf("))
        XCTAssertLessThan(tools.lowerBound, shelf.lowerBound, "道具の列が旅の棚の下にある")
        let card = try XCTUnwrap(page.range(of: "private var tripToolsCard: some View {"))
        let strip = String(page[card.upperBound...].prefix(4000))
        XCTAssertTrue(strip.contains("ScrollView(.horizontal, showsIndicators: false)"), "横に送る列になっていない")
        for name in ["trips.plans", "trips.albums", "trips.passBook"] {
            XCTAssertTrue(strip.contains("\"\(name)\""), "\(name) の札が無い")
        }
        XCTAssertTrue(strip.contains("MyPageTrunkRow(ownerName: model.profile?.name)"))
        XCTAssertFalse(strip.contains("JPRowLabel"), "縦の行が残っている")
    }

    /// タブは4つのまま（2026-11-23 owner「一旦3つのタブにするのは却下」）
    func testTabsStayFour() {
        XCTAssertEqual(ProfileTab.tabs(isMe: true), [.posts, .trips, .wishlist, .favorites])
    }

    /// 🔴 棚に説明の文を出さない（端末の旅のプライバシーの文は初めの許可の札だけ）
    func testShelfHasNoExplanations() throws {
        let device = try source("Features/Trips/DeviceTripShelf.swift")
        let section = try XCTUnwrap(device.range(of: "struct DeviceTripSection: View {"))
        let end = try XCTUnwrap(device.range(of: "struct DeviceOnlyChip"))
        let body = device[section.upperBound..<end.lowerBound]
        XCTAssertFalse(body.contains("撮影日時と場所から見つけた旅です"), "棚にプライバシーの文が残っている")
        XCTAssertFalse(body.contains("50km"), "棚に「家から50km」の文が残っている")
        XCTAssertFalse(body.contains(".jpEyebrow()"), "棚に「端末の中だけ」の眉が残っている")
        XCTAssertTrue(device.contains("DeviceTripText.introPrivacy"), "許可の札からプライバシーの文が消えた")
    }

    // MARK: - 見本（UI テスト）

    /// 見本の「旅が増えたとき」は3年に分けた14冊。同じ写真を1冊に2度入れない
    func testPreviewSampleSpansThreeYears() throws {
        let photos = try (0..<20).map { try photo("p\($0)", date: "2026-01-01") }
        let many = PreviewTripShelf.many(photos: photos)
        XCTAssertEqual(many.count, 14)
        XCTAssertEqual(Set(TripBookshelf.shelves(many.map(TripBookshelf.book)).map(\.year)), [2026, 2025, 2024])
        for trip in many {
            XCTAssertEqual(Set(trip.photos.map(\.id)).count, trip.photos.count, "\(trip.id) に同じ写真が2度入っている")
        }
        XCTAssertEqual(PreviewTripShelf.many(photos: []), [])
    }
}
