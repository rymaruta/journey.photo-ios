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
    /// Commons のファイルのページ（出典）
    let sourceUrl: URL

    var id: URL { sourceUrl }

    /// 縦横比（幅 ÷ 高さ）
    var aspectRatio: Double { width / height }

    /// 1枚に出す最大の枚数（Web の `MAX_SHOWN_SAMPLES`）
    static let maxShown = 6

    /// Commons が作り置きする縮小版の幅（Web の `STANDARD_THUMB_WIDTHS`。任意の幅は作り置きが無い）
    static let standardThumbWidths = [1280, 960, 500, 330, 250]

    /// **小さく出す場所向けの、同じ写真の小さい縮小版**（2026-10-03・ホームの「いまの季節のスポット」）。
    ///
    /// 本文の `src` はたいてい 1280px の縮小版で、幅 240pt の札には重い（1枚 数百KB）。
    /// URL の末尾 `<幅>px-<名前>` の幅だけを、`maxWidth` 以下でいちばん大きい標準の幅に替える。
    /// **同じ Commons の縮小版**なので改変ではなく、元画像（EXIF が残る）にも戻らない。
    /// いまの幅が `maxWidth` 以下・形が違う（縮小版の名前でない）ときは `src` のまま
    func thumbnail(maxWidth: Int) -> URL {
        guard width > Double(maxWidth),
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

    /// 写真のすぐ下の1行「題 / 写真: 作者 / ライセンス / Wikimedia Commons」（Web の `Samples` と同じ並び）
    var credit: String {
        "\(title) / \(L("写真: ", "Photo: "))\(author) / \(license) / Wikimedia Commons"
    }

    /// `credit` と**同じ文字のまま**、ライセンス → 文面・「Wikimedia Commons」→ ファイルのページ に
    /// リンクを付けたもの（Web と同じリンク先）
    var linkedCredit: AttributedString {
        var licensePart = AttributedString(license)
        licensePart.link = licenseUrl
        var source = AttributedString("Wikimedia Commons")
        source.link = sourceUrl
        return AttributedString("\(title) / \(L("写真: ", "Photo: "))\(author) / ")
            + licensePart + AttributedString(" / ") + source
    }

    /// 出典の1行から開ける先（並びは文字の並びと同じ: ライセンス → Wikimedia Commons）。
    /// 文面の URL の無いライセンス（パブリックドメイン・CC0）は Commons のページだけ（`CreditLink` の注記）
    var creditLinks: [CreditLink] {
        (licenseUrl.map { [CreditLink.license(license, url: $0)] } ?? []) + [CreditLink.commonsPage(sourceUrl)]
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
        guard !title.isEmpty,
              let src = https(raw.src), isCommonsThumb(src),
              let source = https(raw.sourceUrl), isCommonsPage(source),
              let width = raw.width, let height = raw.height, width > 0, height > 0,
              width.isFinite, height.isFinite else { return nil }
        let licenseUrl = https(raw.licenseUrl)
        if byLicense && licenseUrl == nil { return nil }
        return SpotSample(src: src, width: width, height: height, title: title, author: author,
                          license: license, licenseUrl: licenseUrl, sourceUrl: source)
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

    /// http は https に上げる（Web の `toSpotSample` と同じ）。空・それ以外の形は nil
    private static func https(_ raw: String?) -> URL? {
        LenientSpotImage.httpsURL(raw)
    }

    private static func isCommonsThumb(_ url: URL) -> Bool {
        url.absoluteString.hasPrefix("https://upload.wikimedia.org/wikipedia/commons/thumb/")
    }

    private static func isCommonsPage(_ url: URL) -> Bool {
        url.absoluteString.hasPrefix("https://commons.wikimedia.org/wiki/File:")
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
    /// 節の見出し（docs/spot-samples-commons.md の決まり）
    static var heading: String { L("作例（Wikimedia Commons より）", "Example photos (from Wikimedia Commons)") }

    /// 見出しの下の注記。撮影者はこのアプリの利用者ではないと添える（決まり）
    static var note: String {
        L("この場所の近くで撮られ、Wikimedia Commons で自由なライセンスのもと公開されている写真です。撮影者はこのアプリの利用者ではありません。",
          "Photos taken near this spot and published under free licenses on Wikimedia Commons. The photographers are not members of this app.")
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
