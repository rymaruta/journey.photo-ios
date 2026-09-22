import Foundation

/// 写真詳細の下段の切り替え（モック6: コメント（N） / 関連写真）。
///
/// **数はサーバーが返した総数だけ。** 端末で数え直さない（1ページ分しか
/// 持っていないので、`comments.count` を出すと総数より少なく見える）。
/// 取れていない回は**数を出さない**——「コメント（0）」は「まだ無い」と
/// 読まれるので、圏外でそう出すと嘘になる。
enum PhotoDetailTab: String, CaseIterable, Identifiable {
    case comments
    case related

    var id: String { rawValue }

    /// - Parameter commentCount: サーバーから取れた総数。取れていなければ nil
    func label(commentCount: Int?) -> String {
        switch self {
        case .comments:
            guard let commentCount else { return L("コメント", "Comments") }
            return L("コメント（\(commentCount)）", "Comments (\(commentCount))")
        case .related:
            return L("関連写真", "Related")
        }
    }
}
