import Foundation

/// **コメントの返信を、相手のコメントのすぐ下に1段下げて並べる**（2026-11-11・札 #541 の ②）。
///
/// 一覧は新しい順（`PhotoDetailViewModel.comments`）。返信（`replyTo` を持つ1件）は、相手のコメントが
/// 一覧に在ればその下へ**古い順**で寄せる（会話として上から読めるように）。相手が一覧に無い
/// （消された・200件の輪から落ちた・ブロックした人のコメントで落とした）返信は、その場に下げずに残す。
/// 返信への返信も、相手が返信なら**同じ親の下**に並べる（段は1つだけ）。
/// Web の `lib/utils/commentThreads.ts` と同じ決まり（2か所で変えるときは両方）
enum CommentThreads {

    struct Entry: Identifiable, Equatable {
        let comment: PhotoComment
        /// 1段下げて出すか
        let isReply: Bool
        var id: String { comment.id }
    }

    static func thread(_ items: [PhotoComment]) -> [Entry] {
        let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        /// 返信の大元（1段目のコメント）の id。相手が無い・輪になったときは nil
        func root(of comment: PhotoComment) -> String? {
            var seen: Set<String> = []
            var current = comment
            while let parentId = current.replyTo?.id, !seen.contains(current.id) {
                seen.insert(current.id)
                guard let parent = byId[parentId] else { return nil }
                if parent.replyTo == nil { return parent.id }
                current = parent
            }
            return nil
        }
        var children: [String: [PhotoComment]] = [:]
        var placed: Set<String> = []
        for comment in items {
            guard let parent = root(of: comment) else { continue }
            children[parent, default: []].append(comment)
            placed.insert(comment.id)
        }
        var out: [Entry] = []
        for comment in items where !placed.contains(comment.id) {
            out.append(Entry(comment: comment, isReply: false))
            // 一覧は新しい順なので、返信は逆にして古い順に
            for reply in (children[comment.id] ?? []).reversed() {
                out.append(Entry(comment: reply, isReply: true))
            }
        }
        return out
    }

    /// 欄の上に出す「〇〇さんに返信中」
    static func replyingLabel(_ target: PhotoComment) -> String {
        L("\(target.name)さんに返信中", "Replying to \(target.name)")
    }

    /// 本文の前に出す相手の名前（「@けんじ」）。返信でなければ nil
    static func mention(_ comment: PhotoComment) -> String? {
        comment.replyTo.map { "@\($0.name)" }
    }

    /// 「返信」を出すか。ログイン中で、コメントを受け付ける写真で、退会していない人のコメントだけ
    static func canReply(to comment: PhotoComment, viewerId: String?, acceptsComments: Bool) -> Bool {
        viewerId != nil && acceptsComments && !comment.isFromDeletedUser
    }
}
