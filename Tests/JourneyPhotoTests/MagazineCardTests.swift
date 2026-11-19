import XCTest
@testable import JourneyPhoto
#if !os(Linux)
import UIKit
#endif

/// 共有の絵「雑誌」の寸法・置き方・字の中身・Vol. の番号（`MagazineCard`・2026-11-18 owner 採用）。描く処理を通さず Linux で見る。
/// 書き出した画像の画素での点検（安全域・明暗の比・重なり・切れ）は Mac の `ShareCardAuditTests`（`testMagazine…`）と、下の Mac だけの試験
final class MagazineCardTests: XCTestCase {
    typealias M = MagazineCard

    static let aspects: [(String, CGFloat)] = [
        ("縦長9:16", 9.0 / 16.0), ("縦長3:4", 0.75), ("縦長4:5", 0.8), ("正方形", 1), ("横長3:2", 1.5),
        ("横長16:9", 16.0 / 9.0), ("パノラマ3:1", 3), ("パノラマ4:1", 4), ("細長1:3", 1.0 / 3.0)]
    static var frames: [(String, M.Frame)] {
        [("ストーリー", .story), ("投稿4:5", .post(.portrait)), ("投稿1:1", .post(.square)), ("投稿9:16", .post(.story))]
    }
    static let heads: [M.Head] = [
        M.Head(titleSize: 88, titleLines: 1, hasSub: true), M.Head(titleSize: 60, titleLines: 2, hasSub: true),
        M.Head(titleSize: 76, titleLines: 1, hasSub: false), M.Head(titleSize: 0, titleLines: 0, hasSub: true),
        M.Head(titleSize: 84, titleLines: 2, hasSub: true)]

    // MARK: - 写真を切らない

    /// 全面に敷くのは切れる量が 8% 以下のときだけ（3:4 を投稿 4:5 に置くと 6.25% 切れる）
    func testFullBleedOnlyWhenTheCropIsAtMostEightPercent() {
        XCTAssertTrue(M.isFullBleed(aspect: 0.75, in: .post(.portrait)))
        XCTAssertEqual(M.crop(aspect: 0.75, in: .post(.portrait)), 0.0625, accuracy: 0.0001)
        XCTAssertTrue(M.isFullBleed(aspect: 0.8, in: .post(.portrait)))
        XCTAssertTrue(M.isFullBleed(aspect: 9.0 / 16.0, in: .story))
        XCTAssertTrue(M.isFullBleed(aspect: 1, in: .post(.square)))
        XCTAssertFalse(M.isFullBleed(aspect: 0.9, in: .post(.square)))   // 10% 切れる
        XCTAssertFalse(M.isFullBleed(aspect: 1.5, in: .post(.portrait)))
        XCTAssertFalse(M.isFullBleed(aspect: 0.75, in: .story))           // 25% 切れる
        XCTAssertFalse(M.isFullBleed(aspect: 0.8, in: .story))
    }

    /// どの写真・どの置き場でも: 全面なら切れる量 8% 以下で絵を覆う、それ以外は縦横比のまま（切らない）で絵の中・床の上
    func testPhotoIsNeverCroppedBeyondEightPercent() {
        for (aName, aspect) in Self.aspects {
            for (fName, frame) in Self.frames {
                for head in Self.heads {
                    for hasExif in [true, false] {
                        let l = M.layout(aspect: aspect, in: frame, head: head, hasExif: hasExif)
                        let label = "\(aName) \(fName) \(head) exif=\(hasExif)"
                        if l.full {
                            XCTAssertLessThanOrEqual(l.crop, 0.08 + 0.0001, label)
                            XCTAssertLessThanOrEqual(l.photo.minX, 0.001, label)
                            XCTAssertLessThanOrEqual(l.photo.minY, 0.001, label)
                            XCTAssertGreaterThanOrEqual(l.photo.maxX, M.width - 0.001, label)
                            XCTAssertGreaterThanOrEqual(l.photo.maxY, frame.height - 0.001, label)
                            XCTAssertNil(l.exifTop, "全面のときは撮影の値を出さない \(label)")
                        } else {
                            XCTAssertEqual(l.photo.width / l.photo.height, aspect, accuracy: 0.002, "切れている \(label)")
                            XCTAssertGreaterThanOrEqual(l.photo.minX, -0.001, label)
                            XCTAssertLessThanOrEqual(l.photo.maxX, M.width + 0.001, label)
                            XCTAssertLessThanOrEqual(l.photo.maxY, frame.photoFloor + 0.001, "床（返信欄）を越えた \(label)")
                            XCTAssertGreaterThan(l.photo.height, 200, "写真が小さすぎる \(label) \(l.photo)")
                        }
                    }
                }
            }
        }
    }

    /// 写真の大きさ（模型と比べる数をログに）。横長 3:2 のストーリー・投稿は幅いっぱい
    func testPhotoSizes() {
        let head = M.Head(titleSize: 88, titleLines: 1, hasSub: true)
        func size(_ aspect: CGFloat, _ frame: M.Frame) -> CGRect {
            M.layout(aspect: aspect, in: frame, head: M.Head(titleSize: M.titleSize(full: false, frame: frame),
                                                             titleLines: 1, hasSub: true)).photo
        }
        XCTAssertEqual(size(1.5, .story).width, 1080, accuracy: 0.01)
        XCTAssertEqual(size(1.5, .post(.portrait)).width, 1080, accuracy: 0.01)
        print("measured [magazine-size] " + Self.frames.flatMap { fName, frame in
            [("3:4", 0.75), ("3:2", 1.5), ("1:1", 1.0)].map { aName, a -> String in
                let p = M.layout(aspect: CGFloat(a), in: frame, head: head).photo
                return "\(fName) \(aName)=\(Int(p.minX)),\(Int(p.minY)),\(Int(p.width))x\(Int(p.height))"
            }
        }.joined(separator: " "))
    }

    // MARK: - 字は余白に（写真の上に載せない）・安全域の中

    /// 字の段の枠（帯・題・撮影地の行・撮影の値の行）
    static func textBoxes(_ l: M.Layout, head: M.Head) -> [(String, CGRect)] {
        var boxes: [(String, CGRect)] = [
            ("帯", CGRect(x: M.margin, y: l.bandTop, width: M.contentWidth, height: M.Band.numberSize * 1.3))]
        if head.titleLines > 0 {
            boxes.append(("題", CGRect(x: M.margin, y: l.titleTop, width: M.contentWidth,
                                      height: CGFloat(head.titleLines) * head.titleSize * M.Title.lineHeight)))
        }
        if head.hasSub {
            boxes.append(("撮影地", CGRect(x: M.margin, y: l.subTop, width: M.contentWidth, height: M.Sub.height)))
        }
        if let exif = l.exifTop {
            boxes.append(("撮影の値", CGRect(x: M.margin, y: exif, width: M.contentWidth, height: M.Exif.height)))
        }
        return boxes
    }

    /// 余白に置く形では、字の段のどれも写真の枠に掛からない（写真の上に字を載せない）。全面の形は題が端の帯の中
    func testTextStaysOffThePhotoAndInsideTheSafeArea() {
        for (aName, aspect) in Self.aspects {
            for (fName, frame) in Self.frames {
                for head in Self.heads {
                    for hasExif in [true, false] {
                        for edge in [M.Edge.top, .bottom] {
                            let l = M.layout(aspect: aspect, in: frame, head: head, hasExif: hasExif, edge: edge)
                            let label = "\(aName) \(fName) \(head) exif=\(hasExif) \(edge)"
                            for (name, box) in Self.textBoxes(l, head: head) {
                                XCTAssertGreaterThanOrEqual(box.minY, frame.textTop - 0.001, "\(name) が上の線より上 \(label)")
                                XCTAssertLessThanOrEqual(box.maxY, frame.textBottom + 0.001, "\(name) が下の線より下 \(label)")
                                if !l.full {
                                    XCTAssertFalse(box.intersects(l.photo.insetBy(dx: 0.5, dy: 0.5)),
                                                   "\(name) が写真の上 \(label) \(box) \(l.photo)")
                                }
                            }
                            if !l.full {
                                // 写真の上の余白（owner「上の余白がないのでバランス悪い」・暦で指摘）: 字の段と写真の間は 44 以上
                                let above = Self.textBoxes(l, head: head).map(\.1).filter { $0.maxY <= l.photo.minY + 0.5 }
                                let gap = l.photo.minY - (above.map(\.maxY).max() ?? 0)
                                XCTAssertGreaterThanOrEqual(gap, 40 - 0.001, "写真の上の余白 \(gap) \(label)")
                            }
                        }
                    }
                }
            }
        }
    }

    /// 字を置く帯は、どの比でも共有カードの安全域（端から 6%・9:16 の上 14% と 4:5 の切り取り・下 20%）の内側
    func testTextZoneIsInsideTheShareCardSafeArea() {
        for ratio in [SignatureShareCardRenderer.Ratio.portrait, .story, .square] {
            let frame = M.Frame.post(ratio)
            let safe = ShareCardSafeArea.rect(ratio: ratio)
            XCTAssertGreaterThanOrEqual(frame.textTop, safe.minY, "\(ratio)")
            XCTAssertLessThanOrEqual(frame.textBottom, safe.maxY, "\(ratio)")
            XCTAssertGreaterThanOrEqual(M.margin, safe.minX)
            XCTAssertLessThanOrEqual(M.right, safe.maxX)
        }
        // ストーリーの返信欄（下 10%）に写真も置かない
        XCTAssertEqual(M.Frame.story.photoFloor, 1920 * 0.9, accuracy: 0.001)
        XCTAssertEqual(M.Frame.post(.story), .story)
        // 投稿も写真の下に左右と同じ 72 を残す（Mac run 1557 の絵で、正方形の写真が下の端に付いていた）
        XCTAssertEqual(M.Frame.post(.portrait).photoFloor, 1350 - 72, accuracy: 0.001)
        XCTAssertEqual(M.Frame.post(.square).photoFloor, 1080 - 72, accuracy: 0.001)
        for aspect in [CGFloat(0.75), 0.5, 1.5] {   // 全面に敷かない形
            let l = M.layout(aspect: aspect, in: .post(.square), head: M.Head(titleSize: 76, titleLines: 1, hasSub: true))
            XCTAssertLessThanOrEqual(l.photo.maxY, 1080 - 72 + 0.001, "\(aspect)")
        }
    }

    /// 全面のときの題の置き場: 下の端なら撮影地の行の下端が字の下端
    func testFullBleedTitleSitsOnTheChosenEdge() {
        let head = M.Head(titleSize: 84, titleLines: 1, hasSub: true)
        let top = M.layout(aspect: 0.75, in: .post(.portrait), head: head, edge: .top)
        let bottom = M.layout(aspect: 0.75, in: .post(.portrait), head: head, edge: .bottom)
        XCTAssertTrue(top.full)
        XCTAssertEqual(top.titleTop, 72 + M.Band.eyebrowBottom + M.Title.gapFull, accuracy: 0.001)
        XCTAssertEqual(bottom.subTop + M.Sub.height, 1278, accuracy: 0.001)
        XCTAssertEqual(top.photo, bottom.photo)
    }

    // MARK: - 題の置き場を自動で選ぶ

    func testQuieterEdgeIsChosen() {
        let flatDark = [Double](repeating: 0.05, count: 100)
        let busyBright = (0..<100).map { $0 % 2 == 0 ? 0.9 : 0.1 }
        XCTAssertEqual(M.quieterEdge(top: busyBright, bottom: flatDark), .bottom)
        XCTAssertEqual(M.quieterEdge(top: flatDark, bottom: busyBright), .top)
        XCTAssertEqual(M.quieterEdge(top: flatDark, bottom: flatDark), .top)
        // 同じばらつきなら暗いほう
        XCTAssertEqual(M.quieterEdge(top: [Double](repeating: 0.8, count: 10), bottom: [Double](repeating: 0.2, count: 10)),
                       .bottom)
    }

    // MARK: - 長い題が入る

    /// 字の幅を「字数 × 大きさ」とみなした測り
    static func fake(_ text: String, _ size: CGFloat) -> CGFloat { CGFloat(text.count) * size }

    func testTitleShrinksThenWrapsToTwoLines() {
        // 12字: 84 では 1008 で入らず、78 で入る（1行）
        let short = M.fitTitle(String(repeating: "あ", count: 12), base: 84, measure: Self.fake)
        XCTAssertEqual(short.size, 78)
        XCTAssertEqual(short.lines.count, 1)
        XCTAssertFalse(short.truncated)
        // 30字: 60 の1行（1800）に入らない → 2行に入る一番大きい大きさ（15字 × 62 = 930）
        let long = M.fitTitle(String(repeating: "い", count: 30), base: 84, measure: Self.fake)
        XCTAssertEqual(long.lines.count, 2)
        XCTAssertFalse(long.truncated)
        XCTAssertEqual(long.size, 62)
        XCTAssertEqual(long.lines.joined(), String(repeating: "い", count: 30))
        for line in long.lines { XCTAssertLessThanOrEqual(Self.fake(line, long.size), 936) }
        // 40字: 60 の2行（15字 + 25字）でも入らない → 2行目を切る（`truncated`）
        let tooLong = M.fitTitle(String(repeating: "う", count: 40), base: 84, measure: Self.fake)
        XCTAssertEqual(tooLong.size, 60)
        XCTAssertEqual(tooLong.lines.count, 2)
        XCTAssertTrue(tooLong.truncated)
    }

    /// 2行に分けるとき、ラテン文字の語の途中で切らず、行頭に句読点を置かない
    func testWrapKeepsWordsAndAvoidsLeadingPunctuation() {
        // 23字目までが入る幅。「Old」の途中で切らず、語の頭（空白の後ろ）で切る
        let latin = M.wrap("Saint-Germain-en-Laye Old Town", maxWidth: 23 * 10) { Self.fake($0, 10) }
        XCTAssertEqual(latin, ["Saint-Germain-en-Laye", "Old Town"])
        let japanese = M.wrap("あいうえおかきくけ、こさしすせ", maxWidth: 9 * 10) { Self.fake($0, 10) }
        XCTAssertEqual(japanese.first?.count, 8)
        XCTAssertFalse(japanese.last?.hasPrefix("、") ?? true)
        XCTAssertEqual(japanese.joined(), "あいうえおかきくけ、こさしすせ")
    }

    // MARK: - 字の中身

    static let october10 = TripBook.utcCalendar.date(from: DateComponents(year: 2026, month: 10, day: 10))!
    static let kanazawa = "兼六園, 兼六町, 金沢市, 石川県, 920-0936, 日本"

    static func credit(title: String? = "緑に包まれた水面の静寂", showsDate: Bool = true,
                       volume: Int? = 12) -> SignatureShareCardRenderer.Credit {
        var credit = SignatureShareCardRenderer.Credit(
            name: "旅灯", username: "tabi_akari", location: LocationMatch.shareCardDisplay(kanazawa), coords: nil,
            camera: "Hasselblad X2D II 100C", lens: "XCD 55V", exposure: "1/90s", aperture: "f/4.5", iso: 50,
            verified: false, proStyle: nil, early: false, badge: nil, place: LocationMatch.shareCardPlace(kanazawa))
        credit.takenDay = october10
        credit.showsDate = showsDate
        credit.title = title
        credit.volume = volume
        return credit
    }

    func testCreditTexts() {
        let t = M.texts(for: Self.credit())
        XCTAssertEqual(t.title, "緑に包まれた水面の静寂")
        XCTAssertEqual(t.place, "石川県 金沢市")
        XCTAssertEqual(t.placeFallback, "石川県")
        XCTAssertEqual(t.date, "2026.10.10")
        XCTAssertEqual(t.camera, "Hasselblad X2D II 100C")
        XCTAssertEqual(t.values, ["f/4.5", "1/90s", "ISO 50"])
        XCTAssertEqual(t.volume, 12)
        // レンズ・座標・県の英名は出さない（字は4つだけ）
        let all = [t.title, t.place, t.date, t.camera].compactMap { $0 }.joined() + t.values.joined()
        XCTAssertFalse(all.contains("XCD"))
        XCTAssertFalse(all.uppercased().contains("ISHIKAWA"))
    }

    /// 題が無ければ撮影地を題にし、撮影地の行には重ねない
    func testTitleFallsBackToThePlaceWithoutRepeatingIt() {
        let t = M.texts(for: Self.credit(title: "  \n "))
        XCTAssertEqual(t.title, "石川県 金沢市")
        XCTAssertNil(t.place)
        XCTAssertNil(t.placeFallback)
        XCTAssertEqual(t.date, "2026.10.10")
        // 改行の入った題は1行にそろえる
        XCTAssertEqual(M.texts(for: Self.credit(title: "朝の\n金沢")).title, "朝の 金沢")
    }

    /// 日付を伏せると日付は出ない（共有画面の「日付」の入切・`ShareCardDateChoice`）
    func testDateOffHidesTheDate() {
        let t = M.texts(for: ShareCardDateChoice.credit(Self.credit(), showsDate: false))
        XCTAssertNil(t.date)
        let all = [t.title, t.place, t.camera].compactMap { $0 }.joined() + t.values.joined()
        XCTAssertFalse(all.contains("2026"), all)
        // 撮った日が分からなくても出さない
        var undated = Self.credit()
        undated.takenDay = nil
        XCTAssertNil(M.texts(for: undated).date)
    }

    /// 無い撮影の値は出さない。何も無ければ撮影の値の行も無い
    func testMissingExifValuesAreSkipped() {
        let t = M.texts(title: "題", place: nil, takenDay: nil, showsDate: true, camera: nil, aperture: "f/8",
                        exposure: nil, iso: nil, volume: nil)
        XCTAssertEqual(t.values, ["f/8"])
        XCTAssertNil(t.camera)
        XCTAssertTrue(t.hasExif)
        let none = M.texts(title: "題", place: nil, takenDay: nil, showsDate: true, camera: " ", aperture: nil,
                           exposure: nil, iso: nil, volume: nil)
        XCTAssertFalse(none.hasExif)
        XCTAssertNil(none.volume)
        XCTAssertNil(M.texts(title: nil, place: nil, takenDay: nil, showsDate: true, camera: nil, aperture: nil,
                             exposure: nil, iso: nil, volume: 0).volume)
    }

    /// 撮影地の1行: 和文は大きい順、ラテン文字は小さい順。区切りに中黒を使わない
    func testPlaceLine() {
        XCTAssertEqual(M.placeLine(LocationMatch.ShareCardPlace(primary: "兵庫県", secondary: "神戸市")), "兵庫県 神戸市")
        XCTAssertEqual(M.placeLine(LocationMatch.ShareCardPlace(primary: "France", secondary: "Versailles")),
                       "Versailles, France")
        XCTAssertEqual(M.placeLine(LocationMatch.ShareCardPlace(primary: "石川県", secondary: nil)), "石川県")
        XCTAssertNil(M.placeLine(nil))
        for line in [M.placeLine(LocationMatch.ShareCardPlace(primary: "兵庫県", secondary: "神戸市")) ?? ""] {
            XCTAssertFalse(line.contains("・") || line.contains("·") || line.contains("|"))
        }
    }

    /// ストーリーは選んだ細かさを守る（県まで・市まで・出さない）。場所を出さないなら、題の代わりの撮影地も出さない
    func testStoryMagazineKeepsTheChosenDetail() {
        var facts = TravelStory.Facts(location: Self.kanazawa, takenDay: Self.october10, name: "旅灯", latitude: 36.56)
        var choice = TravelStory.Choice()
        choice.kind = .magazine
        choice.placeLevel = .prefecture
        XCTAssertEqual(TravelStory.magazine(facts, choice: choice).title, "石川県")
        choice.placeLevel = .city
        XCTAssertEqual(TravelStory.magazine(facts, choice: choice).title, "石川県 金沢市")
        choice.placeLevel = .none
        let hidden = TravelStory.magazine(facts, choice: choice)
        XCTAssertNil(hidden.title)
        XCTAssertNil(hidden.place)
        XCTAssertNil(hidden.placeFallback)
        facts.title = "緑に包まれた水面の静寂"
        let titled = TravelStory.magazine(facts, choice: choice)
        XCTAssertEqual(titled.title, "緑に包まれた水面の静寂")
        XCTAssertNil(titled.place)
        choice.placeLevel = .city
        XCTAssertEqual(TravelStory.magazine(facts, choice: choice).place, "石川県 金沢市")
        XCTAssertEqual(TravelStory.magazine(facts, choice: choice).placeFallback, "石川県")
        // 日付は「出さない」以外なら撮った日（「今日」も日付で書く）
        XCTAssertEqual(TravelStory.magazine(facts, choice: choice).date, "2026.10.10")
        choice.dateLevel = .none
        XCTAssertNil(TravelStory.magazine(facts, choice: choice).date)
    }

    /// 写真から雑誌の題と撮影の値と id を写す（写真の詳細・旅の一冊の両方の入口）
    func testFactsCarryTheTitleExifAndId() throws {
        let photo = try JSONDecoder.api.decode(Photo.self, from: Data("""
        {"id":"p1","src":"/uploads/p1.jpg","title":{"ja":"霞ヶ池","en":"Kasumi Pond"},"location":"石川県",
         "exif":{"camera":"SONY ILCE-7M3","aperture":"f/2.8","exposure":"1/1250s","iso":125}}
        """.utf8))
        let facts = TravelStory.facts(of: photo, name: "旅灯")
        XCTAssertEqual(facts.photoId, "p1")
        XCTAssertEqual(facts.camera, "SONY ILCE-7M3")
        XCTAssertEqual(facts.aperture, "f/2.8")
        XCTAssertEqual(facts.exposure, "1/1250s")
        XCTAssertEqual(facts.iso, 125)
        XCTAssertNotNil(facts.title)
        XCTAssertNil(facts.volume)
    }

    // MARK: - Vol. の番号

    static func photo(_ id: String, created: String?, published: Bool? = true, group: String? = nil) throws -> Photo {
        var fields = ["\"id\":\"\(id)\"", "\"src\":\"/uploads/\(id).jpg\"", "\"userId\":\"me\""]
        if let created { fields.append("\"createdAt\":\"\(created)\"") }
        if let published { fields.append("\"published\":\(published)") }
        if let group { fields.append("\"groupId\":\"\(group)\"") }
        return try JSONDecoder.api.decode(Photo.self, from: Data("{\(fields.joined(separator: ","))}".utf8))
    }

    /// 投稿した日時の順に 1 から。下書きは数えない。同じ投稿の束は1つ。前の投稿を消すと繰り上がる
    func testVolumeCountsPostsInOrder() throws {
        // 一覧は新しい順（`/user/photos` と同じ）
        let mine = [
            try Self.photo("d", created: "2026-11-05T00:00:00.000Z"),
            try Self.photo("draft", created: "2026-11-04T00:00:00.000Z", published: false),
            try Self.photo("c2", created: "2026-11-03T00:00:01.000Z", group: "g"),
            try Self.photo("c1", created: "2026-11-03T00:00:00.000Z", group: "g"),
            try Self.photo("b", created: "2026-11-02T00:00:00.000Z", published: nil),
            try Self.photo("a", created: "2026-11-01T00:00:00.000Z")]
        XCTAssertEqual(M.volume(of: "a", among: mine), 1)
        XCTAssertEqual(M.volume(of: "b", among: mine), 2)
        XCTAssertEqual(M.volume(of: "c1", among: mine), 3)
        XCTAssertEqual(M.volume(of: "c2", among: mine), 3)
        XCTAssertEqual(M.volume(of: "d", among: mine), 4)
        XCTAssertNil(M.volume(of: "draft", among: mine), "下書きに番号を付けた")
        // 前の投稿を消すと繰り上がる
        XCTAssertEqual(M.volume(of: "d", among: mine.filter { $0.id != "a" }), 3)
    }

    /// 番号が分からないときは nil（「Vol.」を出さない）
    func testVolumeIsNilWhenUnknown() throws {
        let mine = [try Self.photo("b", created: "2026-11-02T00:00:00.000Z"),
                    try Self.photo("a", created: "2026-11-01T00:00:00.000Z")]
        XCTAssertNil(M.volume(of: "a", among: nil), "一覧が読めない（圏外）")
        XCTAssertNil(M.volume(of: "zzz", among: mine), "一覧に無い")
        XCTAssertNil(M.volume(of: nil, among: mine))
        XCTAssertNil(M.volume(of: "b", among: mine + [try Self.photo("x", created: nil)]), "順が決められない")
    }

    /// 投稿したばかりでまだ一覧に無い写真は足して数える
    func testVolumeCountsAJustPostedPhoto() throws {
        let mine = [try Self.photo("a", created: "2026-11-01T00:00:00.000Z")]
        let posted = try Self.photo("new", created: "2026-11-18T00:00:00.000Z")
        XCTAssertEqual(M.volume(of: "new", among: mine, justPosted: posted), 2)
        XCTAssertNil(M.volume(of: "new", among: mine))
        // 一覧に来ていれば重ねない
        XCTAssertEqual(M.volume(of: "new", among: mine + [posted], justPosted: posted), 2)
    }

    // MARK: - 字の読みやすさ

    func testShadowTargetsAndSchedule() {
        XCTAssertEqual(M.requiredContrast(fontSize: 60), 7)
        XCTAssertEqual(M.requiredContrast(fontSize: 36), 4.5)
        // 狙う比は守る比より 5% 上（JPEG のにじみの分・Mac run 1552 で 4.50 を僅かに下回った）
        XCTAssertEqual(M.targetContrast(fontSize: 36), 4.5 * 1.05, accuracy: 0.0001)
        XCTAssertGreaterThan(M.targetContrast(fontSize: 60), 7)
        XCTAssertEqual(M.Shadow.blur(size: 84, pass: 0), 84 * 0.26, accuracy: 0.001)
        XCTAssertEqual(M.Shadow.blur(size: 84, pass: 3), 84 * 0.14, accuracy: 0.001)
        XCTAssertEqual(M.Shadow.blur(size: 84, pass: 7), max(6, 84 * 0.07), accuracy: 0.001)
        XCTAssertEqual(M.Shadow.blur(size: 33, pass: 9), 6, accuracy: 0.001)
        // 白い字は黒い地で 4.5 に届く（影は要らない）。灰の字（撮影の値 204）も黒い地では届く
        XCTAssertGreaterThan(M.contrast(ink: M.Ink.exif, background: 0), 4.5)
        XCTAssertLessThan(M.contrast(ink: 1, background: 1), 4.5)
    }

    // MARK: - 型の並びと画面のつなぎ（Linux で画面は描けないので、作りを文字で見る）

    func testStyleOrderAndDateToggle() {
        XCTAssertEqual(ShareCardStyleChoice.order.last, .magazine)
        XCTAssertEqual(ShareCardStyleChoice.title(.magazine), L("雑誌", "Magazine"))
        XCTAssertTrue(ShareCardDateChoice.drawsDate(.magazine))
        XCTAssertTrue(ShareCardDateChoice.showsToggle(style: .magazine, credit: Self.credit()))
        // 撮った日が無くても雑誌は選べる（題と撮影地で組める）
        var undated = Self.credit()
        undated.takenDay = nil
        XCTAssertTrue(ShareCardStyleChoice.order(for: undated).contains(.magazine))
        XCTAssertFalse(ShareCardDateChoice.showsToggle(style: .magazine, credit: undated))
        // 今の「表紙」は残す
        XCTAssertTrue(ShareCardStyleChoice.order.contains(.cover))
        XCTAssertFalse(TravelStory.Kind.magazine.supportsSticker)
        XCTAssertEqual(TravelStory.Kind.allCases.last, .magazine)
        XCTAssertTrue(TravelStory.kinds(for: TravelStory.Facts(location: nil, takenDay: nil, name: "J")).contains(.magazine))
    }

    func testSheetsWaitForTheVolumeAndPassTheIds() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        func source(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }
        let sheet = try source("Sources/JourneyPhoto/Features/Common/SignatureShareCardSheet.swift")
        XCTAssertTrue(sheet.contains("drawn.volume = volume"))
        XCTAssertTrue(sheet.contains("if selectedStyle == .magazine, !volumeLoaded"))
        XCTAssertTrue(sheet.contains("MagazineVolume.load(photoId: credit.photoId, justPosted: posted?.photo"))
        let story = try source("Sources/JourneyPhoto/Features/Common/TravelStorySheet.swift")
        XCTAssertTrue(story.contains("if each.kind == .magazine, !volumeLoaded { continue }"))
        XCTAssertTrue(story.contains("let facts = drawnFacts"))
        let detail = try source("Sources/JourneyPhoto/Features/PhotoDetail/PhotoDetailView.swift")
        XCTAssertTrue(detail.contains("photoId: target.id)"))
        let posted = try source("Sources/JourneyPhoto/Features/Upload/PostedShareCard.swift")
        XCTAssertTrue(posted.contains("photoId: photo.id)"))
        XCTAssertTrue(posted.contains("photo: card.photo))"))
        // 数えるのは読めない行の無い全件だけ
        let service = try source("Sources/JourneyPhoto/Services/PhotoService.swift")
        XCTAssertTrue(service.contains("return list.dropped == 0 ? list.photos : nil"))
    }

    /// 画面・絵の字に中黒を使わない
    func testNoMiddleDots() {
        let t = M.texts(for: Self.credit())
        for text in [t.title, t.place, t.date, t.camera, M.Band.eyebrow, M.Band.vol].compactMap({ $0 }) + t.values {
            XCTAssertFalse(text.contains("・") || text.contains("·") || text.contains("|"), text)
        }
        XCTAssertFalse(ShareCardStyleChoice.title(.magazine).contains("撮りどき"))
    }
}

#if !os(Linux)
/// 書き出した画像で見る（Mac だけ）。写真の枠の画素に字が描かれない・Vol. と日付を伏せると出ない・長い題が切れない
final class MagazineCardRenderTests: XCTestCase {
    typealias M = MagazineCard

    static func photo(width: CGFloat, height: CGFloat, white: Bool = false) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            let colors = (white ? [UIColor.white, UIColor.white]
                                : [UIColor(red: 0.62, green: 0.80, blue: 0.98, alpha: 1), UIColor(red: 0.85, green: 0.78, blue: 0.62, alpha: 1)])
                .map(\.cgColor) as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
            }
        }
    }

    static func render(_ photo: UIImage, _ texts: M.Texts, _ frame: M.Frame, skip: Bool = false)
        -> (Data, [ShareCardProbe.Item]) {
        let probe = ShareCardProbe(skipContent: skip)
        let data = ShareCardProbe.$current.withValue(probe) { MagazineCardRenderer.render(photo: photo, texts: texts, frame: frame) }
        return (data ?? Data(), probe.items)
    }

    /// 余白に置く形: 写真の枠の画素は、字を描いた絵と描かない絵で同じ（写真の上に字も影も無い）
    func testNoTextOrShadowLandsOnThePhoto() throws {
        let photo = Self.photo(width: 1500, height: 1000)
        let texts = M.texts(for: MagazineCardTests.credit())
        for frame in [M.Frame.post(.portrait), .story, .post(.square)] {
            let (full, items) = Self.render(photo, texts, frame)
            let (bare, _) = Self.render(photo, texts, frame, skip: true)
            let a = try XCTUnwrap(ShareCardAuditTests.Bitmap(full)), b = try XCTUnwrap(ShareCardAuditTests.Bitmap(bare))
            // 置き方は描く側と同じ式（題の大きさ・行は記録から）
            let title = items.filter { $0.fontSize >= 60 && $0.text != "12" }
            let head = M.Head(titleSize: title.first?.fontSize ?? 0, titleLines: title.count, hasSub: true)
            let layout = M.layout(aspect: 1.5, in: frame, head: head, hasExif: true)
            XCTAssertFalse(layout.full)
            var changed = 0
            let box = layout.photo.insetBy(dx: 2, dy: 2)
            for y in Int(box.minY)..<Int(box.maxY) where y % 2 == 0 {
                for x in Int(box.minX)..<Int(box.maxX) where x % 2 == 0 {
                    let i = (y * a.width + x) * 4
                    let d = max(abs(Int(a.pixels[i]) - Int(b.pixels[i])), abs(Int(a.pixels[i + 1]) - Int(b.pixels[i + 1])),
                                abs(Int(a.pixels[i + 2]) - Int(b.pixels[i + 2])))
                    if d > 24 { changed += 1 }
                }
            }
            print("measured [magazine-photo] \(frame.height) photo=\(layout.photo) changed=\(changed)")
            XCTAssertEqual(changed, 0, "写真の上に字が描かれた \(frame.height)")
            // 写真の枠の中に記録した字が無い
            for item in items { XCTAssertFalse(item.rect.intersects(box), "\(item.text) \(item.rect)") }
        }
    }

    /// Vol. の番号が無ければ「Vol.」も出さない。日付を伏せると日付は出ない
    func testVolumeAndDateAreLeftOutWhenUnknownOrHidden() {
        let photo = Self.photo(width: 1200, height: 1500)
        let with = Self.render(photo, M.texts(for: MagazineCardTests.credit()), .post(.portrait)).1.map(\.text)
        XCTAssertTrue(with.contains("Vol."), "\(with)")
        XCTAssertTrue(with.contains("12"))
        XCTAssertTrue(with.contains("2026.10.10"))
        let without = Self.render(photo, M.texts(for: MagazineCardTests.credit(showsDate: false, volume: nil)),
                                  .post(.portrait)).1.map(\.text)
        XCTAssertFalse(without.contains("Vol."), "\(without)")
        XCTAssertFalse(without.contains { $0.contains("2026") }, "\(without)")
        XCTAssertTrue(without.contains("JOURNEY PHOTO"))
    }

    /// 長い題が2行に入り、切れない（中身の長さで「…」にしない）
    func testLongTitleFitsOnTwoLines() {
        let photo = Self.photo(width: 1500, height: 1000)
        let title = "朝霧の向こうにゆっくりと浮かび上がる雪吊りの松と霞ヶ池"
        let items = Self.render(photo, M.texts(for: MagazineCardTests.credit(title: title)), .post(.portrait)).1
        let lines = items.filter { $0.fontSize >= M.Title.minimumSize && $0.text != "12" }
        XCTAssertEqual(lines.count, 2, "\(items.map(\.text))")
        XCTAssertEqual(lines.map(\.text).joined(), title)
        XCTAssertFalse(items.contains { $0.truncated }, "\(items.filter(\.truncated).map(\.text))")
        for line in lines { XCTAssertLessThanOrEqual(line.rect.maxX, M.right + 1) }
    }

    /// 全面に敷く形（4:5 の真っ白な写真）でも、字の下の明暗の比が届く（影で）。数は `ShareCardAuditTests` でも見る
    func testFullBleedOnWhiteReachesTheContrast() throws {
        let photo = Self.photo(width: 1080, height: 1350, white: true)
        let texts = M.texts(for: MagazineCardTests.credit())
        let (full, items) = Self.render(photo, texts, .post(.portrait))
        let (bare, _) = Self.render(photo, texts, .post(.portrait), skip: true)
        let a = try XCTUnwrap(ShareCardAuditTests.Bitmap(full)), b = try XCTUnwrap(ShareCardAuditTests.Bitmap(bare))
        XCTAssertFalse(items.contains { $0.text.hasPrefix("Hasselblad") }, "全面のときに撮影の値を出した")
        for item in items {
            var best = 0.0
            let r = item.rect.integral
            for y in max(0, Int(r.minY))..<min(a.height, Int(r.maxY)) {
                for x in max(0, Int(r.minX))..<min(a.width, Int(r.maxX)) {
                    let i = (y * a.width + x) * 4
                    let d = max(abs(Int(a.pixels[i]) - Int(b.pixels[i])), abs(Int(a.pixels[i + 1]) - Int(b.pixels[i + 1])),
                                abs(Int(a.pixels[i + 2]) - Int(b.pixels[i + 2])))
                    guard d >= 48 else { continue }
                    best = max(best, ShareCardSafeArea.luminance(red: Double(b.pixels[i]), green: Double(b.pixels[i + 1]),
                                                                 blue: Double(b.pixels[i + 2])))
                }
            }
            var gray: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            item.color.getRed(&gray, green: &green, blue: &blue, alpha: &alpha)
            let ratio = M.contrast(ink: Double(gray), background: best)
            print("measured [magazine-contrast] \(item.text) size=\(item.fontSize) ratio=\(String(format: "%.2f", ratio))")
            XCTAssertGreaterThanOrEqual(ratio, M.requiredContrast(fontSize: item.fontSize), item.text)
        }
    }
}
#endif
