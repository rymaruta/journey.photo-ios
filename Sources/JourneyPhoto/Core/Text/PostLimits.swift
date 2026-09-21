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

    /// 残りが少ないときだけ数を出す。**いつも出すと数字が気になって
    /// 書けなくなる**ので、2割を切ってから
    static func shouldShowCount(_ text: String, limit: Int) -> Bool {
        text.count >= Int(Double(limit) * 0.8)
    }

    /// 上限で切る（画面側で止める）
    static func clamp(_ text: String, limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit))
    }
}
