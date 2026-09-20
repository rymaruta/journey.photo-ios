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
/// `GET /invites/{token}` で取り直す——持ち主が取り消したら
/// そこで 404 になり、こちらも畳む。
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

    func forget(id: String) {
        entries.removeAll { $0.id == id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key(for: userId))
    }
}
