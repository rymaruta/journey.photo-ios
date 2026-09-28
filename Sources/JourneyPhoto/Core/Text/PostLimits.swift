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
