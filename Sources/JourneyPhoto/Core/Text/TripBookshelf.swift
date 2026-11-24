import Foundation

/// 旅の記録の本棚（札 #714・2026-11-23 owner 決定・案の頁「旅の道具の入口」）。
///
/// 投稿した旅（`TripBook.Trip`）と端末の旅（`LibraryTrip`）を**1つの棚**に、年ごとの段で背表紙として並べる。
/// 画面の部品は `TripBookshelfView`。ここには数と決まりだけを置く（Linux のテストで見張る・`TripBookshelfTests`）。
///
/// - 段は年ごと（新しい年が上）。段の中は新しい旅が左
/// - 背表紙の厚さは写真の枚数（30〜44pt）、高さは日数（200〜220pt）。押せる幅は背の幅＋間
/// - 背の題は旅でいちばん多い県の短い名（「新潟」「北海道」）、海外なら国名（「スペイン」）。取れなければ旅の題
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
        /// 旅でいちばん多い県の短い名（「新潟」「北海道」・`spinePrefecture`）。取れなければ nil
        var prefecture: String? = nil
        /// 県が取れない海外の旅の国の短い名（「スペイン」・`spineCountry`）。取れなければ nil
        var country: String? = nil

        /// 背に縦に並べる字。県が取れればその短い名、海外なら国名、どちらも取れなければ旅の題。
        /// 2026-11-24 owner「何県かわからないの悲しい」（1.2.0 の実機: 背の題が「新︙」「兼︙」で1〜2字しか出なかった）。
        /// 題の全部は開いた一冊と読み上げ（`spokenLabel`）に残す
        var spineText: String { prefecture ?? country ?? title }

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
    //
    // 2026-11-24 判断（owner「幅とか縦大きくしてみやすくしていいよ」・1.2.0 の実機で背の題が1〜2字の「︙」で読めなかった）:
    // 背を一回り大きくした。厚さ 22〜36 → 30〜44、窓 30 → 34、題の明朝 13 → 15pt（1字の箱 18 → 21）、月 12 → 13pt、
    // 高さ 141〜161 → 200〜220、段 164 → 223。**印が1つ付いたいちばん低い背にも5字**（3字の県名・「イギリス」「フランス」の
    // 国名）が切れずに入り、印の無い背は旅の題が5〜6字読める。厚さと高さは前と同じく枚数と日数で変わる（日に 5pt）。
    // 幅 375 の iPhone でも1段に7冊以上（いちばん厚い 44＋間 3 で 343 / 47）並ぶ。案の頁の背よりやや縦長になるが、
    // 縦書きの字を大きくした分で、背の形（上に窓、縦の題、下に月）は崩さない

    /// 背の厚さ: 写真 0 枚で 30、60 枚以上で 44
    static let spineMinWidth: Double = 30
    static let spineMaxWidth: Double = 44
    static let spineWidthPhotos = 60
    /// 背の高さ: 1日で 200、5日以上で 220（195 + 日数 × 5）。
    /// 2026-11-24 判断（owner「何県かわからないの悲しい」「幅とか縦大きくしてみやすくしていいよ」）: 前の 123〜143 では、
    /// いちばん低い背に題が2字、印（iPhone・鍵）が付くと1字しか入らなかった。**印が1つ付いたいちばん低い背にも5字入る**高さにした
    /// （34 窓 + 17 印 + 6 + 5 × 21 + 38 月 = 200）。月の塊を詰める案は、字の行の高さより箱を小さくすることになり、
    /// 字が重なるので取らなかった。印は1冊に1つまで（端末の旅は自分だけの印を持たない・`book(_:name:)`）
    static let spineBaseHeight: Double = 195
    static let spineHeightPerDay: Double = 5
    static let spineMaxDays = 5
    /// 段の高さ（いちばん高い背 220 ＋ 上の余白）
    static let rowHeight: Double = 223
    /// 背の題がいつも入る字の数（印が1つ付いたいちばん低い背でも。3字の県名と「イギリス」のような国名が切れない）
    static let spineMinCharacters = 5
    /// 背どうしの間と、段どうしの間
    static let spineGap: Double = 3
    static let rowGap: Double = 14
    /// 背の上の表紙の窓
    static let windowHeight: Double = 34
    /// 押せる幅は**背の幅＋間**（間の半分ずつを両側に。隣の背との真ん中で区切る・2026-11-23 確かめ役の指摘）。
    /// 44pt に広げると隣の背の当たりと重なり、細い背の右を押すと隣が開いた。押せる高さは背の高さ（200pt 以上）
    static func hitWidth(photos: Int) -> Double { spineWidth(photos: photos) + spineGap }
    /// 背の題（縦書きの明朝・15pt の太）。2026-11-23 owner 判断（札 #714 の案の頁）: `JPFont` の
    /// 「明朝は 18pt 未満に使わない」の例外。背表紙の縦書きは本の形で読ませる飾りに近く、読み上げは題を丸ごと言う。
    /// 2026-11-24 owner「幅とか縦大きくしてみやすくしていいよ」で 13 → 15pt に上げた（例外のまま）
    static let titleSize: Double = 15
    static let monthSize: Double = 13

    static func spineWidth(photos: Int) -> Double {
        let n = Double(min(max(photos, 0), spineWidthPhotos))
        return (spineMinWidth + (n / Double(spineWidthPhotos) * (spineMaxWidth - spineMinWidth))).rounded()
    }

    static func spineHeight(days: Int) -> Double {
        spineBaseHeight + Double(min(max(days, 1), spineMaxDays)) * spineHeightPerDay
    }

    /// 背の題の1字の箱の高さ（明朝 15pt の行の高さ 20〜22pt に合わせて固定する。字ごとに高さを割らない。
    /// 13pt のとき 18 だった比 1.385 のまま）
    static let titleBox: Double = 21

    /// 背に縦に並べる題の字。収まらない分は「…」の縦の形（︙）で切る。縦書きで横を向く字は縦の形にする（`spineGlyph`）
    static func spineTitle(_ title: String, maxCharacters: Int) -> [String] {
        let chars = title.trimmingCharacters(in: .whitespaces).map(String.init)
        guard maxCharacters > 0 else { return [] }
        guard chars.count > maxCharacters else { return chars }
        return Array(chars.prefix(max(0, maxCharacters - 1))) + ["︙"]
    }

    /// 縦書きの1字。縦の形が字に在れば置き換え、無い字（長音の「ー」・波の「〜」・ダッシュ）は 90° 回して描く
    static func spineGlyph(_ char: String) -> (text: String, rotated: Bool) {
        let vertical: [String: String] = ["…": "︙", "‥": "︰", "（": "︵", "）": "︶", "(": "︵", ")": "︶",
                                          "「": "﹁", "」": "﹂", "『": "﹃", "』": "﹄", "【": "︻", "】": "︼",
                                          "、": "︑", "。": "︒", "，": "︐", "：": "︓"]
        if let form = vertical[char] { return (form, false) }
        let turned: Set<String> = ["ー", "－", "-", "—", "―", "〜", "～", "~", "＝", "→", "←"]
        return (char, turned.contains(char))
    }

    /// 印1つの高さ（12pt の絵＋上の 5pt）・題の上の余白・月の塊（13pt の数字と「月」の2行 約 31＋間 1＋下の 6pt）
    static let markHeight: Double = 17
    static let titleTop: Double = 6
    static let monthBlock: Double = 38

    /// 背の高さに入る題の字の数（窓・印・題の上の余白・月の分を引いた残りを、1字の箱 `titleBox` で割る）
    static func spineTitleCapacity(height: Double, marks: Int) -> Int {
        let free = height - windowHeight - Double(marks) * markHeight - titleTop - monthBlock
        return max(1, Int(free / titleBox))
    }

    // MARK: - 背の県

    /// 背の県を引く手がかり。県は写真の撮影地の文字、なければ座標からいちばん近い市区町村の役所の県
    /// （同梱の表 `MunicipalOffices.bundled`・ネットには問い合わせない）。読み方は行った県マップと同じ `PrefectureResolver`
    static let spineResolver = PrefectureResolver(
        spotPrefectures: [:],
        anchors: MunicipalOffices.bundled.map { PrefectureResolver.Anchor(coords: $0.coords, prefecture: $0.prefecture) })

    /// 旅でいちばん多い県の短い名（「新潟県」→「新潟」、「北海道」はそのまま・`PrefectureResolver.shortName`）。
    /// 県と重みを旅の順に渡す。数が同じなら先に出た県。1つも無ければ nil（背は旅の題に戻る）
    static func spinePrefecture(_ weighted: [(prefecture: String?, weight: Int)]) -> String? {
        var totals: [String: Int] = [:]
        var order: [String] = []
        for item in weighted {
            guard let name = item.prefecture, !name.isEmpty, item.weight > 0 else { continue }
            if totals[name] == nil { order.append(name) }
            totals[name, default: 0] += item.weight
        }
        var best: String?
        for name in order where best == nil || totals[name, default: 0] > totals[best!, default: 0] {
            best = name
        }
        return best.map(PrefectureResolver.shortName)
    }

    /// 海外の旅の国（「スペイン」「フランス」）。撮影地・地名の文字に書かれた国名だけを読む（`VisitedCountries.country(in:)`・
    /// 本番の撮影地は「Barcelona (Catalonia, Spain)」の形で国を持つ）。座標から国は引かない（引く表をアプリに持たず、
    /// 地図に問い合わせると通信が要る）。日本は国名にしない（県が取れない国内の旅は題のまま）。多い方、同じ数なら先に出た国
    static func spineCountry(_ texts: [String?]) -> String? {
        var totals: [String: Int] = [:]
        var order: [String] = []
        for text in texts {
            guard let text, let name = VisitedCountries.country(in: text), name != "日本" else { continue }
            if totals[name] == nil { order.append(name) }
            totals[name, default: 0] += 1
        }
        var best: String?
        for name in order where best == nil || totals[name, default: 0] > totals[best!, default: 0] {
            best = name
        }
        return best
    }

    /// 投稿した旅の県: 写真1枚ずつの県（撮影地の文字 → 座標・`PrefectureResolver.prefecture(of:)`）で多い方
    static func spinePrefecture(of trip: TripBook.Trip, resolver: PrefectureResolver) -> String? {
        spinePrefecture(trip.photos.map { (resolver.prefecture(of: $0), 1) })
    }

    /// 端末の旅の県: 日ごとの代表点の県を、その日の写真の枚数で重みづけて多い方（写真1枚ずつ引くと重い）。
    /// 代表点が無ければ旅の代表点、それも引けなければ地名の文字（市区町村、無ければ都道府県・`PhotoLibrary.place`）
    static func spinePrefecture(of trip: LibraryTrip, name: String?, resolver: PrefectureResolver) -> String? {
        var weighted: [(prefecture: String?, weight: Int)] = trip.days.compactMap { day in
            day.center.map { (resolver.nearestPrefecture(to: $0), max(1, day.shots.count)) }
        }
        if let center = trip.center { weighted.append((resolver.nearestPrefecture(to: center), 1)) }
        if let found = spinePrefecture(weighted) { return found }
        return spinePrefecture([(PrefectureResolver.prefecture(inText: name), 1)])
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

    /// 端末の旅を棚に出すか（**判断はここ1か所**・2026-11-23 確かめ役の指摘）。
    ///
    /// 同じ旅を2冊にしない: 投稿した写真がある端末の旅は、投稿した旅として棚に並ぶ。
    /// #710（投稿の後押し）で、一部だけ投稿した旅も端末の旅として残りの写真で届く（`LibraryTrip.postedCount`）ので、
    /// **1枚でも投稿した旅は端末の背表紙にしない**（2026-11-23 判断・1.2.0 の統合で #714 の注記どおりに入れた。
    /// `TripBookshelfTests.testDeviceTripShelfGateIsOnePlace`）
    static func showsOnShelf(_ trip: LibraryTrip) -> Bool {
        trip.postedCount == 0
    }


    static func book(_ trip: TripBook.Trip) -> Book { book(trip, resolver: spineResolver) }

    static func book(_ trip: TripBook.Trip, resolver: PrefectureResolver) -> Book {
        let parts = TripBook.utcCalendar.dateComponents([.year, .month], from: trip.start)
        return Book(source: .posted(trip), title: TripBook.title(of: trip), start: trip.start,
                    photoCount: trip.photos.count, days: trip.days, isPrivate: trip.isPrivate,
                    year: parts.year ?? 0, month: parts.month ?? 1,
                    cloth: clothColor(hex: trip.cover?.dominantColor, seed: trip.id),
                    prefecture: spinePrefecture(of: trip, resolver: resolver),
                    country: spineCountry(trip.photos.map(\.location) + [trip.place]))
    }

    static func book(_ trip: LibraryTrip, name: String?) -> Book { book(trip, name: name, resolver: spineResolver) }

    static func book(_ trip: LibraryTrip, name: String?, resolver: PrefectureResolver) -> Book {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = trip.timeZone
        let parts = calendar.dateComponents([.year, .month], from: trip.start)
        return Book(source: .device(trip), title: DeviceTrips.title(of: trip, name: name), start: trip.start,
                    photoCount: trip.shots.count, days: LibraryTrips.calendarDays(trip), isPrivate: false,
                    year: parts.year ?? 0, month: parts.month ?? 1,
                    cloth: clothColor(hex: nil, seed: trip.id), name: name,
                    prefecture: spinePrefecture(of: trip, name: name, resolver: resolver),
                    country: spineCountry([name]))
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

/// 本を開く動き（札 #714・案の頁の「本を開く（実機）」の「詳しく」）。秒は案の頁の値
///
/// 開く: 引き出しと手前への回転 0.24 秒（ばね 応答 0.3、減衰 0.85）→ 0.12 秒から表紙が -165° めくれる 0.26 秒 →
/// 0.30 秒から頁が画面いっぱいへ 0.23 秒 → 0.54 秒で1回だけ 1.2% はずむ（約 0.55 秒）。
/// 閉じる: 頁が縮む 0.19 秒 → 0.12 秒から表紙が戻る 0.20 秒 → 0.27 秒から棚へ 0.18 秒（約 0.45 秒）
enum TripBookMotion {
    /// 引き出しと手前への回転（ばね）
    static let pullResponse = 0.3
    static let pullDamping = 0.85
    /// 棚に入っているときの本の向き（横を向いて背だけが見える）
    static let shelvedTurn = 78.0
    /// 表紙がめくれ始める時刻と長さ（ゆっくり始まり、ゆっくり止まる）
    static let coverFlipDelay = 0.12
    static let coverFlipDuration = 0.26
    /// めくれた表紙の角度（左の辺を軸に）
    static let coverFlipAngle = -165.0
    static let perspective = 0.45
    /// 頁が画面いっぱいへ広がり始める時刻と長さ（iOS 18 の拡大の移り変わり）
    static let pageGrowAt = 0.30
    static let pageGrowDuration = 0.23
    /// 開き切ってはずむ時刻と大きさ（1回だけ）
    static let bounceAt = 0.54
    static let bounceScale = 1.012
    /// 閉じる: 頁が縮む長さ、表紙が戻る時刻と長さ、棚へ帰る時刻と長さ
    static let pageShrinkDuration = 0.19
    static let coverCloseDelay = 0.12
    static let coverCloseDuration = 0.20
    static let shelveAt = 0.27
    static let shelveDuration = 0.18
    /// 合わせて約 0.55 秒、閉じるのは約 0.45 秒
    static let openTotal = 0.55
    static let closeTotal = 0.45
    /// 引き出した本の真ん中: 見えている所の高さのこの割合（中央より少し上）
    static let stageCenterRatio = 0.45
    /// 本（266pt）が見えている所の上下に残す余白
    static let stageMargin = 24.0
    /// 本の表紙の絵の長い辺の画素（本は約 196×266pt。案の頁「約 400px」に、3倍の画面で粗く見えない分を足した・`BookCoverCache`）
    static let coverPixels = 512

    /// 引き出した本の真ん中の高さ（棚の座標）。見えている所の中で、本が上下にはみ出さない所に置く
    static func stageCenterY(visibleHeight: Double, shelfTopInScroll: Double, bookHeight: Double = 266) -> Double {
        let half = bookHeight / 2
        let lower = stageMargin + half
        let upper = max(lower, visibleHeight - stageMargin - half)
        let inVisible = min(max(visibleHeight * stageCenterRatio, lower), upper)
        return inVisible - shelfTopInScroll
    }

    /// めくれている表紙が裏（見返し）を見せる角度か
    static func showsCoverBack(angle: Double) -> Bool { angle < -90 }
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
    /// スタンプ帳（#712）は 1.2.0 の統合で入ったので、マイページは `stampBookReady: true` で呼ぶ（2026-11-23）
    static func shown(trunkAvailable: Bool, stampBookReady: Bool = false) -> [TripTool] {
        allCases.filter { tool in
            switch tool {
            case .trunk: return trunkAvailable
            case .stampBook: return stampBookReady
            default: return true
            }
        }
    }

    /// 荷札を折り返して並べるか（横に送らない）。**アクセシビリティの大きさの字のときだけ**。
    /// 2026-11-23 判断（Mac run 1765 の `testCapturesTrunkLargeText`）: 大きな字では荷札が伸び、横に送る列では
    /// 3枚目の「旅のトランク」から先が画面の右の外に出て、送らないと見えず押せなかった。入口を隠さないよう、全部を画面の中に並べる
    static func wrapsTags(isAccessibilitySize: Bool) -> Bool {
        isAccessibilitySize
    }
}

/// 開いた一冊で、日のページを左右でめくる（札 #714・2026-11-23 owner 決定）。
///
/// 2026-11-23 判断: 一冊は下へ流れる1本の読み物（`TripBookView`）のまま作り直さず、**左右に払うと次の日・前の日の
/// 見出しへ送る**形にした。縦に読むのはそのまま、払えば本をめくるようにページが背を軸に回って日が替わる（`TripDayFlip`）
enum TripBookPageFlip {
    /// 離したときにめくると決める横の距離（pt）と速さ（pt/秒）
    static let minimumDistance: Double = 60
    static let minimumVelocity: Double = 500
    /// 指を受けるとき、横が縦にこの比で勝っていること
    static let dominance: Double = 1.2
    /// 画面の左の端から始めた指は「戻る」の払いに任せる（めくらない）
    static let backEdge: Double = 24
    /// 日の見出しが「いま読んでいる日」になる、画面の上からの位置
    static let readingLine: Double = 140
    /// 指に付いて回る角度の上限と、めくるときの角度・濃さ・時間
    static let followMax: Double = 14
    static let turnAngle: Double = 80
    static let turnFade: Double = 0.35
    static let turnOutDuration = 0.18
    static let turnInDuration = 0.24
    static let perspective = 0.5

    /// 指を受ける向き（左へ払う = 次の日 = +1、右へ払う = 前の日 = -1）。受けないなら nil。
    /// **その向きにめくる日があるときだけ受ける**——1日目と表紙で右へ払う指、左の端からの指は「戻る」へ譲る
    static func beginDirection(dx: Double, dy: Double, startX: Double, dayIDs: [String], passed: Set<String>) -> Int? {
        guard startX > backEdge, dx != 0, abs(dx) > abs(dy) * dominance else { return nil }
        let direction = dx < 0 ? 1 : -1
        return targetID(dayIDs: dayIDs, passed: passed, direction: direction) == nil ? nil : direction
    }

    /// 離したときにめくる向き。距離か速さが足りなければ nil（元へ戻す）
    static func commitDirection(dx: Double, velocityX: Double) -> Int? {
        let flung = abs(velocityX) >= minimumVelocity && (velocityX < 0) == (dx < 0)
        guard abs(dx) >= minimumDistance || (flung && dx != 0) else { return nil }
        return dx < 0 ? 1 : -1
    }

    /// 指に付いて回る角度（度）。左へ払うと背を軸に左へ少し回る
    static func followAngle(dx: Double, width: Double) -> Double {
        guard width > 0 else { return 0 }
        return min(followMax, max(-followMax, dx / width * followMax * 2))
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
