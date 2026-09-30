import Foundation

/// ホームの上段に出す札を決める（元は板 01・55「開く場面ごとに1枚」。いまは並び）。
///
/// **当たる札を全部、優先順に並べ、その中に必ず「今日のテーマ」を置く**（2026-09-28・
/// owner「1年前の今ごろ、今日のテーマなど両方欲しい」）。ホームでは横にめくる札の
/// 並びにする——縦に積むと写真の一覧が札の数だけ下がる（写真が主役）。
///
/// レビュー（2026-09-27）で一番欠けていたのが「毎回開きたくなるか」だった。
/// ホームが毎日同じ形で、旅の前・最中・後で出す物が変わらない。材料は
/// もうアプリの中にある（旅行プラン・旅の一冊・自分の写真の日付）ので、
/// **その日に当たる札を上に出す**。
///
/// 優先順（上ほど前。**種類ごとに1枚まで**）:
///
///  1. **出発が近い** — 出発日まで 0〜`departureWindowDays` 日の旅行プラン
///  2. **旅の最中** — 出発日を過ぎ、帰着日までの旅行プラン
///  3. **一冊ができた** — 旅が閉じて（最後の写真から `TripBook.maxGapDays` 日空いて）
///     から `bookFreshDays` 日以内で、**まだ開いていない**一冊
///  4. **行きたい場所のこの季節** — 「行きたい」に入れた公開済みのスポットのうち、
///     いまの季節の案内を持つものを**週替わり**で1件（2026-09-29・owner「こういう感じのを
///     もっと増やしたい」）
///  5. **この季節の撮影スポット** — 公開済みで写真があり、**いまの季節の案内を持つ**
///     スポットを**週替わり**で1件（2026-09-29 に日替わりで入れた・owner「毎日開きたくなる
///     仕組みがアプリ側にない」。2026-09-30 に owner「週替わりとかにして欲しい」で週替わりへ。
///     毎日替わる札は「今日のテーマ」が受け持つ）。4 と同じスポットの週は出さない
///  6. **今日のテーマ** — 毎日（当たる札が無い日は、これ1枚）
///  6'. **今日の一問** — その日の問題のファイルが取れた日だけ（2026-09-30・owner「毎日開く理由を
///     作りたい」への案①）。問題は Web がビルド時に書き出したもの（`DailyQuiz`）
///  7. **1年前の今ごろ** — 1年前の今日の前後 `yearAgoWindowDays` 日に撮った自分の写真。
///     **振り返りなので最後**（2026-09-29・owner「1年前の今頃とかは振り返りなので
///     カードの最後の方でいい」）。これから撮りに行く札を前に出す
///
/// 5 は板 55 の④「今月の見ごろ」。以前は季節の案内がアプリ向けの一覧
/// （`app/data/spots.json`）に載っていなかったので入れていなかった。
///
/// **季節の札は今日のテーマより前**（owner・2026-09-29「旅の札 → 今月の見ごろ → 今日のテーマ
/// → 振り返り」）。以前は後ろに置いていた——季節の札はほぼ毎日当たる（季節ごとに100〜150件が
/// 案内を持つ）ので、**今日のテーマはほぼ毎日2枚目になる**。それを承知で owner が選んだ並び。
///
/// **「見頃」とは言わない。見出しは季節の名前（「秋の撮影スポット」）。** 台帳の
/// 季節の案内は「その季節に何が撮れるか」で、開花のような時期を確かめた文ではない。
/// 文の中の月（「9月から10月にかけて…」）で出す日を絞ることは**しない**——
/// 「4月まで」「9月半ばから3月」「5月2日から4日は…3月上旬には…」のような書き方を
/// 規則で読むと、実データで落とす・出すの誤りが両方出た（2026-09-29 のレビュー）。
/// 季節の名前を見出しにすれば、11月末に「9月から10月にかけて」が出ても
/// 「秋の案内」として正しく読める
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
        /// 「行きたい」に入れたスポットの、いまの季節の案内
        case wishlistSeason(spot: OfficialSpot, season: String, guide: String)
        /// `season` は `spring`〜`winter`、`guide` はその季節の案内の文（台帳の文のまま）
        case inSeason(spot: OfficialSpot, season: String, guide: String)
        case theme
        /// 今日の一問（Web の `/q` と同じ問題）。**その日のファイルが取れたときだけ**
        case quiz(DailyQuiz)

        /// 並びの中の目印。**種類ごとに1枚まで**なので種類で足りる（並び順で持つと、
        /// 一冊の札が下がったときに隣の札と取り違える）
        var slot: String {
            switch self {
            case .departure: return "departure"
            case .onTrip: return "onTrip"
            case .bookReady: return "bookReady"
            case .oneYearAgo: return "oneYearAgo"
            case .wishlistSeason: return "wishlistSeason"
            case .inSeason: return "inSeason"
            case .theme: return "theme"
            case .quiz: return "quiz"
            }
        }
    }

    /// 出発の何日前から出すか
    static let departureWindowDays = 7
    /// 旅が閉じてから何日間「一冊ができた」を出すか
    static let bookFreshDays = 7
    /// 1年前の今日から前後何日までを「今ごろ」と呼ぶか
    static let yearAgoWindowDays = 7

    /// 今日の札の並び。**空にならない**（`.theme` を必ず1枚含む。前に旅・季節の札、後ろに1年前が付く日がある）。
    ///
    /// - Parameters:
    ///   - now: いまの時刻。**端末の時刻帯（`timeZone`）の暦日**に直して数える
    ///   - plans: 自分の旅行プラン（未ログインなら空）
    ///   - myPhotos: 自分の写真（未ログインなら空）
    ///   - openedBookDays: 札から一度開いた一冊の日（`bookKey`・`OpenedTripBooks`）
    ///   - spots: 撮影スポットの索引（取れなかった回は空＝季節の札が出ないだけ）
    ///   - wishlist: 「行きたい」の鍵（`WishlistStore.spotIds`・`SavedSpotKey`）
    static func cards(now: Date, plans: [TripPlan], myPhotos: [Photo],
                      openedBookDays: Set<String>, spots: [OfficialSpot] = [],
                      wishlist: Set<String> = [],
                      quiz: DailyQuiz? = nil,
                      timeZone: TimeZone = .current) -> [Choice] {
        // 今日の一問は**今日のテーマの直後**（毎日替わる札どうしを並べる。1年前の振り返りより前）。
        // 取れなかった日は出さない（空き地を作らない）
        let daily: [Choice] = [.theme] + [quiz.map { Choice.quiz($0) }].compactMap { $0 }
        guard let today = today(now, in: timeZone) else { return daily }
        let found: [Choice?] = [
            departure(today: today, plans: plans),
            onTrip(today: today, plans: plans),
            bookReady(today: today, myPhotos: myPhotos, openedBookDays: openedBookDays, timeZone: timeZone),
        ]
        let wished = wishlistSeason(today: today, spots: spots, wishlist: wishlist)
        var wishedId: String?
        if case .wishlistSeason(let spot, _, _)? = wished { wishedId = spot.spotId }
        // 旅の札 → 季節の札（今月の見ごろ）→ 今日のテーマ → 振り返り（owner・2026-09-29）
        let season: [Choice?] = [
            wished,
            inSeason(today: today, spots: spots, excluding: wishedId),
        ]
        let yearAgo = oneYearAgo(today: today, myPhotos: myPhotos, timeZone: timeZone)
        // **今日の一問の答えと同じスポットの季節の札は、その日は出さない**——名前つきの札と
        // 同じ写真の問題の札が横に並び、答えが見える（週に1%前後・f3bcf5a のレビュー）
        let answerId = quiz?.answer
        let seasonShown = season.compactMap { $0 }.filter { choice in
            switch choice {
            case .inSeason(let spot, _, _), .wishlistSeason(let spot, _, _): return spot.spotId != answerId
            default: return true
            }
        }
        return found.compactMap { $0 } + seasonShown + daily + [yearAgo].compactMap { $0 }
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

    // MARK: - 6. この季節の撮影スポット

    /// **週の番号**（月曜はじまり）。紀元（1970-01-01・木曜）からの日数に3を足して7で割る
    /// ——月曜 0 時（端末の暦）で次の週に替わる。ホームのスポットの札は**週替わり**
    /// （owner・2026-09-30「ホームのスポットは週替わりとかにして欲しい」。以前は日替わり）
    static func weekNumber(_ today: Date) -> Int {
        let day = Int((today.timeIntervalSince1970 / 86_400).rounded(.down))
        return Int((Double(day + 3) / 7).rounded(.down))
    }

    /// いまの季節の案内を持つ、写真のある公開済みのスポットから**週替わりで1件**。
    ///
    /// - 季節は `today`（端末の暦の今日を UTC 0 時に置いたもの）の月から決める
    ///   （春3〜5月・夏6〜8月・秋9〜11月・冬12〜2月。`SpotBodyText.season`）
    /// - 候補は `spotId` の順に並べ、**週の番号で1件ずつ進める**（`weekNumber`）——同じ週なら
    ///   何度開いても同じ札。`spotId` は名前と無関係な
    ///   16進なので、県や種別が続けて並ぶことはない
    /// - **下書き・写真の無い行は出さない**（写真が主役の札。下書きを「おすすめ」と
    ///   して出さない）
    static func inSeason(today: Date, spots: [OfficialSpot], excluding: String? = nil) -> Choice? {
        let month = TripPlanText.calendar.component(.month, from: today)
        let season = SpotBodyText.season(ofMonth: month)
        let candidates = spots
            .filter { !$0.isDraft && $0.photo != nil && $0.spotId != excluding }
            .compactMap { spot -> (OfficialSpot, String)? in
                guard let guide = spot.seasons.first(where: { $0.season == season }) else { return nil }
                return (spot, guide.text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .sorted { $0.0.spotId < $1.0.spotId }
        guard !candidates.isEmpty else { return nil }
        let week = weekNumber(today)
        let index = ((week % candidates.count) + candidates.count) % candidates.count
        return .inSeason(spot: candidates[index].0, season: season, guide: candidates[index].1)
    }

    /// 行きたい場所の札の見出しの読み（「行きたい場所・秋」）
    static func wishlistEyebrow(_ season: String) -> String {
        guard let label = SpotBodyText.seasonLabel(season) else {
            return L("行きたい場所", "Your wishlist")
        }
        return L("行きたい場所・\(label)", "Your wishlist · \(label)")
    }

    /// 季節の札の見出しの読み（「今週の撮影スポット・秋」）。**週替わり**なのでそう名乗る。
    /// 知らない季節は季節を付けない
    static func seasonEyebrow(_ season: String) -> String {
        guard let label = SpotBodyText.seasonLabel(season) else {
            return L("今週の撮影スポット", "This week's photo spot")
        }
        return L("今週の撮影スポット・\(label)", "This week's photo spot · \(label)")
    }

    // MARK: - 5. 行きたい場所のこの季節

    /// 「行きたい」に入れた公開済みのスポットのうち、いまの季節の案内を持つものから
    /// **週替わりで1件**（並べ方・回し方は `inSeason` と同じ）。
    /// **写真は無くてもよい**——自分で選んだ場所なので、写真が無くても出す価値がある
    static func wishlistSeason(today: Date, spots: [OfficialSpot], wishlist: Set<String>) -> Choice? {
        guard !wishlist.isEmpty else { return nil }
        let month = TripPlanText.calendar.component(.month, from: today)
        let season = SpotBodyText.season(ofMonth: month)
        let candidates = spots
            .filter { !$0.isDraft && wishlist.contains(SavedSpotKey.official($0.slug)) }
            .compactMap { spot -> (OfficialSpot, String)? in
                guard let guide = spot.seasons.first(where: { $0.season == season }) else { return nil }
                return (spot, guide.text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .sorted { $0.0.spotId < $1.0.spotId }
        guard !candidates.isEmpty else { return nil }
        let week = weekNumber(today)
        let index = ((week % candidates.count) + candidates.count) % candidates.count
        return .wishlistSeason(spot: candidates[index].0, season: season, guide: candidates[index].1)
    }
}
