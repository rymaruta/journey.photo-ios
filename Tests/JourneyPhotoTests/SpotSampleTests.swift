import XCTest
@testable import JourneyPhoto

/// 撮影スポットの作例（`SpotSample`・本文 JSON の `samples`・2026-10-03）。
/// 🔴 **題・作者・ライセンス・出典が揃った1枚だけ出す**（Web の `toSpotSample` と同じ規則）
final class SpotSampleTests: XCTestCase {

    private func decode(_ json: String) throws -> SpotBody {
        try JSONDecoder.api.decode(SpotBody.self, from: Data(json.utf8))
    }

    private func body(samples: String) throws -> SpotBody {
        try decode(#"{"slug":"a","check":{"kind":"human","verifiedAt":"2026-09-25"},"samples":"# + samples + "}")
    }

    /// Web の `toSpotSample` が出す形の1枚（項目を差し替えて使う）
    private func sample(_ overrides: [String: Any?] = [:]) -> String {
        var fields: [String: Any?] = [
            "src": "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Kinkaku.jpg/1280px-Kinkaku.jpg",
            "width": 1280, "height": 853,
            "title": "Kinkaku-ji in autumn",
            "author": "Taro Yamada",
            "license": "CC BY-SA 4.0",
            "licenseUrl": "https://creativecommons.org/licenses/by-sa/4.0",
            "sourceUrl": "https://commons.wikimedia.org/wiki/File:Kinkaku.jpg",
            "takenAt": "2019-11-20 10:00:00",
        ]
        for (k, v) in overrides { fields[k] = v }
        let present = fields.compactMapValues { $0 }
        let data = try! JSONSerialization.data(withJSONObject: present, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    func testReadsSamples() throws {
        let b = try body(samples: "[\(sample())]")
        XCTAssertEqual(b.samples.count, 1)
        let s = try XCTUnwrap(b.samples.first)
        XCTAssertEqual(s.title, "Kinkaku-ji in autumn")
        XCTAssertEqual(s.author, "Taro Yamada")
        XCTAssertEqual(s.license, "CC BY-SA 4.0")
        XCTAssertEqual(s.licenseUrl?.absoluteString, "https://creativecommons.org/licenses/by-sa/4.0")
        XCTAssertEqual(s.sourceUrl.absoluteString, "https://commons.wikimedia.org/wiki/File:Kinkaku.jpg")
        XCTAssertEqual(s.aspectRatio, 1280.0 / 853.0, accuracy: 0.0001)
    }

    /// 後から足された項目なので、無い本文・壊れた形でも本文ごとは落とさない
    /// 撮影日（`takenAt`）は書き方が混在する。年と月が読めれば読み、読めなければ nil（2026-10-07・本番の本文で見た形）
    func testReadsTakenAtInMixedFormats() throws {
        let cases: [(String, Int, Int)] = [
            ("2013-08-03", 2013, 8), ("2009-10-21 16:24:00", 2009, 10), ("2016-02", 2016, 2),
            ("2009/09/21145646", 2009, 9), ("2011-11−18", 2011, 11),
            ("2009年8月16日", 2009, 8), ("2011年4月15日, 14:12:03", 2011, 4), ("2025年1月1日 ( Exif データによる)", 2025, 1),
            ("Taken on 12 August 2011", 2011, 8), ("10 February 2024 (according to Exif data)", 2024, 2),
            ("Taken on 3 July 2026, 07:38:39", 2026, 7), ("August 12, 2011", 2011, 8),
        ]
        for (raw, year, month) in cases {
            XCTAssertEqual(SpotSample.TakenAt.parse(raw), SpotSample.TakenAt(year: year, month: month), raw)
        }
        for raw in [nil, "", "2017", "H20-4", "2016年6月16日, 16:37:38 (UTC)より前", "2019-13-01", "unknown"] {
            XCTAssertNil(SpotSample.TakenAt.parse(raw), raw ?? "nil")
        }
        let b = try body(samples: "[\(sample()),\(sample(["takenAt": nil, "sourceUrl": "https://commons.wikimedia.org/wiki/File:B.jpg"])),\(sample(["takenAt": 2019, "sourceUrl": "https://commons.wikimedia.org/wiki/File:C.jpg"]))]")
        XCTAssertEqual(b.samples.map(\.takenAt), [SpotSample.TakenAt(year: 2019, month: 11), nil, nil],
                       "撮影日が無い・形が違う1枚も落とさない")
    }

    /// 季節は撮影月から。南半球は半年ずらす
    func testTakenAtSeason() {
        XCTAssertEqual(SpotSample.TakenAt(year: 2019, month: 10).season(southern: false), "autumn")
        XCTAssertEqual(SpotSample.TakenAt(year: 2019, month: 12).season(southern: false), "winter")
        XCTAssertEqual(SpotSample.TakenAt(year: 2019, month: 4).season(southern: true), "autumn")
    }

    func testMissingOrBrokenSamplesKeepTheBody() throws {
        XCTAssertEqual(try body(samples: "null").samples, [])
        XCTAssertEqual(try decode(#"{"slug":"a","highlights":["x"],"check":{"kind":"human","verifiedAt":"2026-09-25"}}"#).samples, [])
        XCTAssertEqual(try body(samples: #""壊れた""#).samples, [])
        let mixed = try body(samples: "[1, \"x\", {\"src\":3}, \(sample())]")
        XCTAssertEqual(mixed.samples.count, 1, "壊れた1枚だけ落とす")
    }

    /// 🔴 作者・ライセンス・出典・題が欠けた1枚は出さない
    func testSamplesMissingAttributionAreDropped() throws {
        for key in ["author", "license", "sourceUrl", "title", "src", "width"] {
            XCTAssertEqual(try body(samples: "[\(sample([key: nil]))]").samples, [], "\(key) が無い")
            XCTAssertEqual(try body(samples: "[\(sample([key: "  "]))]").samples, [], "\(key) が空")
        }
        XCTAssertEqual(try body(samples: "[\(sample(["licenseUrl": nil]))]").samples, [],
                       "CC BY 系はライセンスの文面が要る")
        XCTAssertEqual(try body(samples: "[\(sample(["height": 0]))]").samples, [])
    }

    /// 🔴 NC（商用不可）・ND（改変不可）・その他のライセンスは、どの書き方でも出さない
    func testNonCommercialAndNoDerivativesAreDropped() throws {
        for license in ["CC BY-NC 4.0", "CC BY-NC-SA 4.0", "CC BY-ND 2.0", "CC-BY-NC-ND-3.0", "CC BY-SA-NC 2.0",
                        "cc by nc 4.0", "GFDL", "Attribution", "PD-US", "PD-USGov", "Public domain in the United States"] {
            XCTAssertEqual(try body(samples: "[\(sample(["license": license]))]").samples, [], license)
        }
    }

    func testAllowedLicenseKinds() {
        XCTAssertEqual(SpotSample.sampleLicenseKind("CC BY-SA 4.0"), .ccBySA)
        XCTAssertEqual(SpotSample.sampleLicenseKind("CC-BY-SA-3.0"), .ccBySA)
        XCTAssertEqual(SpotSample.sampleLicenseKind("CC BY 2.0"), .ccBy)
        XCTAssertEqual(SpotSample.sampleLicenseKind("cc-by-4.0"), .ccBy)
        XCTAssertEqual(SpotSample.sampleLicenseKind("CC0"), .cc0)
        XCTAssertEqual(SpotSample.sampleLicenseKind("Public domain"), .publicDomain)
        XCTAssertEqual(SpotSample.sampleLicenseKind("PD-self"), .publicDomain)
        XCTAssertNil(SpotSample.sampleLicenseKind("CC BY-NC-SA 2.0"))
    }

    /// パブリックドメイン・CC0 は文面の URL も作者の名前も要らない（Web が「作者不明」を入れて配る）
    func testPublicDomainNeedsNoLicenseURL() throws {
        let pd = try body(samples: "[\(sample(["license": "Public domain", "licenseUrl": nil, "author": "作者不明"]))]")
        XCTAssertEqual(pd.samples.first?.licenseUrl, nil)
        XCTAssertEqual(pd.samples.first?.author, "作者不明")
    }

    /// CC BY 系で作者が名前でない（決まり文句・お願い文・長すぎる）1枚は出さない
    func testPlaceholderAuthorsAreDroppedForBYLicenses() throws {
        for author in ["Own work", "Unknown author", "作者不明", "投稿者自身による著作物", "Please credit me",
                       "Taro (UTC)", String(repeating: "a", count: 81)] {
            XCTAssertEqual(try body(samples: "[\(sample(["author": author]))]").samples, [], author)
        }
    }

    /// 画像は Commons の縮小版だけ（元画像は位置情報が残る）・出典は Commons のファイルのページだけ
    func testOnlyCommonsThumbnailsAndFilePages() throws {
        let original = "https://upload.wikimedia.org/wikipedia/commons/a/ab/Kinkaku.jpg"
        XCTAssertEqual(try body(samples: "[\(sample(["src": original]))]").samples, [], "元画像")
        XCTAssertEqual(try body(samples: "[\(sample(["src": "https://example.com/x.jpg"]))]").samples, [])
        XCTAssertEqual(try body(samples: "[\(sample(["sourceUrl": "https://example.com/File:x"]))]").samples, [])
        // http は https に上げる（Web と同じ）
        let http = try body(samples: "[\(sample(["sourceUrl": "http://commons.wikimedia.org/wiki/File:Kinkaku.jpg"]))]")
        XCTAssertEqual(http.samples.first?.sourceUrl.scheme, "https")
    }

    /// 同じ出典の2枚目は落とし、最大6枚
    func testDeduplicatesAndCapsAtSix() throws {
        let many = (0..<9).map { sample(["sourceUrl": "https://commons.wikimedia.org/wiki/File:K\($0).jpg"]) }
        let list = [sample(), sample()] + many
        let b = try body(samples: "[\(list.joined(separator: ","))]")
        XCTAssertEqual(b.samples.count, 6)
        XCTAssertEqual(Set(b.samples.map(\.sourceUrl)).count, 6)
    }

    // MARK: - 表示の文

    /// 🔴 写真の下の1行は「題 / 写真: 作者 / ライセンス / Wikimedia Commons」（Web の `Samples` と同じ）
    func testCreditLine() throws {
        let s = try XCTUnwrap(try body(samples: "[\(sample())]").samples.first)
        XCTAssertEqual(s.credit, L("Kinkaku-ji in autumn / 写真: Taro Yamada / CC BY-SA 4.0 / Wikimedia Commons",
                                   "Kinkaku-ji in autumn / Photo: Taro Yamada / CC BY-SA 4.0 / Wikimedia Commons"))
        XCTAssertEqual(String(s.linkedCredit.characters), s.credit, "リンクを付けても文字は同じ")
        // ライセンス → 文面・Wikimedia Commons → ファイルのページ
        var links: [String: URL] = [:]
        for run in s.linkedCredit.runs {
            if let link = run.link { links[String(s.linkedCredit[run.range].characters)] = link }
        }
        XCTAssertEqual(links["CC BY-SA 4.0"], s.licenseUrl)
        XCTAssertEqual(links["Wikimedia Commons"], s.sourceUrl)
        XCTAssertEqual(links.count, 2)
    }

    func testHeadingAndNote() throws {
        let commons = try body(samples: "[\(sample())]").samples
        XCTAssertEqual(SpotSampleText.heading(commons), L("作例（Wikimedia Commons より）", "Example photos (from Wikimedia Commons)"))
        XCTAssertEqual(SpotSampleText.note(commons),
                       L("この場所の近くで撮られ、Wikimedia Commons で自由なライセンスのもと公開されている写真です。撮影者はこのアプリの利用者ではありません。",
                         "Photos taken near this spot and published under free licenses on Wikimedia Commons. The photographers are not members of this app."))
    }

    /// 帯の枠は高さをそろえ、幅は縦横比から（極端なものは上下限で止め、切り抜かない）
    func testFrameKeepsAspectWithinBounds() {
        XCTAssertEqual(SpotSampleText.frame(aspectRatio: 1.5).width, 252)
        XCTAssertEqual(SpotSampleText.frame(aspectRatio: 0.2).width, SpotSampleText.minWidth)
        XCTAssertEqual(SpotSampleText.frame(aspectRatio: 5).width, SpotSampleText.maxWidth)
        XCTAssertEqual(SpotSampleText.frame(aspectRatio: .nan).width, SpotSampleText.photoHeight)
        XCTAssertEqual(SpotSampleText.frame(aspectRatio: 1).height, SpotSampleText.photoHeight)
    }

    /// 🔴 出典の1行の当たりは 44pt 以上（押せるものの最小・`WebTheme.minTapTarget`）。
    /// 文中のリンクは字の高さ（≒16pt）しかないので、1行全体を1つの当たりにしている（2026-10-03）。
    /// 幅は写真の幅と同じなので、いちばん細い写真でも 44pt を割らない
    func testCreditTapTargetIsAtLeast44pt() {
        XCTAssertGreaterThanOrEqual(CreditLink.tapHeight, Double(WebTheme.minTapTarget))
        for ratio in [0.05, 0.2, 0.5, 1, 1.5, 5, .nan] {
            XCTAssertGreaterThanOrEqual(SpotSampleText.frame(aspectRatio: ratio).width, Double(WebTheme.minTapTarget),
                                        "縦横比 \(ratio) の1枚")
        }
    }

    /// 出典の1行から開ける先は文字の並びと同じ（ライセンス → Wikimedia Commons）、リンク先は `linkedCredit` と同じ
    func testCreditLinksMatchLinkedCredit() throws {
        let s = try XCTUnwrap(try body(samples: "[\(sample())]").samples.first)
        XCTAssertEqual(s.creditLinks.map(\.url), [s.licenseUrl, s.sourceUrl].compactMap { $0 })
        XCTAssertEqual(s.creditLinks.first?.label.contains("CC BY-SA 4.0"), true)
        XCTAssertEqual(s.creditLinks.last?.label.contains("Wikimedia Commons"), true)
        let inline = s.linkedCredit.runs.compactMap(\.link)
        XCTAssertEqual(Set(s.creditLinks.map(\.url)), Set(inline), "メニューの行き先と文中のリンク先は同じ")
    }

    /// 文面の URL の無いライセンス（パブリックドメイン）は Commons のページだけ（メニューを出さずに開く）
    func testPublicDomainCreditHasOnlyTheSourceLink() throws {
        let s = try XCTUnwrap(try body(samples: "[\(sample(["license": "Public domain", "licenseUrl": nil]))]").samples.first)
        XCTAssertEqual(s.creditLinks.map(\.url), [s.sourceUrl])
    }
    // MARK: - Commons 以外の出どころ（Flickr・2026-10-04・photo-gallery #286 の形）

    private let flickrPage = "https://www.flickr.com/photos/taro/53212345678/"

    /// Web の `toFlickrSample` が出す形（`sourceUrl` と `source.url` は同じ写真のページ）
    private func flickrSample(_ overrides: [String: Any?] = [:]) -> String {
        let base: [String: Any?] = [
            "src": "https://live.staticflickr.com/65535/53212345678_1a2b3c4d5e_b.jpg",
            "sourceUrl": flickrPage,
            "source": ["name": "Flickr", "url": flickrPage],
        ]
        return sample(base.merging(overrides) { $1 })
    }

    /// Flickr の作例を読む（画像は live.staticflickr.com、出典は写真のページ）
    func testReadsFlickrSample() throws {
        let s = try XCTUnwrap(try body(samples: "[\(flickrSample())]").samples.first)
        XCTAssertEqual(s.origin, .flickr)
        XCTAssertEqual(s.src.absoluteString, "https://live.staticflickr.com/65535/53212345678_1a2b3c4d5e_b.jpg")
        XCTAssertEqual(s.sourceUrl.absoluteString, flickrPage)
        XCTAssertEqual(s.title, "Kinkaku-ji in autumn")
        // CC0 は出せる（文面の URL も要らない）
        XCTAssertEqual(try body(samples: "[\(flickrSample(["license": "CC0", "licenseUrl": nil]))]").samples.count, 1)
    }

    /// 🔴 出典の行の最後とメニューの行き先は出どころの名前（「Flickr」「Flickr のページを開く」）、リンク先は写真のページ
    func testFlickrCreditAndMenu() throws {
        let s = try XCTUnwrap(try body(samples: "[\(flickrSample())]").samples.first)
        XCTAssertEqual(s.credit, L("Kinkaku-ji in autumn / 写真: Taro Yamada / CC BY-SA 4.0 / Flickr",
                                   "Kinkaku-ji in autumn / Photo: Taro Yamada / CC BY-SA 4.0 / Flickr"))
        XCTAssertEqual(String(s.linkedCredit.characters), s.credit)
        var links: [String: URL] = [:]
        for run in s.linkedCredit.runs {
            if let link = run.link { links[String(s.linkedCredit[run.range].characters)] = link }
        }
        XCTAssertEqual(links["Flickr"]?.absoluteString, flickrPage)
        XCTAssertEqual(s.creditLinks.last?.label, L("Flickr のページを開く", "Open on Flickr"))
        XCTAssertEqual(s.creditLinks.last?.url.absoluteString, flickrPage)
        XCTAssertFalse(s.creditLinks.contains { $0.label.contains("Wikimedia Commons") })
        let picture = HomeSpotShelf.Picture.sample(s)
        XCTAssertTrue(picture.credit.hasSuffix(" / Flickr"), "ホームの札の出典も同じ")
    }

    /// 🔴 Flickr の縮小版は作り替えない（Commons の名前の形を前提にしているため）
    func testFlickrThumbnailIsNotRewritten() throws {
        let s = try XCTUnwrap(try body(samples: "[\(flickrSample(["width": 1600, "height": 1067]))]").samples.first)
        XCTAssertEqual(s.thumbnail(maxWidth: 500), s.src)
        XCTAssertEqual(HomeSpotShelf.Picture.sample(s).url, s.src, "ホームの札も元の URL のまま")
        // Commons の縮小版の形（`<幅>px-<名前>`）に見える名前でも、Flickr なら触らない
        let lookalike = URL(string: "https://live.staticflickr.com/65535/1280px-53212345678_1a2b3c4d5e.jpg")!
        let odd = SpotSample(src: lookalike, width: 1280, height: 853, title: "T", author: "A", license: "CC0",
                             licenseUrl: nil, sourceUrl: URL(string: flickrPage)!, origin: .flickr)
        XCTAssertEqual(odd.thumbnail(maxWidth: 500), lookalike)
    }

    /// Flickr でも画像・出典・ライセンスは確かめる（Web の `toFlickrSample` と同じ＋元画像 `_o` は落とす）
    func testFlickrRejectsWrongShapes() throws {
        let bad: [(String, Any?)] = [
            ("src", "https://live.staticflickr.com/65535/53212345678_9f8e7d6c5b_o.jpg"),
            ("src", "https://live.staticflickr.com/65535/99999999999_1a2b3c4d5e_b.jpg"),
            ("src", "https://example.com/53212345678_1a2b3c4d5e_b.jpg"),
            ("src", "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/K.jpg/1280px-K.jpg"),
            ("source", ["name": "Flickr", "url": "https://commons.wikimedia.org/wiki/File:Kinkaku.jpg"]),
            ("source", ["name": "Flickr", "url": "https://example.com/photos/taro/53212345678/"]),
            ("source", ["name": "Flickr"]),
            ("license", "Public domain"),
            ("license", "CC BY-NC 2.0"),
            ("licenseUrl", nil),
            ("author", "Own work"),
        ]
        for (key, value) in bad {
            XCTAssertEqual(try body(samples: "[\(flickrSample([key: value]))]").samples, [], "\(key)=\(String(describing: value))")
        }
    }

    /// `source` が無い・形が壊れているときは今まで通り Commons。名前が空の1枚は落とす
    func testMissingOrBrokenSourceMeansCommons() throws {
        for source: Any? in [nil, "Flickr", ["name": 3], [1, 2],
                             ["name": "Wikimedia Commons", "url": "https://commons.wikimedia.org/wiki/File:Kinkaku.jpg"]] {
            let s = try XCTUnwrap(try body(samples: "[\(sample(["source": source]))]").samples.first,
                                  String(describing: source))
            XCTAssertEqual(s.origin, .commons)
            XCTAssertTrue(s.credit.hasSuffix(" / Wikimedia Commons"))
            XCTAssertEqual(s.creditLinks.last?.label, L("Wikimedia Commons のページを開く", "Open on Wikimedia Commons"))
        }
        // 壊れた source の Flickr の1枚は Commons の規則で落ちる
        XCTAssertEqual(try body(samples: "[\(flickrSample(["source": "x"]))]").samples, [])
        for name in ["", "  "] {
            XCTAssertEqual(try body(samples: "[\(sample(["source": ["name": name, "url": flickrPage]]))]").samples, [], name)
        }
        // 綴りを変えても Flickr の検査は抜けられない（Commons の画像は Flickr として出せない）
        XCTAssertEqual(try body(samples: "[\(sample(["source": ["name": " flickr ", "url": flickrPage]]))]").samples, [])
        XCTAssertEqual(try body(samples: "[\(flickrSample(["source": ["name": "FLICKR", "url": flickrPage]]))]").samples.first?.origin, .flickr)
    }

    // MARK: - その他の出どころ（環境省・県の観光連盟など・2026-10-04）

    private let otherPage = "https://www.env.go.jp/park/example/photo/12.html"

    private func otherSample(_ overrides: [String: Any?] = [:]) -> String {
        let base: [String: Any?] = [
            "src": "https://journey-photo.com/samples/env/oze-12.jpg",
            "sourceUrl": otherPage,
            "license": "PDL1.0", "licenseUrl": nil, "author": "環境省",
            "source": ["name": " 環境省 ", "url": otherPage],
        ]
        return sample(base.merging(overrides) { $1 })
    }

    /// 🔴 名前はそのまま出典の行とメニューに、ライセンスは文字のまま、画像は作り替えない
    func testOtherSourceIsShownAsIs() throws {
        let s = try XCTUnwrap(try body(samples: "[\(otherSample(["width": 1600]))]").samples.first)
        XCTAssertEqual(s.origin, .other("環境省"))
        XCTAssertEqual(s.license, "PDL1.0")
        XCTAssertNil(s.licenseUrl)
        XCTAssertEqual(s.credit, L("Kinkaku-ji in autumn / 写真: 環境省 / PDL1.0 / 環境省",
                                   "Kinkaku-ji in autumn / Photo: 環境省 / PDL1.0 / 環境省"))
        XCTAssertEqual(s.creditLinks.map(\.label), [L("環境省 のページを開く", "Open on 環境省")])
        XCTAssertEqual(s.creditLinks.last?.url.absoluteString, otherPage)
        XCTAssertEqual(s.thumbnail(maxWidth: 500), s.src)
        let lookalike = URL(string: "https://journey-photo.com/samples/env/1280px-oze.jpg")!
        let odd = SpotSample(src: lookalike, width: 1280, height: 853, title: "T", author: "A", license: "PDL1.0",
                             licenseUrl: nil, sourceUrl: URL(string: otherPage)!, origin: .other("環境省"))
        XCTAssertEqual(odd.thumbnail(maxWidth: 500), lookalike, "Commons 以外は作り替えない")
        // 文面の URL があればライセンスのリンクも付く
        let withUrl = try XCTUnwrap(try body(samples: "[\(otherSample(["licenseUrl": "https://www.digital.go.jp/resources/open_data/public_data_license_v1.0"]))]").samples.first)
        XCTAssertEqual(withUrl.creditLinks.count, 2)
        // 見出しは Commons が先、その後は出ている順
        let mixed = try body(samples: "[\(otherSample()),\(flickrSample()),\(sample())]").samples
        XCTAssertEqual(SpotSampleText.heading(mixed),
                       L("作例（Wikimedia Commons・環境省・Flickr より）", "Example photos (from Wikimedia Commons and 環境省 and Flickr)"))
    }

    /// その他の出どころでも、https でない画像・出典のページ・NC/ND・作者や題やライセンスの無い1枚は出さない
    func testOtherSourceRejectsUnsafe() throws {
        let bad: [(String, Any?)] = [
            ("src", "ftp://journey-photo.com/samples/a.jpg"),
            ("src", nil),
            ("source", ["name": "環境省"]),
            ("source", ["name": "環境省", "url": "javascript:alert(1)"]),
            ("license", "CC BY-NC 4.0"),
            ("license", " "),
            ("author", ""),
            ("author", "作者不明"),
            ("title", ""),
            ("width", 0),
        ]
        for (key, value) in bad {
            XCTAssertEqual(try body(samples: "[\(otherSample([key: value]))]").samples, [], "\(key)=\(String(describing: value))")
        }
    }

    /// 🔴 見出しと注記は出ている写真の出どころを全部名乗る（Commons が先・Web と同じ）
    func testHeadingNamesShownSources() throws {
        let both = try body(samples: "[\(flickrSample()),\(sample())]").samples
        XCTAssertEqual(both.map(\.origin), [.flickr, .commons])
        XCTAssertEqual(SpotSampleText.heading(both),
                       L("作例（Wikimedia Commons・Flickr より）", "Example photos (from Wikimedia Commons and Flickr)"))
        XCTAssertTrue(SpotSampleText.note(both).contains(L("Wikimedia Commons・Flickr で自由な", "on Wikimedia Commons and Flickr.")))
        let flickrOnly = try body(samples: "[\(flickrSample())]").samples
        XCTAssertEqual(SpotSampleText.heading(flickrOnly), L("作例（Flickr より）", "Example photos (from Flickr)"))
        XCTAssertFalse(SpotSampleText.note(flickrOnly).contains("Wikimedia Commons"))
    }

    // MARK: - サイトに置いた写真（環境省・県の観光連盟など・photo-gallery #290 の形）

    private func hostedSample(_ overrides: [String: Any?] = [:]) -> String {
        let page = "https://www.crossroadfukuoka.jp/photo/123"
        let base: [String: Any?] = [
            "src": "https://journey-photo.com/samples/ukiha-inari/1.jpg",
            "title": "浮羽稲荷神社", "author": "福岡県観光連盟",
            "license": "クロスロードふくおか フォトダウンロード利用規約",
            "licenseUrl": "https://www.crossroadfukuoka.jp/business/photo/guide",
            "sourceUrl": page,
            "source": ["name": "福岡県観光連盟", "url": page],
            "credit": "写真提供：福岡県観光連盟",
            "modified": "journey.photo が縮小して掲載",
            "termsUrl": "https://www.crossroadfukuoka.jp/business/photo/guide",
        ]
        return sample(base.merging(overrides) { $1 })
    }

    /// 🔴 「題 / credit / 規約名（文面へ）/ 提供元（写真のページへ）/ modified」
    func testHostedCreditLine() throws {
        let s = try XCTUnwrap(try body(samples: "[\(hostedSample())]").samples.first)
        XCTAssertEqual(s.credit, "浮羽稲荷神社 / 写真提供：福岡県観光連盟 / クロスロードふくおか フォトダウンロード利用規約 / 福岡県観光連盟 / journey.photo が縮小して掲載")
        var links: [String: URL] = [:]
        for run in s.linkedCredit.runs {
            if let link = run.link { links[String(s.linkedCredit[run.range].characters)] = link }
        }
        XCTAssertEqual(links["クロスロードふくおか フォトダウンロード利用規約"], s.licenseUrl)
        XCTAssertEqual(links["福岡県観光連盟"]?.absoluteString, "https://www.crossroadfukuoka.jp/photo/123")
        XCTAssertEqual(links.count, 2, "credit・modified にはリンクを付けない")
        XCTAssertEqual(s.creditLinks.map(\.label), [L("ライセンス（クロスロードふくおか フォトダウンロード利用規約）を開く",
                                                    "Open license (クロスロードふくおか フォトダウンロード利用規約)"),
                                                  L("福岡県観光連盟 のページを開く", "Open on 福岡県観光連盟")])
        XCTAssertEqual(s.accessibilityLabel, L("作例の写真（写真提供：福岡県観光連盟）", "Example photo by 福岡県観光連盟"))
        // modified が無ければ最後に添えない。credit が無ければ「写真: 作者」
        let plain = try XCTUnwrap(try body(samples: "[\(hostedSample(["modified": nil, "credit": 3]))]").samples.first)
        XCTAssertEqual(plain.credit, L("浮羽稲荷神社 / 写真: 福岡県観光連盟 / クロスロードふくおか フォトダウンロード利用規約 / 福岡県観光連盟",
                                       "浮羽稲荷神社 / Photo: 福岡県観光連盟 / クロスロードふくおか フォトダウンロード利用規約 / 福岡県観光連盟"))
        // Commons・Flickr の1枚に credit が付いていても使わない（その他の出どころだけ）
        let commons = try XCTUnwrap(try body(samples: "[\(sample(["credit": "x", "modified": "y"]))]").samples.first)
        XCTAssertFalse(commons.credit.contains(" / x"))
        XCTAssertFalse(commons.credit.hasSuffix(" / y"))
    }

    /// 規約の文面が写真のページに載っている提供元（licenseUrl＝写真のページ）は、メニューの行き先を1つにする
    func testHostedLicenseOnPhotoPageHasOneLink() throws {
        let page = "https://yamaguchi-tourism.jp/photo/9"
        let s = try XCTUnwrap(try body(samples: "[\(hostedSample(["licenseUrl": page, "sourceUrl": page, "source": ["name": "山口県観光連盟", "url": page]]))]").samples.first)
        XCTAssertEqual(s.creditLinks.map(\.url.absoluteString), [page])
        XCTAssertEqual(Set(s.creditLinks.map(\.id)).count, s.creditLinks.count, "メニューの id が重ならない")
    }

    /// 注記は自由なライセンス（Commons・Flickr）と規約に従う提供元を分けて書く（Web と同じ）
    func testNoteSeparatesHostedSources() throws {
        let mixed = try body(samples: "[\(sample()),\(hostedSample())]").samples
        XCTAssertEqual(SpotSampleText.note(mixed),
                       L("この場所の近くで撮られ、Wikimedia Commons で自由なライセンスのもと公開されている写真です。福岡県観光連盟の写真は、提供元の利用規約に従って掲載しています。撮影者はこのアプリの利用者ではありません。",
                         "Photos taken near this spot and published under free licenses on Wikimedia Commons. Photos from 福岡県観光連盟 are shown under the provider's terms of use. The photographers are not members of this app."))
        let hostedOnly = try body(samples: "[\(hostedSample())]").samples
        XCTAssertEqual(SpotSampleText.note(hostedOnly),
                       L("福岡県観光連盟の写真は、提供元の利用規約に従って掲載しています。撮影者はこのアプリの利用者ではありません。",
                         "Photos from 福岡県観光連盟 are shown under the provider's terms of use. The photographers are not members of this app."))
        XCTAssertEqual(SpotSampleText.heading(hostedOnly), L("作例（福岡県観光連盟 より）", "Example photos (from 福岡県観光連盟)"))
    }
}
