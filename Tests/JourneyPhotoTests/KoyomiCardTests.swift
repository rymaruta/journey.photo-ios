import XCTest
import CoreLocation
@testable import JourneyPhoto

/// 共有の絵「暦（差し色）」の寸法と字（`KoyomiCard`・2026-11-18 owner「暦 差し色採用」）。描く処理を通さず Linux で見る。
/// 書き出した画像の画素での点検（安全域・明暗の比・重なり）は Mac の `ShareCardAuditTests`（`testKoyomi…`）
final class KoyomiCardTests: XCTestCase {
    typealias K = KoyomiCard

    static let aspects: [(String, CGFloat)] = [("縦長3:4", 3.0 / 4.0), ("横長3:2", 3.0 / 2.0), ("正方形", 1),
                                               ("パノラマ4:1", 4), ("縦長9:16", 9.0 / 16.0)]
    static var frames: [(String, K.Frame)] {
        [("ストーリー", .story), ("投稿4:5", .post(.portrait)), ("投稿1:1", .post(.square)), ("投稿9:16", .post(.story))]
    }

    /// 模型（仕様の「結果の例」）の写真の枠
    func testPhotoSizesMatchTheMockup() {
        func size(_ aspect: CGFloat, _ frame: K.Frame) -> (Int, Int) {
            let p = K.place(aspect: aspect, in: frame).photo
            return (Int(p.width.rounded()), Int(p.height.rounded()))
        }
        XCTAssert(size(3.0 / 4.0, .story) == (849, 1132))
        XCTAssert(size(3.0 / 2.0, .story) == (1080, 720))
        XCTAssert(size(1, .story) == (1080, 1080))
        XCTAssert(size(3.0 / 4.0, .post(.portrait)) == (661, 881))
        XCTAssert(size(3.0 / 2.0, .post(.portrait)) == (1080, 720))
        XCTAssert(size(1, .post(.portrait)) == (881, 881))
        XCTAssertEqual(K.Frame.story.textBottom, 1536, accuracy: 0.001)
        XCTAssertEqual(K.Frame.post(.portrait).textBottom, 1285.2, accuracy: 0.001)
        XCTAssertEqual(K.Frame.post(.portrait).textTop, 64.8, accuracy: 0.001)
        XCTAssertEqual(K.Frame.post(.square).height, 1080)
        XCTAssertEqual(K.Frame.post(.story), .story)
    }

    /// 写真を切らない（枠の縦横比が写真と同じ）・絵の中・左右の真ん中・字の段と重ならない
    func testPhotoIsNeverCropped() {
        for (frameName, frame) in Self.frames {
            for (name, aspect) in Self.aspects {
                let p = K.place(aspect: aspect, in: frame)
                let label = "\(frameName) \(name)"
                XCTAssertEqual(p.photo.width / p.photo.height, aspect, accuracy: 0.0005, label)
                XCTAssertGreaterThanOrEqual(p.photo.minX, -0.001, label)
                XCTAssertLessThanOrEqual(p.photo.maxX, K.width + 0.001, label)
                XCTAssertGreaterThanOrEqual(p.photo.minY, -0.001, label)
                XCTAssertEqual(p.photo.midX, K.width / 2, accuracy: 0.001, label)
                XCTAssertEqual(p.blockTop, p.photo.maxY + K.gap, accuracy: 0.001, label)
            }
        }
    }

    /// 字の段（左 65〜右 1008、上端〜下端）が安全域（`ShareCardSafeArea`）の中。9:16 は投稿のフィードの 4:5 の切り取りの内側にも入る
    func testTextBlockIsInsideTheSafeArea() {
        let checks: [(String, K.Frame, CGRect)] = [
            ("ストーリー", .story, ShareCardSafeArea.rect(width: 1080, height: 1920, isStory: true)),
            ("投稿4:5", .post(.portrait), ShareCardSafeArea.rect(ratio: .portrait)),
            ("投稿1:1", .post(.square), ShareCardSafeArea.rect(ratio: .square)),
            ("投稿9:16", .post(.story), ShareCardSafeArea.rect(ratio: .story)),
        ]
        for (frameName, frame, safe) in checks {
            for (name, aspect) in Self.aspects {
                let p = K.place(aspect: aspect, in: frame)
                let block = CGRect(x: K.headingX, y: p.blockTop + K.headingY,
                                   width: K.right - K.headingX, height: K.blockHeight - K.headingY)
                let label = "\(frameName) \(name) \(block)"
                XCTAssertTrue(ShareCardSafeArea.overflow(of: block, in: safe).isInside, label)
                XCTAssertLessThanOrEqual(p.blockTop + K.blockHeight, frame.textBottom + 0.001, label)
                XCTAssertGreaterThanOrEqual(p.blockTop, frame.textTop - 0.001, label)
            }
        }
        // 模型の 64 は安全域（64.8）の外なので 65 にした
        XCTAssertGreaterThanOrEqual(K.headingX, ShareCardSafeArea.rect(ratio: .portrait).minX)
        XCTAssertLessThanOrEqual(K.right, ShareCardSafeArea.rect(ratio: .portrait).maxX)
        // 3列は幅 300 で、隣の列と重ならず右端 1008 を越えない
        for (index, x) in K.columnX.enumerated() {
            XCTAssertLessThanOrEqual(x + K.columnWidth, index + 1 < K.columnX.count ? K.columnX[index + 1] : K.right)
        }
        // 字の大きさ（インスタで 1080px = 393pt）。眉 30px は 11pt 以上、本文 34px は 12pt 以上（板の最小）
        XCTAssertGreaterThanOrEqual(K.eyebrowSize * 393 / 1080, 10.9)
        XCTAssertGreaterThanOrEqual(K.meaningSize * 393 / 1080, 12)
        XCTAssertGreaterThanOrEqual(K.valueMinimumSize * 393 / 1080, 10.9)
    }

    /// 地の色（額装と同じ暗い色）と白の字は 7:1 以上。薄めた白（英字 72%・眉 65%・意味 75%）も 4.5:1 以上
    func testGroundContrastWithWhiteText() {
        let photos: [(Double, Double, Double)] = [(255, 255, 255), (0, 0, 0), (250, 220, 40), (30, 90, 220),
                                                  (200, 30, 40), (120, 160, 90), (128, 128, 128)]
        for photo in photos {
            let ground = ShareCardMap.MatColor.color(red: photo.0, green: photo.1, blue: photo.2)
            XCTAssertGreaterThanOrEqual(K.contrast(ground: ground, whiteAlpha: 1), 7, "\(photo)")
            for alpha in [K.Ink.latin, K.Ink.eyebrow, K.Ink.meaning] {
                XCTAssertGreaterThanOrEqual(K.contrast(ground: ground, whiteAlpha: alpha),
                                            ShareCardSafeArea.minimumTextContrast, "\(photo) \(alpha)")
            }
        }
    }

    // MARK: - 字

    static let october10 = SolarTermTests.day(2026, 10, 10)

    func testNorthernPhotoShowsTheSolarTerm() {
        let t = K.texts(takenDay: Self.october10, showsDate: true, latitude: 36.56, place: "兼六園", country: nil)
        XCTAssertEqual(t.heading, "寒露")
        XCTAssertTrue(t.isSolarTerm)
        XCTAssertEqual(t.latin, "KANRO")
        XCTAssertEqual(t.columns.map(\.key), ["DATE", "PLACE", "SOLAR TERM"])
        XCTAssertEqual(t.columns.map(\.value), ["2026.10.10", "兼六園", "17 / 24"])
        XCTAssertEqual(t.columns.map(\.serif), [false, true, false])
        XCTAssertEqual(t.meaning, SolarTerm.all[16].meaning)
        // 北半球の海外（パリ）はそのまま節気
        let paris = K.texts(takenDay: Self.october10, showsDate: true, latitude: 48.85, place: "Paris", country: "France")
        XCTAssertEqual(paris.heading, "寒露")
    }

    /// 南半球では節気を出さない（座標の緯度、座標が無ければ撮影地の国）。名前の所に撮影地、英字は国名、3列目は COUNTRY
    func testSouthernHemisphereNeverShowsASolarTerm() {
        let byLatitude = K.texts(takenDay: Self.october10, showsDate: true, latitude: -33.86, place: "シドニー",
                                 country: "オーストラリア")
        XCTAssertFalse(byLatitude.isSolarTerm)
        XCTAssertEqual(byLatitude.heading, "シドニー")
        XCTAssertEqual(byLatitude.latin, "AUSTRALIA")
        XCTAssertEqual(byLatitude.columns.map(\.key), ["DATE", "PLACE", "COUNTRY"])
        XCTAssertEqual(byLatitude.columns.last?.value, "オーストラリア")
        XCTAssertNil(byLatitude.meaning)
        let byCountry = K.texts(takenDay: Self.october10, showsDate: true, latitude: nil, place: "Queenstown",
                                country: "New Zealand")
        XCTAssertFalse(byCountry.isSolarTerm)
        XCTAssertEqual(byCountry.latin, "NEW ZEALAND")
        // 緯度が先（南半球の国の名でも、座標が北なら節気）
        XCTAssertTrue(K.texts(takenDay: Self.october10, showsDate: true, latitude: 10, place: "x", country: "ブラジル").isSolarTerm)
        // 節気の名前がどの字にも出ない
        for t in [byLatitude, byCountry] {
            let all = ([t.heading, t.latin ?? "", t.meaning ?? ""] + t.columns.flatMap { [$0.key, $0.value] }).joined()
            for term in SolarTerm.all { XCTAssertFalse(all.contains(term.name), term.name) }
            XCTAssertFalse(all.contains("SOLAR TERM"))
        }
    }

    /// 撮った日が無い・日付を出さないなら、節気も出さない（節気は日付の手がかり）
    func testNoDateMeansNoSolarTerm() {
        let none = K.texts(takenDay: nil, showsDate: true, latitude: 35, place: "京都市", country: nil)
        XCTAssertFalse(none.isSolarTerm)
        XCTAssertEqual(none.heading, "京都市")
        XCTAssertEqual(none.columns.map(\.key), ["PLACE"])
        let hidden = K.texts(takenDay: Self.october10, showsDate: false, latitude: 35, place: "京都市", country: nil)
        XCTAssertFalse(hidden.isSolarTerm)
        XCTAssertFalse(hidden.columns.contains { $0.key == "DATE" })
        let nothing = K.texts(takenDay: nil, showsDate: true, latitude: nil, place: nil, country: nil)
        XCTAssertEqual(nothing.heading, TravelStory.onTheRoad)
        XCTAssertTrue(nothing.columns.isEmpty)
    }

    /// 字に「・」「·」を使わない・「撮りどき」を使わない
    func testNoMiddleDots() {
        let samples = [
            K.texts(takenDay: Self.october10, showsDate: true, latitude: 35, place: "兼六園", country: nil),
            K.texts(takenDay: Self.october10, showsDate: true, latitude: -33, place: "シドニー", country: "オーストラリア"),
        ]
        for t in samples {
            let all = ([t.heading, t.latin ?? "", t.meaning ?? ""] + t.columns.flatMap { [$0.key, $0.value] }).joined()
            XCTAssertFalse(all.contains("・"))
            XCTAssertFalse(all.contains("·"))
            XCTAssertFalse(all.contains("撮りどき"))
        }
    }

    func testCountryOfLocation() {
        XCTAssertEqual(K.country(of: "Sydney, New South Wales, Australia"), "Australia")
        XCTAssertEqual(K.country(of: "シドニー, ニューサウスウェールズ州, オーストラリア"), "オーストラリア")
        XCTAssertNil(K.country(of: "山中湖村, 山梨県, 日本"))
        XCTAssertNil(K.country(of: "京都府（京都市東山区）"))
        XCTAssertNil(K.country(of: "山中湖"))
        XCTAssertEqual(K.country(of: "オーストラリア"), "オーストラリア")
        XCTAssertTrue(K.isSouthern(latitude: nil, country: "南アフリカ共和国"))
        XCTAssertTrue(K.isSouthern(latitude: nil, country: "australia"))
        XCTAssertFalse(K.isSouthern(latitude: nil, country: "France"))
        XCTAssertFalse(K.isSouthern(latitude: nil, country: nil))
    }

    /// 投稿の共有カードの字（撮影地の列は小さい単位・南半球は概略の緯度で見分ける）
    func testCreditTexts() {
        var credit = SignatureShareCardRenderer.Credit(
            name: "旅灯", username: "tabi_akari", location: "石川県（金沢市）",
            coords: CLLocationCoordinate2D(latitude: 36.5, longitude: 136.5),
            camera: nil, lens: nil, exposure: nil, aperture: nil, iso: nil,
            verified: false, proStyle: nil, early: false, badge: nil)
        credit.takenDay = Self.october10
        let t = K.texts(for: credit)
        XCTAssertEqual(t.heading, "寒露")
        XCTAssertEqual(t.columns.map(\.value), ["2026.10.10", "金沢市", "17 / 24"])
        var sydney = SignatureShareCardRenderer.Credit(
            name: "Emily", username: nil, location: "Sydney, New South Wales, Australia",
            coords: SignatureShareCardRenderer.approximateShareCoordinate(Photo.Coords(lat: -33.86, lng: 151.2)),
            camera: nil, lens: nil, exposure: nil, aperture: nil, iso: nil,
            verified: false, proStyle: nil, early: false, badge: nil)
        sydney.takenDay = Self.october10
        // 海外の小さい地名には、入らないときの代わりに国を持たせる（日本は県）
        var paris = SignatureShareCardRenderer.Credit(
            name: "Emily", username: nil, location: "Saint-Germain-en-Laye, Île-de-France, France",
            coords: CLLocationCoordinate2D(latitude: 49, longitude: 2.5),
            camera: nil, lens: nil, exposure: nil, aperture: nil, iso: nil,
            verified: false, proStyle: nil, early: false, badge: nil)
        paris.takenDay = Self.october10
        let pt = K.texts(for: paris).columns.first { $0.key == "PLACE" }
        XCTAssertEqual(pt?.value, "Saint-Germain-en-Laye")
        XCTAssertEqual(pt?.fallback, "France")
        XCTAssertEqual(t.columns.first { $0.key == "PLACE" }?.fallback, "石川県")
        let s = K.texts(for: sydney)
        XCTAssertFalse(s.isSolarTerm)
        XCTAssertEqual(s.latin, "AUSTRALIA")
        XCTAssertEqual(s.columns.last?.key, "COUNTRY")
    }

    // MARK: - 並び（今ある形は変えない・撮った日が無ければ外す）

    func testPostOrderAddsKoyomiAtTheEnd() {
        XCTAssertEqual(ShareCardStyleChoice.order.last, .koyomi)
        XCTAssertEqual(Array(ShareCardStyleChoice.order.prefix(10)),
                       [.band, .fade, .cover, .label, .printed, .ticket, .cinema, .mat, .film, .tanzaku])
        XCTAssertEqual(ShareCardStyleChoice.title(.koyomi), L("暦", "Almanac"))
        var credit = SignatureShareCardRenderer.Credit(
            name: "J", username: nil, location: nil, coords: nil, camera: nil, lens: nil, exposure: nil,
            aperture: nil, iso: nil, verified: false, proStyle: nil, early: false, badge: nil)
        XCTAssertFalse(ShareCardStyleChoice.order(for: credit).contains(.koyomi))
        XCTAssertEqual(ShareCardStyleChoice.style(rawValue: "koyomi", for: credit), .band)
        credit.takenDay = Self.october10
        XCTAssertTrue(ShareCardStyleChoice.order(for: credit).contains(.koyomi))
        XCTAssertEqual(ShareCardStyleChoice.style(rawValue: "koyomi", for: credit), .koyomi)
    }

    func testStoryKindsAddKoyomiAtTheEnd() {
        XCTAssertEqual(TravelStory.Kind.allCases, [.pass, .stamp, .film, .koyomi])
        XCTAssertFalse(TravelStory.Kind.koyomi.supportsSticker)
        XCTAssertFalse(TravelStory.Kind.koyomi.usesPhase)
        let dated = TravelStory.Facts(location: "石川県", takenDay: Self.october10, name: "旅灯")
        let undated = TravelStory.Facts(location: "石川県", takenDay: nil, name: "旅灯")
        XCTAssertEqual(TravelStory.kinds(for: dated), [.pass, .stamp, .film, .koyomi])
        XCTAssertEqual(TravelStory.kinds(for: undated), [.pass, .stamp, .film])
        XCTAssertEqual(TravelStory.nearby(.film, in: TravelStory.kinds(for: undated)), [.film, .stamp])
        XCTAssertEqual(TravelStory.nearby(.koyomi), [.koyomi, .film])
        // ステッカーを選んでいても、暦は写真に重ねる絵（1枚の JPEG）
        var choice = TravelStory.Choice()
        choice.mode = .sticker
        XCTAssertEqual(choice.with(kind: .koyomi).effectiveMode, .photo)
    }

    /// ストーリーの暦は選んだ細かさを守る（県まで・日付を出さない・場所を出さない）
    func testStoryKoyomiKeepsTheChosenDetail() {
        let facts = TravelStory.Facts(location: "兼六園, 兼六町, 金沢市, 石川県, 920-0936, 日本",
                                      takenDay: Self.october10, name: "旅灯", latitude: 36.56)
        var choice = TravelStory.Choice()
        let pref = TravelStory.koyomi(facts, choice: choice)
        XCTAssertEqual(pref.heading, "寒露")
        XCTAssertEqual(pref.columns.map(\.value), ["2026.10.10", "石川県", "17 / 24"])
        XCTAssertNil(pref.columns[1].fallback)
        choice.placeLevel = .city
        XCTAssertEqual(TravelStory.koyomi(facts, choice: choice).columns[1].fallback, "石川県")
        choice.placeLevel = .prefecture
        choice.dateLevel = .none
        let noDate = TravelStory.koyomi(facts, choice: choice)
        XCTAssertFalse(noDate.isSolarTerm)
        XCTAssertFalse(noDate.columns.contains { $0.key == "DATE" })
        choice.dateLevel = .today
        choice.placeLevel = .none
        let noPlace = TravelStory.koyomi(facts, choice: choice)
        XCTAssertEqual(noPlace.columns.map(\.key), ["DATE", "SOLAR TERM"])
        // 南半球で場所を出さない: 国も出さないが、節気も出さない（座標の無い写真でも国で見分ける）
        let sydney = TravelStory.Facts(location: "Sydney, New South Wales, Australia", takenDay: Self.october10, name: "E")
        let hiddenSouth = TravelStory.koyomi(sydney, choice: choice)
        XCTAssertFalse(hiddenSouth.isSolarTerm)
        XCTAssertNil(hiddenSouth.latin)
        XCTAssertFalse(hiddenSouth.columns.contains { $0.value.contains("Australia") })
    }
}
