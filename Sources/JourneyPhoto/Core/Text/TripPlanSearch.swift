import Foundation

/// 旅行プランの「場所を足す」のシートで、**打った字から場所を探す**（2026-11-12 判断・資料「みんなで埋める旅行プラン」
/// の 1.1.85・札 #570・モックの場面5）。
///
/// - 欄が空のときは、今までどおり「行きたい場所」を並べる（今のシートと同じ中身が最初に見える）
/// - 打つと2つの組をまとめて並べる: **行きたい場所**（打った字に当たるものだけ）と、**観光スポット**（台帳・
///   `OfficialSpotIndex.matches`。名前・読み・別名で当てるので、ひらがなや別名でも当たる）。行きたい場所に
///   入っている観光スポットは上の組だけに出す（同じ所を2つ並べない）
/// - **打った字そのものは日程に入れない。** 入るのは結果から選んだ場所だけ（台帳の鍵 `spotId` か撮影地の slug）。
///   「自由入力を置かない」（2026-10・`TripPlanPickSheet` の注記）の理由（綴りの揺れが `/location/*` と噛み合わない）は守る
/// - 地図の場所（店・駅・宿・`MKLocalSearch`）は 1.1.86（日程の項目の種類が増える・サーバーの口の変更が要る）。ここでは作らない
/// - 台帳の運営の下書き（`isDraft`）は検索の結果に出さない（`DMTripPlaces.NameTable` と同じ。人が確かめていない行を勧めない）
///
/// 画面を持たない層に置いて、Linux の `swift test` で見張る
enum TripPlanSearch {

    /// 観光スポットの組に並べる数の上限（打つたびに描き直すので、長い一覧を作らない）
    static let spotLimit = 30

    /// 並べる組
    struct Groups: Equatable {
        /// 行きたい場所（欄が空なら全部）
        var wanted: [TripPlanText.Choice]
        /// 観光スポット（台帳。欄が空なら空）
        var spots: [TripPlanText.Choice]
        var isEmpty: Bool { wanted.isEmpty && spots.isEmpty }
    }

    /// 打った字から組を作る。
    /// - `wanted`: 行きたい場所（`TripPlanText.choices`）
    /// - `index`: 撮影スポットの索引、`aliases`: slug → 別名（取れなければ空）
    static func groups(query: String, wanted: [TripPlanText.Choice], index: [OfficialSpot],
                       aliases: [String: [String]] = [:], limit: Int = spotLimit) -> Groups {
        let needle = OfficialSpotIndex.spotName(query)
        guard !needle.isEmpty else { return Groups(wanted: wanted, spots: []) }
        let published = index.filter { !$0.isDraft }
        let hits = OfficialSpotIndex.matches(published, query: query, aliases: aliases)
        let hitIds = Set(hits.map(\.spotId))
        let wantedHits = wanted.filter { choice in
            switch choice.item {
            case .spot(let spotId, _):
                // 行きたい場所の観光スポットは、台帳の当て方（読み・別名）でも当てる。下書きの行は名前で当てる
                return hitIds.contains(spotId) || OfficialSpotIndex.spotName(choice.name).contains(needle)
            case .location:
                return OfficialSpotIndex.spotName(choice.name).contains(needle)
            }
        }
        let shown = Set(wantedHits.map(\.id))
        var seen = Set<String>()
        let spots = hits
            .map { TripPlanText.Choice(item: .spot(spotId: $0.spotId, note: nil), name: $0.name,
                                       regionLabel: $0.regionLabel, isDraft: $0.isDraft) }
            .filter { !shown.contains($0.id) && seen.insert($0.id).inserted }
        return Groups(wanted: wantedHits, spots: Array(spots.prefix(max(limit, 0))))
    }

    // MARK: - 行の状態

    /// 結果の1行の状態
    enum RowState: Equatable {
        /// 押せば選んでいる日に入る
        case open
        /// このシートで入れた（もう一度押すと取り消す）
        case added
        /// 前から日程に入っている（何日目か・押せない）
        case inPlan(day: Int)
        /// 選んでいる日がいっぱい（押せない）
        case full
    }

    /// 行の状態。**前から日程に入っている場所は押させない**（同じ場所を2つ入れない・モックの場面5）。
    /// このシートで入れた場所は、入った日を選んでいる間だけ「取り消す」にする
    static func state(of item: TripItem, days: [TripDay], selectedDay: Int, addedHere: [Added]) -> RowState {
        let key = SavedSpotsTrip.itemKey(item)
        if addedHere.contains(where: { $0.key == key && $0.day == selectedDay }),
           days.indices.contains(selectedDay),
           days[selectedDay].items.contains(where: { SavedSpotsTrip.itemKey($0) == key }) {
            return .added
        }
        if let day = TripPlanEdit.dayContaining(item, in: days) { return .inPlan(day: day) }
        guard days.indices.contains(selectedDay),
              days[selectedDay].items.count < TripPlanService.itemsPerDayMax else { return .full }
        return .open
    }

    /// このシートで入れた場所（取り消せるのはこれだけ。前から入っていた場所や、ほかの人が足した場所は触らない）
    struct Added: Equatable {
        let key: String
        let day: Int
    }

    /// 取り消す。**その日の中で、このシートで入れた項目のうち最後の1つ**を外す（見つからなければ nil）
    static func undoing(_ item: TripItem, day: Int, in days: [TripDay]) -> [TripDay]? {
        guard days.indices.contains(day) else { return nil }
        let key = SavedSpotsTrip.itemKey(item)
        guard let at = days[day].items.lastIndex(where: { SavedSpotsTrip.itemKey($0) == key }) else { return nil }
        var out = days
        out[day].items.remove(at: at)
        return out
    }

    // MARK: - 文

    /// 行の2行目（状態が分かる字。色だけで伝えない）
    static func stateLine(_ state: RowState) -> String? {
        switch state {
        case .open: return nil
        case .added: return L("入れました。もう一度押すと取り消します", "Added. Tap again to undo.")
        case .inPlan(let day): return L("\(day + 1)日目に入っています", "Already on day \(day + 1)")
        case .full: return nil
        }
    }

    /// 見つからなかったときの文（地図の場所の組は 1.1.86 なので、ここでは言わない）
    static func noResults(_ query: String) -> String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return L("「\(q)」は見つかりません。ほかの言い方で探してください。",
                 "No results for “\(q)”. Try another word.")
    }

    /// 欄の見本の字
    static let placeholder = L("行きたい場所、観光スポットから探す", "Search saved places and spots")

    /// 選んでいる日の一言（いっぱいの日は「いっぱい」と言う）
    static func hint(dayCount: Int) -> String {
        let left = TripPlanService.itemsPerDayMax - dayCount
        if left <= 0 { return L("この日はいっぱいです", "This day is full") }
        return L("押すとこの日に入ります。シートは開いたままです", "Tap to add to this day. The sheet stays open.")
    }
}
