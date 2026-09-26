import Foundation

/// 旅の一冊と背表紙に出す文字と数（板 03「旅の一冊」・16「旅の記録」）。
///
/// 画面を持たない層に置いて、Linux の `swift test` で見張る。
///
/// **日付は全部 UTC の暦で数える。** `TripBook.day(of:)` が撮影日を
/// UTC の 0 時として読むので、端末の時刻帯で書くと西の国では
/// 「09.12」が「09.11」にずれる。
extension TripBook {

    // MARK: - 題

    /// 背表紙・表紙の題（板「金沢の旅」）。撮影地が無ければ「旅の記録」
    static func title(of trip: Trip) -> String {
        let place = trip.place.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !place.isEmpty else { return L("旅の記録", "A trip") }
        return L("\(place)の旅", "Trip to \(place)")
    }

    // MARK: - 期間

    /// 期間の範囲（板「2026.09.12 — 09.14」）。
    ///
    /// - 同じ日なら1つだけ（「2026.09.12 — 09.12」は範囲に見えない）
    /// - **年をまたいだら終わりにも年を書く**（「2025.12.30 — 01.02」だと
    ///   1月2日がどの年か読めない）
    static func dateRange(from start: Date, to end: Date) -> String {
        let first = format(start, "yyyy.MM.dd")
        if utcCalendar.isDate(start, inSameDayAs: end) { return first }
        let sameYear = utcCalendar.component(.year, from: start) == utcCalendar.component(.year, from: end)
        return "\(first) — \(format(end, sameYear ? "MM.dd" : "yyyy.MM.dd"))"
    }

    /// 日ごとの段の日付（板「09.12」）
    static func monthDay(_ date: Date) -> String { format(date, "MM.dd") }

    /// 「3日間」。英語は1日だけ単数
    static func daysLabel(_ days: Int) -> String {
        L("\(days)日間", days == 1 ? "1 day" : "\(days) days")
    }

    /// 暦の上で何日離れているか（同じ日なら0）。
    ///
    /// **経過秒を 86,400 で割らない。** 投稿日で代用した写真は時刻を持つので、
    /// 5/1 20:00 と 5/3 08:00 は36時間＝「1日半」だが、旅としては3日目
    static func calendarDays(from start: Date, to date: Date) -> Int {
        let from = utcCalendar.startOfDay(for: start)
        let to = utcCalendar.startOfDay(for: date)
        return utcCalendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    // MARK: - 数

    /// 撮影地の数（板の「撮影地」の枠）。**同じ名前は1つ**（前後の空白は無視）
    static func placeCount(of photos: [Photo]) -> Int {
        Set(photos.compactMap { $0.location?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }).count
    }

    /// 移動（直線）の枠の数字。数えられない（座標のある写真が2枚未満）なら「—」。
    /// **0 km と「数えられない」を混ぜない**——同じ場所で2枚撮った旅は本当に 0 km
    static func distanceText(_ kilometers: Double?) -> String {
        guard let kilometers else { return "—" }
        return TravelDistance.formatted(kilometers)
    }

    // MARK: - 日ごとの段

    struct Day: Equatable {
        /// 旅の何日目か（1から）
        let number: Int
        let date: Date
        /// その日でいちばん多い撮影地。無ければ空
        let place: String
        /// 時間順
        let photos: [Photo]
    }

    /// 日ごとに分ける（板の DAY 1 / 09.12 の段）。**撮っていない日は段を作らない**
    static func days(of trip: Trip) -> [Day] {
        var result: [Day] = []
        var current: [Photo] = []
        var currentNumber = 0
        var currentDate = trip.start
        func flush() {
            guard !current.isEmpty else { return }
            result.append(Day(number: currentNumber, date: currentDate,
                              place: mainPlace(of: current), photos: current))
            current = []
        }
        for photo in trip.photos {
            let date = day(of: photo) ?? trip.start
            let number = calendarDays(from: trip.start, to: date) + 1
            if number != currentNumber { flush(); currentNumber = number; currentDate = date }
            current.append(photo)
        }
        flush()
        return result
    }

    // MARK: - ルート図

    struct RouteStop: Equatable {
        /// その撮影地に着いた日（旅の何日目か）
        let day: Int
        let place: String
    }

    /// ルート図の点（板「DAY 1 · 金沢」）。通った順に、**同じ場所が続いたらまとめる**。
    ///
    /// **2か所以上のときだけ返す。** 点が1つの「足取り」はかえって壊れて見える
    /// （実機の絵で確認）。呼ぶ側は `isEmpty` で出し分ける。
    static func routeStops(of trip: Trip) -> [RouteStop] {
        var stops: [RouteStop] = []
        for photo in trip.photos {
            guard let place = photo.location?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !place.isEmpty, stops.last?.place != place else { continue }
            let day = calendarDays(from: trip.start, to: TripBook.day(of: photo) ?? trip.start) + 1
            stops.append(RouteStop(day: day, place: place))
        }
        return stops.count >= 2 ? stops : []
    }

    /// 図に載せる点を `limit` 個まで間引く。**最初と最後は必ず残す**
    /// （どこから始まってどこで終わったか、が図のいちばんの情報）。
    /// 幅 350pt に地名の札を並べると、5つ目から重なる
    static func sampledStops(_ stops: [RouteStop], limit: Int = 4) -> [RouteStop] {
        guard stops.count > limit, limit >= 2 else { return stops }
        let last = stops.count - 1
        return (0..<limit).map { index in
            stops[Int((Double(index) * Double(last) / Double(limit - 1)).rounded())]
        }
    }

    // MARK: - 共有

    /// 共有で配る文。
    ///
    /// 🔴 **URL は入れない。** 旅の一冊はアプリの中でその場で組み立てる
    /// ものでサイトに対応するページが無い（サイトの `/trips` は旅行プランの
    /// 画面で別物）。推測で URL を作ると**開けないリンクを配る**
    static func shareText(of trip: Trip) -> String {
        let count = L("\(trip.photos.count)枚", "\(trip.photos.count) photos")
        return "\(title(of: trip))\n\(dateRange(from: trip.start, to: trip.end)) · \(daysLabel(trip.days)) · \(count)"
    }

    // MARK: - 下回り

    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

extension TravelDistance {

    /// 写真をつないだ合計（km）。**座標と日時を持つ写真が2枚未満なら nil**
    /// ——`total` はそのとき 0 を返すので、「0 km」と「数えられない」を
    /// 見分けられない
    static func countableTotal(of photos: [Photo]) -> Double? {
        let countable = photos.filter { $0.coords != nil && TripBook.day(of: $0) != nil }
        return countable.count >= 2 ? total(of: countable) : nil
    }
}
