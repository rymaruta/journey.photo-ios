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

    func testHeadingAndNote() {
        XCTAssertEqual(SpotSampleText.heading, L("作例（Wikimedia Commons より）", "Example photos (from Wikimedia Commons)"))
        XCTAssertTrue(SpotSampleText.note.contains(L("利用者ではありません", "not members")))
    }

    /// 帯の枠は高さをそろえ、幅は縦横比から（極端なものは上下限で止め、切り抜かない）
    func testFrameKeepsAspectWithinBounds() {
        XCTAssertEqual(SpotSampleText.frame(aspectRatio: 1.5).width, 252)
        XCTAssertEqual(SpotSampleText.frame(aspectRatio: 0.2).width, SpotSampleText.minWidth)
        XCTAssertEqual(SpotSampleText.frame(aspectRatio: 5).width, SpotSampleText.maxWidth)
        XCTAssertEqual(SpotSampleText.frame(aspectRatio: .nan).width, SpotSampleText.photoHeight)
        XCTAssertEqual(SpotSampleText.frame(aspectRatio: 1).height, SpotSampleText.photoHeight)
    }
}
