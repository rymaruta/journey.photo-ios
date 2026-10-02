import Foundation

/// 端末の写真ライブラリの1枚（`PHAsset` を写したもの）。
///
/// **画像は持たない。** 旅を探すのに要るのは日時と位置だけで、本体は
/// 選んだ写真だけを最後に読む（`PhotoLibrary.imageData`）
struct LibraryShot: Equatable, Hashable, Sendable {
    /// `PHAsset.localIdentifier`
    let id: String
    let date: Date
    let lat: Double?
    let lng: Double?

    var coords: Photo.Coords? {
        guard let lat, let lng else { return nil }
        return Photo.Coords(lat: lat, lng: lng)
    }
}

/// 写真ライブラリから見つけた旅の1つ。
struct LibraryTrip: Identifiable, Equatable {

    /// 旅の1日。**写真のある日だけ**を持つ（撮らなかった中日は飛ぶ）
    struct Day: Identifiable, Equatable {
        /// 撮影日（`YYYY-MM-DD`・端末の時刻帯）。投稿済みの写真の撮影日と突き合わせる
        let key: String
        /// 旅の何日目か（1始まり・**暦の日で数える**）。撮らなかった日も数に入る
        /// ——3日目に撮らず4日目に撮ったら「DAY 4」
        let number: Int
        let month: Int
        let day: Int
        /// 日時順
        let shots: [LibraryShot]
        /// その日の代表点（位置のある写真でいちばん多い約10kmの升の平均）。無ければ nil
        let center: Photo.Coords?

        var id: String { key }
    }

    /// いちばん古い写真の id（旅の印）
    let id: String
    /// 日時順（古い順）
    let shots: [LibraryShot]
    /// 最初と最後の「旅先」（家から50km以上）の写真の日時
    let start: Date
    let end: Date
    let days: [Day]
    /// 旅の代表点（位置のある写真でいちばん多い約10kmの升の平均）。旅の名前を引くのに使う
    let center: Photo.Coords?

    /// 表紙。**真ん中あたりの1枚**（初日の朝の1枚は駅や車内になりやすい）
    var cover: LibraryShot? {
        shots.isEmpty ? nil : shots[shots.count / 2]
    }
}

/// 写真ライブラリの写真から旅を見つける。**端末の中だけで決める**（どこにも送らない）。
///
/// `TripBook` は投稿済みの写真を日付だけで束ねる（場所では切らない）。こちらは
/// **まだ投稿していない山から旅を拾う**ので、家の近くの日常の写真を落とす必要がある。
/// そのために場所を見る:
///
/// 1. **家**を決める（渡されなければ、位置のある写真でいちばん多い約10kmの升）
/// 2. 家から **50km 以上**離れた位置のある写真を「旅先」とする
/// 3. 旅先の写真を日時順に並べ、前の旅先の写真から `TripBook.maxGapDays` を
///    **超えて**空いたら別の旅（区切りの幅は TripBook と同じ）
/// 4. 旅の期間に入る**位置の無い写真**も含める（機内モード・位置を切ったカメラ）
/// 5. **5枚未満は旅にしない**（たまたま遠くで撮った数枚を「旅」と呼ばない）
///
/// MainActor に置かない——試験から呼び、画面は MainActor の外で回す。
enum LibraryTrips {

    /// 旅先と見なす家からの距離（km）
    static let awayKm = 50.0
    /// 一つの旅に要る最小の枚数
    static let minShots = 5
    /// 家を推す升の細かさ（度）。0.1度 ≒ 約10km
    static let cellDegrees = 0.1

    static func find(_ shots: [LibraryShot],
                     home: (lat: Double, lng: Double)? = nil,
                     timeZone: TimeZone = .current) -> [LibraryTrip] {
        let located = shots.filter { $0.coords != nil }
        let homePoint: Photo.Coords
        if let home {
            homePoint = Photo.Coords(lat: home.lat, lng: home.lng)
        } else if let guessed = busiestCellCenter(of: located) {
            homePoint = guessed
        } else {
            // 位置のある写真が1枚も無い——どこが旅先か決められない
            return []
        }

        let away = located
            .filter { shot in
                guard let coords = shot.coords else { return false }
                return TravelDistance.kilometers(from: homePoint, to: coords) >= awayKm
            }
            .sorted(by: inOrder)

        // 旅先の写真だけで区切る（位置の無い写真で旅をつなげない——
        // 家で撮った位置の無い写真が2つの旅を1つにしてしまう）
        var spans: [(start: Date, end: Date)] = []
        let maxGap = Double(TripBook.maxGapDays) * 86_400
        for shot in away {
            if let last = spans.last, shot.date.timeIntervalSince(last.end) <= maxGap {
                spans[spans.count - 1].end = shot.date
            } else {
                spans.append((shot.date, shot.date))
            }
        }

        let awayIds = Set(away.map(\.id))
        let unlocated = shots.filter { $0.coords == nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        return spans.compactMap { span -> LibraryTrip? in
            let inside = away.filter { $0.date >= span.start && $0.date <= span.end }
                + unlocated.filter { $0.date >= span.start && $0.date <= span.end }
            let ordered = inside.sorted(by: inOrder)
            guard ordered.count >= minShots, let first = ordered.first else { return nil }
            return LibraryTrip(
                id: first.id,
                shots: ordered,
                start: span.start,
                end: span.end,
                days: days(of: ordered, from: span.start, calendar: calendar),
                center: busiestCellCenter(of: ordered.filter { awayIds.contains($0.id) })
            )
        }
        .sorted { $0.start > $1.start }
    }

    /// 投稿済みの写真の撮影日と重なる旅の日数。一覧で「投稿済みの日があります」を出すのに使う。
    /// `postedDayKeys` は `dayKeys(ofPosted:)` で作る
    static func postedDays(trip: LibraryTrip, postedDayKeys: Set<String>) -> Int {
        trip.days.filter { postedDayKeys.contains($0.key) }.count
    }

    /// 自分の投稿の撮影日（`YYYY-MM-DD`）。**撮影日だけ**を見る——投稿日で代用すると、
    /// 旅から帰って投稿した日が「投稿済みの日」になる
    static func dayKeys(ofPosted photos: [Photo]) -> Set<String> {
        Set(photos.compactMap { photo -> String? in
            guard let head = TakenDay.ymd(photo.date) else { return nil }
            let (y, m, d) = head
            return String(format: "%04d-%02d-%02d", y, m, d)
        })
    }

    /// 最初に選んでおく写真。**日ごとにばらける**ように最大 `limit` 枚を均等に間引く。
    ///
    /// - 日が `limit` より多ければ、日を均等に飛ばして1日1枚
    /// - 少なければ、どの日にも同じ数ずつ配る（撮った枚数の少ない日はその日の全部まで）
    /// - 日の中では、写真を均等に区切ったそれぞれの真ん中を取る
    ///
    /// 返すのは旅の並び（日時順）の id
    static func spreadPick(_ trip: LibraryTrip, limit: Int) -> [String] {
        let days = trip.days
        guard limit > 0, !days.isEmpty else { return [] }

        var quotas = Array(repeating: 0, count: days.count)
        if days.count >= limit {
            // 区切った幅の真ん中の日（3日から2日なら1日目と3日目）
            for i in 0..<limit {
                quotas[(2 * i + 1) * days.count / (2 * limit)] = 1
            }
        } else {
            // 順に1枚ずつ配る: **まだ少なくしか選んでいない日**へ。同じなら写真の残りが多い日、
            // それも同じなら早い日。撮った枚数の少ない日は、その日の全部で打ち止め
            var left = min(limit, days.reduce(0) { $0 + $1.shots.count })
            while left > 0 {
                var best: Int?
                for i in days.indices where quotas[i] < days[i].shots.count {
                    guard let b = best else { best = i; continue }
                    let room = days[i].shots.count - quotas[i]
                    let bestRoom = days[b].shots.count - quotas[b]
                    if quotas[i] < quotas[b] || (quotas[i] == quotas[b] && room > bestRoom) { best = i }
                }
                guard let chosen = best else { break }
                quotas[chosen] += 1
                left -= 1
            }
        }

        var picked: [String] = []
        for (day, quota) in zip(days, quotas) where quota > 0 {
            let n = day.shots.count
            for j in 0..<quota {
                picked.append(day.shots[(2 * j + 1) * n / (2 * quota)].id)
            }
        }
        return picked
    }

    /// 選ぶ・外すの切り替え。**上限を超える選びは受けない**（`overLimit` を立てて返す）
    static func toggle(_ id: String, in selected: [String], limit: Int) -> (selected: [String], overLimit: Bool) {
        if selected.contains(id) {
            return (selected.filter { $0 != id }, false)
        }
        guard selected.count < limit else { return (selected, true) }
        return (selected + [id], false)
    }

    /// 期間（等幅で出す）。「2026.09.12 — 09.14」、年をまたげば「2025.12.30 — 2026.01.02」、
    /// 1日なら「2026.09.12」
    static func periodText(_ trip: LibraryTrip, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let a = calendar.dateComponents([.year, .month, .day], from: trip.start)
        let b = calendar.dateComponents([.year, .month, .day], from: trip.end)
        let head = String(format: "%04d.%02d.%02d", a.year ?? 0, a.month ?? 0, a.day ?? 0)
        if a == b { return head }
        let tail = a.year == b.year
            ? String(format: "%02d.%02d", b.month ?? 0, b.day ?? 0)
            : String(format: "%04d.%02d.%02d", b.year ?? 0, b.month ?? 0, b.day ?? 0)
        return "\(head) — \(tail)"
    }

    /// 日の眉ラベル「DAY 1 · 9.12 · 京都市」。地名が引けなければ「DAY 1 · 9.12」
    static func dayLabel(_ day: LibraryTrip.Day, place: String?) -> String {
        let head = "DAY \(day.number) · \(day.month).\(day.day)"
        guard let place, !place.isEmpty else { return head }
        return "\(head) · \(place)"
    }

    /// 地名を引くときに Apple の地図へ渡す座標。**小数第2位（約1km）に丸める**——
    /// 説明の画面で「おおよその位置（約1km）だけ」と約束している
    static func roundedForLookup(_ coords: Photo.Coords) -> Photo.Coords {
        Photo.Coords(lat: (coords.lat * 100).rounded() / 100, lng: (coords.lng * 100).rounded() / 100)
    }

    /// 地名の控えの鍵（丸めた座標が同じなら同じ地名）
    static func lookupKey(_ coords: Photo.Coords) -> String {
        let rounded = roundedForLookup(coords)
        return String(format: "%.2f,%.2f", rounded.lat, rounded.lng)
    }

    // MARK: - 内側

    /// 日時順。同じ日時は id で決める（並びが毎回変わらないように）
    private static func inOrder(_ a: LibraryShot, _ b: LibraryShot) -> Bool {
        a.date != b.date ? a.date < b.date : a.id < b.id
    }

    private struct Cell: Hashable {
        let lat: Int
        let lng: Int
    }

    private static func cell(of coords: Photo.Coords) -> Cell {
        Cell(lat: Int((coords.lat / cellDegrees).rounded()), lng: Int((coords.lng / cellDegrees).rounded()))
    }

    /// 位置のある写真でいちばん多い升の、写真の平均の位置。同じ数なら升の小さい方（毎回同じ答え）
    static func busiestCellCenter(of shots: [LibraryShot]) -> Photo.Coords? {
        var groups: [Cell: [Photo.Coords]] = [:]
        for shot in shots {
            guard let coords = shot.coords else { continue }
            groups[cell(of: coords), default: []].append(coords)
        }
        let best = groups.max { a, b in
            if a.value.count != b.value.count { return a.value.count < b.value.count }
            // 同じ数なら升の小さい方を「大きい」とみなして選ぶ
            return (a.key.lat, a.key.lng) > (b.key.lat, b.key.lng)
        }
        guard let points = best?.value, !points.isEmpty else { return nil }
        let n = Double(points.count)
        return Photo.Coords(lat: points.reduce(0) { $0 + $1.lat } / n,
                            lng: points.reduce(0) { $0 + $1.lng } / n)
    }

    private static func days(of shots: [LibraryShot], from start: Date, calendar: Calendar) -> [LibraryTrip.Day] {
        let startDay = calendar.startOfDay(for: start)
        var order: [String] = []
        var byKey: [String: (parts: DateComponents, shots: [LibraryShot])] = [:]
        for shot in shots {
            let parts = calendar.dateComponents([.year, .month, .day], from: shot.date)
            let key = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
            if byKey[key] == nil {
                order.append(key)
                byKey[key] = (parts, [])
            }
            byKey[key]?.shots.append(shot)
        }
        return order.compactMap { key -> LibraryTrip.Day? in
            guard let entry = byKey[key], let first = entry.shots.first else { return nil }
            let offset = calendar.dateComponents([.day], from: startDay,
                                                 to: calendar.startOfDay(for: first.date)).day ?? 0
            return LibraryTrip.Day(key: key, number: offset + 1,
                                   month: entry.parts.month ?? 0, day: entry.parts.day ?? 0,
                                   shots: entry.shots, center: busiestCellCenter(of: entry.shots))
        }
    }
}
