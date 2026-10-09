import Foundation
// `ObservableObject` と `@Published` は Combine のもの
import Combine

/// 招待リンクから参加したアルバム。**端末に覚える。**
///
/// **サーバーは教えてくれない。** `GET /albums` は
/// `albums.ts` の `a.ownerId !== userId` で自分が作ったものだけを返す
/// （Web も同じ）。Web ではそれで困らない——参加した人は
/// **受け取ったリンク（`/j?t=…`）をブラウザで開き直せる**からで、
/// アプリにはその「リンクを開き直す」場所が無い。覚えていないと、
/// 参加した瞬間にアルバムへの入口が消える（実際そうなっていた）。
///
/// 覚えるのは招待の合図（token）まで。中身はいつも
/// `GET /invites/{token}` で取り直す。
///
/// **合図が死んでも控えは消さない。** 招待は30日で失効し
/// （`invite.ts` の `INVITE_TTL_MS`）、持ち主が作り直しても前のものは
/// 取り消される。しかし**アルバムの会員であることはサーバーに残る**ので、
/// 消すと「中身は見られないが投稿はできる」状態まで一緒に失う
/// （`upload.ts` の `isAlbumMember` は会員なら通す）。
/// 畳むのは本人がスワイプで消したときだけ。
@MainActor
final class JoinedAlbumsStore: ObservableObject {

    struct Entry: Codable, Identifiable, Equatable {
        let id: String
        var title: String
        var token: String
    }

    @Published private(set) var entries: [Entry] = []

    private let defaults: UserDefaults
    private var userId: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static let base = "photo-gallery-joined-albums"

    /// **アカウントごとに分ける**（`FavoritesStore` と同じ理由——
    /// 同じ端末の別の人に、参加したアルバムが見えてはいけない）。
    private func key(for userId: String?) -> String {
        guard let userId, !userId.isEmpty else { return Self.base }
        return "\(Self.base):\(userId)"
    }

    func use(userId: String?) {
        self.userId = userId
        guard let data = defaults.data(forKey: key(for: userId)),
              let saved = try? JSONDecoder().decode([Entry].self, from: data) else {
            entries = []
            return
        }
        entries = saved
    }

    /// 参加した／開き直した。**同じアルバムは1つだけ**（合図は新しい方で上書き）。
    func remember(id: String, title: String, token: String) {
        var next = entries.filter { $0.id != id }
        next.insert(Entry(id: id, title: title, token: token), at: 0)
        entries = next
        save()
    }

    /// いまの控えの持ち主。**参加の答えを待つ前に取り、`remember(id:title:token:for:)` に渡す**
    var owner: String? { userId }

    /// 参加の答えを待った後に覚える。**待っている間に人が替わっていたら、参加した人の控えに書く**
    /// （2026-10-09: 替わった後の人の控えに、前の人が参加したアルバムが入っていた）。
    ///
    /// `SavedPhotosStore`・`ModerationStore` は替わっていたら書かない（サーバーの一覧で取り直せる）が、
    /// 参加したアルバムは**サーバーが教えてくれない**ので、書かずに落とすと参加した人の入口が消える。
    /// だから落とさずに、参加した人の鍵へ書く（いまの人の一覧は触らない）
    func remember(id: String, title: String, token: String, for owner: String?) {
        guard owner != userId else {
            remember(id: id, title: title, token: token)
            return
        }
        let saved = defaults.data(forKey: key(for: owner))
            .flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        var next = saved.filter { $0.id != id }
        next.insert(Entry(id: id, title: title, token: token), at: 0)
        guard let data = try? JSONEncoder().encode(next) else { return }
        defaults.set(data, forKey: key(for: owner))
    }

    func forget(id: String) {
        entries.removeAll { $0.id == id }
        save()
    }

    /// 退会した人の控えを消す（`AccountLocalData`）
    func removeData(for userId: String) {
        defaults.removeObject(forKey: key(for: userId))
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key(for: userId))
    }
}
