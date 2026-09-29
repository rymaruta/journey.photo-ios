import Foundation

/// ホームの上段に出す札を決める（元は板 01・55「開く場面ごとに1枚」。いまは並び）。
///
/// **当たる札を全部、優先順に並べ、そのあとに必ず「今日のテーマ」を置く**（2026-09-28・
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
///  4. **1年前の今ごろ** — 1年前の今日の前後 `yearAgoWindowDays` 日に撮った自分の写真
///  5. **今日のテーマ** — 毎日（自分に当たる札が無い日は、これが先頭）
///  6. **この季節の撮影スポット** — 公開済みで写真があり、**いまの季節の案内を持つ**
///     スポットを日替わりで1件（2026-09-29・owner「毎日開きたくなる仕組みがアプリ側にない」）
///
/// 6 は板 55 の④「今月の見ごろ」。以前は季節の案内がアプリ向けの一覧
/// （`app/data/spots.json`）に載っていなかったので入れていなかった。
///
/// **今日のテーマより後ろに置く。** 季節の札はほぼ毎日当たる（公開済みで写真のある
/// 行のうち、季節ごとに100〜150件が案内を持つ）ので、前に置くと**今日のテーマが
/// 毎日2枚目に下がる**——札の無い人の見た目（テーマが先頭）を変えない。
///
/// **「見頃」とは言わない**——台帳の季節の案内は「その季節に何が撮れるか」で、
/// 開花のような時期を確かめた文ではない。ただし文の中に**月が書いてあれば、その月に
/// だけ出す**（「9月から10月にかけて…」を 11/30 に出さない。`fits(_:month:)`）
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
        /// `guide` はいまの季節の案内の文（台帳の文のまま）
        case inSeason(spot: OfficialSpot, guide: String)
        case theme

        /// 並びの中の目印。**種類ごとに1枚まで**なので種類で足りる（並び順で持つと、
        /// 一冊の札が下がったときに隣の札と取り違える）
        var slot: String {
            switch self {
            case .departure: return "departure"
            case .onTrip: return "onTrip"
            case .bookReady: return "bookReady"
            case .oneYearAgo: return "oneYearAgo"
            case .inSeason: return "inSeason"
            case .theme: return "theme"
            }
        }
    }

    /// 出発の何日前から出すか
    static let departureWindowDays = 7
    /// 旅が閉じてから何日間「一冊ができた」を出すか
    static let bookFreshDays = 7
    /// 1年前の今日から前後何日までを「今ごろ」と呼ぶか
    static let yearAgoWindowDays = 7

    /// 今日の札の並び。**空にならない**（最後は必ず `.theme`）。
    ///
    /// - Parameters:
    ///   - now: いまの時刻。**端末の時刻帯（`timeZone`）の暦日**に直して数える
    ///   - plans: 自分の旅行プラン（未ログインなら空）
    ///   - myPhotos: 自分の写真（未ログインなら空）
    ///   - openedBookDays: 札から一度開いた一冊の日（`bookKey`・`OpenedTripBooks`）
    ///   - spots: 撮影スポットの索引（取れなかった回は空＝季節の札が出ないだけ）
    static func cards(now: Date, plans: [TripPlan], myPhotos: [Photo],
                      openedBookDays: Set<String>, spots: [OfficialSpot] = [],
                      timeZone: TimeZone = .current) -> [Choice] {
        guard let today = today(now, in: timeZone) else { return [.theme] }
        let found: [Choice?] = [
            departure(today: today, plans: plans),
            onTrip(today: today, plans: plans),
            bookReady(today: today, myPhotos: myPhotos, openedBookDays: openedBookDays, timeZone: timeZone),
            oneYearAgo(today: today, myPhotos: myPhotos, timeZone: timeZone),
        ]
        return found.compactMap { $0 } + [.theme] + [inSeason(today: today, spots: spots)].compactMap { $0 }
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

    /// いまの季節の案内を持つ、写真のある公開済みのスポットから**日替わりで1件**。
    ///
    /// - 季節は `today`（端末の暦の今日を UTC 0 時に置いたもの）の月から決める
    ///   （春3〜5月・夏6〜8月・秋9〜11月・冬12〜2月。`SpotBodyText.season`）
    /// - 文に月が書いてあれば、**その月に当たる文だけ**（`fits(_:month:)`）
    /// - 候補は `spotId` の順に並べ、**紀元からの日数で1件ずつ進める**——同じ日なら
    ///   何度開いても同じ札（今日のテーマと同じ考え方）。`spotId` は名前と無関係な
    ///   16進なので、県や種別が続けて並ぶことはない
    /// - **下書き・写真の無い行は出さない**（写真が主役の札。下書きを「おすすめ」と
    ///   して出さない）
    static func inSeason(today: Date, spots: [OfficialSpot]) -> Choice? {
        let month = TripPlanText.calendar.component(.month, from: today)
        let season = SpotBodyText.season(ofMonth: month)
        let candidates = spots
            .filter { !$0.isDraft && $0.photo != nil }
            .compactMap { spot -> (OfficialSpot, String)? in
                guard let guide = spot.seasons.first(where: { $0.season == season && fits($0.text, month: month) })
                else { return nil }
                return (spot, guide.text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .sorted { $0.0.spotId < $1.0.spotId }
        guard !candidates.isEmpty else { return nil }
        let day = Int((today.timeIntervalSince1970 / 86_400).rounded(.down))
        let index = ((day % candidates.count) + candidates.count) % candidates.count
        return .inSeason(spot: candidates[index].0, guide: candidates[index].1)
    }

    /// 文に書かれた月（「11月」「９月」）が、いまの月に当たるか。
    ///
    /// - 月が書いていなければ当たる（季節で決める）
    /// - 「A月からB月」「A〜B月」のような幅は、書かれた月の**いちばん早い月から
    ///   いちばん遅い月まで**を当たりにする。離れすぎた月（差が7か月以上）は
    ///   年をまたぐ幅として読む（「12月から2月」→ 12・1・2月）
    static func fits(_ text: String, month: Int) -> Bool {
        // 全角の数字を半角に（`applyingTransform` は Linux の Foundation に無いので自前で）
        let normalized = String(text.unicodeScalars.map { scalar -> Character in
            (0xFF10...0xFF19).contains(scalar.value)
                ? Character(Unicode.Scalar(scalar.value - 0xFF10 + 0x30)!) : Character(scalar)
        })
        let months = monthPattern.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized))
            .compactMap { Range($0.range(at: 1), in: normalized).flatMap { Int(normalized[$0]) } }
            .filter { (1...12).contains($0) }
        guard let low = months.min(), let high = months.max() else { return true }
        if months.contains(month) { return true }
        // 離れすぎた月（12月と2月）は**年をまたぐ幅**として読む: 12月・1月・2月
        if high - low > 6 { return month >= high || month <= low }
        return (low...high).contains(month)
    }

    private static let monthPattern = try! NSRegularExpression(pattern: "(?<![0-9])([0-9]{1,2})月")
}

