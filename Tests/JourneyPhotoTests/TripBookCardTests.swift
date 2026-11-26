import XCTest
@testable import JourneyPhoto

/// 旅の一冊を1枚の画像にして配る（`TripBookCard`）。
///
/// 固定したいのは:
///  1. 載せる文字は一冊の画面と同じ値だけ。数えられない距離は載せない（「—」を1行の文に出さない）
///  2. 表紙は枠いっぱいに切り抜き、持ち主が選んだ中心を残す。写真の外（黒い隙間）は見せない
///  3. ファイルの名前は旅ごとに1つで、記号を含まない
final class TripBookCardTests: XCTestCase {

    private func photo(_ id: String, location: String? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"https://x/\(id).jpg\""]
        if let location { fields.append("\"location\":\"\(location)\"") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    private func trip(id: String = "2026-09-12", photos: [Photo]) -> TripBook.Trip {
        let start = Date(timeIntervalSince1970: 1_789_171_200) // 2026-09-12 UTC
        return TripBook.Trip(id: id, place: "金沢", start: start, end: start.addingTimeInterval(2 * 86_400), photos: photos)
    }

    func testLinesMatchTheBookScreen() throws {
        let t = trip(photos: [try photo("a", location: "兼六園"), try photo("b", location: "兼六園"), try photo("c", location: "ひがし茶屋街")])
        let lines = TripBookCard.lines(of: t, distance: 12.4)
        XCTAssertEqual(lines.title, TripBook.tripTitle(of: t))
        XCTAssertEqual(lines.period, "\(TripBook.dateRange(from: t.start, to: t.end))\u{2002}\(TripBook.daysLabel(t.days))")
        XCTAssertEqual(lines.stats, L("3枚\u{2002}撮影地 2\u{2002}移動（直線）12 km", "3 photos\u{2002}2 places\u{2002}12 km (straight line)"))
        // 数えられない距離は載せない
        XCTAssertFalse(TripBookCard.lines(of: t, distance: nil).stats.contains("km"))
    }

    /// 🔴 2026-10-09: 撮影地の分かる写真が無い旅に「撮影地 0」（英語 "0 places"）と載せていた。
    /// 0 なら載せない（英語の「1 places」は `EnglishPluralTests` が見る）
    func testZeroPlacesIsLeftOut() throws {
        let none = trip(photos: [try photo("a"), try photo("b")])
        XCTAssertEqual(TripBookCard.lines(of: none, distance: nil).stats, L("2枚", "2 photos"))
        let one = trip(photos: [try photo("a", location: "兼六園")])
        XCTAssertEqual(TripBookCard.lines(of: one, distance: nil).stats, L("1枚\u{2002}撮影地 1", "1 photo\u{2002}1 place"))
    }

    func testCoverFillsTheFrameAndKeepsTheChosenCenter() {
        let canvas = TripBookCard.size
        // 横長の写真（3:2）を縦長の枠へ: 高さに合わせて、横がはみ出す
        let wide = CGSize(width: 3000, height: 2000)
        let centered = TripBookCard.coverRect(image: wide, in: canvas, focal: nil)
        XCTAssertEqual(centered.height, canvas.height, accuracy: 0.5)
        XCTAssertEqual(centered.midX, canvas.width / 2, accuracy: 0.5)
        // 中心を左端に寄せても、写真の外は見せない（左端は 0 まで）
        let left = TripBookCard.coverRect(image: wide, in: canvas, focal: Photo.FocalPoint(x: 0, y: 0.5))
        XCTAssertEqual(left.minX, 0, accuracy: 0.5)
        let right = TripBookCard.coverRect(image: wide, in: canvas, focal: Photo.FocalPoint(x: 1, y: 0.5))
        XCTAssertEqual(right.maxX, canvas.width, accuracy: 0.5)
        // 範囲外の値も枠の中に収める
        let wild = TripBookCard.coverRect(image: wide, in: canvas, focal: Photo.FocalPoint(x: 5, y: -3))
        XCTAssertLessThanOrEqual(wild.minX, 0)
        XCTAssertGreaterThanOrEqual(wild.maxX, canvas.width - 0.5)
        // 大きさの無い写真は枠そのもの
        XCTAssertEqual(TripBookCard.coverRect(image: .zero, in: canvas, focal: nil), CGRect(origin: .zero, size: canvas))
    }

    func testFileNameIsSafeAndStablePerTrip() throws {
        let t = trip(id: "2026-09-12|金沢/../x", photos: [])
        let name = TripBookCard.fileName(for: t)
        XCTAssertEqual(name, "trip-book-20260912x.jpg")
        XCTAssertEqual(name, TripBookCard.fileName(for: t))
        XCTAssertEqual(TripBookCard.fileName(for: trip(id: "金沢", photos: [])), "trip-book-card.jpg")
    }

    /// 題が2行でも、暗くし始めるのは文字より上。少なくとも下の半分は暗い
    func testShadeStartsAboveTheText() {
        let h = TripBookCard.size.height
        let oneLine = TripBookCard.textTop(canvasHeight: h, heights: [30, 100, 40, 40], gaps: [10, 10, 10])
        let twoLines = TripBookCard.textTop(canvasHeight: h, heights: [30, 200, 40, 40], gaps: [10, 10, 10])
        XCTAssertLessThan(twoLines, oneLine)
        XCTAssertLessThanOrEqual(TripBookCard.shadeTop(textTop: twoLines, canvasHeight: h), twoLines - TripBookCard.shadeLead)
        XCTAssertLessThanOrEqual(TripBookCard.shadeTop(textTop: h, canvasHeight: h), h * 0.5)
        // 文字が多すぎても上の余白より上には積まない
        XCTAssertEqual(TripBookCard.textTop(canvasHeight: h, heights: [2000], gaps: []), TripBookCard.margin)
    }

    /// 🔴 2026-11-26 owner: 下の4割が白→灰→黒の帯になり、写真が消えていた（48 段の帯を置き換えで塗っていた）。
    /// 暗くするのは**ひと続きのグラデーション**: 上の端は 0 から傾き 0 で入り（境目を見せない）、
    /// 下ほど濃く（戻らない）、文字の上端で白の字が読める濃さ、下の端で 0.85
    func testShadeIsOneSmoothGradient() throws {
        let top = 600.0, text = 860.0, bottom = 1350.0
        let stops = TripBookCard.shadeStops(top: top, textTop: text, bottom: bottom)
        XCTAssertGreaterThan(stops.count, 4, "段を重ねる形に戻っていないか（止めが2つだと上の端に線が見える）")
        XCTAssertEqual(stops.first?.location, 0)
        XCTAssertEqual(stops.first?.alpha, 0)
        XCTAssertEqual(try XCTUnwrap(stops.last?.location), 1, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(stops.last?.alpha), TripBookCard.shadeMaxAlpha, accuracy: 1e-9)
        for (a, b) in zip(stops, stops.dropFirst()) {
            XCTAssertLessThanOrEqual(a.location, b.location)
            XCTAssertLessThanOrEqual(a.alpha, b.alpha)
        }
        // 上の端は傾き 0 から（はじめの止めの間の濃さの増え方が、真っすぐ伸ばしたときより小さい）
        let knee = (text - top) / (bottom - top)
        XCTAssertLessThan(stops[1].alpha / stops[1].location, TripBookCard.shadeAlphaAtText / knee)
        // 文字の上端で読める濃さ
        let atText = try XCTUnwrap(stops.first { abs($0.location - knee) < 1e-9 })
        XCTAssertGreaterThanOrEqual(atText.alpha, 0.5)
        // 文字が暗くし始める所より上に乗る（写真が短い）ときも、下の端は 0.85 で、位置は 0〜1 の中
        let tight = TripBookCard.shadeStops(top: 900, textTop: 800, bottom: 1350)
        XCTAssertTrue(tight.allSatisfy { (0...1).contains($0.location) })
        XCTAssertEqual(tight.last?.alpha, TripBookCard.shadeMaxAlpha)
    }

    /// 🔴 2026-11-26 owner: 題「蔵王キツネ村（宮城県白石市）の旅」が「…（宮城県白」「石市）の旅」と
    /// 地名の途中で折れた。題は名前だけにして、括弧の地域は下の小さい行へ分ける
    func testPlaceRegionIsSplitOutOfTheTitle() throws {
        XCTAssertEqual(TripBookCard.splitPlace("蔵王キツネ村（宮城県白石市）").name, "蔵王キツネ村")
        XCTAssertEqual(TripBookCard.splitPlace("蔵王キツネ村（宮城県白石市）").region, "宮城県白石市")
        XCTAssertEqual(TripBookCard.splitPlace("Louvre (Paris, France)").name, "Louvre")
        XCTAssertEqual(TripBookCard.splitPlace("Louvre (Paris, France)").region, "Paris, France")
        // 括弧で終わらない名前・括弧だけの名前は、そのまま（地域は空）
        XCTAssertEqual(TripBookCard.splitPlace("金沢").name, "金沢")
        XCTAssertEqual(TripBookCard.splitPlace("金沢").region, "")
        XCTAssertEqual(TripBookCard.splitPlace("（仮）").name, "（仮）")
        XCTAssertEqual(TripBookCard.splitPlace("（仮）").region, "")

        let start = Date(timeIntervalSince1970: 1_789_171_200)
        let zao = TripBook.Trip(id: "z", place: "蔵王キツネ村, 白石市, 宮城県, 989-0733, 日本", start: start, end: start,
                                photos: [try photo("a")])
        let lines = TripBookCard.lines(of: zao, distance: nil)
        XCTAssertEqual(lines.title, L("蔵王キツネ村の旅", "Trip to 蔵王キツネ村"))
        XCTAssertEqual(lines.region, "宮城県白石市")
        // 載せる文字は同じ（足しも作りもしない）: 名前と地域をつなぐと画面の撮影地の形に戻る
        XCTAssertEqual("蔵王キツネ村（\(lines.region)）", LocationMatch.display(zao.place))
        // 地域の無い旅は、題はこれまでどおり
        let plain = trip(photos: [])
        XCTAssertEqual(TripBookCard.lines(of: plain, distance: nil).title, TripBook.tripTitle(of: plain))
        XCTAssertEqual(TripBookCard.lines(of: plain, distance: nil).region, "")
    }

    /// 題は**語の途中で折らない**。和文の名前は1行に入るまで縮める（字の幅を「1字 = 大きさ」で数える）
    func testTitleShrinksToOneLineInsteadOfBreakingAWord() {
        let width = TripBookCard.size.width - TripBookCard.margin * 2 // 936
        let measure: (String, CGFloat) -> CGFloat = { text, size in CGFloat(text.count) * size }
        // 「蔵王キツネ村の旅」8字: 104 なら 832 で1行
        let zao = TripBookCard.titleFit("蔵王キツネ村の旅", width: width, measure: measure)
        XCTAssertEqual(zao.lines, ["蔵王キツネ村の旅"])
        XCTAssertEqual(zao.size, TripBookCard.Font.title)
        // 前の題（括弧つき・14字）でも、字の間では折らない（1行に縮めるか、入らなければ「…」）
        let long = TripBookCard.titleFit("蔵王キツネ村（宮城県白石市）の旅", width: width, measure: measure)
        XCTAssertFalse(long.lines.contains { $0.hasSuffix("白") }, "地名の途中で折れた: \(long.lines)")
        XCTAssertTrue(long.lines.allSatisfy { measure($0, long.size) <= width })
        // 12字の名前は縮めて1行（下限 64 なら 14 字まで入る）
        let twelve = TripBookCard.titleFit("あいうえおかきくけこさしの旅", width: width, measure: measure)
        XCTAssertEqual(twelve.lines.count, 1)
        XCTAssertLessThan(twelve.size, TripBookCard.Font.title)
        XCTAssertGreaterThanOrEqual(twelve.size, TripBookCard.Font.titleMinimum)
        // 英語は語の切れ目（空白）で2行まで
        let english = TripBookCard.titleFit("Trip to Shirakawa-go Gassho Village", width: width, measure: { text, size in
            CGFloat(text.count) * size * 0.5
        })
        XCTAssertLessThanOrEqual(english.lines.count, TripBookCard.titleMaxLines)
        XCTAssertEqual(english.lines.joined(separator: " "), "Trip to Shirakawa-go Gassho Village")
    }

    /// 共有の絵の文字に「·」「・」の区切りを使わない（owner の好み・2026-11-12）
    func testCardTextHasNoMiddleDots() throws {
        let t = trip(photos: [try photo("a", location: "兼六園"), try photo("b", location: "ひがし茶屋街")])
        let lines = TripBookCard.lines(of: t, distance: 3)
        for text in [lines.eyebrow, lines.title, lines.region, lines.period, lines.stats, lines.footer] {
            XCTAssertFalse(text.contains("·") || text.contains("・"), text)
        }
    }

    /// 縮めて展開する大きさ: 枠を埋めるぶんだけ。元より大きくはしない
    func testFillSizeNeverUpscales() {
        let canvas = TripBookCard.size
        XCTAssertEqual(TripBookCard.fillSize(image: CGSize(width: 6000, height: 4000), canvas: canvas),
                       CGSize(width: 2025, height: 1350))
        XCTAssertEqual(TripBookCard.fillSize(image: CGSize(width: 800, height: 600), canvas: canvas),
                       CGSize(width: 800, height: 600))
    }

    /// 書いた画像はフォルダごと消せる（サインアウト・退会）
    func testWriteAndRemoveAll() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("trip-book-cards-test-\(UUID().uuidString)")
        let t = trip(photos: [])
        let url = try XCTUnwrap(TripBookCard.write(Data([1, 2, 3]), for: t, in: dir))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        TripBookCard.removeAll(in: dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }
}
