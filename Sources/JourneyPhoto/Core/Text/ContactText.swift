import Foundation

/// 字の中に**連絡先の形**（URL・メールアドレス・電話番号・LINE などの ID）があるか。
///
/// **2026-10-16 判断（owner の決定）**: すれちがいの自分で書く字（ひとこと・乗車券の発・着）は、電波で
/// 近くの見知らぬ人に署名なしで届くので、連絡先の形を受け付けない。既にあるコメント・自己紹介には同じ
/// 仕組みが無かった（探した）ので、ここに新しく作った。画面を持たない層なので Linux の `swift test` で確かめる。
///
/// 見方: 字を揃えてから（全角→半角・漢数字→数字・「ドット」「dot」→「.」・「アット」→「@」・小文字）、
/// - `http` / `://` / `www.`
/// - よくある終わり（`.com`・`.jp`…）の点つきの並び（点のまわりの空白は詰める）
/// - `@` を挟んだメールの形・`@` で始まる ID・「ID:」
/// - 数字が続けて 8 桁以上（間の `-`・`ー`・空白・`()`・`+`・`.` も続きとみなす）。**日付（2026.10.16 など）は先に外す**
///
/// ⚠️ **抜け道は残る**（言葉で言い換えた番号・珍しい終わりのドメイン・画像の中の字など）。止めるのは
/// 「うっかり・軽い気持ちで書く」形まで
enum ContactText {

    /// よくあるドメインの終わり（点の後）
    /// **強い終わり**: ふつうの単語と重ならない。点のまわりに空白があっても拾う（`abc . com`）
    static let strongDomains: Set<String> = [
        "com", "net", "org", "jp", "io", "ly", "gl", "xyz", "biz", "cn", "kr", "tw", "gg", "cc", "fm", "mobi", "jpn",
    ]
    /// **弱い終わり**: ふつうの単語と重なる（「Hi. Me too」「Kyoto. To Osaka」）。空白なしの `abc.me` 形だけ拾う。
    /// 2026-10-16 の読み直し: 英語の文の誤検知を減らした（「Osaka.Tokyo」も通すため tokyo・osaka は外した）
    static let weakDomains: Set<String> = [
        "co", "ne", "or", "me", "so", "be", "us", "la", "tv", "ai", "to", "uk", "info", "app", "dev", "link", "site",
        "online", "page", "shop", "top", "club", "blog", "work", "ink",
    ]
    static var topLevelDomains: Set<String> { strongDomains.union(weakDomains) }

    /// 判定にかける長さ（貼り付けた長い字で重くしない・欄の上限より十分長い）
    static let scanLimit = 200

    /// 電話番号とみなす数字の数
    static let phoneDigits = 8

    static func contains(_ text: String) -> Bool {
        let n = normalize(String(text.prefix(scanLimit)))
        guard !n.isEmpty else { return false }
        if n.contains("http") || n.contains("://") || n.contains("www.") { return true }
        if hasDomain(n) || hasEmailOrHandle(n) { return true }
        return hasPhone(n)
    }

    // MARK: - 揃える

    private static let kanjiDigits: [Character: Character] = [
        "〇": "0", "零": "0", "一": "1", "二": "2", "三": "3", "四": "4", "五": "5", "六": "6", "七": "7",
        "八": "8", "九": "9",
    ]

    /// 全角・漢数字・言い換えを揃えた小文字の字。
    ///
    /// **保存時に消える字は、判定の前に保存後と同じ形にする。** `PassExchange.cleanText` は
    /// ゼロ幅などの書式を落とし、改行・制御文字を空白にする。空白は電話番号の続きなので、
    /// 落とす前の字だけで見ると「090」と「12345」が改行やゼロ幅で切れて 8 桁に届かず、
    /// 保存したあとに「090 12345」「09012345」へ戻って連絡先になる。
    static func normalize(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for s in text.unicodeScalars {
            switch s.properties.generalCategory {
            case .format:
                continue
            case .control:
                scalars.append(" ")
            default:
                scalars.append(s)
            }
        }
        var s = String(scalars).precomposedStringWithCompatibilityMapping.lowercased()
        for (word, mark) in [("ドット", "."), ("どっと", "."), ("(dot)", "."), ("[dot]", "."), (" dot ", "."),
                             ("。", "."), ("、", ","), ("アットマーク", "@"), ("あっとまーく", "@"), ("アット", "@"),
                             ("あっと", "@"), ("(at)", "@"), ("[at]", "@")] {
            s = s.replacingOccurrences(of: word, with: mark)
        }
        // 「dot」が文字の間に挟まった形（abcdotcom）は、よくある終わりの前だけ点にする
        for tld in topLevelDomains {
            s = s.replacingOccurrences(of: "dot" + tld, with: "." + tld)
        }
        return String(s.map { kanjiDigits[$0] ?? $0 })
    }

    // MARK: - 形

    /// 点の前後に空白を許す並び（強い終わりだけに当てる）と、空白なしの並び（どちらの終わりにも当てる）
    private static let spacedDomainRegex = try! NSRegularExpression(pattern: #"[a-z0-9-]+\s*\.\s*([a-z]{2,8})(?![a-z])"#)
    private static let domainRegex = try! NSRegularExpression(pattern: #"[a-z0-9-]+\.([a-z]{2,8})(?![a-z])"#)
    private static let emailRegex = try! NSRegularExpression(pattern: #"[a-z0-9._%+-]+\s*@\s*[a-z0-9-]+"#)
    private static let handleRegex = try! NSRegularExpression(pattern: #"(^|[^a-z0-9])@\s*[a-z0-9._-]{3,}"#)
    private static let idRegex = try! NSRegularExpression(pattern: #"\bid\s*[:=]"#)
    /// 日付（年.月.日・年-月-日・年/月/日）。電話番号の数えから先に外す。**あり得る日付だけ**（年は 19xx・20xx か
    /// 2 桁、月 1〜12、日 1〜31）で、前後が数字や区切りに続かないときだけ（2026-10-16 の読み直し:
    /// 「+81-90-1234-5678」「090-12-34-5678」が日付として外れていた）
    private static let dateRegex = try! NSRegularExpression(
        pattern: #"(?<![0-9./+-])(?:(?:19|20)\d{2}|\d{2})([./-])(?:0?[1-9]|1[0-2])\1(?:0?[1-9]|[12]\d|3[01])(?![0-9./-])"#)
    /// 年の範囲（2016-2026・2016〜2026）。電話番号にしない
    private static let yearRangeRegex = try! NSRegularExpression(
        pattern: #"(?<![0-9])(?:19|20)\d{2}\s*[-~〜–]\s*(?:19|20)\d{2}(?![0-9])"#)

    private static func matches(_ regex: NSRegularExpression, _ s: String) -> [NSTextCheckingResult] {
        regex.matches(in: s, range: NSRange(s.startIndex..., in: s))
    }

    static func hasDomain(_ n: String) -> Bool {
        func ends(_ regex: NSRegularExpression, in set: Set<String>) -> Bool {
            matches(regex, n).contains { m in
                guard let r = Range(m.range(at: 1), in: n) else { return false }
                return set.contains(String(n[r]))
            }
        }
        return ends(domainRegex, in: topLevelDomains) || ends(spacedDomainRegex, in: strongDomains)
    }

    static func hasEmailOrHandle(_ n: String) -> Bool {
        !matches(emailRegex, n).isEmpty || !matches(handleRegex, n).isEmpty || !matches(idRegex, n).isEmpty
    }

    static func hasPhone(_ n: String) -> Bool {
        var s = n
        for regex in [dateRegex, yearRangeRegex] {
            for m in matches(regex, s).reversed() {
                // 外した所は数字の続きを切る字にする（前後の数字とつなげない）
                if let r = Range(m.range, in: s) { s.replaceSubrange(r, with: "|") }
            }
        }
        let separators: Set<Character> = ["-", "‐", "−", "ー", "—", " ", "(", ")", "+", ".", "・", "_"]
        var run = 0
        for ch in s {
            if ch.isASCII, ch.isNumber {
                run += 1
                if run >= phoneDigits { return true }
            } else if !separators.contains(ch) {
                run = 0
            }
        }
        return false
    }
}
