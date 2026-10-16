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
    static let topLevelDomains: Set<String> = [
        "com", "net", "org", "jp", "co", "ne", "or", "me", "io", "info", "biz", "xyz", "app", "dev", "ly", "gl",
        "link", "site", "online", "tv", "us", "uk", "cn", "kr", "tw", "page", "shop", "top", "to", "cc", "be",
        "fm", "la", "ai", "so", "gg", "mobi", "tokyo", "osaka", "club", "blog", "work", "ink", "jpn",
    ]

    /// 電話番号とみなす数字の数
    static let phoneDigits = 8

    static func contains(_ text: String) -> Bool {
        let n = normalize(text)
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

    /// 全角・漢数字・言い換えを揃えた小文字の字
    static func normalize(_ text: String) -> String {
        var s = text.precomposedStringWithCompatibilityMapping.lowercased()
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

    private static let domainRegex = try! NSRegularExpression(pattern: #"[a-z0-9-]+\s*\.\s*([a-z]{2,8})(?![a-z])"#)
    private static let emailRegex = try! NSRegularExpression(pattern: #"[a-z0-9._%+-]+\s*@\s*[a-z0-9-]+"#)
    private static let handleRegex = try! NSRegularExpression(pattern: #"(^|[^a-z0-9])@\s*[a-z0-9._-]{3,}"#)
    private static let idRegex = try! NSRegularExpression(pattern: #"\bid\s*[:=]"#)
    /// 日付（年.月.日・年-月-日・年/月/日・月/日）。電話番号の数えから先に外す
    private static let dateRegex = try! NSRegularExpression(
        pattern: #"\d{2,4}\s*[./-]\s*\d{1,2}\s*[./-]\s*\d{1,2}"#)

    private static func matches(_ regex: NSRegularExpression, _ s: String) -> [NSTextCheckingResult] {
        regex.matches(in: s, range: NSRange(s.startIndex..., in: s))
    }

    static func hasDomain(_ n: String) -> Bool {
        matches(domainRegex, n).contains { m in
            guard let r = Range(m.range(at: 1), in: n) else { return false }
            return topLevelDomains.contains(String(n[r]))
        }
    }

    static func hasEmailOrHandle(_ n: String) -> Bool {
        !matches(emailRegex, n).isEmpty || !matches(handleRegex, n).isEmpty || !matches(idRegex, n).isEmpty
    }

    static func hasPhone(_ n: String) -> Bool {
        var s = n
        for m in matches(dateRegex, s).reversed() {
            if let r = Range(m.range, in: s) { s.replaceSubrange(r, with: " ") }
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
