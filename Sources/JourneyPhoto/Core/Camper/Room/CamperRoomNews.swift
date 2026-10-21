import Foundation

// 新しく届いた家具の印と、初めての人への短い手引き（2026-10-21・owner「もっとこうした方がユーザー使いやすい」）。
//
// - 新しい家具: 届いたのに、まだ置いても寄りで見てもいない家具。棚と図鑑の枠に真鍮の点、「置く」の道具に件数バッジ。
//   人ごとにこの端末へ覚える（`camper.room.seen.<userId>`・退会で消す）。
//   2026-10-21 判断: 初めて開いた時は、その時に持っている家具を全部「見た」にする（最初から持っている 27 点に印が並ぶと、
//   新しく届いた物の合図にならない）。
// - 手引き: 部屋に初めて入った時だけ、長押しで持ち上げる・二本指でひねって回す・二度押しで寄る、の 3 行（端末に 1 回）。

struct CamperRoomSeenStore {
    static func key(_ userId: String) -> String { "camper.room.seen.\(userId)" }

    private let defaults: UserDefaults
    let userId: String?

    init(userId: String?, defaults: UserDefaults = .standard) {
        self.userId = userId
        self.defaults = defaults
    }

    /// 見た家具。まだ一度も覚えていなければ nil
    func load() -> Set<String>? {
        guard let userId, let list = defaults.stringArray(forKey: Self.key(userId)) else { return nil }
        return Set(list)
    }

    func save(_ seen: Set<String>) {
        guard let userId else { return }
        defaults.set(seen.sorted(), forKey: Self.key(userId))
    }

    /// 新しい家具（持っているのに見ていない）。初めての時は今の持ち物を全部見たにして、空を返す。
    /// 写真を読み終える前は空を返し、控えを読みも書きもしない（2026-10-21 見直し: 読む前の初回に最初の 27 点だけを
    /// 見たにすると、写真が届いたとき前から持っていた家具が全部「新しい」と出た。車庫の `openArrivals` と同じ考え）
    func news(owned: Set<String>, photosLoaded: Bool) -> Set<String> {
        guard photosLoaded else { return [] }
        guard let seen = load() else {
            save(owned)
            return []
        }
        return owned.subtracting(seen)
    }

    /// 見たにする（置いた・寄りで見た）
    func markSeen(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        var seen = load() ?? []
        let before = seen.count
        seen.formUnion(ids)
        if seen.count != before { save(seen) }
    }

    static func removeData(for userId: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(userId))
    }
}

/// 初めての人への手引き（端末に 1 回）
enum CamperRoomCoach {
    static let key = "camper.room.coach.v1"

    static func shouldShow(_ defaults: UserDefaults = .standard) -> Bool { !defaults.bool(forKey: key) }

    static func done(_ defaults: UserDefaults = .standard) { defaults.set(true, forKey: key) }
}
