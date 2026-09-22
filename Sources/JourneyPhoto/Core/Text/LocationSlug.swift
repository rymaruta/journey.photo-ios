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
        var s = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // 空白は `-`（連続はあとでまとめる）
        s = s.replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
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

    private static func isAllDots(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0 == "." }
    }

    /// **文字数ではなくバイト数で切る**（日本語は1文字3バイト）。
    /// 切った先が文字の途中にならないよう、文字単位で詰める
    private static func clamp(_ s: String) -> String {
        guard s.utf8.count > maxBytes else { return s }
        var out = ""
        var bytes = 0
        for ch in s {
            let n = String(ch).utf8.count
            if bytes + n > maxBytes { break }
            out.append(ch)
            bytes += n
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
