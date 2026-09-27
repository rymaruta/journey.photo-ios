import Foundation

/// 旅行プランの画面の決まり（キャンバスの 17・17b・17c）。画面から切り離して試験する。
///
/// **Web の `/trips`（`app/trips/TripsClient.tsx`）と同じ約束:**
///
/// - 日付は `2026年12月24日` の形で出す。`YYYY-MM-DD` を画面に出さない
///   （`TakenDay` と同じ。読めない値は出さない）
/// - 足せるのは**保存済みの行きたい場所だけ**。自由入力にしない
///   （綴りの違う地名が増えて `/location/*` と噛み合わなくなる）
/// - 移動時間・費用・距離は**出さない**（計算していない数字）
enum TripPlanText {

    // MARK: - 日付

    /// 「2026年12月24日 〜 2026年12月25日」。片方しか無ければその1つ。
    /// **無ければ nil**（作り話をしない）
    static func period(start: String?, end: String?) -> String? {
        let s = TakenDay.label(start)
        let e = TakenDay.label(end)
        switch (s, e) {
        case let (s?, e?): return "\(s) 〜 \(e)"
        case let (s?, nil): return s
        case let (nil, e?): return e
        default: return nil
        }
    }

    /// 日の見出し「1 日目・2026年12月24日」。
    ///
    /// 日付は**その日が持っているもの**を先に使う（Web で付けた日付）。
    /// 無ければ**出発日から数える**——本人が入れた出発日に日数を足すだけで、
    /// 推測はしない。帰着日を越える日は数えない（旅程が日付より長いときに
    /// 帰ったあとの日付を出さない）。どちらも無ければ日付は出さない
    static func dayHeading(index: Int, day: TripDay, start: String?, end: String?) -> String {
        let number = L("\(index + 1) 日目", "Day \(index + 1)")
        guard let date = dayDate(index: index, day: day, start: start, end: end),
              let label = TakenDay.label(date) else { return number }
        return "\(number)・\(label)"
    }

    /// その日の日付（`YYYY-MM-DD`）。上の規則で決められなければ nil
    static func dayDate(index: Int, day: TripDay, start: String?, end: String?) -> String? {
        // **実在する日だけ**（`date(fromYMD:)` と同じ基準。2月31日を出さない）
        if let own = day.date, date(fromYMD: own) != nil { return own }
        guard let first = date(fromYMD: start),
              let shifted = calendar.date(byAdding: .day, value: index, to: first) else { return nil }
        if let last = date(fromYMD: end), shifted > last { return nil }
        return ymd(shifted)
    }

    /// 日付の計算は**グレゴリオ暦・UTC で固定**する。端末の暦（和暦など）や
    /// 時差で1日ずれない（Web の `photoDate.ts` が同じ理由で閲覧者のゾーンに寄せない）
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// `YYYY-MM-DD` → その日の 0 時（UTC）。**実在しない日は nil**（2月30日を繰り上げない）
    static func date(fromYMD raw: String?) -> Date? {
        guard let (y, m, d) = TakenDay.ymd(raw) else { return nil }
        let parts = DateComponents(calendar: calendar, year: y, month: m, day: d)
        guard let date = calendar.date(from: parts) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == y, back.month == m, back.day == d else { return nil }
        return date
    }

    /// 日付（**この型の UTC の暦で作った値**）→ `YYYY-MM-DD`。
    /// ⚠️ **ピッカーの値を渡さない**——端末のゾーンのその日なので `ymd(pickedIn:)` を使う
    static func ymd(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 日付ピッカーが返した値（**端末のゾーンの**その日）を、その日の
    /// `YYYY-MM-DD` にする。UTC で読むと、日本の朝に選んだ日が前日になる
    static func ymd(pickedIn zone: TimeZone, _ date: Date) -> String {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = zone
        let c = local.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// `YYYY-MM-DD` を、端末のゾーンのその日の正午にする（ピッカーに渡す値）。
    /// 正午にするのは、夏時間の切り替わりで日がずれないため
    static func pickerDate(fromYMD raw: String?, in zone: TimeZone) -> Date? {
        // 実在しない日は渡さない（2月30日を3月2日に繰り上げてピッカーに出さない）
        guard date(fromYMD: raw) != nil, let (y, m, d) = TakenDay.ymd(raw) else { return nil }
        var local = Calendar(identifier: .gregorian)
        local.timeZone = zone
        return local.date(from: DateComponents(year: y, month: m, day: d, hour: 12))
    }

    // MARK: - 数

    /// 「00 か所」。**数えた値**
    static func placeCount(_ n: Int) -> String {
        L("\(n) か所", n == 1 ? "1 place" : "\(n) places")
    }

    /// 一覧の副文。**聞けたときだけ数を出す**（失敗した回に「0件」と言い切らない）
    static func listSubtitle(count: Int?) -> String {
        guard let count else {
            return L("行きたい場所を、いつ・どの順で回るかに並べる。", "Plan where to go, and when.")
        }
        return L("旅行プラン \(count) 件", count == 1 ? "1 trip" : "\(count) trips")
    }

    // MARK: - 行きたい場所から選ぶ

    /// 選べる1か所。
    struct Choice: Identifiable, Equatable {
        let item: TripItem
        let name: String
        /// 撮影スポットの「県 · 市」。撮影地には無い
        let regionLabel: String?
        var isOfficial: Bool { if case .spot = item { return true } else { return false } }
        var id: String {
            switch item {
            case .spot(let spotId, _): return "spot:\(spotId)"
            case .location(let slug, _): return "location:\(slug)"
            }
        }
    }

    /// 「行きたい」の鍵から、日程に置ける候補を作る。撮影スポットが先、撮影地が後。
    ///
    /// - 撮影スポット（`SPOT-<slug>`）は**索引で `spotId` が引けるものだけ**。
    ///   プランに入るのは台帳の鍵で、slug からは作れない（Web も引けないものは出さない）
    /// - 撮影地は**いまの写真から導いた地点に在るものだけ**（マイページの
    ///   「行きたい場所」と同じ行＝押した覚えのある行がそのまま並ぶ）
    static func choices(wishlistKeys: Set<String>,
                        places: [DerivedSpot.Place],
                        index: [OfficialSpot]) -> [Choice] {
        let bySlug = Dictionary(index.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        // **同じ鍵は1件に。** 撮影地は綴りの揺れ（空白の数・「/」）で同じスラッグに
        // なることがあり、そのまま並べると同じ行が2つ出る（Web はスラッグで1件）
        var seen = Set<String>()
        let spots = wishlistKeys
            .compactMap { key -> Choice? in
                guard let slug = SavedSpotKey.slug(fromOfficial: key), let spot = bySlug[slug] else { return nil }
                return Choice(item: .spot(spotId: spot.spotId, note: nil), name: spot.name,
                              regionLabel: spot.regionLabel)
            }
            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
            .filter { seen.insert($0.id).inserted }
        // 同じスラッグの地点が2つあるときは**`places` の先に来る方**の名前を採る。
        // 日程に入ったあとの行の名前（`label(for:)`）と同じ規則——並べ替えてから
        // 1件に寄せると、選んだ名前と入った行の名前が食い違う
        let locations = places
            .filter { !$0.slug.isEmpty && wishlistKeys.contains($0.slug) && !SavedSpotKey.isOfficial($0.slug) }
            .map { Choice(item: .location(slug: $0.slug, note: nil), name: $0.label, regionLabel: nil) }
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
        return spots + locations
    }

    /// 項目に出す名前。**引けないときは鍵をそのまま出す**
    /// ——「不明な場所」のような、こちらで作った言葉を置かない（Web の `itemLabel`）
    static func label(for item: TripItem, index: [OfficialSpot], places: [DerivedSpot.Place]) -> String {
        switch item {
        case .spot(let spotId, _):
            let name = index.first { $0.spotId == spotId }?.name ?? ""
            return name.isEmpty ? spotId : name
        case .location(let slug, _):
            if let place = places.first(where: { $0.slug == slug }) { return place.label }
            return slug.removingPercentEncoding ?? slug
        }
    }

    // MARK: - 保存

    /// **変えていなければ保存を押させない**（無駄な往復と、他の端末の編集の打ち消しを避ける）
    static func isDirty(plan: TripPlan, days: [TripDay], start: String?, end: String?) -> Bool {
        plan.days != days || (plan.startDate ?? "") != (start ?? "") || (plan.endDate ?? "") != (end ?? "")
    }

    /// 送る差分。**変えた項目だけ**（Web の `/user/edit` と同じ——他の端末の編集を消さない）。
    /// 日付を消したときは空文字を送る（サーバーが消す）
    static func patch(plan: TripPlan, days: [TripDay], start: String?, end: String?) -> TripPlanService.Patch {
        var p = TripPlanService.Patch()
        if plan.days != days { p.days = days }
        if (plan.startDate ?? "") != (start ?? "") { p.startDate = start ?? "" }
        if (plan.endDate ?? "") != (end ?? "") { p.endDate = end ?? "" }
        return p
    }
}
