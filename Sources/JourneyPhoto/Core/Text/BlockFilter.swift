import Foundation

/// ブロックした人を画面から外す（審査 1.2）。
///
/// **サーバーが絞らない口の分だけ、端末で落とす。** コメントの一覧
/// （`GET /photos/{id}/comments`）と人の検索（`/users/search`）はログイン不要の口で、
/// 誰がブロックしたかを知らない。ストーリーの返信は前から端末で落としていた
/// （`StoryViewerView`）のに、この2つだけ抜けていた。
///
/// **画面の外に置く**（`Shims/` の模型では `View` の中を動かせないので、試験のため）。
enum BlockFilter {
    static func comments(_ comments: [PhotoComment], blocked: Set<String>) -> [PhotoComment] {
        guard !blocked.isEmpty else { return comments }
        return comments.filter { !blocked.contains($0.uid) }
    }

    static func users(_ users: [UserProfile], blocked: Set<String>) -> [UserProfile] {
        guard !blocked.isEmpty else { return users }
        return users.filter { !blocked.contains($0.userId) }
    }
}
