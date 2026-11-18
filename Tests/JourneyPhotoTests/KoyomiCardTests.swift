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

    /// 写真の大きさ（2026-11-18: 写真の上に余白を取るように替えた後の値。横長は模型のまま）
    func testPhotoSizes() {
        func size(_ aspect: CGFloat, _ frame: K.Frame) -> (Int, Int) {
            let p = K.place(aspect: aspect, in: frame).photo
            return (Int(p.width.rounded()), Int(p.height.rounded()))
        }
        XCTAssert(size(3.0 / 2.0, .story) == (1080, 720))
        XCTAssert(size(3.0 / 2.0, .post(.portrait)) == (1080, 720))
        print("measured [koyomi-size] story 3:4=\(size(0.75, .story)) 3:2=\(size(1.5, .story)) 1:1=\(size(1, .story)) "
              + "post4x5 3:4=\(size(0.75, .post(.portrait))) 3:2=\(size(1.5, .post(.portrait))) 1:1=\(size(1, .post(.portrait))) "
              + "post1x1 3:4=\(size(0.75, .post(.square))) 3:2=\(size(1.5, .post(.square))) 1:1=\(size(1, .post(.square)))")
        XCTAssertEqual(K.Frame.story.textBottom, 1536, accuracy: 0.001)
        XCTAssertEqual(K.Frame.post(.portrait).textBottom, 1285.2, accuracy: 0.001)
        XCTAssertEqual(K.Frame.post(.portrait).textTop, 64.8, accuracy: 0.001)
        XCTAssertEqual(K.Frame.post(.square).height, 1080)
        XCTAssertEqual(K.Frame.post(.story), .story)
    }

    /// 投稿の縦長 3:4 は写真が主役の大きさ（幅 560 以上・2026-11-18 まとめ役。上の余白を左右にそろえたら 409 幅になった）
    func testPostPortraitPhotoStaysLarge() {
        let p = K.place(aspect: 0.75, in: .post(.portrait)).photo
        XCTAssertGreaterThanOrEqual(p.width, 560, "\(p)")
        XCTAssertEqual(p.minY, 96, accuracy: 0.01)
    }

    /// 写真の上の余白は 96 以上。ストーリーは写真の左右の余白以上（幅いっぱいの写真は上 14% の帯の下から）、投稿は 96。
    /// 2026-11-18 owner「上の余白がないのでバランス悪い」（前は縦長の写真の上端が 0 だった）
    func testPhotoHasATopMarginAtLeastItsSideMargin() {
        for (frameName, frame) in Self.frames {
            for (name, aspect) in Self.aspects {
                let p = K.place(aspect: aspect, in: frame).photo
                let side = (K.width - p.width) / 2
                let label = "\(frameName) \(name) \(p)"
                XCTAssertGreaterThanOrEqual(p.minY, K.photoTopMinimum - 0.01, label)
                if frame == .story {
                    // ストーリー: 上の余白＝左右の余白（以上）
                    XCTAssertGreaterThanOrEqual(p.minY, side - 0.01, label)
                } else {
                    // 投稿: 上の余白は 96 に固定（塊は上から詰める・2026-11-18 まとめ役）
                    XCTAssertEqual(p.minY, K.photoTopMinimum, accuracy: 0.01, label)
                }
                if frame == .story, side < 0.5 {
                    XCTAssertGreaterThanOrEqual(p.minY, K.Frame.story.textTop - 0.01, label)
                }
                // 写真＋間＋段の塊は、下の線を越えない範囲で上下の真ん中（上の余白が取れない分だけ写真が縮む）
                // 写真は大きさを保つ: 幅か高さが 400px 以上（小さな切手のようにしない）
                XCTAssertGreaterThanOrEqual(max(p.width, p.height), 400, label)
                let groupBottom = p.maxY + K.gap + K.blockHeight
                XCTAssertLessThanOrEqual(groupBottom, frame.textBottom + 0.01, label)
            }
        }
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
            // 値は幅 276 まで。隣の列の値との間は最低 24px（2026-11-18 確かめ役）
            if index + 1 < K.columnX.count {
                XCTAssertGreaterThanOrEqual(K.columnX[index + 1] - (x + K.valueWidth), K.columnGapMinimum)
            }
        }
        XCTAssertLessThanOrEqual(K.columnX.last! + K.valueWidth, K.right)
        XCTAssertEqual(K.columnGapMinimum, 24)
        // 字の大きさ（インスタで 1080px = 393pt）。眉 30px は 11pt 以上、本文 34px は 12pt 以上（板の最小）
        XCTAssertGreaterThanOrEqual(K.eyebrowSize * 393 / 1080, 10.9)
        XCTAssertGreaterThanOrEqual(K.meaningSize * 393 / 1080, 12)
        XCTAssertGreaterThanOrEqual(K.valueMinimumSize * 393 / 1080, 12)
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

    /// 南半球では節気を出さない（座標の緯度、座標が無ければ撮影地の国）。大きな名前に撮影地、英字は国の英名、列は DATE だけ
    func testSouthernHemisphereNeverShowsASolarTerm() {
        let byLatitude = K.texts(takenDay: Self.october10, showsDate: true, latitude: -33.86, place: "シドニー",
                                 country: "オーストラリア")
        XCTAssertFalse(byLatitude.isSolarTerm)
        XCTAssertEqual(byLatitude.heading, "シドニー")
        XCTAssertEqual(byLatitude.latin, "AUSTRALIA")
        XCTAssertEqual(byLatitude.columns.map(\.key), ["DATE"])
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

    /// 節気を出さないとき、同じ地名を2度出さない（名前・英字・列の値に同じ字が無い。大文字小文字を問わない）
    func testNoPlaceNameAppearsTwice() {
        let cases: [(String?, String?, Double?)] = [
            ("シドニー", "オーストラリア", -33.9), ("Sydney", "Australia", -33.9), ("Australia", "Australia", -33.9),
            ("オーストラリア", "オーストラリア", nil), (nil, "Australia", -33.9), ("京都市", nil, 35),
            ("ケープタウン", "南アフリカ", nil), ("Lima", "ペルー", nil), ("ある町", "ガラパゴスの国", -1),
        ]
        for (place, country, latitude) in cases {
            for takenDay in [Self.october10, nil] as [Date?] {
                let t = K.texts(takenDay: takenDay, showsDate: true, latitude: latitude, place: place, country: country)
                XCTAssertFalse(t.isSolarTerm && latitude.map { $0 < 0 } == true)
                let shown = ([t.heading] + [t.latin].compactMap { $0 } + t.columns.map(\.value)).map { $0.lowercased() }
                XCTAssertEqual(Set(shown).count, shown.count, "\(place ?? "-") \(country ?? "-") \(shown)")
            }
        }
        // 英字の作れない国は列に出す（名前・英字のどこにも国が無くならないように）
        let unknown = K.texts(takenDay: Self.october10, showsDate: true, latitude: -1, place: "ある町", country: "ガラパゴスの国")
        XCTAssertNil(unknown.latin)
        XCTAssertEqual(unknown.columns.map(\.key), ["DATE", "COUNTRY"])
        // 国だけのとき: 大きな名前が国で、英字は和名なら英名、英名なら出さない
        XCTAssertEqual(K.texts(takenDay: nil, showsDate: true, latitude: nil, place: nil, country: "オーストラリア").latin,
                       "AUSTRALIA")
        XCTAssertNil(K.texts(takenDay: nil, showsDate: true, latitude: nil, place: nil, country: "Australia").latin)
    }

    /// 撮った日が無い・日付を出さないなら、節気も出さない（節気は日付の手がかり）
    func testNoDateMeansNoSolarTerm() {
        let none = K.texts(takenDay: nil, showsDate: true, latitude: 35, place: "京都市", country: nil)
        XCTAssertFalse(none.isSolarTerm)
        XCTAssertEqual(none.heading, "京都市")
        XCTAssertTrue(none.columns.isEmpty)
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

    /// 本番と同じ形の共有カード（`PostedShareCardCredit.make`・`PhotoDetailView.prepareThreads` と同じ:
    /// location は `shareCardDisplay(raw)`、place は `shareCardPlace(raw)`、座標は約 50km に丸めた概略）
    static func credit(_ raw: String, lat: Double?, lng: Double = 0) -> SignatureShareCardRenderer.Credit {
        var credit = SignatureShareCardRenderer.Credit(
            name: "旅灯", username: "tabi_akari", location: LocationMatch.shareCardDisplay(raw),
            coords: SignatureShareCardRenderer.approximateShareCoordinate(lat.map { Photo.Coords(lat: $0, lng: lng) }),
            camera: nil, lens: nil, exposure: nil, aperture: nil, iso: nil,
            verified: false, proStyle: nil, early: false, badge: nil,
            place: LocationMatch.shareCardPlace(raw))
        credit.takenDay = october10
        return credit
    }

    /// 投稿の共有カードの字（撮影地の列は小さい単位・南半球は概略の緯度、座標が無ければ撮影地の国で見分ける）
    func testCreditTexts() {
        let kanazawa = K.texts(for: Self.credit("兼六園, 兼六町, 金沢市, 石川県, 920-0936, 日本", lat: 36.56, lng: 136.66))
        XCTAssertEqual(kanazawa.heading, "寒露")
        XCTAssertEqual(kanazawa.columns.map(\.value), ["2026.10.10", "金沢市", "17 / 24"])
        XCTAssertEqual(kanazawa.columns[1].fallback, "石川県")

        // 座標の無いシドニー（英文・和文）: 国を撮影地の2行から取り、南半球と見なす（節気を出さない）
        let raws = ["Sydney, New South Wales, Australia", "シドニー, ニューサウスウェールズ州, オーストラリア"]
        for raw in raws {
            let credit = Self.credit(raw, lat: nil)
            XCTAssertFalse(credit.location?.isEmpty ?? true)
            let t = K.texts(for: credit)
            XCTAssertFalse(t.isSolarTerm, raw)
            XCTAssertEqual(t.latin, "AUSTRALIA", raw)
            let all = ([t.heading, t.latin ?? ""] + t.columns.map(\.value)).joined()
            XCTAssertFalse(all.contains(")"), "\(raw) \(all)")
            XCTAssertFalse(all.contains("）"), "\(raw) \(all)")
            for term in SolarTerm.all { XCTAssertFalse(all.contains(term.name), "\(raw) \(term.name)") }
        }
        XCTAssertEqual(K.texts(for: Self.credit(raws[0], lat: nil)).heading, "Sydney")
        XCTAssertEqual(K.texts(for: Self.credit(raws[1], lat: nil)).heading, "シドニー")
        // 座標のあるシドニーも同じ
        XCTAssertFalse(K.texts(for: Self.credit(raws[0], lat: -33.86, lng: 151.2)).isSolarTerm)
        // 本番の location の形（括弧つき）のままでは国が取れないことの確かめ（前の作りの誤り）
        XCTAssertNotEqual(K.country(of: LocationMatch.shareCardDisplay(raws[0])), "Australia")

        // 北半球の海外は節気。撮影地の列の代わりに国（長い地名は入らないとき）
        let paris = K.texts(for: Self.credit("Saint-Germain-en-Laye, Île-de-France, France", lat: 48.9, lng: 2.1))
        XCTAssertTrue(paris.isSolarTerm)
        let pt = paris.columns.first { $0.key == "PLACE" }
        XCTAssertEqual(pt?.value, "Saint-Germain-en-Laye")
        XCTAssertEqual(pt?.fallback, "France")
        // 日本の撮影地は国にしない
        XCTAssertNil(K.country(of: LocationMatch.shareCardPlace("山中湖村, 山梨県, 日本")))
        XCTAssertNil(K.country(of: LocationMatch.shareCardPlace("Kyoto, Kyoto Prefecture, Japan")))
        XCTAssertNil(K.country(of: LocationMatch.shareCardPlace("山中湖")))
        XCTAssertEqual(K.country(of: LocationMatch.shareCardPlace("オーストラリア")), "オーストラリア")
    }

    // MARK: - 共有画面の「日付」の入切（2026-11-18 判断・`ShareCardDateChoice`）

    /// 既定は出す・切った値を覚える
    func testDateChoiceDefaultsToShownAndIsRemembered() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "KoyomiCardTests.date"))
        defaults.removePersistentDomain(forName: "KoyomiCardTests.date")
        XCTAssertTrue(ShareCardDateChoice.load(defaults: defaults))
        ShareCardDateChoice.save(false, defaults: defaults)
        XCTAssertFalse(ShareCardDateChoice.load(defaults: defaults))
        ShareCardDateChoice.save(true, defaults: defaults)
        XCTAssertTrue(ShareCardDateChoice.load(defaults: defaults))
        defaults.removePersistentDomain(forName: "KoyomiCardTests.date")
    }

    /// 入切を出すのは、日付を描く型（暦・写真の色）で撮った日のある写真のときだけ
    func testDateToggleOnlyForDatedStyles() {
        let dated = Self.credit("兼六園, 兼六町, 金沢市, 石川県, 920-0936, 日本", lat: 36.56)
        var undated = dated
        undated.takenDay = nil
        XCTAssertEqual(SignatureShareCardRenderer.Style.allCases.filter(ShareCardDateChoice.drawsDate), [.koyomi, .photoColor])
        XCTAssertTrue(ShareCardDateChoice.showsToggle(style: .koyomi, credit: dated))
        XCTAssertFalse(ShareCardDateChoice.showsToggle(style: .koyomi, credit: undated))
        XCTAssertTrue(ShareCardDateChoice.showsToggle(style: .photoColor, credit: dated))
        XCTAssertFalse(ShareCardDateChoice.showsToggle(style: .photoColor, credit: undated))
        for style in SignatureShareCardRenderer.Style.allCases where style != .koyomi && style != .photoColor {
            XCTAssertFalse(ShareCardDateChoice.showsToggle(style: style, credit: dated), style.rawValue)
        }
        XCTAssertFalse(ShareCardDateChoice.label.contains("撮りどき"))
    }

    /// 切ったら、暦は日付も節気も出さない（撮った日が外に出ない）
    func testDateOffHidesDateAndSolarTerm() {
        let credit = ShareCardDateChoice.credit(
            Self.credit("兼六園, 兼六町, 金沢市, 石川県, 920-0936, 日本", lat: 36.56, lng: 136.66), showsDate: false)
        XCTAssertFalse(credit.showsDate)
        let t = K.texts(for: credit)
        XCTAssertFalse(t.isSolarTerm)
        XCTAssertNil(t.meaning)
        let all = ([t.heading, t.latin ?? ""] + t.columns.flatMap { [$0.key, $0.value] }).joined()
        XCTAssertFalse(all.contains("2026"), all)
        XCTAssertFalse(all.contains("DATE"), all)
        XCTAssertFalse(all.contains("SOLAR TERM"), all)
        for term in SolarTerm.all { XCTAssertFalse(all.contains(term.name) || all.contains(term.latin), term.name) }
        // 入れたまま（既定）なら節気
        XCTAssertTrue(K.texts(for: ShareCardDateChoice.credit(credit, showsDate: true)).isSolarTerm)
    }

    /// 共有画面は入切を写した中身で描き、入切を出す（画面は Linux で描けないので、作りを文字で見る）
    func testShareSheetDrawsWithTheDateChoice() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let sheet = try String(contentsOf: root.appendingPathComponent(
            "Sources/JourneyPhoto/Features/Common/SignatureShareCardSheet.swift"), encoding: .utf8)
        XCTAssertTrue(sheet.contains("SignatureShareCardRenderer.render(photoData, credit: drawnCredit,"))
        XCTAssertFalse(sheet.contains("SignatureShareCardRenderer.render(photoData, credit: credit,"),
                       "入切を写さない中身で描いている")
        XCTAssertTrue(sheet.contains("ShareCardDateChoice.showsToggle(style: style, credit: credit)"))
        XCTAssertTrue(sheet.contains("\"signatureShare.date\""))
        XCTAssertTrue(sheet.contains("ShareCardDateChoice.save(newValue)"))
    }

    /// 日本の「〇〇郡〇〇町」は郡を落とす（列が詰まらないように）
    func testDistrictIsDropped() {
        XCTAssertEqual(K.withoutDistrict("東牟婁郡那智勝浦町"), "那智勝浦町")
        XCTAssertEqual(K.withoutDistrict("南都留郡山中湖村"), "山中湖村")
        XCTAssertEqual(K.withoutDistrict("金沢市"), "金沢市")
        XCTAssertEqual(K.withoutDistrict("郡山市"), "郡山市")
        let t = K.texts(for: Self.credit("那智の滝, 那智山, 東牟婁郡那智勝浦町, 和歌山県, 649-5301, 日本", lat: 33.67, lng: 135.89))
        XCTAssertEqual(t.columns.first { $0.key == "PLACE" }?.value, "那智勝浦町")
    }

    // MARK: - 並び（今ある形は変えない・撮った日が無ければ外す）

    func testPostOrderAddsKoyomiAtTheEnd() {
        // 2026-11-18: 写真の色を暦の後ろに足した（暦は後ろから2つ目）
        XCTAssertEqual(Array(ShareCardStyleChoice.order.suffix(2)), [.koyomi, .photoColor])
        XCTAssertEqual(Array(ShareCardStyleChoice.order.prefix(10)),
                       [.band, .fade, .cover, .label, .printed, .ticket, .cinema, .mat, .film, .tanzaku])
        XCTAssertEqual(ShareCardStyleChoice.title(.koyomi), L("暦", "Almanac"))
        var credit = SignatureShareCardRenderer.Credit(
            name: "J", username: nil, location: nil, coords: nil, camera: nil, lens: nil, exposure: nil,
            aperture: nil, iso: nil, verified: false, proStyle: nil, early: false, badge: nil)
        XCTAssertFalse(ShareCardStyleChoice.order(for: credit).contains(.koyomi))
        // 写真の色は撮った日が無くても選べる（日付を出さないだけ）
        XCTAssertTrue(ShareCardStyleChoice.order(for: credit).contains(.photoColor))
        XCTAssertEqual(ShareCardStyleChoice.style(rawValue: "koyomi", for: credit), .band)
        credit.takenDay = Self.october10
        XCTAssertTrue(ShareCardStyleChoice.order(for: credit).contains(.koyomi))
        XCTAssertEqual(ShareCardStyleChoice.style(rawValue: "koyomi", for: credit), .koyomi)
    }

    func testStoryKindsAddKoyomiAtTheEnd() {
        XCTAssertEqual(TravelStory.Kind.allCases, [.pass, .stamp, .film, .koyomi, .photoColor])
        XCTAssertFalse(TravelStory.Kind.koyomi.supportsSticker)
        XCTAssertFalse(TravelStory.Kind.koyomi.usesPhase)
        let dated = TravelStory.Facts(location: "石川県", takenDay: Self.october10, name: "旅灯")
        let undated = TravelStory.Facts(location: "石川県", takenDay: nil, name: "旅灯")
        XCTAssertEqual(TravelStory.kinds(for: dated), [.pass, .stamp, .film, .koyomi, .photoColor])
        // 写真の色は撮った日が無くても選べる（暦だけ外す）
        XCTAssertEqual(TravelStory.kinds(for: undated), [.pass, .stamp, .film, .photoColor])
        XCTAssertEqual(TravelStory.nearby(.film, in: TravelStory.kinds(for: undated)), [.film, .stamp, .photoColor])
        XCTAssertEqual(TravelStory.nearby(.koyomi), [.koyomi, .film, .photoColor])
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
