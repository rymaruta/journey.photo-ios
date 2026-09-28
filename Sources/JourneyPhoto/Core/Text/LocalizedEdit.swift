import Foundation

/// 写真の題・説明を直すときの「欄に出す値」と「保存で送る値」。
///
/// 題と説明は `{ja, en}` で保存されている写真がある（`LocalizedText`）。
/// 編集欄は1つ（日本語）だけなので、**欄の文字列をそのまま平文で送ると
/// 英語側が消える**——JSON-LD と写真ページの英語併記まで失われる。
/// Web の `/user/edit`（`mergeLocalizedTitle` / `mergeLocalizedDescription`）と
/// 同じく、日本語だけ差し替えて英語は残す。
///
/// **触っていない欄は送らない**（`nil`）。欄は表示用に整えた値
/// （「無題」を落とす・段落に割る）なので、毎回送ると触っていない題まで
/// 書き換わる。2つの端末で開いて片方で直したあと、もう片方で別の項目を
/// 保存すると、先の編集が古い写しで黙って消える（Web も同じ理由で差分送信）。
enum LocalizedEdit {

    /// 題の欄に出す値。サーバーが入れていた「無題」は出さない（`PhotoTitle`）
    static func titleField(_ title: LocalizedText?) -> String {
        PhotoTitle.display(title?.resolved())
    }

    /// 説明の欄に出す値（段落を改行でつなぐ）
    static func descriptionField(_ description: LocalizedParagraphs?) -> String {
        (description?.resolved() ?? []).joined(separator: "\n")
    }

    /// 題として送る値。**欄を触っていなければ nil**（送らない）。
    ///
    /// 空にしたら英語ごと消す（空文字を送る）——英語だけ残すと、表示は
    /// 英語に落ちて「消したはずの題」が出続ける（Web と同じ判断）
    static func title(original: LocalizedText?, field: String) -> LocalizedPatchValue? {
        let text = field.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text != titleField(original) else { return nil }
        if text.isEmpty { return .plain("") }
        if case .byLocale(let map) = original, let en = map["en"], !en.isEmpty {
            return .texts(["ja": text, "en": en])
        }
        return .plain(text)
    }

    /// 説明として送る値。**欄を触っていなければ nil**（送らない）
    static func description(original: LocalizedParagraphs?, field: String) -> LocalizedPatchValue? {
        let lines = paragraphs(field)
        guard lines != paragraphs(descriptionField(original)) else { return nil }
        if lines.isEmpty { return .plain("") }
        if case .byLocale(let map) = original, let en = map["en"], !en.isEmpty {
            return .paragraphs(["ja": lines, "en": en])
        }
        // **日本語だけの説明は文字列で送る**（Web の `mergeLocalizedDescription` と同じ・段落の数に
        // 上限が無い）。ただし全体が文字列の上限（2000）を超えるときは段落の形で送る——文字列だと
        // サーバーが全体を 2000 で切るが、段落の形なら1段落ごとに 2000 まで（ja だけの形も受ける）
        if PostLimits.length(field.trimmingCharacters(in: .whitespacesAndNewlines)) > PostLimits.description {
            return .paragraphs(["ja": lines])
        }
        return .plain(field)
    }

    /// 保存の前に告げる、説明の長さの断り。問題なければ nil。
    ///
    /// **欄では止めない**（送る形で上限が変わる——文字列なら全体 2000・段落の形なら 1段落 2000・
    /// 50段落まで。`sanitizeDescription`）。超えていたら、**保存させずに**知らせる——送ると
    /// サーバーが黙って切る（Web の `describeOverLimit` は知らせるだけで保存は止めない）
    static func descriptionOverLimit(original: LocalizedParagraphs?, field: String) -> String? {
        let limit = PostLimits.description
        switch description(original: original, field: field) {
        case .plain(let text):
            let count = PostLimits.length(text.trimmingCharacters(in: .whitespacesAndNewlines))
            guard count > limit else { return nil }
            return L("説明は\(limit)字までです（\(count)字）", "Up to \(limit) characters (\(count))")
        case .paragraphs(let map):
            let lines = map["ja"] ?? []
            if lines.count > PostLimits.descriptionParagraphs {
                return L("説明は\(PostLimits.descriptionParagraphs)段落までです（\(lines.count)段落）",
                         "Up to \(PostLimits.descriptionParagraphs) paragraphs (\(lines.count))")
            }
            if let long = lines.map(PostLimits.length).max(), long > limit {
                return L("説明の1段落は\(limit)字までです（\(long)字）",
                         "Each paragraph can be up to \(limit) characters (\(long))")
            }
            return nil
        default:
            return nil
        }
    }

    private static func paragraphs(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// 題・説明として送る形（`api-user/src/sanitize.ts` の `sanitizeTitle` /
/// `sanitizeDescription` が受ける3つの形）。
enum LocalizedPatchValue: Encodable, Equatable {
    case plain(String)
    case texts([String: String])
    case paragraphs([String: [String]])

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .plain(let text): try c.encode(text)
        case .texts(let map): try c.encode(map)
        case .paragraphs(let map): try c.encode(map)
        }
    }
}
