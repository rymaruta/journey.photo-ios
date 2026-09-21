import Foundation

/// プロフィールの表示切り替え。Web 側と同じ2つ（内部名 `timeline` は年表）。
enum ProfileTab: String, CaseIterable, Identifiable {
    case posts
    case timeline

    var id: String { rawValue }

    var label: String {
        switch self {
        case .posts: return L("投稿", "Posts")
        case .timeline: return L("年表", "Timeline")
        }
    }
}
