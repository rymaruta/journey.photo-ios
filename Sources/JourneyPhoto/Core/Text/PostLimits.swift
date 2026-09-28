import Foundation

/// 投稿で受け付けられる長さ。**サーバーの値を写したもの**
/// （`api-user/src/sanitize.ts` の `sanitizeTitle` / `sanitizeDescription`
/// / `sanitizeText(location, 200)`）。
///
/// **画面に出す数はここから取る。** 提案の絵には「6/50」「25/500」と
/// あったが、**サーバーは 200 と 2000 で切る**。画面だけ短く見せると、
/// 書ける文章を書けないと思わせるし、逆に長く見せると**黙って切られる**。
///
/// 超えたぶんは**サーバーが黙って切る**ので、画面側で止める
/// （切られたことに気づけないのがいちばん困る）。
enum PostLimits {
    static let title = 200
    static let description = 2_000
    /// 段落の形で送る説明の段落の数（`sanitizeDescription` の `slice(0, 50)`）
    static let descriptionParagraphs = 50
    static let location = 200
    /// ストーリーのひとこと（`stories.ts` の `truncate(caption, 200)`）
    static let storyCaption = 200
    /// コメント（`comments.ts` の `TEXT_MAX`）
    static let comment = 500
    /// ストーリーへの返信（`storyReplies.ts` の `TEXT_MAX`）
    static let storyReply = 200

    /// **サーバーと同じ数え方（UTF-16 の単位）。** `truncate`（`sanitize.ts`）は JavaScript の
    /// `length` で数えるので、絵文字は2つ以上に数える。字（書記素）で数えると、画面では上限内に
    /// 見えてもサーバーで黙って切られていた
    static func length(_ text: String) -> Int { text.utf16.count }

    /// 残りが少ないときだけ数を出す。**いつも出すと数字が気になって
    /// 書けなくなる**ので、2割を切ってから
    static func shouldShowCount(_ text: String, limit: Int) -> Bool {
        length(text) >= Int(Double(limit) * 0.8)
    }

    /// 欄が変わったときに残す文。**ブラウザの `maxLength` に寄せて、入れようとした字のほうを削る。**
    ///
    /// 先頭から残して末尾を切ると、上限いっぱいの文の途中に打ち込んだ・貼った回に、画面の外の
    /// 末尾が黙って消えた。前の文と共通の頭と尻を残し、差し込んだ部分だけを残りの字数まで入れる
    /// （置き換えて貼った長い文も、入るぶんだけ入る）。
    /// - 頭と尻は**Unicode のスカラーで**比べる（結合文字を足した回に、直前の字を差し込みに
    ///   数えて消さない）
    /// - 差し込みの末尾の空白・改行は残す（カーソルの位置は分からないので、区切りを貼った文の
    ///   側に数える。段落の区切りが消えて、次の段落とつながらない）
    /// - 前の文がもう上限を超えていれば、減らす変更だけ受ける（入れた回に黙って切らない）
    static func limited(old: String, new: String, limit: Int) -> String {
        guard length(new) > limit else { return new }
        guard length(old) <= limit else { return length(new) <= length(old) ? new : old }
        let oldScalars = Array(old.unicodeScalars), newScalars = Array(new.unicodeScalars)
        var head = 0
        while head < oldScalars.count, head < newScalars.count, oldScalars[head] == newScalars[head] { head += 1 }
        var tail = 0
        while tail < oldScalars.count - head, tail < newScalars.count - head,
              oldScalars[oldScalars.count - 1 - tail] == newScalars[newScalars.count - 1 - tail] { tail += 1 }
        func text(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars)
            return String(view)
        }
        let prefix = text(newScalars[..<head])
        let suffix = text(newScalars[(newScalars.count - tail)...])
        let inserted = text(newScalars[head..<(newScalars.count - tail)])
        let room = limit - length(prefix) - length(suffix)
        guard room > 0 else { return old }
        // 末尾の空白・改行（区切り）は残し、その前を削る。後ろから数える（正規表現の `\s+$` は
        // 空白の長い並びで2乗の時間がかかった）。区切りが残りより長ければ、最後の1つだけ残す
        let insertedScalars = Array(inserted.unicodeScalars)
        var cut = insertedScalars.count
        while cut > 0, CharacterSet.whitespacesAndNewlines.contains(insertedScalars[cut - 1]) { cut -= 1 }
        let body = text(insertedScalars[..<cut])
        var trail = text(insertedScalars[cut...])
        if length(trail) >= room, let last = trail.last { trail = String(last) }
        let kept = length(trail) < room ? clamp(body, limit: room - length(trail)) + trail : trail
        return prefix + (length(kept) <= room ? kept : clamp(inserted, limit: room)) + suffix
    }

    /// 上限で切る（画面側で止める）。**字の途中では切らない**（サーバーの `truncate` と同じく、
    /// 上限に収まる最後の字まで）
    static func clamp(_ text: String, limit: Int) -> String {
        guard length(text) > limit else { return text }
        var used = 0
        var end = text.startIndex
        for index in text.indices {
            let next = text.index(after: index)
            used += text[index..<next].utf16.count
            guard used <= limit else { break }
            end = next
        }
        return String(text[..<end])
    }
}
