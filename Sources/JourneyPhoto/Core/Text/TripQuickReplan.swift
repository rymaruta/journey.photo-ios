import Foundation

/// 「もっとゆっくり」「雨なら」を、AI を使わずにアプリが決まった手順で組み直す（2026-11-24 判断）。
///
/// owner（2026-11-24・TestFlight 1.2.1）「『もっとゆっくり』とかのボタンの使い勝手悪すぎる」。前は押すたびに AI を1回使い、
/// 待って、「今 | 組み直した案」を見比べ、「この案にする」を押すまで変わらなかった（押す2回と待ち時間）。しかも日数は変えられないので、
/// 「ゆっくり」は1日3か所以下のプランでは何も変わらず「今の日程のままがよさそうです」と出た。端末の AI が無い iPhone の無料の人は
/// 押しても「この iPhone では AI で組み直せません」だった。
///
/// 今の形（案のページ「旅行プランの組み直しのボタン」の推奨）:
/// - チップを押したら**すぐ日程が変わる**（1回）。変えた所は知らせの帯で言い、「元に戻す」で戻せる（`TripReplan.Step`）
/// - AI を使わない（回数0・費用0円・同意のシートなし・圏外でも動く・どの iPhone でも同じ）
/// - 外した所は日の下の「外しました　戻す」へ（消さない）
/// - AI は「書いて頼む」（自由な文）にだけ使う
enum TripQuickReplan {

    struct Result: Equatable {
        let days: [TripDay]
        /// 日程から外した所（日の下の「外しました　戻す」へ）
        let dropped: [TripAIRevise.Dropped]
        /// 別の日へ移した数
        let moved: Int
        /// 入れ替えた数（雨: 屋外 → 屋内）
        let swapped: Int
        /// 知らせの帯の1行
        let line: String
        var changed: Bool { !dropped.isEmpty || moved > 0 || swapped > 0 }
    }

    // MARK: - もっとゆっくり

    /// 1日の上限。いちばん多い日より1つ少なく、3を超えない。2より下げない（2か所以下なら nil＝もう減らさない）
    static func slowerCap(_ counts: [Int]) -> Int? {
        let most = counts.max() ?? 0
        guard most > 2 else { return nil }
        return max(2, min(3, most - 1))
    }

    /// 1日の数を上限まで減らす。あふれた所は、寄り道がいちばん大きい所（前後の場所から外れている所）から順に外し、
    /// 空きのある別の日で 30km 以内に近い所があればそこへ移す。無ければ「外しました　戻す」へ
    static func slower(_ days: [TripDay], coords: (TripItem) -> Photo.Coords?) -> Result {
        guard let cap = slowerCap(days.map(\.items.count)) else {
            return Result(days: days, dropped: [], moved: 0, swapped: 0,
                          line: L("もう1日2か所までです。日程はそのままです", "Already at 2 places a day. No change."))
        }
        var out = days
        var overflow: [(day: Int, index: Int, item: TripItem)] = []
        for d in out.indices {
            // 元の並びの番号を覚えて外す（「戻す」で元の位置へ）
            var rows = out[d].items.enumerated().map { (index: $0.offset, item: $0.element) }
            while rows.count > cap {
                let pick = mostOutOfWay(rows.map(\.item), coords: coords)
                overflow.append((day: d, index: rows[pick].index, item: rows[pick].item))
                rows.remove(at: pick)
            }
            out[d].items = rows.map(\.item)
        }
        var dropped: [TripAIRevise.Dropped] = []
        var moved = 0
        for o in overflow {
            if let (target, at) = bestDay(for: o.item, from: o.day, in: out, cap: cap, coords: coords) {
                out[target].items.insert(o.item, at: at)
                moved += 1
            } else {
                dropped.append(TripAIRevise.Dropped(day: o.day, index: o.index, item: o.item))
            }
        }
        let line: String
        switch (moved, dropped.count) {
        case (0, let n): line = L("1日\(cap)か所までにしました。\(n)か所を外しました", "Up to \(cap) a day. Removed \(n).")
        case (let m, 0): line = L("1日\(cap)か所までにしました。\(m)か所を別の日へ", "Up to \(cap) a day. Moved \(m).")
        case (let m, let n): line = L("1日\(cap)か所までにしました。\(m)か所を別の日へ、\(n)か所を外しました",
                                      "Up to \(cap) a day. Moved \(m), removed \(n).")
        }
        return Result(days: out, dropped: dropped, moved: moved, swapped: 0, line: line)
    }

    /// 寄り道がいちばん大きい所の番号（前後を結んだ線からの遠回り）。座標の無い所は外さない（最後の手段で末尾）
    static func mostOutOfWay(_ items: [TripItem], coords: (TripItem) -> Photo.Coords?) -> Int {
        let c = items.map(coords)
        var best = -1
        var bestDetour = -1.0
        for i in items.indices {
            guard let here = c[i] else { continue }
            let prev = i > 0 ? c[i - 1] : nil
            let next = i + 1 < items.count ? c[i + 1] : nil
            let detour: Double
            switch (prev, next) {
            case let (p?, n?): detour = km(p, here) + km(here, n) - km(p, n)
            case let (p?, nil): detour = km(p, here)
            case let (nil, n?): detour = km(here, n)
            default: detour = 0
            }
            if detour > bestDetour { bestDetour = detour; best = i }
        }
        return best >= 0 ? best : items.count - 1
    }

    /// 移す先（空きのある日のうち、いちばん近い所がある日。30km より遠ければ移さない）と、入れる位置（遠回りがいちばん小さい所）
    private static func bestDay(for item: TripItem, from day: Int, in days: [TripDay], cap: Int,
                                coords: (TripItem) -> Photo.Coords?) -> (Int, Int)? {
        guard let here = coords(item) else { return nil }
        var best: (day: Int, km: Double)?
        for d in days.indices where d != day && days[d].items.count < cap {
            let near = days[d].items.compactMap(coords).map { km($0, here) }.min()
            guard let near, near <= moveKm else { continue }
            if best == nil || near < best!.km { best = (d, near) }
        }
        guard let target = best?.day else { return nil }
        let row = days[target].items.map(coords)
        var at = row.count
        var cost = Double.greatestFiniteMagnitude
        for i in 0...row.count {
            let p = i > 0 ? row[i - 1] : nil
            let n = i < row.count ? row[i] : nil
            let add: Double
            switch (p, n) {
            case let (p?, n?): add = km(p, here) + km(here, n) - km(p, n)
            case let (p?, nil): add = km(p, here)
            case let (nil, n?): add = km(here, n)
            default: add = 0
            }
            if add < cost { cost = add; at = i }
        }
        return (target, at)
    }

    /// 別の日へ移してよい近さ（これより遠い日へは移さず「外しました」へ）
    static let moveKm = 30.0

    // MARK: - 雨なら

    /// 雨で楽しみにくい種類（台帳の `category`）。2026-11-24 の本番の台帳の種類から選んだ
    static let outdoor: Set<String> = [
        "山岳", "島", "公園", "海岸", "湖沼", "滝", "樹木", "橋", "庭園", "展望台", "渓谷", "岬", "高原", "棚田", "灯台", "湿原",
        "湖", "並木道", "渓流", "森林", "峡谷", "池", "自然現象", "火山", "ダム", "道路", "古道", "遊園地", "動物園", "城跡",
        "遺跡", "港", "運河", "農村", "湧水", "動物",
    ]
    /// 雨の日に向く屋内の種類
    static let indoor: Set<String> = ["博物館", "美術館", "水族館", "市場", "劇場", "鍾乳洞", "洞窟", "教会", "アート", "温泉"]

    /// 入れ替える先を探す近さ（屋外の所から）
    static let rainKm = 20.0

    /// 屋外の所を、近くの屋内の観光スポット（日程に無い所）に入れ替える。同じ場所の位置に入れるので、並びと日は変わらない。
    /// 替えた元の所は「外しました　戻す」へ。近くに屋内が無い所はそのまま
    static func rain(_ days: [TripDay], spots lookup: [String: OfficialSpot], pool: [OfficialSpot]) -> Result {
        var out = days
        var used = Set(days.flatMap(\.items).compactMap { item -> String? in
            if case .spot(let id, _) = item { return id }
            return nil
        })
        let rooms = pool.filter { indoor.contains($0.category ?? "") && $0.coords != nil && !$0.isDraft }
        var dropped: [TripAIRevise.Dropped] = []
        var kept = 0
        for d in out.indices {
            for i in out[d].items.indices {
                guard case .spot(let id, let note) = out[d].items[i], let spot = lookup[id],
                      outdoor.contains(spot.category ?? ""), let here = spot.coords else { continue }
                var swapTo: OfficialSpot?
                var bestKm = rainKm
                for room in rooms where !used.contains(room.spotId) {
                    guard let c = room.coords else { continue }
                    let d = km(here, c)
                    if d < bestKm || (d == bestKm && swapTo.map { room.spotId < $0.spotId } == true) {
                        bestKm = d
                        swapTo = room
                    }
                }
                guard let swap = swapTo else { kept += 1; continue }
                used.insert(swap.spotId)
                dropped.append(TripAIRevise.Dropped(day: d, index: i, item: .spot(spotId: id, note: note)))
                out[d].items[i] = .spot(spotId: swap.spotId, note: nil)
            }
        }
        let line: String
        if dropped.isEmpty {
            line = kept == 0
                ? L("雨でも回りやすい所ばかりです。日程はそのままです", "Already rain-friendly. No change.")
                : L("近くに屋内の観光スポットが見つかりませんでした。日程はそのままです", "No indoor spots nearby. No change.")
        } else if kept == 0 {
            line = L("屋外の\(dropped.count)か所を、近くの屋内に替えました", "Swapped \(dropped.count) outdoor places for indoor ones nearby.")
        } else {
            line = L("屋外の\(dropped.count)か所を近くの屋内に替えました。\(kept)か所は近くに屋内が無いのでそのままです",
                     "Swapped \(dropped.count) for indoor places. \(kept) had none nearby.")
        }
        return Result(days: out, dropped: dropped, moved: 0, swapped: dropped.count, line: line)
    }

    static func km(_ a: Photo.Coords, _ b: Photo.Coords) -> Double { TripAICandidates.km(a, b) }
}
