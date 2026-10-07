import Foundation

/// 旅の一冊と背表紙に出す文字と数（板 03「旅の一冊」・16「旅の記録」）。
///
/// 画面を持たない層に置いて、Linux の `swift test` で見張る。
///
/// **日は「その日の UTC 0 時」で持ち、UTC の暦で数える。** `TripBook.day(of:in:)` が
/// 撮影日をそう読み、投稿日時も**旅の時刻帯（`Trip.timeZone`＝既定は端末の時刻帯）の
/// 暦日に直してから**同じ形に揃える。だからここで端末の時刻帯を使って書くと、西の国では
/// 「09.12」が「09.11」にずれる（時刻帯を効かせるのは `day(of:in:)` の1か所だけ）。
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
            let date = day(of: photo, in: trip.timeZone) ?? trip.start
            let number = calendarDays(from: trip.start, to: date) + 1
            if number != currentNumber { flush(); currentNumber = number; currentDate = date }
            current.append(photo)
        }
        flush()
        return result
    }

    // MARK: - ページの行（画面外を読まないため）

    /// 段の頭と写真の間・写真どうしの間（前の `VStack(spacing: 20)`）
    static let pageSpacing: Double = 20
    /// 段と段の間（前の `VStack(spacing: 36)`）
    static let daySpacing: Double = 36

    /// ページを**平らな1列**にしたときの1行。
    ///
    /// **一冊の全ページを一度に作らない（2026-10-02）。** 日の段を入れ子の `VStack` で並べると、
    /// 開いた瞬間に全ページの `RemoteImage` が作られ、画面外の元画像まで一度に読んでいた。
    /// 平らな行にして `LazyVStack(spacing: 0)` に並べ、間は行ごとの `topSpacing` で前と同じに保つ
    /// （段の間 36・段の中 20。並びと余白は変えない）
    struct PageRow: Identifiable, Equatable {
        enum Kind: Equatable {
            case header(Day)
            case page(Photo, dayPlace: String)
        }
        let id: String
        let kind: Kind
        /// この行の上に空ける高さ（先頭は 0）
        let topSpacing: Double
    }

    static func pageRows(of days: [Day]) -> [PageRow] {
        var rows: [PageRow] = []
        for day in days {
            rows.append(PageRow(id: "day-\(day.number)", kind: .header(day),
                                topSpacing: rows.isEmpty ? 0 : daySpacing))
            for photo in day.photos {
                rows.append(PageRow(id: "photo-\(photo.id)", kind: .page(photo, dayPlace: day.place),
                                    topSpacing: pageSpacing))
            }
        }
        return rows
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
            let day = calendarDays(from: trip.start, to: TripBook.day(of: photo, in: trip.timeZone) ?? trip.start) + 1
            stops.append(RouteStop(day: day, place: place))
        }
        return stops.count >= 2 ? stops : []
    }

    /// 図に載せる点を `limit` 個まで間引く。**最初と最後は必ず残す**
    /// （どこから始まってどこで終わったか、が図のいちばんの情報）。
    /// 幅 350pt に地名の札を並べると、5つ目から重なる。
    ///
    /// **まとめたあとに2か所未満なら空を返す**（呼ぶ側は `isEmpty` で図を出さない。
    /// `routeStops` と同じ約束）。行き来した旅（A,B,A,B,A,B,A）は間引くと
    /// A,A,A,A になり、点1つの図になる
    static func sampledStops(_ stops: [RouteStop], limit: Int = 4) -> [RouteStop] {
        guard stops.count > limit, limit >= 2 else { return stops }
        let last = stops.count - 1
        let picked = (0..<limit).map { index in
            stops[Int((Double(index) * Double(last) / Double(limit - 1)).rounded())]
        }
        // **間引いたあとにも隣の同名をまとめる。** 行って戻った旅（A,B,A,B,C）は
        // 間の点を抜くと B,B が隣り合い、同じ地名の点が2つ並ぶ。
        // 終点の並びは**最後の1つ**を残す（終点の DAY は旅の終わりの日）
        var result: [RouteStop] = []
        for (index, stop) in picked.enumerated() {
            if result.last?.place == stop.place {
                if index == picked.count - 1, result.count >= 2 {
                    result[result.count - 1] = stop
                }
                continue
            }
            result.append(stop)
        }
        return result.count >= 2 ? result : []
    }

    // MARK: - 共有

    /// 共有で配る文。
    ///
    /// 🔴 **URL は入れない。** 旅の一冊はアプリの中でその場で組み立てる
    /// ものでサイトに対応するページが無い（サイトの `/trips` は旅行プランの
    /// 画面で別物）。推測で URL を作ると**開けないリンクを配る**
    static func shareText(of trip: Trip) -> String {
        let count = PhotoMapViewModel.photoCountLabel(trip.photos.count)
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

    /// 旅の一冊の「移動（直線）」（km）。**座標と日時を持つ写真が2枚未満なら nil**
    /// ——`total` はそのとき 0 を返すので、「0 km」と「数えられない」を
    /// 見分けられない。
    ///
    /// つなぐ順は**旅の一冊と同じ**（`TripBook.inOrder`・`trip.timeZone` の暦日）。
    /// ルート図・日の段と同じ順でつなぐので、図と数字が食い違わない。
    /// プロフィールの合計（`total`）は Web に合わせた別の並び
    static func countableTotal(of photos: [Photo], timeZone: TimeZone) -> Double? {
        let countable = TripBook.inOrder(photos, timeZone: timeZone)
            .filter { $0.coords != nil && TripBook.day(of: $0, in: timeZone) != nil }
        return countable.count >= 2 ? connect(countable) : nil
    }
}
