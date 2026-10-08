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

    // MARK: - 長い一覧（地図の「スポット」「リスト」の札・2026-10-08）

    /// 長い一覧で、一度に詳細を読む行の数（1頁）。
    ///
    /// 地図の「スポット」「リスト」の札は全件（数千件）を Lazy に並べる。全件の詳細を読むと、
    /// 分けた置き場で**全区分を読むのと同じ**になるので、**見えた行の頁と次の頁まで**だけ読む
    static let listPage = 30

    /// 最初の深さ（頭から何行）。**頭の頁と次の頁**——頭の行が見えた瞬間に深さが上がって `.task` を
    /// 走り直させないように、`listDepth(after: 0..)` と同じ値から始める
    static let firstDepth = listPage * 2

    /// 一覧の `index` 番目（0 から）の行が見えたときの、詳細を読む深さ（頭から何行）。
    /// **深くなるだけ**で浅くはしない（戻ったときに読み直さない）。頁ごとに上がるので、
    /// 1行見えるたびに鍵が変わって読み直すことはない
    static func listDepth(after index: Int, current: Int) -> Int {
        max(current, (max(0, index) / listPage + 2) * listPage)
    }

    /// 一覧の深さと、**それを測ったときの絞り込み**（語・カテゴリ）。
    ///
    /// 絞り込みが変わったら、並びも変わるので深さは頭に戻す。`onChange` で戻すと1回遅れ
    /// （古い深さのまま新しい並びの頭から何百行も読みに行き、区分の読み込みは取り消せない）、
    /// その札が出ていない間は戻らない。そこで**描く回の中で**「測ったときと同じなら測った深さ、
    /// 違えば最初の深さ」を決める（`depth(query:category:)`・2026-10-08 のレビュー）
    struct ListDepth: Equatable {
        var query: String = ""
        var category: String? = nil
        var depth: Int = SpotDetailNeeds.firstDepth

        /// 今の絞り込みでの深さ
        func depth(query: String, category: String?) -> Int {
            self.query == query && self.category == category ? depth : SpotDetailNeeds.firstDepth
        }

        /// 今の絞り込みで `index` 番目の行が見えたあとの値
        func seen(_ index: Int, query: String, category: String?) -> ListDepth {
            ListDepth(query: query, category: category,
                      depth: SpotDetailNeeds.listDepth(after: index, current: depth(query: query, category: category)))
        }
    }

    /// 並んだ行の**頭から `depth` 行**のうち、まだ索引だけの行
    static func listed(_ spots: [OfficialSpot], through depth: Int) -> [OfficialSpot] {
        indexOnly(Array(spots.prefix(max(0, depth))))
    }

    /// 地図の「スポット」の札（近い順の一覧）: **頭から `depth` 行**のうち、まだ索引だけの行
    static func mapSpotList(_ rows: [OfficialSpotList.Row], through depth: Int) -> [OfficialSpot] {
        indexOnly(rows.prefix(max(0, depth)).map(\.spot))
    }

    /// 地図の「リスト」の札で、**開いている県**の撮影スポットの行を、画面に並ぶ順につないだもの。
    /// 閉じた県の行は描かないので入れない（件数だけ出る）。詳細を読む行は、これを `listed` で頭から切る
    static func mapRegionRows(_ sections: [RegionList.Section],
                              isOpen: (RegionList.Section) -> Bool) -> [OfficialSpot] {
        sections.filter(isOpen).flatMap { $0.spots.map(\.spot) }
    }

    /// 一覧の詳細を読む `.task(id:)` の鍵。**読み込みの回も入れる**——読んでいる途中に読み直しが
    /// 始まると、その回の答えは捨てる（`PhotoMapViewModel.loadListDetails`）。行が同じ索引だけの行で
    /// 返っても回が変われば鍵が変わり、読み直す。要る行が無ければ回によらず空（走っても何もしない）
    static func listTaskId(_ needs: [OfficialSpot], generation: Int) -> String {
        let key = key(needs)
        return key.isEmpty ? "" : "\(generation)|\(key)"
    }

    /// 今の行に、重ねた行（詳細あり）だけを差し込む。
    ///
    /// **待っている間に変わった行を古い写しで戻さない**——差し込むのは、今まだ索引だけの行に、
    /// 同じ `spotId` の詳細つきの行が届いたときだけ。待っている間に読み直した索引の行・
    /// 別の回が先に重ねた行はそのまま（`PhotoMapViewModel` のピンと一覧が使う）
    static func overlay(_ current: [OfficialSpot], with merged: [OfficialSpot]) -> [OfficialSpot] {
        let detailed = Dictionary(merged.filter { !$0.isIndexOnly }.map { ($0.spotId, $0) },
                                  uniquingKeysWith: { first, _ in first })
        guard !detailed.isEmpty else { return current }
        return current.map { row in
            guard row.isIndexOnly, let hit = detailed[row.spotId] else { return row }
            return hit
        }
    }
}
