import XCTest
import CoreLocation
#if !os(Linux)
import UIKit
#endif
@testable import JourneyPhoto

/// 共有の絵「写真の色」（`PhotoColorCard`・2026-11-18 owner 採用）。寸法・色の取り方・字は描く処理を通さず Linux で見る。
/// 描いた画像での確かめ（写真が切れていない・伏せた字が描かれない・長い撮影地）は下の `#if !os(Linux)` の節、
/// 安全域・明暗の比・重なりの画素の点検は Mac の `ShareCardAuditTests`（`testPhotoColor…`）
final class PhotoColorCardTests: XCTestCase {
    typealias C = PhotoColorCard

    static let aspects: [(String, CGFloat)] = [("縦長3:4", 3.0 / 4.0), ("横長3:2", 3.0 / 2.0), ("正方形", 1),
                                               ("パノラマ4:1", 4), ("縦長9:16", 9.0 / 16.0),
                                               ("細い1:10", 0.1), ("細長10:1", 10)]
    static var frames: [(String, C.Frame, CGRect)] {
        [("ストーリー", .story, ShareCardSafeArea.rect(width: 1080, height: 1920, isStory: true)),
         ("投稿4:5", .post(.portrait), ShareCardSafeArea.rect(ratio: .portrait)),
         ("投稿1:1", .post(.square), ShareCardSafeArea.rect(ratio: .square)),
         ("投稿9:16", .post(.story), ShareCardSafeArea.rect(ratio: .story))]
    }

    // MARK: - 寸法

    /// 仕様メモ（模型の `lay`）の写真の枠と字の段
    func testPhotoSizesMatchTheSpec() {
        func box(_ aspect: CGFloat, _ frame: C.Frame) -> [Int] {
            let p = C.place(aspect: aspect, in: frame)
            return [p.photo.width, p.photo.height, p.photo.minY, p.text.minY].map { Int($0.rounded()) }
        }
        XCTAssertEqual(box(3.0 / 4.0, .story), [864, 1152, 188, 1396])
        XCTAssertEqual(box(3.0 / 2.0, .story), [864, 576, 574, 1206])
        XCTAssertEqual(box(1, .story), [864, 864, 430, 1350])
        XCTAssertEqual(box(3.0 / 4.0, .post(.portrait)), [763, 1017, 72, 1145])
        XCTAssertEqual(box(3.0 / 2.0, .post(.portrait)), [864, 576, 289, 921])
        XCTAssertEqual(box(1, .post(.portrait)), [864, 864, 145, 1065])
        XCTAssertEqual(C.Frame.story.textTop, 268.8, accuracy: 0.001)
        XCTAssertEqual(C.Frame.story.textBottom, 1536, accuracy: 0.001)
        XCTAssertEqual(C.Frame.post(.portrait).height, 1350)
        XCTAssertEqual(C.Frame.post(.portrait).textBottom, 1285.2, accuracy: 0.001)
        XCTAssertEqual(C.Frame.post(.square).height, 1080)
        XCTAssertEqual(C.Frame.post(.story), .story)
        // 字の左右は写真の左端と右端
        let p = C.place(aspect: 3.0 / 4.0, in: .post(.portrait))
        XCTAssertEqual(p.text.minX, p.photo.minX, accuracy: 0.001)
        XCTAssertEqual(p.text.width, p.photo.width, accuracy: 0.001)
    }

    /// 写真を切らない（枠の縦横比が写真と同じ）・絵の中・左右の真ん中・写真の上に字の段が無い
    func testPhotoIsNeverCropped() {
        for (frameName, frame, _) in Self.frames {
            for (name, aspect) in Self.aspects {
                let p = C.place(aspect: aspect, in: frame)
                let label = "\(frameName) \(name)"
                XCTAssertEqual(p.photo.width / p.photo.height, aspect, accuracy: 0.0005, label)
                XCTAssertGreaterThanOrEqual(p.photo.minX, 108 - 0.001, label)
                XCTAssertLessThanOrEqual(p.photo.maxX, C.width - 108 + 0.001, label)
                XCTAssertGreaterThanOrEqual(p.photo.minY, frame.photoTop - 0.001, label)
                XCTAssertEqual(p.photo.midX, C.width / 2, accuracy: 0.001, label)
                XCTAssertEqual(p.text.minY, p.photo.maxY + C.gap, accuracy: 0.001, label)
                XCTAssertFalse(p.photo.intersects(p.text), label)
            }
        }
    }

    /// 字の段（撮影地の上端 −6 から段の下端まで）が安全域（`ShareCardSafeArea`）の中。
    /// ストーリーは上 14%・下 20% に掛からない。9:16 の投稿はフィードの 4:5 の切り取りの内側にも入る
    func testTextBlockIsInsideTheSafeArea() {
        for (frameName, frame, safe) in Self.frames {
            for (name, aspect) in Self.aspects {
                let p = C.place(aspect: aspect, in: frame)
                let label = "\(frameName) \(name) text=\(p.text) safe=\(safe)"
                let drawn = CGRect(x: p.text.minX, y: p.text.minY + C.placeY, width: p.text.width,
                                   height: p.text.height - C.placeY)
                XCTAssertTrue(safe.insetBy(dx: -0.001, dy: -0.001).contains(drawn), label)
                XCTAssertLessThanOrEqual(p.text.maxY, frame.textBottom + 0.001, label)
                XCTAssertGreaterThanOrEqual(p.text.minY + C.placeY, frame.textTop - 0.001, label)
            }
        }
        // ストーリーの線はインスタの上 14%・下 20%
        XCTAssertEqual(C.Frame.story.textTop, 1920 * 0.14, accuracy: 0.001)
        XCTAssertEqual(C.Frame.story.textBottom, 1920 * 0.80, accuracy: 0.001)
    }

    /// 細い縦長の写真でも、字の段は 600 の幅を持つ（撮影地が入る）
    func testNarrowPhotoKeepsATextColumn() {
        let p = C.place(aspect: 0.1, in: .story)
        XCTAssertEqual(p.text.width, C.textMinWidth, accuracy: 0.001)
        XCTAssertEqual(p.text.midX, C.width / 2, accuracy: 0.001)
    }

    /// 字の大きさ: 撮影地 56（縮めても 36）、下の段 34（縮めても 33＝インスタで 12pt）。どれも 33px 以上
    func testTextSizesFollowTheSpec() {
        XCTAssertEqual(C.placeSize, 56)
        XCTAssertEqual(C.placeMinimumSize, 36)
        XCTAssertEqual(C.rowSize, 34)
        XCTAssertEqual(C.rowMinimumSize, 33)
        XCTAssertGreaterThanOrEqual(min(C.placeMinimumSize, C.rowMinimumSize), 1080.0 / 393.0 * 12, "12pt より小さい字がある")
        XCTAssertEqual(C.placeY, -6)
        XCTAssertEqual(C.rowY, 86)
    }

    // MARK: - 色

    static func solid(_ c: C.RGB, count: Int = 4096) -> [C.RGB] { [C.RGB](repeating: c, count: count) }

    /// 試す写真の画素（白っぽい・黒っぽい・単色・灰色・2色・夕焼けのような勾配・緑の森）
    static var samples: [(String, [C.RGB])] {
        var gradient: [C.RGB] = []
        for i in 0..<4096 {
            let t = Double(i) / 4095
            gradient.append(C.RGB(250 - 60 * t, 160 - 120 * t, 60 + 100 * t))
        }
        var forest: [C.RGB] = []
        for i in 0..<4096 {
            switch i % 10 {
            case 0..<6: forest.append(C.RGB(40, 90 + Double(i % 7) * 5, 50))
            case 6..<9: forest.append(C.RGB(200, 220, 235))
            default: forest.append(C.RGB(20, 25, 20))
            }
        }
        return [
            ("白", solid(C.RGB(255, 255, 255))),
            ("白っぽい", solid(C.RGB(246, 244, 238), count: 3000) + solid(C.RGB(230, 236, 245), count: 1096)),
            ("黒", solid(C.RGB(0, 0, 0))),
            ("黒っぽい", solid(C.RGB(12, 14, 22), count: 3500) + solid(C.RGB(60, 40, 30), count: 596)),
            ("灰色", solid(C.RGB(128, 128, 128))),
            ("赤", solid(C.RGB(255, 0, 0))),
            ("黄", solid(C.RGB(255, 255, 0))),
            ("緑", solid(C.RGB(0, 255, 0))),
            ("水色", solid(C.RGB(0, 255, 255))),
            ("青", solid(C.RGB(0, 0, 255))),
            ("桃", solid(C.RGB(255, 0, 255))),
            ("夕焼け", gradient),
            ("森", forest),
        ]
    }

    /// 字と地の明暗の比が 7:1 以上（どの写真でも）。地は淡い色（L 0.9 前後）、字は濃い色
    func testInkAndGroundContrastIsAtLeastSeven() {
        for (name, pixels) in Self.samples {
            let tone = C.tone(pixels: pixels)
            XCTAssertGreaterThanOrEqual(tone.contrast, 7, "\(name) ground=\(tone.ground) ink=\(tone.ink)")
            XCTAssertEqual(C.hsl(tone.ground).l, 0.9, accuracy: 0.01, name)
            XCTAssertLessThanOrEqual(C.hsl(tone.ink).l, 0.17 + 0.005, name)
            XCTAssertLessThanOrEqual(C.hsl(tone.ground).s, 0.3 + 0.02, name)
        }
    }

    /// 同じ写真なら毎回同じ色（乱数を使わない）
    func testSamePhotoGivesTheSameTone() {
        for (name, pixels) in Self.samples {
            XCTAssertEqual(C.tone(pixels: pixels), C.tone(pixels: pixels), name)
        }
    }

    /// 地はいちばん多い色の色相、字は暗くて色のある色の色相（模型の `makeTone`）
    func testGroundAndInkTakeTheirHuesFromThePhoto() {
        // 7割が空色、3割が暗い赤茶
        let pixels = Self.solid(C.RGB(120, 170, 230), count: 2900) + Self.solid(C.RGB(110, 40, 20), count: 1196)
        let tone = C.tone(pixels: pixels)
        XCTAssertEqual(C.hsl(tone.ground).h, C.hsl(C.RGB(120, 170, 230)).h, accuracy: 0.01, "地が空色の色相でない")
        XCTAssertEqual(C.hsl(tone.ink).h, C.hsl(C.RGB(110, 40, 20)).h, accuracy: 0.01, "字が赤茶の色相でない")
        let palette = C.palette(pixels)
        XCTAssertEqual(palette.map(\.share).reduce(0, +), 1, accuracy: 0.0001)
        XCTAssertTrue(palette.allSatisfy { $0.share > 0.01 })
    }

    /// 白黒・灰色の写真の字は無彩色（写真に無い赤を出さない）
    func testAchromaticPhotoGetsAchromaticInk() {
        for name in ["白", "黒", "灰色"] {
            let tone = C.tone(pixels: Self.samples.first { $0.0 == name }!.1)
            XCTAssertEqual(tone.ink.red, tone.ink.green, name)
            XCTAssertEqual(tone.ink.green, tone.ink.blue, name)
            XCTAssertEqual(tone.ground.red, tone.ground.blue, name)
        }
    }

    /// 無彩色はクロマ（RGB の最大−最小）で見る: ほぼ黒の RGB(30,27,25) は無彩色、色のある暗い写真は無彩色にしない
    func testAchromaticIsJudgedByChroma() {
        let nearBlack = C.tone(pixels: Self.solid(C.RGB(30, 27, 25)))
        XCTAssertEqual(nearBlack.ink.red, nearBlack.ink.blue, "ほぼ黒の写真の字に色が付いた: \(nearBlack.ink)")
        XCTAssertEqual(nearBlack.ground.red, nearBlack.ground.blue, "ほぼ黒の写真の地に色が付いた: \(nearBlack.ground)")
        // 夜の青い写真・暗い赤茶の写真（暗いが色がある）
        for (name, c) in [("夜の青", C.RGB(20, 30, 70)), ("暗い赤茶", C.RGB(70, 30, 20))] {
            let tone = C.tone(pixels: Self.solid(c))
            XCTAssertGreaterThan(C.chroma(tone.ink), 12, "\(name) の字が無彩色になった: \(tone.ink)")
            XCTAssertEqual(C.hsl(tone.ink).h, C.hsl(c).h, accuracy: 0.02, name)
            XCTAssertGreaterThanOrEqual(tone.contrast, 7, name)
        }
    }

    /// 字の元の色は、暗い影より写真の色を選ぶ（クロマ ×（1 − L））。半分が茶色の影、半分が空色の写真で、字は空色の色相
    func testInkPrefersPhotoColorOverDarkShadow() {
        let shadow = C.RGB(35, 25, 20), sky = C.RGB(120, 140, 170)
        XCTAssertGreaterThan(C.hsl(shadow).s * (1 - C.hsl(shadow).l), C.hsl(sky).s * (1 - C.hsl(sky).l),
                             "彩度の点数で影が勝つ例になっていない")
        let tone = C.tone(pixels: Self.solid(shadow, count: 2048) + Self.solid(sky, count: 2048))
        XCTAssertEqual(C.hsl(tone.ink).h, C.hsl(sky).h, accuracy: 0.02, "字が影の色相になった: \(tone.ink)")
    }

    /// 明暗の比が足りなければ字を暗くする（はじめの L が明るすぎて 7 に届かない色でも 7 以上にする）
    func testInkIsDarkenedUntilSevenToOne() {
        let ground = C.tone(pixels: Self.solid(C.RGB(0, 255, 0))).ground
        let start = C.rgb(h: 1.0 / 3, s: 0.5, l: 0.4).rounded
        XCTAssertLessThan(ShareCardSafeArea.contrast(start.luminance, ground.luminance), 7, "はじめの字で足りてしまい、試験にならない")
        let ink = C.ink(h: 1.0 / 3, s: 0.5, l: 0.4, on: ground)
        XCTAssertGreaterThanOrEqual(ShareCardSafeArea.contrast(ink.luminance, ground.luminance), 7)
        XCTAssertEqual(C.hsl(ink).h, 1.0 / 3, accuracy: 0.02, "色相が変わった")
    }

    func testHSLRoundTrip() {
        for c in [C.RGB(255, 0, 0), C.RGB(12, 200, 90), C.RGB(30, 30, 200), C.RGB(240, 230, 210)] {
            let (h, s, l) = C.hsl(c)
            let back = C.rgb(h: h, s: s, l: l)
            XCTAssertEqual(back.red, c.red, accuracy: 0.5)
            XCTAssertEqual(back.green, c.green, accuracy: 0.5)
            XCTAssertEqual(back.blue, c.blue, accuracy: 0.5)
        }
    }

    // MARK: - 字

    static let day = TripBook.utcCalendar.date(from: DateComponents(year: 2026, month: 10, day: 10))!
    static let kenrokuen = "兼六園, 兼六町, 金沢市, 石川県, 920-0936, 日本"

    static func credit(location: String?, takenDay: Date?) -> SignatureShareCardRenderer.Credit {
        SignatureShareCardRenderer.Credit(
            name: "旅灯", username: "tabi_akari", location: location.map(LocationMatch.shareCardDisplay), coords: nil,
            camera: nil, lens: nil, exposure: nil, aperture: nil, iso: nil,
            verified: false, proStyle: nil, early: false, badge: nil,
            place: LocationMatch.shareCardPlace(location), takenDay: takenDay)
    }

    /// 投稿: 小さい単位（市区町村・海外の地名）を大きく、大きい単位（県・国）を下の段に。観光スポットの名前は出さない
    func testPostTexts() {
        XCTAssertEqual(C.texts(for: Self.credit(location: Self.kenrokuen, takenDay: Self.day)),
                       C.Texts(place: "金沢市", region: "石川県", date: "2026.10.10"))
        XCTAssertEqual(C.texts(for: Self.credit(location: "Saint-Germain-en-Laye, Île-de-France, France", takenDay: nil)),
                       C.Texts(place: "Saint-Germain-en-Laye", region: "France", date: nil))
        XCTAssertEqual(C.texts(for: Self.credit(location: "山中湖", takenDay: Self.day)),
                       C.Texts(place: "山中湖", region: nil, date: "2026.10.10"))
        XCTAssertEqual(C.texts(for: Self.credit(location: nil, takenDay: nil)), C.Texts(place: nil, region: nil, date: nil))
        let texts = C.texts(for: Self.credit(location: Self.kenrokuen, takenDay: Self.day))
        XCTAssertFalse([texts.place, texts.region].compactMap { $0 }.contains { $0.contains("兼六園") }, "スポットの名前が出た")
    }

    static func facts(_ location: String? = kenrokuen, day: Date? = day) -> TravelStory.Facts {
        TravelStory.Facts(location: location, takenDay: day, name: "旅灯")
    }

    static func choice(place: TravelStory.PlaceLevel, date: TravelStory.DateLevel) -> TravelStory.Choice {
        var choice = TravelStory.Choice()
        choice.kind = .photoColor
        choice.placeLevel = place
        choice.dateLevel = date
        return choice
    }

    /// ストーリー: 選んだ細かさを守る。場所・日付を「出さない」にしたら、それぞれ出さない
    func testStoryTextsKeepTheChosenDetail() {
        let now = TripBook.utcCalendar.date(from: DateComponents(year: 2026, month: 11, day: 18))!
        func texts(_ place: TravelStory.PlaceLevel, _ date: TravelStory.DateLevel, _ location: String? = PhotoColorCardTests.kenrokuen) -> C.Texts {
            TravelStory.photoColor(Self.facts(location), choice: Self.choice(place: place, date: date), now: now,
                                   timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        }
        XCTAssertEqual(texts(.city, .date), C.Texts(place: "金沢市", region: "石川県", date: "2026.10.10"))
        XCTAssertEqual(texts(.prefecture, .date), C.Texts(place: "石川県", region: nil, date: "2026.10.10"))
        XCTAssertEqual(texts(.none, .date), C.Texts(place: nil, region: nil, date: "2026.10.10"))
        XCTAssertEqual(texts(.city, .none), C.Texts(place: "金沢市", region: "石川県", date: nil))
        XCTAssertEqual(texts(.none, .none), C.Texts(place: nil, region: nil, date: nil))
        // 県までで、県と分からない1つの欠片（「山中湖」）は出さない（`TravelStory.placeText`）
        XCTAssertEqual(texts(.prefecture, .none, "山中湖"), C.Texts(place: nil, region: nil, date: nil))
        // 撮った日の無い写真は日付を出さない
        let noDay = TravelStory.photoColor(Self.facts(day: nil), choice: Self.choice(place: .city, date: .date), now: now)
        XCTAssertNil(noDay.date)
        // 場所を出さないと、どの字にも地名が残らない
        let hidden = texts(.none, .date)
        for name in ["兼六", "金沢", "石川"] {
            XCTAssertFalse([hidden.place, hidden.region, hidden.date].compactMap { $0 }.contains { $0.contains(name) })
        }
    }

    /// 撮影地が入らないときの代わり: 一つ上の単位を大きく、下の段の左は空ける
    func testWidenedTexts() {
        let texts = C.Texts(place: "Llanfairpwllgwyngyllgogerychwyrndrobwllllantysiliogogogoch", region: "United Kingdom",
                            date: "2026.10.10")
        XCTAssertEqual(texts.widened, C.Texts(place: "United Kingdom", region: nil, date: "2026.10.10"))
        XCTAssertNil(C.Texts(place: "金沢市", region: nil, date: nil).widened)
    }

    /// 「・」「·」で区切らない（県と市は別の行・日付は位置で分ける）
    func testNoMiddleDots() {
        let all = [C.texts(for: Self.credit(location: Self.kenrokuen, takenDay: Self.day)),
                   TravelStory.photoColor(Self.facts(), choice: Self.choice(place: .city, date: .date))]
        for texts in all {
            for value in [texts.place, texts.region, texts.date].compactMap({ $0 }) {
                XCTAssertFalse(value.contains("・") || value.contains("·"), value)
            }
        }
    }

    // MARK: - 並び

    /// 投稿の型の並びのいちばん後ろ・ストーリーの型のいちばん後ろに足した（前からの並びは変えない）。ステッカーにはしない
    func testAddedAtTheEnd() {
        XCTAssertEqual(ShareCardStyleChoice.order.last, .photoColor)
        XCTAssertEqual(ShareCardStyleChoice.title(.photoColor), L("写真の色", "Photo color"))
        XCTAssertEqual(TravelStory.Kind.allCases.last, .photoColor)
        XCTAssertEqual(TravelStory.Kind.photoColor.name, L("写真の色", "Photo color"))
        XCTAssertFalse(TravelStory.Kind.photoColor.supportsSticker)
        var choice = Self.choice(place: .city, date: .date)
        choice.mode = .sticker
        XCTAssertEqual(choice.effectiveMode, .photo)
    }

    #if !os(Linux)
    // MARK: - 描いた画像（Mac）

    /// 単色・4辺に色の付いた写真（UIImage）
    static func image(_ size: CGSize, fill: UIColor, edges: Bool = false) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            fill.setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: size))
            guard edges else { return }
            let e: CGFloat = 12
            UIColor.red.setFill(); context.cgContext.fill(CGRect(x: 0, y: 0, width: e, height: size.height))
            UIColor.blue.setFill(); context.cgContext.fill(CGRect(x: size.width - e, y: 0, width: e, height: size.height))
            UIColor.green.setFill(); context.cgContext.fill(CGRect(x: e, y: 0, width: size.width - 2 * e, height: e))
            UIColor.yellow.setFill()
            context.cgContext.fill(CGRect(x: e, y: size.height - e, width: size.width - 2 * e, height: e))
        }
    }

    static func pixel(_ image: UIImage, _ x: Int, _ y: Int) -> (Int, Int, Int) {
        let cg = image.cgImage!
        var buffer = [UInt8](repeating: 0, count: 4)
        buffer.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.draw(cg, in: CGRect(x: -x, y: y - cg.height + 1, width: cg.width, height: cg.height))
        }
        return (Int(buffer[0]), Int(buffer[1]), Int(buffer[2]))
    }

    /// 写真を切っていない: 4辺の色の帯（左赤・右青・上緑・下黄）が、置いた枠の内側の縁にそのまま見える
    func testRenderedPhotoIsNotCropped() throws {
        for (name, size) in [("縦長", CGSize(width: 600, height: 800)), ("横長", CGSize(width: 900, height: 600)),
                             ("正方形", CGSize(width: 700, height: 700))] {
            for (frameName, frame) in [("ストーリー", C.Frame.story), ("投稿", C.Frame.post(.portrait))] {
                let photo = Self.image(size, fill: .gray, edges: true)
                let data = PhotoColorCardRenderer.render(photo: photo, texts: C.Texts(place: nil, region: nil, date: nil),
                                                         frame: frame)
                let out = try XCTUnwrap(UIImage(data: data))
                let p = C.place(aspect: size.width / size.height, in: frame).photo
                let label = "\(frameName) \(name)"
                XCTAssertEqual(Int(out.size.height), Int(frame.height), label)
                func near(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Bool {
                    abs(a.0 - b.0) < 40 && abs(a.1 - b.1) < 40 && abs(a.2 - b.2) < 40
                }
                let midX = Int(p.midX), midY = Int(p.midY)
                XCTAssertTrue(near(Self.pixel(out, Int(p.minX) + 3, midY), (255, 0, 0)), "\(label) 左が切れた")
                XCTAssertTrue(near(Self.pixel(out, Int(p.maxX) - 4, midY), (0, 0, 255)), "\(label) 右が切れた")
                XCTAssertTrue(near(Self.pixel(out, midX, Int(p.minY) + 3), (0, 255, 0)), "\(label) 上が切れた")
                XCTAssertTrue(near(Self.pixel(out, midX, Int(p.maxY) - 4), (255, 255, 0)), "\(label) 下が切れた")
                // 写真の外は地の色（写真がはみ出していない）
                let ground = PhotoColorCardRenderer.tone(photo).ground
                let g = (Int(ground.red), Int(ground.green), Int(ground.blue))
                XCTAssertTrue(near(Self.pixel(out, Int(p.minX) - 6, midY), g), "\(label) 左の外が地でない")
                XCTAssertTrue(near(Self.pixel(out, midX, Int(p.minY) - 6), g), "\(label) 上の外が地でない")
            }
        }
    }

    /// 描いた画像の写真から取った色でも 7:1 以上（白っぽい・黒っぽい・単色の写真）
    func testRenderedToneContrastOnPhotos() {
        let colors: [(String, UIColor)] = [("白", .white), ("黒", .black), ("灰", .gray), ("赤", .red), ("黄", .yellow),
                                           ("緑", .green), ("青", .blue), ("空", UIColor(red: 0.62, green: 0.8, blue: 0.98, alpha: 1))]
        for (name, color) in colors {
            let tone = PhotoColorCardRenderer.tone(Self.image(CGSize(width: 300, height: 200), fill: color))
            XCTAssertGreaterThanOrEqual(tone.contrast, 7, "\(name) \(tone)")
            XCTAssertEqual(tone, PhotoColorCardRenderer.tone(Self.image(CGSize(width: 300, height: 200), fill: color)),
                           "\(name) 同じ写真で色が変わった")
        }
    }

    /// 描いた字を点検の記録（`ShareCardProbe`）で取る
    static func drawnTexts(_ render: () -> Void) -> [ShareCardProbe.Item] {
        let probe = ShareCardProbe(skipContent: false)
        ShareCardProbe.$current.withValue(probe) { render() }
        return probe.items.filter { $0.kind == .text }
    }

    static func storyItems(place: TravelStory.PlaceLevel, date: TravelStory.DateLevel) -> [ShareCardProbe.Item] {
        let photo = image(CGSize(width: 600, height: 800), fill: .orange).jpegData(compressionQuality: 0.9)!
        return drawnTexts {
            _ = TravelStoryRenderer.render([photo], facts: facts(), choice: choice(place: place, date: date))
        }
    }

    /// 場所・日付を「出さない」にしたら、描いた絵にそれぞれ出ない
    func testHiddenPlaceAndDateAreNotDrawn() {
        let all = Self.storyItems(place: .city, date: .date).map(\.text)
        XCTAssertEqual(Set(all), ["金沢市", "石川県", "2026.10.10"])
        XCTAssertEqual(Self.storyItems(place: .none, date: .date).map(\.text), ["2026.10.10"])
        XCTAssertEqual(Set(Self.storyItems(place: .city, date: .none).map(\.text)), ["金沢市", "石川県"])
        XCTAssertTrue(Self.storyItems(place: .none, date: .none).isEmpty)
    }

    /// 字は字の段の中（写真の上に字を置かない）・33px 以上・字の色と地の明暗の比 7:1 以上・県と市と日付が重ならない
    func testDrawnTextsStayBelowThePhoto() {
        let photo = Self.image(CGSize(width: 600, height: 800), fill: .orange)
        let placement = C.place(aspect: 0.75, in: .story)
        let items = Self.drawnTexts {
            _ = PhotoColorCardRenderer.render(photo: photo, texts: C.Texts(place: "金沢市", region: "石川県", date: "2026.10.10"),
                                              frame: .story)
        }
        let ground = PhotoColorCardRenderer.tone(photo).ground
        XCTAssertEqual(items.count, 3)
        for item in items {
            XCTAssertGreaterThanOrEqual(item.rect.minY, placement.photo.maxY, "\(item.text) が写真に掛かる")
            XCTAssertGreaterThanOrEqual(item.fontSize, 33, item.text)
            XCTAssertFalse(item.truncated, item.text)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            item.color.getRed(&r, green: &g, blue: &b, alpha: &a)
            let ink = ShareCardSafeArea.luminance(red: Double(r * 255), green: Double(g * 255), blue: Double(b * 255))
            XCTAssertGreaterThanOrEqual(ShareCardSafeArea.contrast(ink, ground.luminance), 7, item.text)
        }
        let region = items.first { $0.text == "石川県" }!, date = items.first { $0.text == "2026.10.10" }!
        XCTAssertLessThanOrEqual(region.rect.maxX + C.rowGap, date.rect.minX + 0.5)
        XCTAssertEqual(date.rect.maxX, placement.text.maxX, accuracy: 1, "日付の右端が写真の右端にそろっていない")
    }

    /// 長い撮影地: 36px まで縮め、それでも入らなければ一つ上の単位を大きく出す（切り詰めない）
    func testLongPlaceFits() {
        let photo = Self.image(CGSize(width: 600, height: 800), fill: .orange)
        for frame in [C.Frame.story, .post(.portrait)] {
            let long = Self.drawnTexts {
                _ = PhotoColorCardRenderer.render(
                    photo: photo,
                    texts: C.Texts(place: "Llanfairpwllgwyngyllgogerychwyrndrobwllllantysiliogogogoch",
                                   region: "United Kingdom", date: "2026.10.10"),
                    frame: frame)
            }
            XCTAssertEqual(Set(long.map(\.text)), ["United Kingdom", "2026.10.10"], "\(frame.height)")
            XCTAssertTrue(long.allSatisfy { !$0.truncated && $0.fontSize >= 33 })
            let japanese = Self.drawnTexts {
                _ = PhotoColorCardRenderer.render(
                    photo: photo, texts: C.Texts(place: "東牟婁郡那智勝浦町", region: "和歌山県", date: "2026.10.10"),
                    frame: frame)
            }
            let place = japanese.first { $0.text == "東牟婁郡那智勝浦町" }
            XCTAssertNotNil(place, "日本の長い地名が代わりに替わった")
            XCTAssertFalse(place?.truncated ?? true)
            XCTAssertGreaterThanOrEqual(place?.fontSize ?? 0, 36)
        }
    }
    #endif
}
