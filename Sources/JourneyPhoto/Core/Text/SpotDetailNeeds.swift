import Foundation

/// **詳細を読む撮影スポットを選ぶ**（分けた置き場・2026-10-07・photo-gallery の `docs/spot-feed-sharding.md`）。
///
/// 索引（`spot-feed/index.json`）の行は写真・概要・季節/時間帯の文を持たない。画面は**出す行だけ**を
/// ここで選び、`OfficialSpotService.withDetails` で詳細を重ねる。選ぶのは**まだ索引だけの行**
/// （`OfficialSpot.isIndexOnly`）だけ——古い置き場の行・重ね済みの行は空になり、通信しない。
///
/// 詳細の和が小さいうち（`OfficialSpotService.detailPrefetchBudget`）はサービスが索引のあと全区分を
/// 読むので、どれも空を返す（画面は今と同じ）。
enum SpotDetailNeeds {

    /// まだ索引だけの行
    static func indexOnly(_ spots: [OfficialSpot]) -> [OfficialSpot] {
        spots.filter(\.isIndexOnly)
    }

    /// `.task(id:)` の鍵。**要る行が変わったときだけ**読み直す（重ねたら空になって止まる）
    static func key(_ spots: [OfficialSpot]) -> String {
        indexOnly(spots).map(\.spotId).sorted().joined(separator: ",")
    }

    /// 旅行プランに入っているスポット（当日の光の行・プランの画面）
    static func inPlans(_ plans: [TripPlan], spots: [OfficialSpot]) -> [OfficialSpot] {
        var ids = Set<String>()
        for plan in plans {
            for day in plan.days {
                for item in day.items {
                    if case .spot(let spotId, _) = item { ids.insert(spotId) }
                }
            }
        }
        guard !ids.isEmpty else { return [] }
        return indexOnly(spots.filter { ids.contains($0.spotId) })
    }

    /// 「行きたい」に入れたスポット（マイページの行・行きたい場所の地図）
    static func wished(_ keys: Set<String>, spots: [OfficialSpot]) -> [OfficialSpot] {
        guard !keys.isEmpty else { return [] }
        return indexOnly(spots.filter { keys.contains(SavedSpotKey.official($0.slug)) })
    }

    /// ホームの札（季節・行きたい場所の季節）と段（いまの季節のスポット）、札の旅行プランの当日の行に出るスポット
    static func home(choices: [HomeTopCard.Choice], shelf: HomeSpotShelf.Shelf?, spots: [OfficialSpot]) -> [OfficialSpot] {
        var picked: [OfficialSpot] = []
        var plans: [TripPlan] = []
        for choice in choices {
            switch choice {
            case .inSeason(let spot, _, _), .wishlistSeason(let spot, _, _):
                picked.append(spot)
            case .departure(let plan, _), .onTrip(let plan, _):
                plans.append(plan)
            default:
                break
            }
        }
        picked += shelf?.entries.map(\.spot) ?? []
        let ids = Set(picked.map(\.spotId))
        let fromChoices = indexOnly(spots.filter { ids.contains($0.spotId) })
        let fromPlans = inPlans(plans, spots: spots).filter { !ids.contains($0.spotId) }
        return fromChoices + fromPlans
    }
}
