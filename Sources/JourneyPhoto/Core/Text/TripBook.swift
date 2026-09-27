import Foundation

/// 写真を「旅」にまとめる。
///
/// **帰ってきたら、旅が勝手に一冊になっている。** 投稿は入力でしかなく、
/// 返ってくるのは自分の旅の記録——これがこのアプリを開く理由。
/// 撮った人が何も指定しなくても、日付と場所から一冊が立ち上がる。
///
/// 規則はたった3つ:
///
/// 1. **日が近ければ同じ旅**（`maxGapDays` 日まで空いてよい）。
///    旅は連続した日々だが、移動日に1枚も撮らない日はよくある
/// 2. **2枚以上で一冊。** 1枚は旅ではない（ただのその日の写真）
/// 3. **題はその旅でいちばん多い撮影地。** 無ければ日付で呼ぶ
///
/// **場所では切らない。** 金沢へ行って、帰りに福井へ寄った——これは
/// 2つの旅ではなく1つの旅。場所で切ると、**移動そのものが消える**。
enum TripBook {

    /// 同じ旅と見なす日の空き。**3日**——2泊3日の旅で中日に撮らなくても、
    /// 前後がつながる
    static let maxGapDays = 3

    /// 一冊に要る最小の枚数
    static let minPhotos = 2

    struct Trip: Identifiable, Equatable {
        let id: String
        /// 画面に出す題（いちばん多い撮影地）。無ければ空
        let place: String
        let start: Date
        let end: Date
        /// 時間順（古い順＝旅の進む向き）
        let photos: [Photo]
        /// 投稿日時を暦の日に直すときの時刻帯（`day(of:in:)`）。アプリでは
        /// 端末の時刻帯。日の段・ルート図・移動（直線）もこれで数え直す
        var timeZone: TimeZone = .current

        /// 表紙。**いいねがいちばん多い1枚**、並びが同じなら最初の1枚
        var cover: Photo? {
            photos.max { ($0.likes ?? 0) < ($1.likes ?? 0) } ?? photos.first
        }

        /// 何日間の旅か（同じ日なら1日）。**暦の日で数える**——経過秒で割ると、
        /// 時刻を持つ写真（投稿日で代用したもの）で「2026.05.01 — 05.03」の旅が
        /// 「2日間」になり、並べて出す期間の範囲と食い違う
        var days: Int {
            max(1, TripBook.calendarDays(from: start, to: end) + 1)
        }
    }

    /// 新しい旅が先頭。
    ///
    /// **旅は1人のもの。** 投稿者ごとに分けてからまとめる——日付だけで
    /// 束ねると、**同じ日に別の人が撮った写真が1つの旅に混ざる**
    /// （公開一覧は全員のぶんが入っているので、人が増えた瞬間に起きる）。
    static func trips(from photos: [Photo], timeZone: TimeZone = .current) -> [Trip] {
        var byUser: [String: [Photo]] = [:]
        for photo in photos {
            // 投稿者が分からない写真は**それだけで1つの束**にしない。
            // 空文字を鍵にすると、身元の分からない写真どうしが
            // 「同じ人の旅」になってしまう
            byUser[photo.userId ?? photo.uploadedBy ?? "unknown-\(photo.id)", default: []].append(photo)
        }
        return byUser.values.flatMap { tripsForOnePerson($0, timeZone: timeZone) }
            .sorted { $0.start > $1.start }
    }

    private static func tripsForOnePerson(_ photos: [Photo], timeZone: TimeZone) -> [Trip] {
        // **日付を持たない写真は旅に入れない。** いつの旅か決まらないものを
        // 混ぜると、関係ない写真が一冊に紛れ込む
        let dated = inOrder(photos, timeZone: timeZone).compactMap { photo -> (Photo, Date)? in
            guard let date = day(of: photo, in: timeZone) else { return nil }
            return (photo, date)
        }

        var groups: [[(Photo, Date)]] = []
        for item in dated {
            if let last = groups.last?.last,
               item.1.timeIntervalSince(last.1) <= Double(maxGapDays) * 86_400 {
                groups[groups.count - 1].append(item)
            } else {
                groups.append([item])
            }
        }

        return groups
            .filter { $0.count >= minPhotos }
            .compactMap { group -> Trip? in
                guard let start = group.first?.1, let end = group.last?.1 else { return nil }
                let photos = group.map(\.0)
                return Trip(
                    id: photos.map(\.id).joined(separator: "-"),
                    place: mainPlace(of: photos),
                    start: start,
                    end: end,
                    photos: photos,
                    timeZone: timeZone
                )
            }
    }

    /// その写真の日。**撮影日を優先**し、無ければ投稿日で代用する
    /// （撮った日の方が旅の順番に合う）。
    ///
    /// **返すのは「その日の UTC 0 時」**——撮影日（`2026-05-02`）はそう読むので、
    /// 投稿日時も同じ基準に揃える。投稿日時は UTC の瞬間（`…T22:00:00Z`）なので、
    /// **`timeZone` の暦日に直してから** 0 時にする。アプリからは既定の
    /// **端末の時刻帯**（`.current`）で呼ぶ——撮った人の時刻帯ではない
    /// （写真は投稿した場所の時刻帯を持っていない）。直さないと、
    /// 日本時間の 0〜9 時の投稿が前の日になり（JST 5/2 07:00 は UTC では 5/1）、
    /// 同じ日の2枚が「05.01 — 05.02・2日間」に割れる
    static func day(of photo: Photo, in timeZone: TimeZone = .current) -> Date? {
        if let date = photo.date, let parsed = dayFormatter.date(from: String(date.prefix(10))) {
            return parsed
        }
        if let created = photo.createdAt {
            if let instant = instant(created) {
                var local = Calendar(identifier: .gregorian)
                local.timeZone = timeZone
                let parts = local.dateComponents([.year, .month, .day], from: instant)
                return utcCalendar.date(from: parts)
            }
            // 時刻の無い日付だけの投稿日は、撮影日と同じく書いてある日のまま
            return dayFormatter.date(from: String(created.prefix(10)))
        }
        return nil
    }

    /// **自分の旅の棚**（マイページの「旅の記録」・ホームの「一冊ができた」）。
    /// 下書きは入れない——見せていない写真が一冊に紛れ込み、入口によって
    /// 同じ旅の枚数・表紙・区切りが変わる。**絞り方はここ1か所**
    static func shelfTrips(from photos: [Photo], timeZone: TimeZone = .current) -> [Trip] {
        trips(from: photos.filter { $0.published != false }, timeZone: timeZone)
    }

    /// `day(of:in:)` が**撮影日**で日を決めたか（false なら投稿日で代用した・日が無い）。
    /// 読み方は `day(of:in:)` と同じ——別の読み方で判定すると、端の値で食い違う
    static func hasTakenDay(_ photo: Photo) -> Bool {
        guard let date = photo.date else { return false }
        return dayFormatter.date(from: String(date.prefix(10))) != nil
    }

    /// 旅の進む向きに並べる。**日で並べ、同じ日の中は投稿の時刻順**
    /// （日に丸めたあとで並べるだけだと、同じ日の写真の順が決まらない）。
    /// 日の決まらない写真は後ろ（旅には入らない）。
    ///
    /// ⚠️ **撮影日の時刻は見ていない。** `date` に時刻の入った写真
    /// （EXIF 由来の `2024-11-01T07:30:00`、`…Z` 形）も `day(of:in:)` で日に
    /// 丸めるので、同じ日の中は**撮った時刻ではなく投稿の時刻順**になる
    /// （撮った順と違う順に投稿すると、撮った順とは食い違う）。投稿日時の無い
    /// 写真はその日の先頭に来る。
    ///
    /// プロフィールの距離（`TravelDistance.total`）はこの並びを使わない
    /// （Web の `compareOldest` に合わせてあり、端末の時刻帯に左右されない）
    static func inOrder(_ photos: [Photo], timeZone: TimeZone = .current) -> [Photo] {
        photos.enumerated().sorted { lhs, rhs in
            let l = day(of: lhs.element, in: timeZone) ?? .distantFuture
            let r = day(of: rhs.element, in: timeZone) ?? .distantFuture
            if l != r { return l < r }
            let lt = lhs.element.createdAt.flatMap(instant) ?? .distantPast
            let rt = rhs.element.createdAt.flatMap(instant) ?? .distantPast
            if lt != rt { return lt < rt }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private static func instant(_ text: String) -> Date? {
        isoFormatter.date(from: text) ?? isoFormatterNoFraction.date(from: text)
    }

    /// その旅でいちばん多い撮影地。同数なら**先に出てきた方**
    /// （旅の始まりの土地を題にする）。
    static func mainPlace(of photos: [Photo]) -> String {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for place in photos.compactMap(\.location) {
            let trimmed = place.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if counts[trimmed] == nil { order.append(trimmed) }
            counts[trimmed, default: 0] += 1
        }
        return order.max { (counts[$0] ?? 0, order.firstIndex(of: $1) ?? 0)
                            < (counts[$1] ?? 0, order.firstIndex(of: $0) ?? 0) } ?? ""
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
