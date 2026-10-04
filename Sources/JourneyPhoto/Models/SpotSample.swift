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
///   - `name` が "Flickr"・"Wikimedia Commons" のどちらでもない → 落とす（Web と同じ）
///   - Flickr: ライセンスは CC BY・CC BY-SA・CC0 だけ（パブリックドメインは出さない）、出典は
///     `source.url`（`https://www.flickr.com/photos/<人>/<写真ID>/`）、画像は
///     `https://live.staticflickr.com/<server>/<写真ID>_<secret>[_<大きさ>].jpg|png` で、2つの写真ID が同じ。
///     Web より1つ厳しく、元画像（大きさ `_o`）は落とす（EXIF の位置情報が残りうる）
/// 出典の行・メニューに出す名前は `Origin.name`（サーバーの文字をそのまま出さない）。
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

    /// 作例の出どころ。名前は出典の行の最後とメニューに出す
    enum Origin: Equatable {
        case commons, flickr

        var name: String {
            switch self {
            case .commons: return "Wikimedia Commons"
            case .flickr: return "Flickr"
            }
        }

        /// サーバーの `source.name` から（Web の `sampleSourceName` と同じく2つの名前だけ）。知らない名前は nil
        static func named(_ raw: String?) -> Origin? {
            switch raw?.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "Wikimedia Commons": return .commons
            case "Flickr": return .flickr
            default: return nil
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
    /// 出どころは `origin.name`＝「Wikimedia Commons」「Flickr」）
    var credit: String {
        "\(title) / \(L("写真: ", "Photo: "))\(author) / \(license) / \(origin.name)"
    }

    /// `credit` と**同じ文字のまま**、ライセンス → 文面・出どころの名前 → その写真のページ に
    /// リンクを付けたもの（Web と同じリンク先）
    var linkedCredit: AttributedString {
        var licensePart = AttributedString(license)
        licensePart.link = licenseUrl
        var source = AttributedString(origin.name)
        source.link = sourceUrl
        return AttributedString("\(title) / \(L("写真: ", "Photo: "))\(author) / ")
            + licensePart + AttributedString(" / ") + source
    }

    /// 出典の1行から開ける先（並びは文字の並びと同じ: ライセンス → 出どころのページ）。
    /// 文面の URL の無いライセンス（パブリックドメイン・CC0）は出どころのページだけ（`CreditLink` の注記）
    var creditLinks: [CreditLink] {
        (licenseUrl.map { [CreditLink.license(license, url: $0)] } ?? []) + [CreditLink.sourcePage(origin.name, url: sourceUrl)]
    }

    /// 写真の読み上げ名（Web の alt と同じ）
    var accessibilityLabel: String {
        L("作例の写真（撮影: \(author)）", "Example photo by \(author)")
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
        }

        private enum CodingKeys: String, CodingKey {
            case src, width, height, title, author, license, licenseUrl, sourceUrl, source
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
        let license = trimmed(raw.license)
        guard let kind = sampleLicenseKind(license), !isUsOnlyPublicDomain(license) else { return nil }
        let byLicense = kind == .ccBy || kind == .ccBySA
        let author = trimmed(raw.author)
        // 作者が名前でない1枚は、CC BY 系なら出せない（作者表示が使う条件）。
        // パブリックドメイン・CC0 でも空は出さない（Web は「作者不明」を入れて配る）
        if author.isEmpty || (byLicense && isPlaceholderAuthor(author)) { return nil }
        let title = trimmed(raw.title)
        guard !title.isEmpty, let origin = origin(of: raw.source) else { return nil }
        // Flickr はパブリックドメイン（Public Domain Mark など）を出さない（Web の `toFlickrSample`）
        if origin == .flickr && kind == .publicDomain { return nil }
        guard let src = https(raw.src), let source = pageURL(raw, origin: origin), isAllowed(src: src, page: source, origin: origin),
              let width = raw.width, let height = raw.height, width > 0, height > 0,
              width.isFinite, height.isFinite else { return nil }
        let licenseUrl = https(raw.licenseUrl)
        if byLicense && licenseUrl == nil { return nil }
        return SpotSample(src: src, width: width, height: height, title: title, author: author,
                          license: license, licenseUrl: licenseUrl, sourceUrl: source, origin: origin)
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
        case .flickr: return https(raw.source?.url)
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
        origins.sort { $0 == .commons && $1 != .commons }
        let names = (origins.isEmpty ? [.commons] : origins).map(\.name)
        return names.joined(separator: L("・", " and "))
    }

    /// 節の見出し（docs/spot-samples-commons.md の決まり）。Commons だけなら「作例（Wikimedia Commons より）」
    static func heading(_ samples: [SpotSample]) -> String {
        let from = sourceNames(samples)
        return L("作例（\(from) より）", "Example photos (from \(from))")
    }

    /// 見出しの下の注記。撮影者はこのアプリの利用者ではないと添える（決まり）
    static func note(_ samples: [SpotSample]) -> String {
        let from = sourceNames(samples)
        return L("この場所の近くで撮られ、\(from) で自由なライセンスのもと公開されている写真です。撮影者はこのアプリの利用者ではありません。",
                 "Photos taken near this spot and published under free licenses on \(from). The photographers are not members of this app.")
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
