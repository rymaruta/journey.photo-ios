import Foundation

/// 投稿した写真を **Threads にも載せる**（owner 2026-10-02「Journey Photo に写真を投稿したら、
/// その写真を Threads にも簡単に投稿できる機能が欲しい」）。
///
/// **共有の画面（`UIActivityViewController`）に写真と文を渡す形にした。**
/// - Threads の公開の口（`threads.net/intent/post`）は文と URL しか渡せず、写真は入らない
///   （URL の札＝OGP の縮んだ絵になる）。共有の画面なら写真そのものが Threads の投稿に入る
/// - Threads API は Meta の審査と、サーバーに利用者ごとの鍵を持つ作りが要る。1枚載せるために
///   持つには重い（「機能は足すより減らす」）
///
/// 渡す写真は**投稿に使った画像そのもの**（`ImagePreparer` が位置などの EXIF を落としたもの）。
/// 端末の原本は渡さない（GPS が載ったまま外へ出る）
enum ThreadsShare {

    /// 投稿したら共有の画面を開くか（端末に覚える）
    static let defaultsKey = "upload.shareToThreads"
    /// 一度に渡す写真の上限（Threads の1投稿は20枚まで。共有の画面に重い画像を並べすぎない）
    static let maxImages = 10
    /// Threads の本文の上限（500字）
    static let maxTextLength = 500

    /// 外へ渡してよい投稿か。**公開・全体に公開だけ**——非公開・親しい友達だけの写真を
    /// 外の SNS に流す口を作らない
    static func isEligible(published: Bool, audience: Audience) -> Bool {
        published && audience == .everyone
    }

    /// 添える文: 題・説明・撮影地・写真のページを**空行で段落に分ける**（owner 2026-10-02
    /// 「タイトル／文章／撮影地(あれば) みたいな改行を入れたい」）。無い項目の段落は作らない。
    /// 上限を超えるときは前の方を詰めて、**URL は必ず丸ごと残す**（途中で切れた URL は開けない）。
    /// **タグは入れない**——Threads は1投稿に1つしかトピックにならず、並べても飾りの文字になる
    static func text(title: String, description: String = "", location: String, url: URL?) -> String {
        let link = url?.absoluteString ?? ""
        var lines: [String] = []
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { lines.append(t) }
        // 説明の中の空行は詰める（段落の区切りと見分けがつかなくなる）
        let d = description.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\n")
        if !d.isEmpty { lines.append(d) }
        let l = location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !l.isEmpty { lines.append("📍 \(l)") }
        var head = lines.joined(separator: "\n\n")
        let budget = maxTextLength - link.count - (link.isEmpty || head.isEmpty ? 0 : 2)
        if head.count > budget {
            head = budget > 1 ? String(head.prefix(budget - 1)) + "…" : ""
        }
        return [head, link].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}
