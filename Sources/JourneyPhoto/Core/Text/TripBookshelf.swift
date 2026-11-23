import Foundation

/// 旅の記録の本棚（札 #714・2026-11-23 owner 決定・案の頁「旅の道具の入口」）。
///
/// 投稿した旅（`TripBook.Trip`）と端末の旅（`LibraryTrip`）を**1つの棚**に、年ごとの段で背表紙として並べる。
/// 画面の部品は `TripBookshelfView`。ここには数と決まりだけを置く（Linux のテストで見張る・`TripBookshelfTests`）。
///
/// - 段は年ごと（新しい年が上）。段の中は新しい旅が左
/// - 背表紙の厚さは写真の枚数（22〜36pt）、高さは日数（118〜143pt）。押せる幅は 44pt（細い背は当たりを左右に広げる）
/// - 端末の中だけの旅は iPhone の印、自分だけの旅は鍵の印（色だけで言わない）
enum TripBookshelf {

    /// 棚の1冊
    struct Book: Identifiable, Hashable {
        enum Source {
            case posted(TripBook.Trip)
            case device(LibraryTrip)
        }

        let source: Source
        /// 背と読み上げの題（場所の名前。無ければ期間）
        let title: String
        let start: Date
        let photoCount: Int
        let days: Int
        /// 自分だけの一冊（非公開の写真が入っている）
        let isPrivate: Bool
        /// 年と月（撮った土地の暦）
        let year: Int
        let month: Int
        /// 背の地の色（写真の代表色を暗くしたもの・`clothColor`）
        let cloth: UInt32
        /// 端末の旅の地名（開いた一冊に渡す・`DeviceTripBookView`）。投稿した旅は nil
        var name: String? = nil

        var isDevice: Bool {
            if case .device = source { return true }
            return false
        }

        var id: String {
            switch source {
            case .posted(let trip): return "posted-\(trip.id)"
            case .device(let trip): return "device-\(trip.id)"
            }
        }

        static func == (a: Book, b: Book) -> Bool { a.id == b.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    /// 年の段
    struct Shelf: Identifiable, Equatable {
        let year: Int
        let books: [Book]
        var id: Int { year }
    }

    // MARK: - 寸法（案の頁の「詳しく」）

    /// 背の厚さ: 写真 0 枚で 22、60 枚以上で 36
    static let spineMinWidth: Double = 22
    static let spineMaxWidth: Double = 36
    static let spineWidthPhotos = 60
    /// 背の高さ: 1日で 123、5日以上で 143（118 + 日数 × 5）
    static let spineBaseHeight: Double = 118
    static let spineHeightPerDay: Double = 5
    static let spineMaxDays = 5
    /// 段の高さ（いちばん高い背 143 ＋ 上の余白）
    static let rowHeight: Double = 146
    /// 背どうしの間と、段どうしの間
    static let spineGap: Double = 3
    static let rowGap: Double = 14
    /// 背の上の表紙の窓
    static let windowHeight: Double = 30
    /// 押せる幅（44pt・CLAUDE.md）。背が細くても当たりはこの幅
    static let tapWidth: Double = 44
    /// 背の題（縦書きの明朝・13pt の太）。2026-11-23 owner 判断（札 #714 の案の頁）: `JPFont` の
    /// 「明朝は 18pt 未満に使わない」の例外。背表紙の縦書きは本の形で読ませる飾りに近く、読み上げは題を丸ごと言う
    static let titleSize: Double = 13
    static let monthSize: Double = 12

    static func spineWidth(photos: Int) -> Double {
        let n = Double(min(max(photos, 0), spineWidthPhotos))
        return (spineMinWidth + (n / Double(spineWidthPhotos) * (spineMaxWidth - spineMinWidth))).rounded()
    }

    static func spineHeight(days: Int) -> Double {
        spineBaseHeight + Double(min(max(days, 1), spineMaxDays)) * spineHeightPerDay
    }

    /// 背に縦に並べる題の字。収まらない分は「…」の縦の形（︙）で切る
    static func spineTitle(_ title: String, maxCharacters: Int) -> [String] {
        let chars = title.trimmingCharacters(in: .whitespaces).map(String.init)
        guard maxCharacters > 0 else { return [] }
        guard chars.count > maxCharacters else { return chars }
        return Array(chars.prefix(max(0, maxCharacters - 1))) + ["︙"]
    }

    /// 背の高さに入る題の字の数（窓・印・月の分を引いた残りを 1 字 = 字の大きさ＋1 で割る）
    static func spineTitleCapacity(height: Double, marks: Int) -> Int {
        let monthBlock = 34.0
        let free = height - windowHeight - Double(marks) * 17 - monthBlock - 12
        return max(1, Int(free / (titleSize + 1)))
    }

    /// 読み上げ（「旅、金沢、2026年9月、24枚、端末の中だけ、自分だけ」）
    static func spokenLabel(_ book: Book) -> String {
        var parts = [L("旅、\(book.title)", "Trip, \(book.title)"),
                     L("\(book.year)年\(book.month)月", "\(monthName(book.month)) \(book.year)"),
                     L("\(book.photoCount)枚", book.photoCount == 1 ? "1 photo" : "\(book.photoCount) photos")]
        if book.isDevice { parts.append(L("端末の中だけ", "On this iPhone only")) }
        if book.isPrivate { parts.append(L("自分だけ", "Only you")) }
        return parts.joined(separator: L("、", ", "))
    }

    private static func monthName(_ month: Int) -> String {
        let names = ["January", "February", "March", "April", "May", "June", "July",
                     "August", "September", "October", "November", "December"]
        return names.indices.contains(month - 1) ? names[month - 1] : "\(month)"
    }

    // MARK: - 並べる

    /// 投稿した旅と端末の旅を、年の段に分ける。新しい年が上、段の中は新しい旅が先
    static func shelves(_ books: [Book]) -> [Shelf] {
        let byYear = Dictionary(grouping: books, by: \.year)
        return byYear.keys.sorted(by: >).map { year in
            Shelf(year: year, books: byYear[year, default: []].sorted { a, b in
                a.start != b.start ? a.start > b.start : a.id < b.id
            })
        }
    }

    /// 段の中で、幅に入るだけ並べて折り返す（背の幅の並び → 行ごとの番号）
    static func rows(widths: [Double], available: Double, gap: Double = spineGap) -> [[Int]] {
        var rows: [[Int]] = []
        var current: [Int] = []
        var used = 0.0
        for (index, width) in widths.enumerated() {
            let need = current.isEmpty ? width : used + gap + width
            if !current.isEmpty, need > available {
                rows.append(current)
                current = [index]
                used = width
            } else {
                current.append(index)
                used = need
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    // MARK: - 本にする

    static func book(_ trip: TripBook.Trip) -> Book {
        let parts = TripBook.utcCalendar.dateComponents([.year, .month], from: trip.start)
        return Book(source: .posted(trip), title: TripBook.title(of: trip), start: trip.start,
                    photoCount: trip.photos.count, days: trip.days, isPrivate: trip.isPrivate,
                    year: parts.year ?? 0, month: parts.month ?? 1,
                    cloth: clothColor(hex: trip.cover?.dominantColor, seed: trip.id))
    }

    static func book(_ trip: LibraryTrip, name: String?) -> Book {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = trip.timeZone
        let parts = calendar.dateComponents([.year, .month], from: trip.start)
        return Book(source: .device(trip), title: DeviceTrips.title(of: trip, name: name), start: trip.start,
                    photoCount: trip.shots.count, days: LibraryTrips.calendarDays(trip), isPrivate: false,
                    year: parts.year ?? 0, month: parts.month ?? 1,
                    cloth: clothColor(hex: nil, seed: trip.id), name: name)
    }

    // MARK: - 背の地の色

    /// 写真の色が無いときの布の色（案の頁の見本の8色。どれも黒地の上で白い字が読める暗さ）
    static let cloths: [UInt32] = [0x26301F, 0x3F2620, 0x333C42, 0x20243A, 0x2C3A23, 0x4A3D2A, 0x3E242B, 0x1B3444]
    /// 写真の色を暗くするときの、いちばん明るい色の明るさ（白い字との差を保つ）
    static let clothBrightness = 0.30

    /// 背の地の色。写真の代表色（`#rrggbb`）の色みを残して暗くする。無ければ id で決まる布の色
    static func clothColor(hex: String?, seed: String) -> UInt32 {
        if let rgb = parseHex(hex) {
            let r = Double((rgb >> 16) & 0xFF), g = Double((rgb >> 8) & 0xFF), b = Double(rgb & 0xFF)
            let top = max(r, g, b)
            if top > 0 {
                let k = clothBrightness * 255 / top
                func c(_ v: Double) -> UInt32 { UInt32(min(255, max(0, (v * k).rounded()))) }
                return (c(r) << 16) | (c(g) << 8) | c(b)
            }
        }
        // 文字の和で選ぶ（`hashValue` は起動ごとに変わる）
        let sum = seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF }
        return cloths[sum % cloths.count]
    }

    private static func parseHex(_ hex: String?) -> UInt32? {
        guard var text = hex?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 else { return nil }
        return UInt32(text, radix: 16)
    }
}

/// 本を開く動き（札 #714・案の頁の「本を開く（実機）」）。秒は案の頁の値
enum TripBookMotion {
    /// 表紙がめくれ始める時刻と長さ（ゆっくり始まり、ゆっくり止まる）
    static let coverFlipDelay = 0.12
    static let coverFlipDuration = 0.26
    /// めくれた表紙の角度（左の辺を軸に）
    static let coverFlipAngle = -165.0
    static let perspective = 0.45
    /// 開き切ってはずむ時刻と大きさ（1回だけ）
    static let bounceAt = 0.54
    static let bounceScale = 1.012
    /// 合わせて約 0.55 秒、閉じるのは約 0.45 秒
    static let openTotal = 0.55
    static let closeTotal = 0.45
}

/// 旅の記録のタブの頭の、荷札の道具の列（札 #714）。**並びは決まった順、新しい道具は最後に足す**
enum TripTool: String, CaseIterable, Identifiable {
    case plans, albums, trunk, stampBook, passBook

    var id: String { rawValue }

    /// 画面の目印（UI テスト）。今までの行と同じ名前
    var identifier: String {
        switch self {
        case .plans: return "trips.plans"
        case .albums: return "trips.albums"
        case .trunk: return "trips.trunk"
        case .stampBook: return "trips.stampBook"
        case .passBook: return "trips.passBook"
        }
    }

    var title: String {
        switch self {
        case .plans: return L("旅行プラン", "Trip plans")
        case .albums: return Labels.Navigation.albums
        case .trunk: return TrunkEntryText.title
        case .stampBook: return L("スタンプ帳", "Stamp book")
        case .passBook: return L("すれちがい帳", "Pass book")
        }
    }

    /// 列に出す道具。トランクは口が読めたことのある人だけ（`TrunkAvailability`）。
    /// スタンプ帳（#712）はまだ無いので場所だけ用意して出さない
    static func shown(trunkAvailable: Bool, stampBookReady: Bool = false) -> [TripTool] {
        allCases.filter { tool in
            switch tool {
            case .trunk: return trunkAvailable
            case .stampBook: return stampBookReady
            default: return true
            }
        }
    }
}

/// 開いた一冊で、日のページを左右でめくる（札 #714・2026-11-23 owner 決定）。
///
/// 2026-11-23 判断: 一冊は下へ流れる1本の読み物（`TripBookView`）のまま作り直さず、**左右に払うと次の日・前の日の
/// 見出しへ送る**形にした。縦に読むのはそのまま、払えば本をめくるように日が替わる
enum TripBookPageFlip {
    /// めくったと見なす横の距離（pt）と、縦より横が勝つ比
    static let minimumDistance: Double = 60
    static let dominance: Double = 2
    /// 画面の左の端から始めた指は「戻る」の払いに任せる（めくらない）
    static let backEdge: Double = 24
    /// 日の見出しが「いま読んでいる日」になる、画面の上からの位置
    static let readingLine: Double = 140
    /// 次の日へ送る動きの長さ（秒）
    static let duration = 0.35

    /// 払いが日をめくる向き（左へ払う = 次の日 = +1、右へ払う = 前の日 = -1）。めくらないなら nil
    static func direction(dx: Double, dy: Double, startX: Double) -> Int? {
        guard startX > backEdge, abs(dx) >= minimumDistance, abs(dx) >= abs(dy) * dominance else { return nil }
        return dx < 0 ? 1 : -1
    }

    /// めくった先の日（1から）。いまの日が 0 なのは、まだ表紙や数字を読んでいるとき。行き先が無ければ nil
    static func target(current: Int, dayCount: Int, direction: Int) -> Int? {
        let next = current + direction
        guard dayCount > 0, (1...dayCount).contains(next) else { return nil }
        return next
    }

    /// いま読んでいる日（1から・0 は表紙）。見出しが読む線を過ぎた日のうち、いちばん後の日
    static func current(dayIDs: [String], passed: Set<String>) -> Int {
        (dayIDs.lastIndex { passed.contains($0) } ?? -1) + 1
    }

    /// めくった先の見出しの id。行き先が無ければ nil
    static func targetID(dayIDs: [String], passed: Set<String>, direction: Int) -> String? {
        target(current: current(dayIDs: dayIDs, passed: passed), dayCount: dayIDs.count, direction: direction)
            .map { dayIDs[$0 - 1] }
    }

    /// 見出しの行の id（`TripBook.pageRows` と同じ）
    static func headerID(day: Int) -> String { "day-\(day)" }
}
