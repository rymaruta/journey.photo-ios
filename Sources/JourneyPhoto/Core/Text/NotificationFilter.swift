import Foundation

/// お知らせの絞り込み（提案の絵・モック10）。
///
/// **種類はサーバーが決めている4つだけ**（`api-user/src/notify.ts` の
/// `type: "like" | "comment" | "follow" | "storyreply"`）。ここで
/// 新しい種類を作らない——受け取れない絞り込みを画面に出さない。
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
    }
}
