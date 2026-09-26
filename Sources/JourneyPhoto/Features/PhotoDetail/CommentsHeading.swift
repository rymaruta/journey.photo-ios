import Foundation

/// 写真詳細のコメントの見出し（「コメント（N）」）。
///
/// **数はサーバーが返した総数だけ。** 端末で数え直さない（1ページ分しか
/// 持っていないので、`comments.count` を出すと総数より少なく見える）。
/// 取れていない回は**数を出さない**——「コメント（0）」は「まだ無い」と
/// 読まれるので、圏外でそう出すと嘘になる。
///
/// 以前は「コメント／関連写真」の札の名前だった。板 02 で札をやめ、
/// 関連写真は「この近くで撮られた写真」に置き換えた
enum CommentsHeading {

    /// - Parameter commentCount: サーバーから取れた総数。取れていなければ nil
    static func label(commentCount: Int?) -> String {
        guard let commentCount else { return L("コメント", "Comments") }
        return L("コメント（\(commentCount)）", "Comments (\(commentCount))")
    }
}
