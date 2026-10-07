import Foundation

/// 撮影スポットの**作例**（Wikimedia Commons の自由に使える写真・2026-10-03）。
///
/// 本文 JSON（`/app/data/spots/<slug>.json`・`SpotBody.samples`）の `samples` の1枚。
/// 形は Web の `lib/data/spotSamples.ts` の `SpotSample`、決まりは photo-gallery の
/// `docs/spot-samples-commons.md`。
///
/// 🔴 **題・作者・ライセンス・出典を必ず一緒に出す**（CC BY・CC BY-SA の表示条件）。
/// どれかが欠けた1枚は、ここで落とす——画面が表示を忘れる余地を作らない。
///
/// 2026-10-03 判断: Web は配る前に `toSpotSample` で落としているが、**アプリでも同じ規則で
/// もう一度落とす**（本文 JSON が手で直された・古い版が残った、でも守れるように）。
/// 移したのは `toSpotSample` の規則のうち、本文 JSON に載る項目で見られるもの:
///   - ライセンスが CC0・パブリックドメイン・CC BY・CC BY-SA でない（NC・ND・その他）→ 落とす
///     （`sampleLicenseKind` ＝ Web の `sampleLicenseKind`＋`coverLicenseOf`）
///   - アメリカだけのパブリックドメイン（PD-US 系）→ 落とす（`isUsOnlyPublicDomain`）
///   - 作者が空・決まり文句・お願い文 → CC BY 系は落とす。パブリックドメイン・CC0 は
///     Web が「作者不明」に替えて配るので、そのまま出す（`isPlaceholderAuthor`）
///   - 画像が Commons の**縮小版**でない・出典が Commons のファイルのページでない → 落とす
///     （元画像は EXIF の位置情報が残るので表示に使わない。Web は縮小版に替えて配る）
///   - CC BY 系なのにライセンスの文面の URL が無い → 落とす
///   - 題が空・縦横が無い → 落とす
/// 移していないもの: 人物の権利の印（`personality`）・人や催しの語（`EVENT_OR_PERSON`）は
/// 本文 JSON に載らない項目で決まるので、Web の側だけで落とす。
///
/// 2026-10-04 判断: **Commons 以外の出どころ（まず Flickr）にも対応**（photo-gallery #286 の
/// `toFlickrSample` と同じ規則）。サーバーは Commons 以外のときだけ1枚に
/// `source: {"name": "Flickr", "url": <写真のページ>}` を足す。
///   - `source` が無い・形が壊れている（オブジェクトでない）→ 今まで通り Commons
///   - `name` が空 → 落とす
///   - Flickr: ライセンスは CC BY・CC BY-SA・CC0 だけ（パブリックドメインは出さない）、出典は
///     `source.url`（`https://www.flickr.com/photos/<人>/<写真ID>/`）、画像は
///     `https://live.staticflickr.com/<server>/<写真ID>_<secret>[_<大きさ>].jpg|png` で、2つの写真ID が同じ。
///     Web より1つ厳しく、元画像（大きさ `_o`）は落とす（EXIF の位置情報が残りうる）
///   - 2026-10-04 判断（方針変更）: **その他の出どころ**（環境省・県の観光連盟など。画像は
///     journey-photo.com/samples/… に自前で置く）も受け入れる。名前はサーバーの文字のまま出典の行と
///     メニュー（「<名前> のページを開く」）に出す。画像・出典のページは https なら可（作り替えない）、
///     ライセンスは文字のまま出す（"PDL1.0" など。Commons の種類の判定は使わない）。ただし
///     NC・ND と読める書き方・作者が空や決まり文句の1枚は、どの出どころでも落とす
///   - 2026-10-04（photo-gallery #290）: その他の出どころは `credit`（規約が求める出典の文・例
///     「写真提供：福岡県観光連盟」）と `modified`（加工の表記）を持つことがある。出典の行は
///     「題 / credit（無ければ 写真: 作者）/ ライセンス（文面へ）/ 提供元（写真のページへ）/ modified」。
///     `termsUrl`（規約のページ）は Web の構造化データ用で、アプリの画面には出さない（読まない）
/// "Flickr"・"Wikimedia Commons" は大文字・小文字を問わずそろえ、その出どころの検査を必ず通す
/// （綴りを変えて Flickr の検査を抜けられないように）。
struct SpotSample: Equatable, Identifiable {
    /// 表示に使う Commons の縮小版（upload.wikimedia.org/…/thumb/…）
    let src: URL
    let width: Double
    let height: Double
    /// 題（Commons のファイル名から "File:" と拡張子を除いたもの）
    let title: String
    let author: String
    /// Commons の短い名前（例 "CC BY-SA 4.0"）
    let license: String
    /// ライセンスの文面。パブリックドメインなど URL の無いものは nil
    let licenseUrl: URL?
    /// その写真のページ（出典。Commons ならファイルのページ、Flickr なら写真のページ）
    let sourceUrl: URL
    /// 出どころ（無ければ Commons・2026-10-04）
    var origin: Origin = .commons
    /// 規約が求める出典の文（その他の出どころだけ）。あれば「写真: 作者」の代わりにそのまま出す
    var creditText: String? = nil
    /// 加工の表記（その他の出どころで縮小したとき）。あれば出典の行の最後に添える
    var modified: String? = nil
    /// 撮った年と月（本文の `takenAt`＝撮影日の文字。書き方が混在するので、読めなければ nil・2026-10-07）。
    /// ホームの「いまの季節のスポット」が、季節の合う作例を選ぶのに使う（`HomeSpotShelf.picture`）
    var takenAt: TakenAt? = nil

    /// 撮った年と月（`takenAt` の読み取り結果）
    struct TakenAt: Equatable {
        let year: Int
        let month: Int

        /// 季節（`SpotBodyText.season`）。**南半球（緯度が負）は半年ずらす**——その土地の季節
        /// （`ShootingTime.season(of:)` と同じ読み替え）
        func season(southern: Bool) -> String {
            let season = SpotBodyText.season(ofMonth: month)
            guard southern, let s = ShootingTime.Season(rawValue: season) else { return season }
            return s.opposite.rawValue
        }

        private static let englishMonths = ["january", "february", "march", "april", "may", "june", "july",
                                            "august", "september", "october", "november", "december"]

        /// 本文の `takenAt` を読む（2026-10-07 に本番の本文で見た書き方）:
        ///   - `2013-08-03`・`2009-10-21 16:24:00`・`2016-02`・`2009/09/21…`（年-月 が先頭）
        ///   - `2009年8月16日`・`2011年4月15日, 14:12:03`
        ///   - `Taken on 12 August 2011`・`10 February 2024 (according to Exif data)`
        /// 2026-10-07 判断: 「〜より前」「before」は**その日より前のどこか**で月が決まらないので nil。
        /// 年だけ（`2017`）・和暦（`H20-4`）も nil（季節を当てない）
        static func parse(_ raw: String?) -> TakenAt? {
            let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty, !text.contains("より前"),
                  text.range(of: "before", options: .caseInsensitive) == nil else { return nil }
            if let g = groups(text, #"^(\d{4})\s*[-/]\s*(\d{1,2})(?!\d)"#) {
                return make(year: Int(g[0]), month: Int(g[1]))
            }
            if let g = groups(text, #"(\d{4})\s*年\s*(\d{1,2})\s*月"#) {
                return make(year: Int(g[0]), month: Int(g[1]))
            }
            let names = englishMonths.joined(separator: "|")
            if let g = groups(text, #"(?<!\d)\d{1,2}\s+("# + names + #")\s+(\d{4})"#) {
                return make(year: Int(g[1]), month: (englishMonths.firstIndex(of: g[0].lowercased()) ?? -1) + 1)
            }
            if let g = groups(text, #"("# + names + #")\s+\d{1,2},?\s+(\d{4})"#) {
                return make(year: Int(g[1]), month: (englishMonths.firstIndex(of: g[0].lowercased()) ?? -1) + 1)
            }
            return nil
        }

        private static func make(year: Int?, month: Int?) -> TakenAt? {
            guard let year, let month, (1...12).contains(month), (1800...2100).contains(year) else { return nil }
            return TakenAt(year: year, month: month)
        }

        /// かっこの中身（大文字・小文字を問わない）
        private static func groups(_ s: String, _ pattern: String) -> [String]? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
            return (1..<m.numberOfRanges).map { i in Range(m.range(at: i), in: s).map { String(s[$0]) } ?? "" }
        }
    }

    /// 作例の出どころ。名前は出典の行の最後とメニューに出す
    enum Origin: Equatable {
        case commons, flickr
        /// その他（環境省・県の観光連盟など）。名前はサーバーの文字（前後の空白を除く）
        case other(String)

        var name: String {
            switch self {
            case .commons: return "Wikimedia Commons"
            case .flickr: return "Flickr"
            case .other(let name): return name
            }
        }

        /// サーバーの `source.name` から。空は nil（その1枚は落とす）
        static func named(_ raw: String?) -> Origin? {
            let name = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            switch name.lowercased() {
            case "": return nil
            case "wikimedia commons": return .commons
            case "flickr": return .flickr
            default: return .other(name)
            }
        }
    }

    var id: URL { sourceUrl }

    /// 縦横比（幅 ÷ 高さ）
    var aspectRatio: Double { width / height }

    /// 1枚に出す最大の枚数（Web の `MAX_SHOWN_SAMPLES`）
    static let maxShown = 6

    /// Commons が作り置きする縮小版の幅（Web の `STANDARD_THUMB_WIDTHS`。任意の幅は作り置きが無い）
    static let standardThumbWidths = [1280, 960, 500, 330, 250]

    /// **小さく出す場所向けの、同じ写真の小さい縮小版**（2026-10-03・ホームの「いまの季節のスポット」）。
    ///
    /// 2026-10-04: **Commons の縮小版の名前を前提にした作り替え**なので、Commons 以外（Flickr）は
    /// `src` のまま（Flickr の URL の綴りは違い、作り替えると別の画像・存在しない URL になりうる）。
    ///
    /// 本文の `src` はたいてい 1280px の縮小版で、幅 240pt の札には重い（1枚 数百KB）。
    /// URL の末尾 `<幅>px-<名前>` の幅だけを、`maxWidth` 以下でいちばん大きい標準の幅に替える。
    /// **同じ Commons の縮小版**なので改変ではなく、元画像（EXIF が残る）にも戻らない。
    /// いまの幅が `maxWidth` 以下・形が違う（縮小版の名前でない）ときは `src` のまま
    func thumbnail(maxWidth: Int) -> URL {
        guard origin == .commons, width > Double(maxWidth),
              let target = Self.standardThumbWidths.first(where: { $0 <= maxWidth && Double($0) < width }) else { return src }
        // **文字列のまま替える**（`lastPathComponent` は %xx をほどくので、組み直すと綴りが変わりうる）
        let raw = src.absoluteString
        guard let slash = raw.range(of: "/", options: .backwards) else { return src }
        let name = raw[slash.upperBound...]
        guard let dash = name.range(of: "px-"),
              let current = Int(name[name.startIndex..<dash.lowerBound]), current > target else { return src }
        return URL(string: raw[..<slash.upperBound] + "\(target)px-" + name[dash.upperBound...]) ?? src
    }

    // MARK: - 表示の文

    /// 写真のすぐ下の1行「題 / 写真: 作者 / ライセンス / 出どころ」（Web の `Samples` と同じ並び。
    /// 出どころは `origin.name`＝「Wikimedia Commons」「Flickr」「福岡県観光連盟」など）。
    /// その他の出どころは「写真: 作者」の代わりに `creditText`、最後に `modified` を添える
    var credit: String {
        String(linkedCredit.characters)
    }

    /// 「写真: 作者」の部分（`creditText` があればそれ）
    private var byline: String {
        creditText ?? "\(L("写真: ", "Photo: "))\(author)"
    }

    /// `credit` と**同じ文字のまま**、ライセンス → 文面・出どころの名前 → その写真のページ に
    /// リンクを付けたもの（Web と同じリンク先）
    var linkedCredit: AttributedString {
        var licensePart = AttributedString(license)
        licensePart.link = licenseUrl
        var source = AttributedString(origin.name)
        source.link = sourceUrl
        return AttributedString("\(title) / \(byline) / ")
            + licensePart + AttributedString(" / ") + source
            + AttributedString(modified.map { " / \($0)" } ?? "")
    }

    /// 出典の1行から開ける先（並びは文字の並びと同じ: ライセンス → 出どころのページ）。
    /// 文面の URL の無いライセンス（パブリックドメイン・CC0）は出どころのページだけ（`CreditLink` の注記）
    /// 規約の文面が写真のページに載っている提供元（Web は licenseUrl＝写真のページで配る）は、同じ行き先が
    /// 2つ並ぶ（メニューの id も重なる）ので、写真のページの1つだけにする（2026-10-04）
    var creditLinks: [CreditLink] {
        let licenseLinks = licenseUrl.flatMap { $0 == sourceUrl ? nil : [CreditLink.license(license, url: $0)] } ?? []
        return licenseLinks + [CreditLink.sourcePage(origin.name, url: sourceUrl)]
    }

    /// 写真の読み上げ名（Web の alt と同じ。規約の出典の文があればそれ）
    var accessibilityLabel: String {
        L("作例の写真（\(creditText ?? "撮影: \(author)")）", "Example photo by \(author)")
    }

    // MARK: - 読み込み

    /// 本文 JSON の1枚の生の形（壊れた1枚は `Lenient` が落とす）
    struct Raw: Decodable {
        let src: String?
        let width: Double?
        let height: Double?
        let title: String?
        let author: String?
        let license: String?
        let licenseUrl: String?
        let sourceUrl: String?
        /// 出どころ（任意・2026-10-04）。壊れた形でも1枚ごとは落とさない
        let source: Source?
        /// 規約が求める出典の文・加工の表記（その他の出どころだけ・任意。壊れた形は無いものとみなす）
        let credit: String?
        let modified: String?
        /// 撮影日（任意・書き方が混在・2026-10-07）。壊れた形は無いものとみなす
        let takenAt: String?

        struct Source: Decodable {
            let name: String?
            let url: String?
        }

        /// 他の項目は今まで通り（型が違えば1枚ごと落ちる）。`source` だけは壊れていても nil にする
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            src = try c.decodeIfPresent(String.self, forKey: .src)
            width = try c.decodeIfPresent(Double.self, forKey: .width)
            height = try c.decodeIfPresent(Double.self, forKey: .height)
            title = try c.decodeIfPresent(String.self, forKey: .title)
            author = try c.decodeIfPresent(String.self, forKey: .author)
            license = try c.decodeIfPresent(String.self, forKey: .license)
            licenseUrl = try c.decodeIfPresent(String.self, forKey: .licenseUrl)
            sourceUrl = try c.decodeIfPresent(String.self, forKey: .sourceUrl)
            source = (try? c.decodeIfPresent(Source.self, forKey: .source)) ?? nil
            credit = (try? c.decodeIfPresent(String.self, forKey: .credit)) ?? nil
            modified = (try? c.decodeIfPresent(String.self, forKey: .modified)) ?? nil
            takenAt = (try? c.decodeIfPresent(String.self, forKey: .takenAt)) ?? nil
        }

        private enum CodingKeys: String, CodingKey {
            case src, width, height, title, author, license, licenseUrl, sourceUrl, source, credit, modified, takenAt
        }
    }

    /// 出どころを決める。`source` が無い・形が壊れている → Commons。知らない名前 → nil（落とす）
    static func origin(of source: Raw.Source?) -> Origin? {
        guard let source else { return .commons }
        return Origin.named(source.name)
    }

    enum LicenseKind: Equatable { case cc0, publicDomain, ccBy, ccBySA }

    /// 生の1枚を表示の形へ。**出してはいけない1枚は nil**（規則は型の注記）
    static func make(_ raw: Raw) -> SpotSample? {
        guard let origin = origin(of: raw.source) else { return nil }
        let license = trimmed(raw.license)
        if case .other = origin { return makeOther(raw, origin: origin, license: license) }
        guard let kind = sampleLicenseKind(license), !isUsOnlyPublicDomain(license) else { return nil }
        let byLicense = kind == .ccBy || kind == .ccBySA
        let author = trimmed(raw.author)
        // 作者が名前でない1枚は、CC BY 系なら出せない（作者表示が使う条件）。
        // パブリックドメイン・CC0 でも空は出さない（Web は「作者不明」を入れて配る）
        if author.isEmpty || (byLicense && isPlaceholderAuthor(author)) { return nil }
        let title = trimmed(raw.title)
        guard !title.isEmpty else { return nil }
        // Flickr はパブリックドメイン（Public Domain Mark など）を出さない（Web の `toFlickrSample`）
        if origin == .flickr && kind == .publicDomain { return nil }
        guard let src = https(raw.src), let source = pageURL(raw, origin: origin), isAllowed(src: src, page: source, origin: origin),
              let width = raw.width, let height = raw.height, width > 0, height > 0,
              width.isFinite, height.isFinite else { return nil }
        let licenseUrl = https(raw.licenseUrl)
        if byLicense && licenseUrl == nil { return nil }
        return SpotSample(src: src, width: width, height: height, title: title, author: author,
                          license: license, licenseUrl: licenseUrl, sourceUrl: source, origin: origin,
                          takenAt: TakenAt.parse(raw.takenAt))
    }

    /// その他の出どころの1枚（型の注記）。ライセンスは文字のまま・画像と出典のページは https なら可
    private static func makeOther(_ raw: Raw, origin: Origin, license: String) -> SpotSample? {
        let author = trimmed(raw.author), title = trimmed(raw.title)
        guard !license.isEmpty, !matches(license.replacingOccurrences(of: "-", with: " "), #"\bnc\b|\bnd\b"#),
              !isPlaceholderAuthor(author), !title.isEmpty,
              let src = https(raw.src), let source = https(raw.source?.url),
              let width = raw.width, let height = raw.height, width > 0, height > 0,
              width.isFinite, height.isFinite else { return nil }
        let creditText = trimmed(raw.credit), modified = trimmed(raw.modified)
        return SpotSample(src: src, width: width, height: height, title: title, author: author,
                          license: license, licenseUrl: https(raw.licenseUrl), sourceUrl: source, origin: origin,
                          creditText: creditText.isEmpty ? nil : creditText, modified: modified.isEmpty ? nil : modified,
                          takenAt: TakenAt.parse(raw.takenAt))
    }

    /// 本文 JSON の `samples` を読む。壊れた・出せない1枚だけ落とし、同じ出典の2枚目も落とす。最大6枚
    static func list(_ raws: [Raw]) -> [SpotSample] {
        var seen = Set<URL>()
        var out: [SpotSample] = []
        for raw in raws {
            guard let sample = make(raw), seen.insert(sample.sourceUrl).inserted else { continue }
            out.append(sample)
            if out.count >= maxShown { break }
        }
        return out
    }

    /// ライセンスの種類（Web の `sampleLicenseKind` → `coverLicenseOf`）。
    /// "CC BY-SA 4.0" と "CC-BY-SA-3.0" の両方の書き方をそろえてから判定する。
    /// **NC（商用不可）・ND（改変不可）は、どの書き方でも先に落とす**。その他は nil
    static func sampleLicenseKind(_ label: String) -> LicenseKind? {
        var s = label.trimmingCharacters(in: .whitespacesAndNewlines)
        s = replacing(s, #"^cc[-\s]by[-\s]sa(?=[-\s]|$)"#, with: "CC BY-SA")
        s = replacing(s, #"^cc[-\s]by(?=[-\s]|$)"#, with: "CC BY")
        s = s.lowercased()
        if matches(s.replacingOccurrences(of: "-", with: " "), #"\bnc\b|\bnd\b"#) { return nil }
        if matches(s, #"^cc0\b"#) { return .cc0 }
        if s == "public domain" || s == "pd" || matches(s, #"^pd[-\s]"#) { return .publicDomain }
        if matches(s, #"^cc by-sa\b"#) { return .ccBySA }
        if matches(s, #"^cc by\b"#) { return .ccBy }
        return nil
    }

    /// アメリカだけのパブリックドメイン（Web の `isUsOnlyPublicDomain`）。日本では保護期間内のことがある
    static func isUsOnlyPublicDomain(_ license: String) -> Bool {
        matches(license, #"\bpd[-\s]?us|pd[-\s]?usgov|public domain in the united states"#)
    }

    /// 名前ではない作者の欄か（Web の `isPlaceholderAuthor`・同じ語の並び・80字超も名前とみなさない）
    static func isPlaceholderAuthor(_ author: String) -> Bool {
        let a = author.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty || a.count > 80 { return true }
        return matches(a, placeholderAuthor)
    }

    private static let placeholderAuthor = [
        "推定されます", "コンピュータが読み取れる", "投稿者自身", "自分で撮影", "作者不明", "^不明", "お願い",
        "own work", "unknown author", "^unknown$", "anonymous", "please", "feel free", "i would appreciate",
        "credit (me|its author)", "this (image|photo|picture) (is|was)", "you are free", "want to use this image",
        "wikimedia commons user", #"\((utc|est|cet)\)"#, "^author$",
    ].joined(separator: "|")

    // MARK: - 小さな道具

    private static func trimmed(_ s: String?) -> String {
        s?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// 出典のページ。Commons は `sourceUrl`、Flickr は `source.url`（Web は同じ値を両方に入れる）
    private static func pageURL(_ raw: Raw, origin: Origin) -> URL? {
        switch origin {
        case .commons: return https(raw.sourceUrl)
        case .flickr, .other: return https(raw.source?.url)
        }
    }

    /// 画像と出典のページの形。Commons は縮小版とファイルのページ（元画像は EXIF の位置情報が残る）。
    /// Flickr は live.staticflickr.com の画像と写真のページで、写真ID が同じもの（元画像 `_o` は落とす）
    private static func isAllowed(src: URL, page: URL, origin: Origin) -> Bool {
        let srcRaw = src.absoluteString, pageRaw = page.absoluteString
        switch origin {
        case .commons:
            return srcRaw.hasPrefix("https://upload.wikimedia.org/wikipedia/commons/thumb/")
                && pageRaw.hasPrefix("https://commons.wikimedia.org/wiki/File:")
        case .flickr:
            guard let pageId = firstGroup(pageRaw, #"^https://www\.flickr\.com/photos/[A-Za-z0-9@_-]+/(\d+)/?$"#),
                  let imageId = firstGroup(srcRaw, #"^https://live\.staticflickr\.com/\d+/(\d+)_[0-9a-f]+(?:_[a-z0-9]{1,2})?\.(?:jpe?g|png)$"#),
                  pageId == imageId else { return false }
            return !matches(srcRaw, #"_o\.(?:jpe?g|png)$"#)
        case .other:
            return true
        }
    }

    /// 正規表現の最初のかっこの中身（大文字・小文字は区別する）
    private static func firstGroup(_ s: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    /// http は https に上げる（Web の `toSpotSample` と同じ）。空・それ以外の形は nil
    private static func https(_ raw: String?) -> URL? {
        LenientSpotImage.httpsURL(raw)
    }

    private static func matches(_ s: String, _ pattern: String) -> Bool {
        s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func replacing(_ s: String, _ pattern: String, with replacement: String) -> String {
        s.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
    }
}

/// 作例の節の言葉と大きさ（画面 `OfficialSpotView.samplesSection` が使う・Web の `Samples` と同じ言葉）
enum SpotSampleText {
    /// 見出しと注記で名乗る出どころ（2026-10-04・Web の `Samples` と同じ）。**出ている写真の分だけ**、
    /// Commons が先、日本語は「・」・英語は " and " でつなぐ。1枚も無ければ Commons
    static func sourceNames(_ samples: [SpotSample]) -> String {
        var origins: [SpotSample.Origin] = []
        for sample in samples where !origins.contains(sample.origin) { origins.append(sample.origin) }
        origins = origins.filter { $0 == .commons } + origins.filter { $0 != .commons }
        let names = (origins.isEmpty ? [.commons] : origins).map(\.name)
        return names.joined(separator: L("・", " and "))
    }

    /// 節の見出し（docs/spot-samples-commons.md の決まり）。Commons だけなら「作例（Wikimedia Commons より）」
    static func heading(_ samples: [SpotSample]) -> String {
        let from = sourceNames(samples)
        return L("作例（\(from) より）", "Example photos (from \(from))")
    }

    /// 見出しの下の注記。撮影者はこのアプリの利用者ではないと添える（決まり）。
    /// 自由なライセンスの出どころ（Commons・Flickr）と、規約に従って載せる提供元（その他）を分けて書く
    /// （後者は「自由なライセンス」ではない・Web の `Samples` と同じ・2026-10-04）
    static func note(_ samples: [SpotSample]) -> String {
        var free: [SpotSample] = [], hosted: [SpotSample] = []
        for s in samples {
            if case .other = s.origin { hosted.append(s) } else { free.append(s) }
        }
        let freePart = free.isEmpty && !hosted.isEmpty ? "" : {
            let from = sourceNames(free)
            return L("この場所の近くで撮られ、\(from) で自由なライセンスのもと公開されている写真です。",
                     "Photos taken near this spot and published under free licenses on \(from). ")
        }()
        let hostedPart = hosted.isEmpty ? "" : {
            let from = sourceNames(hosted)
            return L("\(from)の写真は、提供元の利用規約に従って掲載しています。",
                     "Photos from \(from) are shown under the provider's terms of use. ")
        }()
        return freePart + hostedPart + L("撮影者はこのアプリの利用者ではありません。", "The photographers are not members of this app.")
    }

    /// 帯の写真の高さ
    static let photoHeight: Double = 168
    /// 写真の幅の下限・上限（極端な縦長・横長でも帯が崩れないように。はみ出す分は余白を置き、**切り抜かない**）
    static let minWidth: Double = 120
    static let maxWidth: Double = 300

    /// 1枚の枠。高さをそろえ、幅は縦横比から（上下限の内側）
    static func frame(aspectRatio: Double) -> (width: Double, height: Double) {
        let ratio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1
        return (min(max(photoHeight * ratio, minWidth), maxWidth), photoHeight)
    }
}
