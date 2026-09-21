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

        /// 表紙。**いいねがいちばん多い1枚**、並びが同じなら最初の1枚
        var cover: Photo? {
            photos.max { ($0.likes ?? 0) < ($1.likes ?? 0) } ?? photos.first
        }

        /// 何日間の旅か（同じ日なら1日）
        var days: Int {
            let seconds = end.timeIntervalSince(start)
            return max(1, Int(seconds / 86_400) + 1)
        }
    }

    /// 新しい旅が先頭。
    static func trips(from photos: [Photo]) -> [Trip] {
        // **日付を持たない写真は旅に入れない。** いつの旅か決まらないものを
        // 混ぜると、関係ない写真が一冊に紛れ込む
        let dated = photos.compactMap { photo -> (Photo, Date)? in
            guard let date = day(of: photo) else { return nil }
            return (photo, date)
        }.sorted { $0.1 < $1.1 }

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
                    photos: photos
                )
            }
            // 新しい旅から見せる（いちばん近い記憶が先）
            .sorted { $0.start > $1.start }
    }

    /// 通った順に並べた撮影地。**同じ場所が続いたらまとめる**
    /// （「金沢・金沢・金沢」と並べても足取りにならない）。
    ///
    /// **2か所以上のときだけ意味がある。** 1か所しか無い旅で線を引くと、
    /// 点が1つあるだけの「足取り」になり、かえって壊れて見える
    /// （実機の絵で確認）。呼ぶ側は `isEmpty` で出し分ける。
    static func route(of photos: [Photo]) -> [String] {
        var result: [String] = []
        for place in photos.compactMap(\.location) {
            let trimmed = place.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, result.last != trimmed else { continue }
            result.append(trimmed)
        }
        return result.count >= 2 ? result : []
    }

    /// その写真の日。**撮影日を優先**し、無ければ投稿日で代用する
    /// （撮った日の方が旅の順番に合う）。
    static func day(of photo: Photo) -> Date? {
        if let date = photo.date, let parsed = dayFormatter.date(from: String(date.prefix(10))) {
            return parsed
        }
        if let created = photo.createdAt, let parsed = isoFormatter.date(from: created) {
            return parsed
        }
        if let created = photo.createdAt,
           let parsed = dayFormatter.date(from: String(created.prefix(10))) {
            return parsed
        }
        return nil
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

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
