import Foundation

/// 題が無い写真の扱い。
///
/// owner:「中には、タイトルとか入れずに気軽に投稿する人もいるみたい。
/// タイトルに無題と入ってしまう。一覧を見たときに無題ではなくて、
/// タイトルなくてもいいよ」
///
/// **「無題」は表示の落とし先ではなく、サーバーが実際に保存していた文字列**
/// だった（`api-user/src/upload.ts` が `sanitizeTitle(title) ?? { ja: "無題" }`）。
/// 保存はやめたが、**既に上がっている写真には残る**ので出す側でも落とす。
/// Web 側の `lib/utils/photoTitle.ts` と同じ判断・同じ語。
///
/// **丸ごとその言葉のときだけ落とす。** 「無題の風景」は人が書いた題なので残す。
enum PhotoTitle {

    private static let serverPlaceholders: Set<String> = ["無題", "Untitled"]

    /// 題として出してよい文字列。無ければ空（呼ぶ側が「出さない」を決める）。
    static func display(_ title: String?) -> String {
        let trimmed = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return serverPlaceholders.contains(trimmed) ? "" : trimmed
    }
}
