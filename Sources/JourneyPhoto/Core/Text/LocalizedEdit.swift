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
        return .plain(field)
    }

    /// 説明の欄の上限。**文字列で送る写真だけ**全体を 2000 で止める（`sanitizeDescription` は
    /// 文字列なら全体を 2000 で黙って切る）。英語の説明がある写真は段落ごとに送り、上限も
    /// 段落ごとなので、全体では止めない（止めると直しただけで後ろの段落が消えた）
    static func descriptionLimit(original: LocalizedParagraphs?) -> Int? {
        if case .byLocale(let map) = original, let en = map["en"], !en.isEmpty { return nil }
        return PostLimits.description
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
