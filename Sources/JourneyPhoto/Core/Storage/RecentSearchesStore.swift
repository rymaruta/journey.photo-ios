import Foundation

/// この端末で前に探した言葉（探すの欄が空のときに、新しい順に出す）。
///
/// 2026-11-14 判断（人間工学の点検・owner「今ある機能を更に使いやすく」）:
/// - **端末の中だけに覚える。** サーバー・DB には送らない（探した言葉は人に見せるものではない）
/// - **既定でオン・設定の行は増やさない。** 要らない人は1つずつ（×）か全部（「すべて消す」）で消せる
/// - 出すのは新しい順に5つまで（`limit`）。持つのも5つまで（古いものは消える）
/// - 同じ言葉は1つにまとめ、いちばん上へ上げる（大文字小文字・前後の空白は同じとみなす）
/// - **鍵はアカウントごとに分ける**（`RecentSongsStore` と同じ。同じ端末の別の人に前の人の言葉が並ばないように）。
///   ログインしていない間は共通の鍵
///
/// 画面が開くたびに読み、探したときに書くだけなので `ObservableObject` にしない（配るものを増やさない）。
struct RecentSearchesStore {

    /// 出す・持つ数
    static let limit = 5
    /// 長すぎる言葉は覚えない（貼り付けた文など。探す欄の言葉ではない）
    static let maxLength = 60

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static let sharedKey = "journey-photo-recent-searches"

    static func key(for userId: String?) -> String {
        guard let userId, !userId.isEmpty else { return sharedKey }
        return "\(sharedKey):\(userId)"
    }

    /// 新しい順。読めない・壊れているときは空
    func words(userId: String?) -> [String] {
        let stored = defaults.stringArray(forKey: Self.key(for: userId)) ?? []
        return Array(stored.prefix(Self.limit))
    }

    /// 探した言葉を覚える。戻り値は覚えたあとの並び
    @discardableResult
    func remember(_ word: String, userId: String?) -> [String] {
        let next = Self.remembering(word, in: words(userId: userId))
        save(next, userId: userId)
        return next
    }

    /// 1つ消す。戻り値は消したあとの並び
    @discardableResult
    func remove(_ word: String, userId: String?) -> [String] {
        let next = words(userId: userId).filter { Self.normalized($0) != Self.normalized(word) }
        save(next, userId: userId)
        return next
    }

    /// 全部消す
    func removeAll(userId: String?) {
        defaults.removeObject(forKey: Self.key(for: userId))
    }

    /// 退会した人の控えを消す（`AccountLocalData`）
    func removeData(for userId: String) {
        defaults.removeObject(forKey: Self.key(for: userId))
    }

    private func save(_ words: [String], userId: String?) {
        if words.isEmpty {
            defaults.removeObject(forKey: Self.key(for: userId))
        } else {
            defaults.set(words, forKey: Self.key(for: userId))
        }
    }

    // MARK: - 決まり（単体テストで見張る）

    /// `word` を先頭に足した並び。空・長すぎる言葉は足さない。同じ言葉は前の位置から外す
    static func remembering(_ word: String, in words: [String]) -> [String] {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { return words }
        let key = normalized(trimmed)
        let rest = words.filter { normalized($0) != key }
        return Array(([trimmed] + rest).prefix(limit))
    }

    /// 探す画面に出すか。**欄が空の間だけ**、言葉があり、「発見」の顔か欄を押しているとき
    /// （カテゴリだけで絞って結果を見ている間は、結果の上に割り込ませない）
    static func shows(query: String, words: [String], discovering: Bool, focused: Bool) -> Bool {
        query.isEmpty && !words.isEmpty && (discovering || focused)
    }

    /// 同じ言葉かを比べる形（前後の空白・大文字小文字・全角半角の違いを無視）
    static func normalized(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
    }
}
