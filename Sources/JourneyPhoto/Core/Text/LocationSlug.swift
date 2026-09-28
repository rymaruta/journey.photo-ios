import Foundation

/// 撮影地のスラッグ（`/location/<スラッグ>` の鍵）。
///
/// 🔴 **Web の `slugify(_, "location")` と同じ値にする。**
/// この値は表示用ではなく**鍵**で、
///
///   - サーバーの「行きたい場所」（`spots#<uid>` に入るのはこの文字列）
///   - Web の `/location/<スラッグ>` のページ
///
/// の両方と突き合わさる。ずれると、アプリで入れた「行きたい」が
/// **Web の一覧に別の行として並ぶ**（あるいは開けないリンクになる）。
///
/// 写して2つ持つと静かにずれるので、**期待値を Web の実装から取って
/// テストに焼いてある**（`LocationSlugTests` の表は `lib/utils/collections.ts`
/// の `slugify` を実際に動かして作った）。
enum LocationSlug {

    /// URL とファイル名になるので**バイトで切る**（Web と同じ 200 バイト）
    static let maxBytes = 200

    static func make(_ value: String?) -> String {
        guard let value else { return "" }
        var s = lowercasedLikeJS(value.trimmingCharacters(in: jsWhitespace))

        // 空白は `-`（連続はあとでまとめる）。
        //
        // 🔴 **ICU の `\\s` は JS の `\\s` と違う**——JS は `U+FEFF`（BOM）を空白に
        // 数えるが ICU は数えない。以前は `\\s+` と書いていたので、BOM の混じった
        // 撮影地（コピー＆ペーストで紛れ込む）が Web と別のスラッグになった
        // （`"a\u{FEFF}b"` → Web `a-b` / iOS `a\u{FEFF}b`）。JS の空白の集合を
        // そのまま書く（制御文字と同じく Swift 側で本物の文字に展開して渡す）
        s = s.replacingOccurrences(of: "[\(jsWhitespaceChars)]+", with: "-", options: .regularExpression)
        // **URL のパスに置けない文字。** `/` `\` `?` `#` `%` は
        // 静的書き出しとパスの解釈を壊す（Web 側に理由が書いてある）
        s = s.replacingOccurrences(of: "[/\\\\?#%]+", with: "-", options: .regularExpression)
        // 制御文字（`\0` が混じるとファイル名を作れない）。
        //
        // ⚠️ **`\\u{...}` と書かない。** Swift の文字列としてはただの文字列で、
        // ICU の正規表現は `\uFFFF`（4桁）しか解さない——書いた形は
        // 文字の集合 `{ u 0 1 F 7 9 { } }` として読まれ、**英数字まで
        // `-` に置き換わって結果が空になる**（最初にそう書いて全部空になった）。
        // Swift 側で本物の文字に展開してから渡す。
        let controls = "[\u{0000}-\u{001F}\u{007F}-\u{009F}]+"
        s = s.replacingOccurrences(of: controls, with: "-", options: .regularExpression)
        s = s.replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        // **`.` だけの値は捨てる。** パス片としては「今／親のディレクトリ」に
        // なり、Web 側はビルドごと落ちる
        if isAllDots(s) { return "" }
        let cut = clamp(s)
        return isAllDots(cut) ? "" : cut
    }

    /// JS の `String.prototype.trim` が落とす文字（WhiteSpace ＋ LineTerminator）。
    ///
    /// **`.whitespacesAndNewlines` ではない。** あちらは `U+FEFF` を含まず、
    /// Web が落とす前後の BOM が残った（`"\u{FEFF}パリ"` → Web `パリ`）。
    /// 逆に `U+0085` はこちらだけが含むが、残っても下で `-` になって端から
    /// 落ちるので結果は同じ
    ///
    /// ⚠️ **`CharacterSet.whitespaces` も `\\p{Zs}` も使わない。** Linux の Foundation の
    /// `whitespaces` は `U+200B`（幅のない空白・いまの Unicode では Zs ではない）を
    /// 含み、Web が残す `"\u{200B}"` を落とした（2000件の突き合わせで出た）。
    /// どの版の表を引くかで揺れないよう、JS の集合（Zs は Unicode 15 の17文字）を書き出す
    private static let jsWhitespaceChars =
        "\t\n\u{000B}\u{000C}\r\u{FEFF}\u{2028}\u{2029}"
        + " \u{00A0}\u{1680}\u{2000}-\u{200A}\u{202F}\u{205F}\u{3000}"

    private static let jsWhitespace: CharacterSet = {
        var set = CharacterSet(charactersIn: "\t\n\u{000B}\u{000C}\r\u{FEFF}\u{2028}\u{2029}"
                                   + " \u{00A0}\u{1680}\u{202F}\u{205F}\u{3000}")
        set.insert(charactersIn: "\u{2000}"..."\u{200A}")
        return set
    }()

    /// JS の `toLowerCase()` と同じ小文字化。
    ///
    /// 🔴 **Swift の `lowercased()` は語末のシグマを見ない。** JS（Unicode の
    /// Final_Sigma 規則）は語末の `Σ` を `ς` にするが、Swift は常に `σ` にする
    /// ——ギリシャ語の撮影地（`ΟΔΟΣ`）が Web `οδος` / iOS `οδοσ` と別の鍵になった。
    /// それ以外は1文字ずつの対応（`lowercaseMapping`）で JS と同じ
    private static func lowercasedLikeJS(_ value: String) -> String {
        let scalars = Array(value.unicodeScalars)
        var out = String.UnicodeScalarView()
        for (i, scalar) in scalars.enumerated() {
            if scalar == "\u{03A3}", isFinalSigma(scalars, at: i) {
                out.append("\u{03C2}")
            } else {
                out.append(contentsOf: scalar.properties.lowercaseMapping.unicodeScalars)
            }
        }
        return String(out)
    }

    /// Unicode の Final_Sigma: 前に（大小を無視できる文字を挟んで）大小のある文字があり、
    /// 後ろに（同じく挟んで）大小のある文字が続かない
    private static func isFinalSigma(_ s: [Unicode.Scalar], at i: Int) -> Bool {
        var before = i - 1
        while before >= 0, s[before].properties.isCaseIgnorable { before -= 1 }
        guard before >= 0, s[before].properties.isCased else { return false }
        var after = i + 1
        while after < s.count, s[after].properties.isCaseIgnorable { after += 1 }
        return !(after < s.count && s[after].properties.isCased)
    }

    private static func isAllDots(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0 == "." }
    }

    /// **文字数ではなくバイト数で切る**（日本語は1文字3バイト）。
    ///
    /// 🔴 **コードポイント（`unicodeScalars`）単位で詰める。** Web の
    /// `clampSlugBytes` は `for (const ch of s)`＝コードポイントで回す。以前は
    /// Swift の `Character`（書記素のまとまり）で回していたので、境目に
    /// 結合文字（`e` ＋ `U+0301`）や ZWJ でつないだ絵文字があると、Web は
    /// 途中まで入れ、iOS はまとまりごと落として**別の鍵**になった
    private static func clamp(_ s: String) -> String {
        guard s.utf8.count > maxBytes else { return s }
        var out = String.UnicodeScalarView()
        var bytes = 0
        for scalar in s.unicodeScalars {
            let n = UTF8.width(scalar)
            if bytes + n > maxBytes { break }
            out.append(scalar)
            bytes += n
        }
        return String(out).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
