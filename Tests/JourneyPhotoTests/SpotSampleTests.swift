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

    /// `source` が無い・形が壊れているときは今まで通り Commons。2つ以外の名前の1枚は落とす（Web と同じ）
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
        for name in ["Instagram", "flickr", ""] {
            XCTAssertEqual(try body(samples: "[\(sample(["source": ["name": name, "url": flickrPage]]))]").samples, [], name)
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
}
