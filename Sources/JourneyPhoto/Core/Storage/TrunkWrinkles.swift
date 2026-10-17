import Foundation

/// 貼ったあとに動かしたラベルの「よれ」（自分の手で貼る・2026-10-17 次の版）。
///
/// サーバーは置き場（x・y・rot）しか持たないので、**動かした回数はこの端末にだけ控える**
/// （2026-10-17 判断: よれは飾りで、別の端末で消えても困らない。サーバーの1行の残りは 1.7KB しかない）。
/// 人ごとに分け、退会で消す（`AccountLocalData`）。多くても 200 枚ぶん（古いものから落とす）
struct TrunkWrinkles {

    static let maxEntries = 200

    static func key(_ userId: String) -> String { "trunk.wrinkles.\(userId)" }

    private let defaults: UserDefaults
    private let userId: String?

    init(userId: String?, defaults: UserDefaults = .standard) {
        self.userId = userId
        self.defaults = defaults
    }

    /// ラベルの id → 動かした回数
    var moves: [String: Int] {
        guard let userId, let raw = defaults.dictionary(forKey: Self.key(userId)) else { return [:] }
        return raw.compactMapValues { ($0 as? Int).map { max(0, $0) } }
    }

    /// よれの強さ（`TrunkPlacement.wrinkle`）。描く側へ渡す形
    var strengths: [String: Double] {
        moves.mapValues(TrunkPlacement.wrinkle(moves:))
    }

    /// 1回動かした
    func noteMoved(_ id: String) {
        guard let userId else { return }
        var all = moves
        all[id, default: 0] += 1
        if all.count > Self.maxEntries {
            // 回数の少ないものから落とす（同じなら id の順・決まった落とし方）
            let drop = all.sorted { ($0.value, $0.key) < ($1.value, $1.key) }.prefix(all.count - Self.maxEntries).map(\.key)
            for key in drop { all.removeValue(forKey: key) }
        }
        defaults.set(all, forKey: Self.key(userId))
    }
}
