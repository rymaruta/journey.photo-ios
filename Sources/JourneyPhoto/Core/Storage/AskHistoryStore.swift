import Foundation

/// 「AI に頼む」の答えの控え（札 #652）。**端末の中だけ**に置き、サーバーには残さない。
///
/// - 頼んだ文そのものは「最近の検索」（`RecentSearchesStore`）に混ぜて並べる。ここは答えの中身だけ
/// - 同じ日の同じ頼みは、ここから前の答えを出す（**回数を使わない**・Artifact 7「数えない回」）
/// - 消し方: 最近の検索の × と「すべて消す」、ログアウト、退会（`AccountLocalData`）
/// - 持つのは新しい順に `limit` 件まで。日付が替わった答えは、開いても使わない（翌日は数え直す）
///
/// 鍵はアカウントごと（同じ端末の別の人に前の人の答えを出さない）。
struct AskHistoryStore {

    static let baseKey = "journey-photo-ask-history"
    static let limit = 20

    struct Entry: Codable, Equatable {
        /// 日本時間の日付（`YYYY-MM-DD`）
        let day: String
        let thread: [AskExchange]
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func key(for userId: String?) -> String {
        RecentSearchesStore.key(base: baseKey, userId: userId)
    }

    /// 文ごとの控え（鍵は `RecentSearchesStore.normalized` の形）
    func all(userId: String?) -> [String: Entry] {
        guard let data = defaults.data(forKey: Self.key(for: userId)),
              let map = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return map
    }

    /// 今日の同じ頼みの答え（無ければ nil）
    func today(_ question: String, userId: String?, now: Date = Date()) -> [AskExchange]? {
        guard let entry = all(userId: userId)[RecentSearchesStore.normalized(question)],
              entry.day == Self.day(now) else { return nil }
        return entry.thread
    }

    /// 1つの会話（最初の頼みと続き）を覚える
    func remember(_ thread: [AskExchange], userId: String?, now: Date = Date()) {
        guard let first = thread.first else { return }
        var map = all(userId: userId)
        map[RecentSearchesStore.normalized(first.question)] = Entry(day: Self.day(now), thread: thread)
        // 古い日から落とす
        if map.count > Self.limit {
            let keep = map.sorted { $0.value.day > $1.value.day }.prefix(Self.limit)
            map = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        save(map, userId: userId)
    }

    /// 1つ消す（最近の検索の ×）
    func remove(_ question: String, userId: String?) {
        var map = all(userId: userId)
        map[RecentSearchesStore.normalized(question)] = nil
        save(map, userId: userId)
    }

    /// 全部消す（「すべて消す」、ログアウト、退会）
    func removeAll(userId: String?) {
        defaults.removeObject(forKey: Self.key(for: userId))
    }

    /// ログアウトのとき: 答えの控えと、最近の検索に混ぜた頼みの文を消す（打った語はアカウントごとの鍵で残す）
    func forgetOnSignOut(userId: String?) {
        removeAll(userId: userId)
        let recent = RecentSearchesStore(defaults: defaults)
        for word in recent.words(userId: userId) where AskQuery.form(word) == .ask {
            recent.remove(word, userId: userId)
        }
    }

    private func save(_ map: [String: Entry], userId: String?) {
        if map.isEmpty {
            defaults.removeObject(forKey: Self.key(for: userId))
        } else if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: Self.key(for: userId))
        }
    }

    /// 日本時間の日付（回数の日の区切りと同じ）
    static func day(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
