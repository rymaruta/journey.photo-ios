import Foundation

/// 「AI に頼む」の答えの控え（札 #652）。**端末の中だけ**に置き、サーバーには残さない。
///
/// - 2026-11-21 判断（札 #678・owner「探すの方にまで AI で頼んだ履歴出てくるのいやだな」）: 頼んだ文は探すの「最近の検索」
///   （`RecentSearchesStore`）に混ぜない。AI に頼んだことは AI の画面の中だけ（無料は今の会話1つ、Pro は「前の会話」）
/// - 同じ日の同じ頼みは、ここから前の答えを出す（**回数を使わない**・Artifact 7「数えない回」）
/// - 消し方: AI の画面の「新しく頼む」（無料）と「前の会話」の一覧（Pro）、ログアウト、退会（`AccountLocalData`）。
///   探すの「すべて消す」は探すの言葉だけを消す
/// - 持つのは新しい順に `limit` 件まで。日付が替わった答えは、開いても使わない（翌日は数え直す）
///
/// 鍵はアカウントごと（同じ端末の別の人に前の人の答えを出さない）。
/// 2026-11-21 判断（札 #678 の確かめ役の指摘）: **ログインしていない間は何も残さない**（読むと空、書いても捨てる）。
/// 同じ端末を使うほかの人に、ログインしていない間の頼みを見せない
struct AskHistoryStore {

    static let baseKey = "journey-photo-ask-history"
    static let limit = 20

    struct Entry: Codable, Equatable {
        /// 日本時間の日付（`YYYY-MM-DD`）
        let day: String
        let thread: [AskExchange]
        /// 覚えた時刻（同じ日の中で新しい方を残す・札 #684。前の版の控えには無い）
        var savedAt: Date? = nil
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
        guard userId?.isEmpty == false, let data = defaults.data(forKey: Self.key(for: userId)),
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
        guard userId?.isEmpty == false, let first = thread.first else { return }
        var map = all(userId: userId)
        map[RecentSearchesStore.normalized(first.question)] = Entry(day: Self.day(now), thread: thread, savedAt: now)
        // 古い日から落とす。2026-11-22 判断（札 #684）: 同じ日の中は覚えた時刻で並べる。前は日付だけで並べ、同じ日に
        // 21件目を入れると辞書の順で決まり、いま入れた答えが落ちることがあった（同じ頼みでまた AI と回数を使う）
        if map.count > Self.limit {
            let keep = map.sorted {
                if $0.value.day != $1.value.day { return $0.value.day > $1.value.day }
                return ($0.value.savedAt ?? .distantPast) > ($1.value.savedAt ?? .distantPast)
            }.prefix(Self.limit)
            map = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        save(map, userId: userId)
    }

    /// 全部消す（「すべて消す」、ログアウト、退会）。会話の控え（札 #678）も消す
    func removeAll(userId: String?) {
        Self.bumpGeneration(userId)
        defaults.removeObject(forKey: Self.key(for: userId))
        defaults.removeObject(forKey: Self.conversationsKey(for: userId))
    }

    // MARK: - 消した回の数（札 #678 の確かめ役の指摘）

    // 答えを待っている間にログアウト・退会で控えを消すと、待っていた答えがあとから前の人の鍵に書かれてしまう。
    // 消すたびに人ごとの数を上げ、`AskEngine` は頼み始めたときの数と変わっていたら書かない（アプリが動いている間だけの数）
    private final class Generations: @unchecked Sendable {
        let lock = NSLock()
        var counts: [String: Int] = [:]
    }
    private static let generations = Generations()

    /// その人の控えを消した回の数
    static func generation(_ userId: String?) -> Int {
        generations.lock.lock(); defer { generations.lock.unlock() }
        return generations.counts[userId ?? ""] ?? 0
    }

    private static func bumpGeneration(_ userId: String?) {
        generations.lock.lock(); defer { generations.lock.unlock() }
        generations.counts[userId ?? "", default: 0] += 1
    }

    // MARK: - 会話（札 #678・2026-11-21 判断）

    // owner「閉じたら AI との会話履歴消えちゃうんだね」「AI との会話で別スレッドにするには月額500円の有料プラン（Pro）なら
    // 使えるようにしたい」（2026-11-21）。画面に出した会話を**そのまま**（言葉の表の答え、使い切った帯、旅行プランの流れも）
    // 端末の中に残し、閉じて開き直したとき・アプリを落としたときに続きから出す。**AI は呼ばない、回数も使わない。**
    //
    // - 上の「同じ日の同じ頼み」の控え（`remember`・`today`）とは別に持つ。あちらは回数を使わないための控えで、
    //   AI で答えた回と断った回だけを残す決まり（`AskEngine.keepable`）を変えない
    // - 無料: 「新しく頼む」で今の会話を消す（会話は1本）。Pro: 残して別の会話を始め、「前の会話」から続きを選べる（`AskConversationRule`）
    // - Pro が切れても消さない（今の会話だけを見せる。また Pro になれば一覧が戻る）
    // - 消し方: 無料は「新しく頼む」、Pro は「前の会話」の一覧（長押し・左へ払う・すべて消す）、ログアウト、退会。
    //   会話を消したら、その頼みの答えの控え（同じ日の同じ頼み）も消す
    // - 1つの会話に残すのは新しい `turnLimit` 往復まで

    static let conversationsBaseKey = "journey-photo-ask-conversations"
    /// 1つの会話に残す往復（新しい方から）
    static let turnLimit = 30

    struct Conversation: Codable, Equatable, Identifiable {
        let id: String
        var thread: [AskExchange]
        /// 一覧に出す字（最初の頼み）
        var question: String { thread.first?.question ?? "" }
    }

    struct Conversations: Codable, Equatable {
        /// 新しく話した順（`limit` 件まで）
        var items: [Conversation] = []
        /// 開くと出す会話（「新しく頼む」のあと、まだ頼んでいなければ nil）
        var currentId: String?

        var current: Conversation? {
            guard let currentId else { return nil }
            return items.first { $0.id == currentId }
        }
    }

    static func conversationsKey(for userId: String?) -> String {
        RecentSearchesStore.key(base: conversationsBaseKey, userId: userId)
    }

    /// 会話の控え。まだ無ければ、前からある答えの控え（`all`）を会話に移して見せる（今の会話は無し。保存は次に変わったとき）
    func conversations(userId: String?) -> Conversations {
        guard userId?.isEmpty == false else { return Conversations() }
        if let data = defaults.data(forKey: Self.conversationsKey(for: userId)),
           let list = try? JSONDecoder().decode(Conversations.self, from: data) {
            return list
        }
        let migrated = all(userId: userId)
            .filter { !$0.value.thread.isEmpty }
            .sorted { $0.value.day == $1.value.day ? $0.key < $1.key : $0.value.day > $1.value.day }
            .prefix(Self.limit)
            .map { Conversation(id: "saved-" + $0.key, thread: $0.value.thread) }
        return Conversations(items: Array(migrated), currentId: nil)
    }

    /// 会話を覚えて、今の会話にする（新しく話した順の先頭へ。`limit` を超えたら古い順に落とす）
    func saveConversation(id: String, thread: [AskExchange], userId: String?) {
        guard userId?.isEmpty == false, !thread.isEmpty else { return }
        let thread = Array(thread.suffix(Self.turnLimit))
        var list = conversations(userId: userId)
        // 前の控えから移した会話（`saved-`）が同じ頼みで始まっていれば、この会話に置き換える（答えの控えを先に書くので二重になる）
        let first = RecentSearchesStore.normalized(thread[0].question)
        list.items.removeAll { $0.id == id || ($0.id.hasPrefix("saved-") && RecentSearchesStore.normalized($0.question) == first) }
        list.items.insert(Conversation(id: id, thread: thread), at: 0)
        if list.items.count > Self.limit { list.items = Array(list.items.prefix(Self.limit)) }
        list.currentId = id
        saveConversations(list, userId: userId)
    }

    /// 開くと出す会話を替える（nil で何も頼んでいない画面）
    func setCurrentConversation(_ id: String?, userId: String?) {
        guard userId?.isEmpty == false else { return }
        var list = conversations(userId: userId)
        guard list.currentId != id else { return }
        list.currentId = id.flatMap { id in list.items.contains { $0.id == id } ? id : nil }
        saveConversations(list, userId: userId)
    }

    /// 前の会話を全部消す（Pro の「前の会話」の一覧の「すべて消す」）。`keeping` の会話（いま画面に出ている会話）は残す
    func removeConversations(keeping id: String?, userId: String?) {
        var list = conversations(userId: userId)
        forgetAnswers(of: list.items.filter { $0.id != id }, userId: userId)
        list.items.removeAll { $0.id != id }
        if list.currentId != id { list.currentId = nil }
        saveConversations(list, userId: userId)
    }

    /// 会話を1つ消す（無料の「新しく頼む」、Pro の一覧の長押しと左へ払う）
    func removeConversation(_ id: String, userId: String?) {
        var list = conversations(userId: userId)
        forgetAnswers(of: list.items.filter { $0.id == id }, userId: userId)
        list.items.removeAll { $0.id == id }
        if list.currentId == id { list.currentId = nil }
        saveConversations(list, userId: userId)
    }

    /// 会話の控えだけを消す（UI テストの見本で、前の試験の会話を持ち越さない）。
    /// 空の一覧を書く（消すと、前からある答えの控えから移し直してしまう）
    func forgetConversations(userId: String?) {
        saveConversations(Conversations(), userId: userId)
    }

    /// 消した会話の頼みの答えの控え（同じ日の同じ頼み）も消す。会話の中のどの頼みで始まる控えも消す
    private func forgetAnswers(of removed: [Conversation], userId: String?) {
        guard !removed.isEmpty else { return }
        var map = all(userId: userId)
        let keys = Set(removed.flatMap { $0.thread.map { RecentSearchesStore.normalized($0.question) } })
        let before = map.count
        for key in keys { map[key] = nil }
        if map.count != before { save(map, userId: userId) }
    }

    private func saveConversations(_ list: Conversations, userId: String?) {
        guard userId?.isEmpty == false else { return }
        // 空でも書く（消したあとに前の答えの控えから移し直さない）
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: Self.conversationsKey(for: userId))
        }
    }

    /// ログアウトのとき: 答えの控えと会話、最近の検索に前の作りで混ざった頼みの文（答えの控えに同じ文があるもの）を消す。
    /// 打った語はアカウントごとの鍵で残す
    func forgetOnSignOut(userId: String?) {
        let asked = Set(all(userId: userId).keys)
        removeAll(userId: userId)
        let recent = RecentSearchesStore(defaults: defaults)
        for word in recent.words(userId: userId) where asked.contains(RecentSearchesStore.normalized(word)) {
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
