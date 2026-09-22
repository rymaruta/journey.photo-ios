import Foundation
import Combine

/// 見たストーリー（リングの色を分けるため）。
///
/// **サーバーに口が無い。** `POST /stories/{id}/view` は**投稿者に**
/// 「誰が見たか」を伝えるためのもので、見た側に「自分が見たか」は返らない
/// （`GET /stories` の `Story` に印は無い）。だから端末に覚える——
/// Web の `lib/stories.ts` と同じ形。
///
/// **アカウントごとに鍵を分ける。** 1本の共有鍵にすると、同じ端末で別の人が
/// ログインしたときに**前の人の既読リング**が付いて見える。Web はそれを
/// 避けるためにログアウトのたびに全部消していて、その結果
/// **同じ人がログインし直すと一度見たストーリーが新着に戻っていた**
/// （owner の報告・2026-09-20）。鍵を分ければ、消さずに両方満たせる。
@MainActor
final class SeenStoriesStore: ObservableObject {

    /// **25時間で捨てる。** ストーリー自体が24時間で消えるので、
    /// それより古い印は誰のことでもない（放っておくと増え続ける）
    static let lifetime: TimeInterval = 25 * 60 * 60

    @Published private(set) var ids: Set<String> = []

    private let defaults: UserDefaults
    private var userId: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static let sharedKey = "journey-photo-seen-stories"

    private func key(for userId: String?) -> String {
        guard let userId, !userId.isEmpty else { return Self.sharedKey }
        return "\(Self.sharedKey):\(userId)"
    }

    func use(userId: String?, now: Date = Date()) {
        self.userId = userId
        ids = Set(fresh(now: now).keys)
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    /// その人のストーリーに**1本でも未読があるか**（リングの色を決める）
    func hasUnseen(_ stories: [Story]) -> Bool {
        stories.contains { !contains($0.id) }
    }

    /// 見た印を付ける。**古い印はこのときに掃除する**
    func markSeen(_ id: String, now: Date = Date()) {
        guard !id.isEmpty else { return }
        var kept = fresh(now: now)
        kept[id] = now.timeIntervalSince1970
        defaults.set(kept, forKey: key(for: userId))
        ids = Set(kept.keys)
    }

    /// まだ生きている印だけ（読むときにも掃除の目で見る）
    private func fresh(now: Date) -> [String: Double] {
        let raw = defaults.dictionary(forKey: key(for: userId)) as? [String: Double] ?? [:]
        return raw.filter { now.timeIntervalSince1970 - $0.value < Self.lifetime }
    }
}
