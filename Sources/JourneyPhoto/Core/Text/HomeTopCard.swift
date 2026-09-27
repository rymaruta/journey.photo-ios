import Foundation

/// ホームの上段に出す札を**1枚だけ**決める（板 01・55「開く場面ごとに1枚」）。
///
/// レビュー（2026-09-27）で一番欠けていたのが「毎回開きたくなるか」だった。
/// ホームが毎日同じ形で、旅の前・最中・後で出す物が変わらない。材料は
/// もうアプリの中にある（旅行プラン・旅の一冊・自分の写真の日付）ので、
/// **その日に当たる1枚を選んで上に出す**。
///
/// 優先順（上ほど強い・同じ日に当たる物が複数あっても1枚だけ）:
///
///  1. **出発が近い** — 出発日まで 0〜`departureWindowDays` 日の旅行プラン
///  2. **旅の最中** — 出発日を過ぎ、帰着日までの旅行プラン
///  3. **一冊ができた** — 旅が閉じて（最後の写真から `TripBook.maxGapDays` 日空いて）
///     から `bookFreshDays` 日以内で、**まだ開いていない**一冊
///  4. **1年前の今ごろ** — 1年前の今日の前後 `yearAgoWindowDays` 日に撮った自分の写真
///  5. **今日のテーマ** — どれにも当たらない日（いまの札のまま）
///
/// 「今月の見ごろ」（板 55 の④）は入れていない——撮影スポットの季節の案内が
/// アプリ向けの一覧（`app/data/spots.json`）に載っていないため。
///
/// 🔴 **当たる物が無い日に空き地を作らない。** 数は自分の枚数・日数だけで、
/// 人数・順位・連続記録は出さない。催促の文言も書かない
enum HomeTopCard {

    enum Choice: Equatable {
        /// `daysUntil` が 0 なら出発当日
        case departure(plan: TripPlan, daysUntil: Int)
        /// `dayNumber` は1から（出発日が1日目）
        case onTrip(plan: TripPlan, dayNumber: Int)
        case bookReady(trip: TripBook.Trip)
        /// `byUploadDate` は撮影日が無く、投稿日で当てたとき（「1年前に投稿」と言う）
        case oneYearAgo(photo: Photo, byUploadDate: Bool)
        case theme
    }

    /// 出発の何日前から出すか
    static let departureWindowDays = 7
    /// 旅が閉じてから何日間「一冊ができた」を出すか
    static let bookFreshDays = 7
    /// 1年前の今日から前後何日までを「今ごろ」と呼ぶか
    static let yearAgoWindowDays = 7

    /// 今日の札を選ぶ。
    ///
    /// - Parameters:
    ///   - now: いまの時刻。**端末の時刻帯（`timeZone`）の暦日**に直して数える
    ///   - plans: 自分の旅行プラン（未ログインなら空）
    ///   - myPhotos: 自分の写真（未ログインなら空）
    ///   - openedBookDays: 札から一度開いた一冊の日（`bookKey`・`OpenedTripBooks`）
    static func pick(now: Date, plans: [TripPlan], myPhotos: [Photo],
                     openedBookDays: Set<String>, timeZone: TimeZone = .current) -> Choice {
        guard let today = today(now, in: timeZone) else { return .theme }
        if let found = departure(today: today, plans: plans) { return found }
        if let found = onTrip(today: today, plans: plans) { return found }
        if let found = bookReady(today: today, myPhotos: myPhotos,
                                 openedBookDays: openedBookDays, timeZone: timeZone) { return found }
        if let found = oneYearAgo(today: today, myPhotos: myPhotos, timeZone: timeZone) { return found }
        return .theme
    }

    /// 端末の時刻帯の今日を、**その日の UTC 0 時**にする（`TripPlanText` と `TripBook.day` の基準）
    static func today(_ now: Date, in timeZone: TimeZone) -> Date? {
        TripPlanText.date(fromYMD: TripPlanText.ymd(pickedIn: timeZone, now))
    }

    // MARK: - 1. 出発が近い

    /// 一番近い出発。**同じ日なら先に作ったプラン**（並びが開くたびに変わらないように）
    static func departure(today: Date, plans: [TripPlan]) -> Choice? {
        let candidates = plans.compactMap { plan -> (TripPlan, Int)? in
            guard let start = TripPlanText.date(fromYMD: plan.startDate) else { return nil }
            let days = TripBook.calendarDays(from: today, to: start)
            guard (0...departureWindowDays).contains(days) else { return nil }
            return (plan, days)
        }
        guard let best = candidates.min(by: { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return (lhs.0.createdAt ?? lhs.0.planId) < (rhs.0.createdAt ?? rhs.0.planId)
        }) else { return nil }
        return .departure(plan: best.0, daysUntil: best.1)
    }

    // MARK: - 2. 旅の最中

    /// 出発日の翌日から帰着日まで。**帰着日の無いプランは当てない**
    /// （いつまで旅なのか分からないものを「旅の最中」と言い続けない）
    static func onTrip(today: Date, plans: [TripPlan]) -> Choice? {
        let candidates = plans.compactMap { plan -> (TripPlan, Int)? in
            guard let start = TripPlanText.date(fromYMD: plan.startDate),
                  let end = TripPlanText.date(fromYMD: plan.endDate) else { return nil }
            let sinceStart = TripBook.calendarDays(from: start, to: today)
            let untilEnd = TripBook.calendarDays(from: today, to: end)
            guard sinceStart >= 1, untilEnd >= 0 else { return nil }
            return (plan, sinceStart + 1)
        }
        // 重なっていたら、後に出発した方（いま進んでいる方）
        guard let best = candidates.min(by: { $0.1 < $1.1 }) else { return nil }
        return .onTrip(plan: best.0, dayNumber: best.1)
    }

    // MARK: - 3. 一冊ができた

    /// 閉じたばかりで、まだ札から開いていない一冊。**一番新しい旅だけを見る**
    /// ——古い旅の札を後から出さない（新しい旅がもう閉じているなら、そちらが今の話）。
    /// 旅は**マイページの「旅の記録」と同じ棚**（`TripBook.shelfTrips`・下書きを入れない）
    static func bookReady(today: Date, myPhotos: [Photo], openedBookDays: Set<String>,
                          timeZone: TimeZone) -> Choice? {
        guard let latest = TripBook.shelfTrips(from: myPhotos, timeZone: timeZone).first else { return nil }
        let sinceEnd = TripBook.calendarDays(from: latest.end, to: today)
        let closed = sinceEnd > TripBook.maxGapDays
        let fresh = sinceEnd <= TripBook.maxGapDays + bookFreshDays
        guard closed, fresh, !isOpened(latest, openedBookDays: openedBookDays) else { return nil }
        return .bookReady(trip: latest)
    }

    /// 開いた印に使う鍵（旅の**始まりの日** `YYYY-MM-DD`）。
    ///
    /// 🔴 **旅の id（写真の id をつないだもの）で持たない。** 撮り残しを1枚足す・
    /// 1枚消すだけで id が変わり、開いた一冊の札がまた出てきた
    static func bookKey(_ trip: TripBook.Trip) -> String {
        TripPlanText.ymd(trip.start)
    }

    /// 印の日が**この旅の期間の中にあれば**開いたことにする。始まりの日で持つので、
    /// 開いたあとに前の日の写真を足して始まりが早まっても、同じ旅と分かる
    static func isOpened(_ trip: TripBook.Trip, openedBookDays: Set<String>) -> Bool {
        openedBookDays.contains { key in
            guard let day = TripPlanText.date(fromYMD: key) else { return false }
            return day >= trip.start && day <= trip.end
        }
    }

    // MARK: - 4. 1年前の今ごろ

    /// 1年前の今日に一番近い1枚（前後 `yearAgoWindowDays` 日まで）。**下書きは出さない**
    /// （一冊の札と同じく、公開した写真だけ）。
    /// **撮影日のある写真を先に見る**——撮った日の方が「今ごろ」の話に合う。
    /// 同じ近さなら、いいねの多い方・id の順（開くたびに入れ替わらない）
    static func oneYearAgo(today: Date, myPhotos: [Photo], timeZone: TimeZone) -> Choice? {
        guard let target = TripPlanText.calendar.date(byAdding: .year, value: -1, to: today) else { return nil }
        let candidates = myPhotos.filter { $0.published != false }.compactMap { photo -> (Photo, Int, Bool)? in
            guard let day = TripBook.day(of: photo, in: timeZone) else { return nil }
            let distance = abs(TripBook.calendarDays(from: target, to: day))
            guard distance <= yearAgoWindowDays else { return nil }
            let byUploadDate = !TripBook.hasTakenDay(photo)
            return (photo, distance, byUploadDate)
        }
        guard let best = candidates.min(by: { lhs, rhs in
            if lhs.2 != rhs.2 { return !lhs.2 }
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            if (lhs.0.likes ?? 0) != (rhs.0.likes ?? 0) { return (lhs.0.likes ?? 0) > (rhs.0.likes ?? 0) }
            return lhs.0.id < rhs.0.id
        }) else { return nil }
        return .oneYearAgo(photo: best.0, byUploadDate: best.2)
    }
}
