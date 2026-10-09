import Foundation

/// お知らせの絞り込み（提案の絵・モック10）。
///
/// **絞り込みの札はサーバーの種類から作る**（`api-user/src/notify.ts` の
/// `type: "like" | "comment" | "follow" | "storyreply" | "badge"`）。ここで
/// 新しい種類を作らない——受け取れない絞り込みを画面に出さない。
///
/// **新しいメダル（`badge`）は「すべて」にだけ出す**（2026-10-09）。自分の出来事で
/// 人からの便りではなく、数も少ないので札を増やさない。
///
/// **ストーリーの返信は「コメント」に入れる。** 利用者から見れば
/// どちらも「言葉が届いた」で、分けても探しやすくならない。
enum NotificationFilter: String, CaseIterable, Identifiable {
    case all, like, comment, follow

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return L("すべて", "All")
        case .like: return L("いいね", "Likes")
        case .comment: return L("コメント", "Comments")
        case .follow: return L("フォロー", "Follows")
        }
    }

    func matches(_ kind: AppNotification.Kind) -> Bool {
        switch self {
        case .all: return true
        case .like: return kind == .like
        case .comment: return kind == .comment || kind == .storyreply
        case .follow: return kind == .follow
        }
        // `badge` は上のどれにも当たらない（「すべて」だけ）
    }
}
