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

    /// 厚さは写真の枚数（22〜36）、高さは日数（136 + 日数 × 5、5日まで・2026-11-24 に 18pt 上げた）
    func testSpineSizeFollowsPhotosAndDays() {
        XCTAssertEqual(TripBookshelf.spineWidth(photos: 0), 22)
        XCTAssertEqual(TripBookshelf.spineWidth(photos: 2), 22)
        XCTAssertEqual(TripBookshelf.spineWidth(photos: 30), 29)
        XCTAssertEqual(TripBookshelf.spineWidth(photos: 60), 36)
        XCTAssertEqual(TripBookshelf.spineWidth(photos: 400), 36, "厚さに上限が無い")
        XCTAssertEqual(TripBookshelf.spineHeight(days: 1), 141)
        XCTAssertEqual(TripBookshelf.spineHeight(days: 3), 151)
        XCTAssertEqual(TripBookshelf.spineHeight(days: 30), 161, "高さに上限が無い")
        XCTAssertEqual(TripBookshelf.rowHeight, 164, "段の高さがいちばん高い背＋3pt でない")
        XCTAssertLessThanOrEqual(TripBookshelf.spineHeight(days: 99), TripBookshelf.rowHeight, "いちばん高い背が段に入らない")
        // 押せる幅は背の幅＋間（隣と重ならない）。押せる高さは 44 を超える
        XCTAssertEqual(TripBookshelf.hitWidth(photos: 0), 22 + TripBookshelf.spineGap)
        XCTAssertGreaterThanOrEqual(TripBookshelf.spineHeight(days: 1), 44)
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

    /// 🔴 2026-11-24 owner「何県かわからないの悲しい」: 印が1つ付いたいちばん低い背にも3字の県名（「北海道」「鹿児島」）が
    /// 「︙」で切れずに入る。前の寸法（123〜143）では印つきの低い背に1字しか入らなかった
    func testSpineFitsThreeCharacterPrefecture() {
        XCTAssertEqual(TripBookshelf.spineMinCharacters, 3)
        for days in 1...5 {
            for marks in 0...1 {
                let capacity = TripBookshelf.spineTitleCapacity(height: TripBookshelf.spineHeight(days: days), marks: marks)
                XCTAssertGreaterThanOrEqual(capacity, TripBookshelf.spineMinCharacters, "\(days)日・印\(marks)の背に3字が入らない")
                for name in ["北海道", "鹿児島", "神奈川", "和歌山", "新潟"] {
                    XCTAssertEqual(TripBookshelf.spineTitle(name, maxCharacters: capacity).joined(), name,
                                   "\(days)日・印\(marks)の背で「\(name)」が切れる")
                }
            }
        }
        // 寸法の部品（印 17・題の上 6・月の塊 34）は背の絵と同じ数
        XCTAssertEqual(TripBookshelf.markHeight, 17)
        XCTAssertEqual(TripBookshelf.titleTop, 6)
        XCTAssertEqual(TripBookshelf.monthBlock, 34)
    }

    // MARK: - 背の県

    private func located(_ id: String, location: String?, lat: Double? = nil, lng: Double? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\"", "\"userId\":\"owner\"",
                      "\"date\":\"2026-09-10\""]
        if let location { fields.append("\"location\":\"\(location)\"") }
        if let lat, let lng { fields.append("\"coords\":{\"lat\":\(lat),\"lng\":\(lng)}") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func postedTrip(_ photos: [Photo], place: String = "兼六園") -> TripBook.Trip {
        let start = Date(timeIntervalSince1970: 1_789_000_000)
        return TripBook.Trip(id: "t", place: place, start: start, end: start, photos: photos)
    }

    /// 市区町村の役所の代わり（試験では同梱の表を読まない）
    private let resolver = PrefectureResolver(spotPrefectures: [:], anchors: [
        .init(coords: Photo.Coords(lat: 36.561, lng: 136.656), prefecture: "石川県"),   // 金沢市
        .init(coords: Photo.Coords(lat: 37.916, lng: 139.036), prefecture: "新潟県"),   // 新潟市
        .init(coords: Photo.Coords(lat: 43.064, lng: 141.347), prefecture: "北海道"),   // 札幌市
        .init(coords: Photo.Coords(lat: 31.597, lng: 130.557), prefecture: "鹿児島県"), // 鹿児島市
    ])

    /// 多い方の県。同じ数なら先に出た県。「県」「府」「都」を外した短い形、北海道はそのまま
    func testSpinePrefectureIsTheMostCommonShortName() {
        XCTAssertEqual(TripBookshelf.spinePrefecture([("新潟県", 1), ("石川県", 1), ("石川県", 1)]), "石川")
        XCTAssertEqual(TripBookshelf.spinePrefecture([("新潟県", 1), ("石川県", 1)]), "新潟", "同じ数で先に出た県にならない")
        XCTAssertEqual(TripBookshelf.spinePrefecture([("新潟県", 1), ("石川県", 5)]), "石川", "重みを数えていない")
        XCTAssertEqual(TripBookshelf.spinePrefecture([("北海道", 1)]), "北海道")
        XCTAssertEqual(TripBookshelf.spinePrefecture([("京都府", 1)]), "京都")
        XCTAssertEqual(TripBookshelf.spinePrefecture([("東京都", 1)]), "東京")
        XCTAssertEqual(TripBookshelf.spinePrefecture([("鹿児島県", 1)]), "鹿児島")
        XCTAssertNil(TripBookshelf.spinePrefecture([(nil, 3), ("", 1)]))
        XCTAssertNil(TripBookshelf.spinePrefecture([]))
    }

    /// 投稿した旅: 撮影地の文字に県が無い写真（「兼六園」）は座標から。背は県、読み上げは題のまま
    func testPostedBookSpineShowsPrefecture() throws {
        let trip = postedTrip([try located("a", location: "兼六園", lat: 36.562, lng: 136.662),
                               try located("b", location: "新潟県新潟市", lat: nil, lng: nil),
                               try located("c", location: "ひがし茶屋街", lat: 36.572, lng: 136.666)])
        let book = TripBookshelf.book(trip, resolver: resolver)
        XCTAssertEqual(book.prefecture, "石川")
        XCTAssertEqual(book.spineText, "石川", "背が県名でない")
        XCTAssertEqual(book.title, "兼六園", "題を県名で置き換えた（開いた一冊の題が変わる）")
        XCTAssertTrue(TripBookshelf.spokenLabel(book).contains("兼六園"), "読み上げから題の全部が消えた")
    }

    /// 県が取れない旅（海外・座標も県も無い）は今の題に戻る
    func testSpineFallsBackToTitleWithoutPrefecture() throws {
        let paris = postedTrip([try located("p", location: "Paris, France", lat: 48.857, lng: 2.352)], place: "パリ")
        let book = TripBookshelf.book(paris, resolver: resolver)
        XCTAssertNil(book.prefecture)
        XCTAssertEqual(book.spineText, "パリ")
        let bare = postedTrip([try located("q", location: nil)], place: "")
        XCTAssertEqual(TripBookshelf.book(bare, resolver: resolver).spineText, TripBookshelf.book(bare, resolver: resolver).title)
    }

    /// 端末の旅: 日の代表点の県を、その日の枚数で重みづけて多い方。代表点が引けなければ地名の文字
    func testDeviceBookSpineShowsPrefecture() {
        func shot(_ id: String, _ lat: Double, _ lng: Double) -> LibraryShot {
            LibraryShot(id: id, date: Date(timeIntervalSince1970: 1_789_000_000), lat: lat, lng: lng)
        }
        let niigata = (0..<2).map { shot("n\($0)", 37.92, 139.04) }
        let hokkaido = (0..<5).map { shot("h\($0)", 43.06, 141.35) }
        let days = [LibraryTrip.Day(key: "2026-09-10", number: 1, month: 9, day: 10, shots: niigata,
                                    center: Photo.Coords(lat: 37.92, lng: 139.04)),
                    LibraryTrip.Day(key: "2026-09-11", number: 2, month: 9, day: 11, shots: hokkaido,
                                    center: Photo.Coords(lat: 43.06, lng: 141.35))]
        let trip = LibraryTrip(id: "d", shots: niigata + hokkaido, start: niigata[0].date, end: hokkaido[0].date,
                               days: days, center: Photo.Coords(lat: 37.92, lng: 139.04), timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        let book = TripBookshelf.book(trip, name: "新潟市", resolver: resolver)
        XCTAssertEqual(book.spineText, "北海道", "枚数の多い日の県にならない")
        XCTAssertEqual(book.title, "新潟市")
        // 座標の県が引けない旅（手がかりが無い）は地名の文字から、それも無ければ題
        XCTAssertEqual(TripBookshelf.book(trip, name: "鹿児島県", resolver: .empty).spineText, "鹿児島")
        XCTAssertEqual(TripBookshelf.book(trip, name: "金沢市", resolver: .empty).spineText, "金沢市")
    }

    /// 🔴 1字の箱は明朝 13pt の行の高さ（17〜19pt）で数える。14pt で数えると字が背からはみ出した
    func testSpineTitleFitsTheRealLineHeight() {
        XCTAssertGreaterThanOrEqual(TripBookshelf.titleBox, 17)
        XCTAssertLessThanOrEqual(TripBookshelf.titleBox, 19)
        for days in 1...5 {
            for marks in 0...2 {
                let height = TripBookshelf.spineHeight(days: days)
                let capacity = Double(TripBookshelf.spineTitleCapacity(height: height, marks: marks))
                let used = TripBookshelf.windowHeight + Double(marks) * 17 + 6 + capacity * TripBookshelf.titleBox + 34
                XCTAssertLessThanOrEqual(used, height, "\(days)日・印\(marks)の背で題がはみ出す")
            }
        }
    }

    /// 縦書きで横を向く字は縦の形にする（長音の「ー」は回す、括弧と「…」は縦の形の字）
    func testSpineGlyphsAreVertical() {
        XCTAssertEqual(TripBookshelf.spineGlyph("ー").rotated, true)
        XCTAssertEqual(TripBookshelf.spineGlyph("〜").rotated, true)
        XCTAssertEqual(TripBookshelf.spineGlyph("…").text, "︙")
        XCTAssertEqual(TripBookshelf.spineGlyph("（").text, "︵")
        XCTAssertEqual(TripBookshelf.spineGlyph("金").text, "金")
        XCTAssertEqual(TripBookshelf.spineGlyph("金").rotated, false)
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
        XCTAssertEqual(TripBookMotion.pullResponse, 0.3)
        XCTAssertEqual(TripBookMotion.pullDamping, 0.85)
        XCTAssertEqual(TripBookMotion.coverFlipDelay, 0.12)
        XCTAssertEqual(TripBookMotion.coverFlipDuration, 0.26)
        XCTAssertEqual(TripBookMotion.coverFlipAngle, -165)
        XCTAssertEqual(TripBookMotion.pageGrowAt, 0.30)
        XCTAssertEqual(TripBookMotion.pageGrowDuration, 0.23)
        XCTAssertEqual(TripBookMotion.bounceAt, 0.54)
        XCTAssertEqual(TripBookMotion.bounceScale, 1.012, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(TripBookMotion.coverFlipDelay + TripBookMotion.coverFlipDuration, TripBookMotion.bounceAt)
        XCTAssertEqual(TripBookMotion.pageGrowAt + TripBookMotion.pageGrowDuration, 0.53, accuracy: 0.001)
        XCTAssertEqual(TripBookMotion.openTotal, 0.55)
        // 閉じる: 頁が縮む 0.19 → 0.12 から表紙が戻る 0.20 → 0.27 から棚へ 0.18（約 0.45）
        XCTAssertEqual(TripBookMotion.pageShrinkDuration, 0.19)
        XCTAssertEqual(TripBookMotion.coverCloseDelay, 0.12)
        XCTAssertEqual(TripBookMotion.coverCloseDuration, 0.20)
        XCTAssertEqual(TripBookMotion.shelveAt, 0.27)
        XCTAssertEqual(TripBookMotion.shelveDuration, 0.18)
        XCTAssertEqual(TripBookMotion.shelveAt + TripBookMotion.shelveDuration, TripBookMotion.closeTotal, accuracy: 0.001)
        // 表紙は 90° を越えたら裏（見返し）を見せる
        XCTAssertFalse(TripBookMotion.showsCoverBack(angle: -60))
        XCTAssertTrue(TripBookMotion.showsCoverBack(angle: TripBookMotion.coverFlipAngle))
    }

    /// 引き出した本は見えている所の中央より少し上。上下にはみ出さない
    func testStageCenterStaysOnScreen() {
        // 棚が見えている所の上から 300pt にあるとき、見えている高さ 800 の 45% = 360 → 棚の座標で 60
        XCTAssertEqual(TripBookMotion.stageCenterY(visibleHeight: 800, shelfTopInScroll: 300), 60, accuracy: 0.001)
        // 低い画面でも本の上端が見えている所の上に出ない
        let y = TripBookMotion.stageCenterY(visibleHeight: 400, shelfTopInScroll: 0)
        XCTAssertGreaterThanOrEqual(y - 133, TripBookMotion.stageMargin - 0.001)
    }

    /// 🔴 開く動き: 動かすのは位置・向き・大きさ・透明度だけ。表紙は読み終えた絵だけで描き（読み込みの輪を出さない）、
    /// 動いている間は棚にも一冊の頁にも押しが届かない。動きを減らす設定ではすぐ開く。閉じると表紙が戻って棚へ帰る
    func testOpeningIsLightAndSafe() throws {
        let stage = try source("Features/Trips/TripBookStage.swift")
        let shelf = try source("Features/Trips/TripShelf.swift")
        // 表紙は控えに在る絵（`BookCoverCache`）を `Image(uiImage:)` で描くだけ
        let face = try XCTUnwrap(shelf.range(of: "struct BookCoverFace: View {"))
        let faceBody = String(shelf[face.lowerBound...].prefix(2000))
        XCTAssertTrue(faceBody.contains("Image(uiImage: image)"))
        XCTAssertFalse(faceBody.contains("RemoteImage") || faceBody.contains("ProgressView") || faceBody.contains("LibraryThumbView"),
                       "表紙が開くたびに絵を読み直す")
        // 型の名前は分けて書く（検査 `check-swift-refs.js` は文字列の中の「型.関数(」もテストからの呼び出しと数える）
        let cache = "BookCover" + "Cache"
        XCTAssertTrue(stage.contains("image: \(cache).image(for: book)"), "押す前に読み終えた絵を渡していない")
        XCTAssertTrue(shelf.contains(".task(id: book.id) { await \(cache).prefetch(book) }"), "背表紙が出たときに表紙を読んでいない")
        // 表紙は約 400px 以上の縮小版（背の窓の 256px ではない）
        XCTAssertTrue(stage.contains("trip.cover?.gridImageURL"))
        XCTAssertGreaterThanOrEqual(TripBookMotion.coverPixels, 400)
        // 引き出す・手前に回す・めくる（位置・大きさ・向き・透明度だけ）
        let pose = try XCTUnwrap(stage.range(of: "struct BookStagePose: ViewModifier {"))
        let poseBody = String(stage[pose.lowerBound...].prefix(1800))
        XCTAssertTrue(poseBody.contains(".rotation3DEffect(.degrees(pulled ? 0 : TripBookMotion.shelvedTurn)"), "手前に回していない")
        XCTAssertFalse(poseBody.contains(".frame(width:") || poseBody.contains(".blur("), "大きさの枠・ぼかしを動かしている")
        XCTAssertTrue(stage.contains("anchor: .leading, perspective: TripBookMotion.perspective"), "表紙が左の辺を軸にめくれていない")
        XCTAssertTrue(stage.contains(".drawingGroup()"), "本を1枚の絵にまとめていない")
        // 閉じるときは逆の順（表紙が戻る → 棚へ）
        let close = try XCTUnwrap(stage.range(of: "func close(arrived:"))
        let closeBody = String(stage[close.lowerBound...].prefix(1500))
        let coverBack = try XCTUnwrap(closeBody.range(of: "self.stage?.coverOpen = false"))
        let shelve = try XCTUnwrap(closeBody.range(of: "self.stage?.pulled = false"))
        XCTAssertLessThan(coverBack.lowerBound, shelve.lowerBound, "表紙が戻る前に棚へ帰している")
        // 動いている間の押し: 棚は本の層が止め、一冊の頁は広がり切るまで止める（下の頁に届かない）
        let opening = try XCTUnwrap(stage.range(of: "struct TripBookOpening: ViewModifier {"))
        let openingBody = String(stage[opening.lowerBound...].prefix(2000))
        XCTAssertTrue(openingBody.contains("if animated && settling {"), "広がっている間に下の頁が押せる")
        XCTAssertTrue(stage.contains("guard task == nil, stage == nil else { return }"), "動いている間に押すと二重に開く")
        XCTAssertTrue(shelf.contains("guard presented == nil, !stage.isBusy, stage.stage == nil else { return }"))
        // 動きを減らす設定ではすぐ開く
        XCTAssertTrue(shelf.contains("if reduceMotion {\n            presented = book"), "動きを減らす設定でも本を開く動きをしている")
        XCTAssertTrue(shelf.contains("TripBookOpening(book: book, namespace: bookSpace, animated: !reduceMotion)"))
    }

    /// 🔴 背表紙の当たりは背の幅＋間（隣と重ならない）。負の余白で広げない
    func testSpineHitAreaDoesNotOverlap() throws {
        let shelf = try source("Features/Trips/TripShelf.swift")
        let slot = try XCTUnwrap(shelf.range(of: "struct BookSpineSlot: View {"))
        let slotBody = String(shelf[slot.lowerBound...].prefix(900))
        XCTAssertTrue(slotBody.contains(".padding(.horizontal, CGFloat(TripBookshelf.spineGap / 2))"))
        XCTAssertFalse(shelf.contains(".padding(.horizontal, -"), "負の余白で当たりを広げている（隣の背の当たりと重なる）")
        XCTAssertTrue(shelf.contains("HStack(alignment: .bottom, spacing: 0) {"), "背の間を当たりの外に空けている")
        // 段の折り返しも当たりの幅で数える
        let widths = [22.0, 36, 29].map { $0 + TripBookshelf.spineGap }
        XCTAssertEqual(TripBookshelf.rows(widths: widths, available: 96, gap: 0), [[0, 1, 2]])
        XCTAssertEqual(TripBookshelf.rows(widths: widths, available: 95, gap: 0), [[0, 1], [2]])
    }

    /// 端末の旅を棚に出す判断は1か所（同じ旅を2冊にしない・枝 post-nudges-710 をまとめるときにここを替える）
    func testDeviceTripShelfGateIsOnePlace() throws {
        let shelf = try source("Features/Trips/TripShelf.swift")
        XCTAssertTrue(shelf.contains("deviceBooks.filter(TripBookshelf.showsOnShelf)"))
        let rule = try source("Core/Text/TripBookshelf.swift")
        XCTAssertTrue(rule.contains("trip.postedCount == 0"), "一部だけ投稿した旅を端末の旅として出している")
        // 振る舞い: 1枚でも投稿した旅は端末の背表紙にしない（投稿した旅として並ぶ・同じ旅を2冊にしない）
        let trip = LibraryTrip(id: "t", shots: [], start: Date(), end: Date(), days: [], center: nil, timeZone: .current)
        XCTAssertTrue(TripBookshelf.showsOnShelf(trip))
        XCTAssertFalse(TripBookshelf.showsOnShelf(LibraryTrips.keeping(trip, shots: [], postedCount: 1)),
                       "一部だけ投稿した旅が端末の旅としても並ぶ（同じ旅が2冊）")
    }

    // MARK: - 日のページを左右でめくる

    /// 横に払い、その向きにめくる日があるときだけ指を受ける。縦の指・左の端からの指・1日目と表紙で右へ払う指は「戻る」へ
    func testPageFlipBegins() {
        let ids = ["day-1", "day-2", "day-3"]
        XCTAssertEqual(TripBookPageFlip.beginDirection(dx: -20, dy: 5, startX: 200, dayIDs: ids, passed: []), 1, "表紙で左へ払うと1日目")
        XCTAssertNil(TripBookPageFlip.beginDirection(dx: 20, dy: 5, startX: 200, dayIDs: ids, passed: []), "表紙で右へ払う指を取った")
        XCTAssertNil(TripBookPageFlip.beginDirection(dx: 20, dy: 5, startX: 200, dayIDs: ids, passed: ["day-1"]),
                     "1日目で右へ払う指を取った（「戻る」に譲る）")
        XCTAssertEqual(TripBookPageFlip.beginDirection(dx: 20, dy: 5, startX: 200, dayIDs: ids, passed: ["day-1", "day-2"]), -1)
        XCTAssertNil(TripBookPageFlip.beginDirection(dx: -20, dy: 5, startX: 200, dayIDs: ids, passed: Set(ids)), "最後の日の先")
        XCTAssertNil(TripBookPageFlip.beginDirection(dx: -10, dy: 30, startX: 200, dayIDs: ids, passed: []), "縦の指を取った")
        XCTAssertNil(TripBookPageFlip.beginDirection(dx: 20, dy: 0, startX: 10, dayIDs: ids, passed: ["day-1", "day-2"]),
                     "左の端からの「戻る」を取った")
    }

    /// 離したとき: 距離か速さが足りればめくる。足りなければ戻す
    func testPageFlipCommits() {
        XCTAssertEqual(TripBookPageFlip.commitDirection(dx: -80, velocityX: 0), 1)
        XCTAssertEqual(TripBookPageFlip.commitDirection(dx: 80, velocityX: 0), -1)
        XCTAssertNil(TripBookPageFlip.commitDirection(dx: -30, velocityX: -100))
        XCTAssertEqual(TripBookPageFlip.commitDirection(dx: -30, velocityX: -900), 1, "速く払ってもめくらない")
        XCTAssertNil(TripBookPageFlip.commitDirection(dx: -30, velocityX: 900), "逆の向きに速いのにめくった")
        XCTAssertEqual(TripBookPageFlip.followAngle(dx: -1000, width: 390), -TripBookPageFlip.followMax)
        XCTAssertEqual(TripBookPageFlip.followAngle(dx: 0, width: 390), 0)
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

    /// 🔴 めくる id は一冊の行の id と同じ（違うと送れない）。投稿した一冊と端末の一冊の両方に付ける。
    /// 指は UIKit のパンで受ける（`simultaneousGesture` の `DragGesture` は実機で離しても呼ばれなかった・2026-10-28）
    func testPageFlipIsWiredToBothBooks() throws {
        let rows = TripBook.pageRows(of: TripBook.days(of: try trip("t", year: 2026, month: 9, photos: 2)))
        XCTAssertEqual(rows.first?.id, TripBookPageFlip.headerID(day: 1))
        let book = try source("Features/Trips/TripBookView.swift")
        XCTAssertTrue(book.contains(".modifier(TripDayFlip(dayIDs: TripBook.days(of: book).map { TripBookPageFlip.headerID(day: $0.number) }))"))
        XCTAssertTrue(book.contains(".tripDayHeader(id: TripBookPageFlip.headerID(day: day.number))"))
        XCTAssertTrue(book.contains(".tripDayFlipCatcher()"))
        XCTAssertTrue(book.contains(".accessibilityIdentifier(\"trips.day.\\(day.number)\")"), "UI テストで日の見出しを探せない")
        let device = try source("Features/Trips/DeviceTripShelf.swift")
        XCTAssertTrue(device.contains(".modifier(TripDayFlip(dayIDs: shown.days.map(\\.id)))"))
        XCTAssertTrue(device.contains(".tripDayHeader(id: day.id)"))
        XCTAssertTrue(device.contains(".tripDayFlipCatcher()"))
        let flip = try source("Features/Trips/TripDayFlip.swift")
        XCTAssertFalse(flip.contains(".simultaneousGesture("), "指を SwiftUI の払いで受けている（実機で離しても呼ばれない）")
        XCTAssertFalse(flip.contains("DragGesture("))
        XCTAssertTrue(flip.contains("UIPanGestureRecognizer"))
        XCTAssertTrue(flip.contains("otherGestureRecognizer === host?.panGestureRecognizer"), "縦の送りが先に動く")
        XCTAssertTrue(flip.contains("return isNavigationPop(otherGestureRecognizer)"), "「戻る」の払いが先に動く")
        // 本を開く拡大（`navigationTransition(.zoom)`）の閉じる払いも待たせる: 積む画面の view だけでなく、縦の送りの祖先の view に
        // 付いた払いはどれも（Mac run 1765 の `testCapturesTripBookOpened`「左へ払っても日がめくれない」）
        let pop = try XCTUnwrap(flip.range(of: "private func isNavigationPop(_ other: UIGestureRecognizer) -> Bool {"))
        let popBody = String(flip[pop.upperBound...].prefix(300))
        XCTAssertTrue(popBody.contains("host.isDescendant(of: view)"), "拡大の閉じる払いが日めくりより先に指を取る")
        XCTAssertFalse(popBody.contains("navigationController?.view"), "積む画面の view の払いしか待たせていない")
        XCTAssertTrue(flip.contains("guard !reduceMotion else {"), "動きを減らす設定でも動かしている")
        // 読み上げの「次の日」「前の日」は見出し（読み上げで止まる要素）に付ける
        let header = try XCTUnwrap(flip.range(of: "private struct TripDayHeader: ViewModifier {"))
        XCTAssertTrue(flip[header.lowerBound...].prefix(1500).contains(".accessibilityAction(named: L(\"次の日\""))
        // めくる見た目は向きと透明度だけ（一冊の body は作り直さない）
        let follow = try XCTUnwrap(flip.range(of: "struct DayTurnFollow<Content: View>: View {"))
        let followBody = String(flip[follow.lowerBound...].prefix(600))
        XCTAssertTrue(followBody.contains(".rotation3DEffect(") && followBody.contains(".opacity(model.fade)"))
    }

    /// 🔴 荷札の触覚は押しが決まったときだけ（押したまま送りに移った指では鳴らさない）
    func testTagHapticOnlyOnTap() throws {
        let tag = try source("Features/Profile/TripToolTag.swift")
        let style = try XCTUnwrap(tag.range(of: "struct TripToolTagStyle: ButtonStyle {"))
        let feedback = try XCTUnwrap(tag.range(of: "struct TripToolTapFeedback: ViewModifier {"))
        XCTAssertFalse(tag[style.lowerBound..<feedback.lowerBound].contains(".sensoryFeedback("), "押した・離しただけで鳴る")
        XCTAssertTrue(tag[feedback.lowerBound...].contains(".simultaneousGesture(TapGesture().onEnded { taps += 1 })"))
        let page = try source("Features/Profile/MyPageView.swift")
        XCTAssertEqual(page.components(separatedBy: ".buttonStyle(TripToolTagStyle())").count,
                       page.components(separatedBy: ".modifier(TripToolTapFeedback())").count, "触覚の無い荷札がある")
    }

    // MARK: - 荷札の道具の列

    /// 並びは決まった順、新しい道具は最後。スタンプ帳（#712）はマイページで出す。トランクは口のある人だけ
    func testToolOrderAndGating() throws {
        XCTAssertEqual(TripTool.allCases, [.plans, .albums, .trunk, .stampBook, .passBook])
        XCTAssertEqual(TripTool.shown(trunkAvailable: true), [.plans, .albums, .trunk, .passBook])
        XCTAssertEqual(TripTool.shown(trunkAvailable: false), [.plans, .albums, .passBook])
        XCTAssertEqual(TripTool.shown(trunkAvailable: true, stampBookReady: true), TripTool.allCases)
        XCTAssertEqual(TripTool.shown(trunkAvailable: false, stampBookReady: true), [.plans, .albums, .stampBook, .passBook])
        // マイページはスタンプ帳を出す（1.2.0 の統合で #712 が入った）。荷札の名前は「スタンプ帳」、画面の題は「旅のスタンプ帳」
        let page = try source("Features/Profile/MyPageView.swift")
        XCTAssertTrue(page.contains("TripTool.shown(trunkAvailable: trunkAvailability.isAvailable, stampBookReady: true)"))
        XCTAssertTrue(page.contains("case .stampBook:") && page.contains("StampBookToolTag()"), "荷札の列にスタンプ帳が無い")
        XCTAssertEqual(TripTool.stampBook.title, L("スタンプ帳", "Stamp book"))
        XCTAssertEqual(StampBookEntry.title, L("旅のスタンプ帳", "Travel stamp book"))
        let tag = try source("Features/Profile/StampBookScreen.swift")
        XCTAssertTrue(tag.contains(".buttonStyle(TripToolTagStyle())\n        .modifier(TripToolTapFeedback())"), "スタンプ帳の荷札に触覚が無い")
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

    /// 🔴 大きな字（アクセシビリティの大きさ）では荷札を折り返して、全部を画面の中に並べる（Mac run 1765 の
    /// `testCapturesTrunkLargeText`: 横に送る列では「旅のトランク」が画面の右の外に出て押せなかった）。ふつうの大きさは横に送る列のまま
    func testToolStripWrapsAtAccessibilitySizes() throws {
        XCTAssertTrue(TripTool.wrapsTags(isAccessibilitySize: true), "大きな字で荷札が横に送る列のまま（入口が画面の外に出る）")
        XCTAssertFalse(TripTool.wrapsTags(isAccessibilitySize: false), "ふつうの字で折り返している")
        let page = try source("Features/Profile/MyPageView.swift")
        let card = try XCTUnwrap(page.range(of: "private var tripToolsCard: some View {"))
        let tags = try XCTUnwrap(page.range(of: "private var tripToolTags: some View {"))
        let body = String(page[card.upperBound..<tags.lowerBound])
        let wrap = try XCTUnwrap(body.range(of: "if TripTool.wrapsTags(isAccessibilitySize: typeSize.isAccessibilitySize) {"))
        let flow = try XCTUnwrap(body.range(of: "FlowLayout(spacing: TripToolTag.spacing"))
        let scroll = try XCTUnwrap(body.range(of: "ScrollView(.horizontal, showsIndicators: false)"))
        XCTAssertTrue(wrap.lowerBound < flow.lowerBound && flow.lowerBound < scroll.lowerBound, "大きな字の枝が折り返しになっていない")
        // 荷札は1か所で書き、両方の並びで同じものを使う
        XCTAssertEqual(body.components(separatedBy: "tripToolTags").count - 1, 2, "荷札の並びを両方の枝で使っていない")
        XCTAssertTrue(page.contains("@Environment(\\.dynamicTypeSize) private var typeSize"))
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

    /// 見本の日の置き直しは、欄の多い写真（寸法・いいね・タグ・題・公開）でも作り直せる（元のまま残さない）。id は変えない
    func testPreviewSampleRedatesFullPhotos() throws {
        let json = ##"{"id":"full","src":"https://x/full.jpg","thumbSrc":"https://x/t.webp","userId":"owner","date":"2019-01-01","##
            + ##""createdAt":"2019-01-01T00:00:00.000Z","location":"金沢","width":4032,"height":3024,"likes":12,"published":true,"##
            + ##""tags":["秋"],"title":"兼六園","dominantColor":"#334455","displayName":"見本"}"##
        let full = try JSONDecoder.api.decode(Photo.self, from: Data(json.utf8))
        for trip in PreviewTripShelf.many(photos: [full]) {
            XCTAssertEqual(trip.photos.map(\.id), ["full"])
            XCTAssertNil(trip.photos.first?.date, "\(trip.id) の写真が置き直されていない（元の撮影日のまま）")
            XCTAssertEqual(TripBook.days(of: trip).map(\.number), [1])
        }
    }

    /// 見本の一冊の日の段は 1日目から旅の日数まで（写真の撮影日が旅の外でも、旅の日に置き直す）。
    /// 2026-11-23・Mac run 1765 と 1769: 見本の写真の撮影日のままで「-23日目」「5日目」になり、1日目が無く日めくりの試験が落ちた
    func testPreviewSampleDaysStartAtOne() throws {
        let photos = try (0..<30).map { try photo("p\($0)", date: $0 % 2 == 0 ? "2026-10-10" : "2023-03-01") }
        for trip in PreviewTripShelf.many(photos: photos) {
            let days = TripBook.days(of: trip).map(\.number)
            XCTAssertEqual(days.first, 1, "\(trip.id) が1日目から始まらない: \(days)")
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            let span = (utc.dateComponents([.day], from: trip.start, to: trip.end).day ?? 0) + 1
            XCTAssertTrue(days.allSatisfy { (1...span).contains($0) }, "\(trip.id) の日が旅の外: \(days)（\(span)日間）")
            XCTAssertEqual(days, days.sorted(), "\(trip.id) の日が順に並ばない")
            XCTAssertEqual(TripBookPageFlip.targetID(dayIDs: days.map { TripBookPageFlip.headerID(day: $0) }, passed: [], direction: 1),
                           "day-1", "表紙から左へ払っても1日目へめくれない")
        }
    }
}
