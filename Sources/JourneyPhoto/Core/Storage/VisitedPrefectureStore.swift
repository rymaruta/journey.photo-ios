import Foundation

/// 行った県マップの記録（`VisitedPrefectures`）を**この端末にだけ**置く（札 #503・2026-11-08 owner 決定）。
///
/// - 保存先は UserDefaults。サーバー・DB・API には送らない（機種変更で消える・Web には出ない、が弱点）
/// - 鍵は人ごとに分ける（同じ端末で人が替わったとき、前の人の記録を見せない）。未ログインでは使わない
/// - 退会で消す（`AccountLocalData`・審査 5.1.1(v)）。ログアウトでは消さない（同じ人が入り直すと戻る）
/// - 読めない・形の違う値は**空として読む**。県名が47都道府県に無い行・回数が上限（99）を超える行は落とす
///   （`VisitedPrefectures.init`）。新しい欄を足しても古い値を捨てないよう、欄ごとに `decodeIfPresent`
struct VisitedPrefectureStore {

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static let key = "journey-photo-visited-prefectures"

    static func key(for userId: String) -> String { "\(key):\(userId)" }

    /// 保存する形。`VisitedPrefectures` 本体の欄をそのまま Codable にはしない（内部の `private(set)` を
    /// 外へ出さないため・形を変えても読めるように）
    private struct Stored: Codable {
        var v: Int
        var visits: [String: [String]]
        var dismissed: [String]
        var seenRounds: Int?

        init(v: Int, visits: [String: [String]], dismissed: [String], seenRounds: Int?) {
            self.v = v
            self.visits = visits
            self.dismissed = dismissed
            self.seenRounds = seenRounds
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            v = try c.decodeIfPresent(Int.self, forKey: .v) ?? 1
            visits = try c.decodeIfPresent([String: [String]].self, forKey: .visits) ?? [:]
            dismissed = try c.decodeIfPresent([String].self, forKey: .dismissed) ?? []
            seenRounds = try c.decodeIfPresent(Int.self, forKey: .seenRounds)
        }
    }

    func load(for userId: String?) -> VisitedPrefectures {
        guard let userId, !userId.isEmpty,
              let data = defaults.data(forKey: Self.key(for: userId)),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return VisitedPrefectures() }
        // 読めない日付の行は落とす
        let visits = stored.visits.mapValues { $0.filter(VisitedDay.isValid) }
        return VisitedPrefectures(visits: visits, dismissed: Set(stored.dismissed), seenRounds: stored.seenRounds)
    }

    func save(_ record: VisitedPrefectures, for userId: String?) {
        guard let userId, !userId.isEmpty else { return }
        let stored = Stored(v: 1, visits: record.visits, dismissed: record.dismissed.sorted(),
                            seenRounds: record.seenRounds)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: Self.key(for: userId))
    }

    /// 退会した人の記録を消す（`AccountLocalData`）
    func removeData(for userId: String) {
        defaults.removeObject(forKey: Self.key(for: userId))
    }
}
