import Foundation

/// 旅をインスタのストーリーに（1.1.83・資料「画面デザインの案」第9章・2026-11-12 判断）。
///
/// 旅の流れ（行ってきます・今ここ・ただいま・旅の3枚）を、**切手と消印・フィルムの帯・搭乗券**の3つの型で
/// 9:16 の1枚（またはステッカー）にする。描くのは `TravelStoryRenderer`（UIKit）。ここは文字・既定・寸法だけで、
/// Linux の `swift test` で見張る。
///
/// **場所と日付の守り方（章の「守り方の決め事」）**
/// - 場所はいつも**写真の撮影地**（投稿にもう付いているもの）から作る。端末の今いる所は読まない（「今ここ」も撮影地）
/// - 細かさの既定は**県まで（海外は国まで）**。市まで・出さないは本人が選ぶ。選んだ値は次も使う
/// - 日付の既定は「今日」。**写真が今日撮ったものでなければ日付だけ**（「今日」と偽らない）。分までの時刻は出さない
/// - 家からの距離・次の行き先（旅行プラン）は出さない。ただいまの km は旅の中の移動（直線）だけ
/// - 自分の、全体に公開した写真だけ（`CollectionScreen.isShareable`・呼ぶ側で絞る）
enum TravelStory {

    // MARK: - 選ぶもの

    /// 型。**並びは章の触れる模型どおり**（搭乗券・切手と消印・フィルムの帯）。はじめは推奨 1 の切手と消印
    enum Kind: String, CaseIterable, Identifiable {
        case pass
        case stamp
        case film

        var id: String { rawValue }

        var name: String {
            switch self {
            case .pass: return L("搭乗券", "Boarding pass")
            case .stamp: return L("切手と消印", "Stamp & postmark")
            case .film: return L("フィルムの帯", "Film strip")
            }
        }

        /// ステッカー（透明の地）にできるか。フィルムの帯は3枚を並べる型なので写真に重ねるだけ（章の模型）
        var supportsSticker: Bool { self != .film }

        /// 旅のどこ（行ってきます・今ここ・ただいま）を選ぶか。搭乗券だけ（章の模型）
        var usesPhase: Bool { self == .pass }
    }

    /// 描いて置いておく型: 今の型と両隣（払った先だけ。2026-11-12・確かめ役「置き場を今の選び＋両隣に」）。
    /// 先頭が今の型（先に描く）
    static func nearby(_ kind: Kind) -> [Kind] {
        let all = Kind.allCases
        guard let index = all.firstIndex(of: kind) else { return [kind] }
        return [kind] + [index - 1, index + 1].filter(all.indices.contains).map { all[$0] }
    }

    /// 形。写真に重ねる（9:16 の JPEG）か、ステッカー（透明の PNG）か
    enum Mode: String, CaseIterable, Identifiable {
        case photo
        case sticker

        var id: String { rawValue }

        var label: String {
            self == .photo ? L("写真に重ねる", "On the photo") : L("ステッカー", "Sticker")
        }
    }

    /// 旅のどこ（搭乗券の場面）
    enum Phase: String, CaseIterable, Identifiable {
        case go
        case now
        case home

        var id: String { rawValue }

        var label: String {
            switch self {
            case .go: return L("行ってきます", "Off I go")
            case .now: return L("今ここ", "Right now")
            case .home: return L("ただいま", "Back home")
            }
        }

        /// 搭乗券の左上の小さな字（行き先・今・出発地）
        var head: String {
            switch self {
            case .go: return "TO"
            case .now: return "NOW"
            case .home: return "FROM"
            }
        }
    }

    /// 場所の細かさ。**既定は県まで**（海外は国まで）
    enum PlaceLevel: String, CaseIterable, Identifiable {
        case prefecture
        case city
        case none

        var id: String { rawValue }

        var label: String {
            switch self {
            case .prefecture: return L("県まで", "Region")
            case .city: return L("市まで", "City")
            case .none: return L("出さない", "Hide")
            }
        }
    }

    /// 日付。**既定は「今日」**（今日撮った写真でなければ日付）
    enum DateLevel: String, CaseIterable, Identifiable {
        case today
        case date
        case none

        var id: String { rawValue }

        var label: String {
            switch self {
            case .today: return L("今日", "Today")
            case .date: return L("日付", "Date")
            case .none: return L("出さない", "Hide")
            }
        }
    }

    /// 画面で選んでいるもの。**型・形・場所・日付は次も使う**（`load`/`save`）。場面は入口で決める（覚えない）
    struct Choice: Equatable, Hashable {
        var kind: Kind = .stamp
        var mode: Mode = .photo
        var placeLevel: PlaceLevel = .prefecture
        var dateLevel: DateLevel = .today
        var phase: Phase = .now

        /// 描くときの形。ステッカーにできない型（フィルムの帯）は写真に重ねる
        var effectiveMode: Mode { kind.supportsSticker ? mode : .photo }

        /// 型を替えたときの選び。形・場所・日付・場面は保つ（描くときに `effectiveMode` で読む）
        func with(kind: Kind) -> Choice {
            var next = self
            next.kind = kind
            return next
        }

        /// 絵を控える鍵（使わない選びを落とす。フィルムの帯で形を替えても描き直さない）
        var renderKey: String {
            [kind.rawValue, effectiveMode.rawValue, placeLevel.rawValue, dateLevel.rawValue,
             kind.usesPhase ? phase.rawValue : "-"].joined(separator: "|")
        }
    }

    // MARK: - 覚える（端末の UserDefaults・`SignatureShareCardSheet` の型と同じ扱い）

    static let defaultsPrefix = "travelStory."

    /// 前に選んだもの。初めては切手と消印・写真に重ねる・県まで・今日。場面は入口から
    static func load(phase: Phase, defaults: UserDefaults = .standard) -> Choice {
        var choice = Choice()
        choice.phase = phase
        if let raw = defaults.string(forKey: defaultsPrefix + "kind"), let kind = Kind(rawValue: raw) { choice.kind = kind }
        if let raw = defaults.string(forKey: defaultsPrefix + "mode"), let mode = Mode(rawValue: raw) { choice.mode = mode }
        if let raw = defaults.string(forKey: defaultsPrefix + "place"),
           let level = PlaceLevel(rawValue: raw) { choice.placeLevel = level }
        if let raw = defaults.string(forKey: defaultsPrefix + "date"),
           let level = DateLevel(rawValue: raw) { choice.dateLevel = level }
        return choice
    }

    static func save(_ choice: Choice, defaults: UserDefaults = .standard) {
        defaults.set(choice.kind.rawValue, forKey: defaultsPrefix + "kind")
        defaults.set(choice.mode.rawValue, forKey: defaultsPrefix + "mode")
        defaults.set(choice.placeLevel.rawValue, forKey: defaultsPrefix + "place")
        defaults.set(choice.dateLevel.rawValue, forKey: defaultsPrefix + "date")
    }

    // MARK: - 載せる事実（作り話をしない・`TripBookCard` と同じ考え）

    /// 旅の一冊から開いたときの数
    struct TripFacts: Equatable {
        /// 枚数（ただいまの PHOTOS）
        let photoCount: Int
        /// 旅の中の移動（直線・km）。数えられなければ nil（`TravelDistance`）
        let distanceKm: Double?
        /// 何日間の旅か（ただいまの DAY）
        let days: Int
        /// 先頭の写真が旅の何日目か（今ここの DAY・切手の「2日目」）。分からなければ nil
        let leadDay: Int?
    }

    struct Facts: Equatable {
        /// 先頭の写真の撮影地（投稿に付いている文字）
        let location: String?
        /// 先頭の写真の撮った日（`TripBook.day(of:)`・その日の UTC 0 時）。分からなければ nil
        let takenDay: Date?
        /// 撮った人の名前（搭乗券の PASSENGER）
        let name: String
        /// 旅の一冊から開いたときだけ
        var trip: TripFacts? = nil
    }

    /// 写真1枚（写真の詳細の ⋯ → ストーリーに）の事実
    static func facts(of photo: Photo, name: String) -> Facts {
        Facts(location: photo.location,
              takenDay: TripBook.hasTakenDay(photo) ? TripBook.day(of: photo) : nil,
              name: name)
    }

    /// 旅の一冊（「ストーリーに」）の事実。`lead` は絵に載せる先頭の1枚（呼ぶ側は旅の最後の、配ってよい1枚を渡す）。
    /// **場所と日付は `lead` からだけ取る**（配らない写真の撮影地を載せない）
    static func facts(of trip: TripBook.Trip, lead: Photo, name: String, distance: Double?) -> Facts {
        let day = TripBook.hasTakenDay(lead) ? TripBook.day(of: lead, in: trip.timeZone) : nil
        let leadDay = day.map { TripBook.calendarDays(from: trip.start, to: $0) + 1 }
        return Facts(location: lead.location,
                     takenDay: day,
                     name: name,
                     trip: TripFacts(photoCount: trip.photos.count,
                                     distanceKm: TripBook.showsDistance(distance) ? distance : nil,
                                     days: trip.days,
                                     leadDay: leadDay))
    }

    /// 画面に渡す写真の URL と事実（写真の詳細・旅の一冊の両方の入口から作る）
    struct Source: Equatable {
        let lead: URL
        let film: [URL]
        let facts: Facts
    }

    /// 写真の詳細から開いたときのフィルムの帯。先頭は上に出ている1枚、残りは同じ投稿の束から。
    /// **載せるのは自分の、全体に公開した写真だけ**（`CollectionScreen.isShareable`・2026-11-12 確かめ役「入口の条件を試験で縛る」）
    static func filmPicks(target: Photo, group: [Photo]) -> [Photo] {
        guard CollectionScreen.isShareable(target) else { return [] }
        let rest = group.filter { $0.id != target.id && CollectionScreen.isShareable($0) }
        return filmPicks([target] + rest)
    }

    /// 旅の一冊から開くときの元。先頭は旅の最後の、配ってよい1枚（ただいまの場所）、フィルムの帯は始め・中ほど・終わり。
    /// **配ってよい写真が1枚も無ければ nil**（入口を出さない）。配らない写真の撮影地・画像は使わない
    static func source(of trip: TripBook.Trip, name: String, distance: Double?) -> Source? {
        let shareable = trip.photos.filter(CollectionScreen.isShareable)
        guard let last = shareable.last, let lead = last.detailImageURL else { return nil }
        return Source(lead: lead,
                      film: filmPicks(shareable).compactMap(\.detailImageURL),
                      facts: facts(of: trip, lead: last, name: name, distance: distance))
    }

    /// フィルムの帯に並べる写真（最大3枚）。**旅の流れに沿って、始め・中ほど・終わり**を選ぶ。
    /// 3枚に満たなければあるだけ（同じ写真を繰り返さない）
    static func filmPicks<T>(_ items: [T]) -> [T] {
        guard items.count > 3 else { return items }
        let last = items.count - 1
        return [items[0], items[last / 2], items[last]]
    }

    // MARK: - 文字

    /// 絵に載せる文字。**選んだ細かさより細かい場所・日付を出さない**
    struct Texts: Equatable {
        /// 場所（和文）。県まで＝都道府県（海外は国）、市まで＝市区町村。出さない・分からないは nil
        let place: String?
        /// 場所のラテン文字（搭乗券の大きな字・消印の上）。県まで・市まで＝都道府県の英名（海外は国名がラテン文字なら）
        let placeLatin: String?
        /// 「今日」か「2026.11.11」。出さないは nil
        let date: String?
        /// 消印の日付「26.11.11」。出さない・分からないは nil
        let postmark: String?
        /// 旅の何日目か（一冊から開いたときだけ）
        let tripDay: Int?
    }

    static func texts(_ facts: Facts, choice: Choice, now: Date = Date(),
                      timeZone: TimeZone = .current) -> Texts {
        let place = placeText(facts.location, level: choice.placeLevel)
        let latin = choice.placeLevel == .none ? nil : placeLatin(facts.location)
        return Texts(place: place,
                     placeLatin: latin,
                     date: dateText(facts.takenDay, level: choice.dateLevel, now: now, timeZone: timeZone),
                     postmark: choice.dateLevel == .none ? nil : facts.takenDay.map { format($0, "yy.MM.dd") },
                     tripDay: facts.trip?.leadDay)
    }

    /// 場所の文字。`LocationMatch.shareCardPlace`（大きい単位／小さい単位）から選ぶ。
    ///
    /// 県までに出すのは**都道府県か国と分かるものだけ**——「山中湖」のような1つの欠片は県より細かいかもしれず、
    /// 文字だけでは見分けられないので出さない（安全側・2026-11-12 判断）
    static func placeText(_ location: String?, level: PlaceLevel) -> String? {
        guard level != .none, let place = LocationMatch.shareCardPlace(location) else { return nil }
        let region = isRegion(place.primary, location: location)
        switch level {
        case .prefecture:
            return region ? place.primary : nil
        case .city:
            return cityText(place, location: location, region: region) ?? (region ? place.primary : nil)
        case .none:
            return nil
        }
    }

    /// 住所の欠片（`LocationMatch.shareCardPlace` と同じ区切り・郵便番号だけの欠片は落とす）
    private static func pieces(_ location: String?) -> [String] {
        (location ?? "").components(separatedBy: CharacterSet(charactersIn: ",，、"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !LocationMatch.isPostalOrNumber($0) }
    }

    /// 1行目が県・国か（確かめ役の実測・2026-11-12 で直した）。
    /// - 都道府県の和名（「石川県」）
    /// - 最後が日本（「日本」「Japan」）の住所: 英文の県（"Kyoto Prefecture" から作った "Kyoto"）だけ。
    ///   「富士山, 日本」「富士吉田市, 日本」「Kyoto City, Japan」「Mt Fuji, Japan」の1行目は県より細かいので国とみなさない
    /// - それ以外（海外）: 欠片が2つ以上あり、1行目が最後の欠片（国）そのもののとき
    static func isRegion(_ primary: String, location: String?) -> Bool {
        if RegionList.prefectures.contains(primary) { return true }
        let parts = pieces(location)
        guard parts.count >= 2, let last = parts.last else { return false }
        if LocationMatch.isJapan(last) {
            return parts.dropLast().contains {
                LocationMatch.isEnglishPrefecture($0) && LocationMatch.shortEnglishPrefecture($0) == primary
            }
        }
        return primary == last
    }

    /// 市までの文字。日本は市区町村（`LocationMatch.shareCardPlace` の2行目）。
    ///
    /// **海外は、市と見なせるときだけ出し、見なせなければ国にとどめる**（安全な側・2026-11-12 確かめ役）。
    /// 文字だけでは「都市か施設か」を見分けられない（`LocationMatch.shareCardPlace` の注記）:
    /// 「Eiffel Tower, France」の1つ目は施設、Nominatim の長い形
    /// 「ヴェルサイユ, …, フランス・メトロポリテーヌ, 78000, フランス」の国の手前は地方。
    /// 市と見なすのは、座標からの自動入力の形「市, 州, 国」の3つで、真ん中が州・地域の名前
    /// （州・地域圏・省・Province・State・Region などで終わる）のときの1つ目だけ
    private static func cityText(_ place: LocationMatch.ShareCardPlace, location: String?, region: Bool) -> String? {
        let parts = pieces(location)
        guard let last = parts.last, !LocationMatch.isJapan(last), place.primary == last else {
            return place.secondary
        }
        guard region, parts.count == 3, isStateName(parts[1]) else { return nil }
        return parts[0]
    }

    /// 州・地域の名前か（国の1つ下の区分）
    private static func isStateName(_ part: String) -> Bool {
        if ["州", "地域圏", "省", "自治区", "特別市", "道"].contains(where: part.hasSuffix) { return true }
        let lower = part.lowercased()
        return [" state", " province", " region", " prefecture", " county", " oblast", " territory"]
            .contains(where: lower.hasSuffix)
    }

    /// 大きな字のラテン文字。日本は都道府県の英名（`ShareCardMap.englishPrefectures`）、
    /// 海外は国名がラテン文字ならそのまま。**市の英名は持っていないので、市までのときも県の英名**
    static func placeLatin(_ location: String?) -> String? {
        if let pref = ShareCardMap.prefectureName(in: location),
           let index = RegionList.prefectures.firstIndex(of: pref),
           ShareCardMap.englishPrefectures.indices.contains(index) {
            return ShareCardMap.englishPrefectures[index].uppercased()
        }
        guard let place = LocationMatch.shareCardPlace(location),
              isRegion(place.primary, location: location),
              place.primary.unicodeScalars.allSatisfy({ $0.isASCII }) else { return nil }
        return place.primary.uppercased()
    }

    /// 日付の文字。「今日」は**今日撮った写真のときだけ**。それ以外は撮った日
    static func dateText(_ takenDay: Date?, level: DateLevel, now: Date, timeZone: TimeZone) -> String? {
        guard level != .none, let takenDay else { return nil }
        if level == .today, isToday(takenDay, now: now, timeZone: timeZone) { return L("今日", "Today") }
        return format(takenDay, "yyyy.MM.dd")
    }

    /// 撮った日（UTC 0 時で持つ暦の日）が、端末の時刻帯の今日か
    static func isToday(_ takenDay: Date, now: Date, timeZone: TimeZone) -> Bool {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let today = local.dateComponents([.year, .month, .day], from: now)
        let taken = TripBook.utcCalendar.dateComponents([.year, .month, .day], from: takenDay)
        return today.year == taken.year && today.month == taken.month && today.day == taken.day
    }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = TripBook.utcCalendar
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// 旅の何日目（「2日目」「Day 2」）
    static func dayLabel(_ day: Int?) -> String? {
        day.map { L("\($0)日目", "Day \($0)") }
    }

    /// 場所が出せないときの言い方
    static var onTheRoad: String { L("旅の途中", "On the road") }

    // MARK: - 搭乗券の文字

    struct PassTexts: Equatable {
        /// 右上（明朝）の場面の名前
        let phaseLabel: String
        /// 左の小さな字（TO・NOW・FROM）
        let head: String
        /// 大きな字（ラテン文字）
        let big: String
        /// 大きな字の下（明朝）
        let local: String
        /// 右の DAY の数。分からなければ出さない
        let day: Int?
        /// 半券の欄（小さな見出しと値）
        let foot: [Field]

        struct Field: Equatable {
            let key: String
            let value: String
        }
    }

    static func pass(_ facts: Facts, choice: Choice, texts: Texts) -> PassTexts {
        let phase = choice.phase
        let day: Int?
        switch phase {
        case .go: day = 1
        case .now: day = texts.tripDay
        case .home: day = facts.trip?.days
        }
        var foot: [PassTexts.Field] = []
        if phase == .home, let trip = facts.trip {
            foot.append(.init(key: "PHOTOS", value: "\(trip.photoCount)"))
            if let km = trip.distanceKm { foot.append(.init(key: "DISTANCE", value: "\(TravelDistance.formatted(km)) km")) }
        } else {
            foot.append(.init(key: "DATE", value: texts.date ?? "—"))
            let name = facts.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { foot.append(.init(key: "PASSENGER", value: name)) }
        }
        return PassTexts(phaseLabel: phase.label,
                         head: phase.head,
                         big: texts.placeLatin ?? "ON THE ROAD",
                         local: texts.place ?? onTheRoad,
                         day: day,
                         foot: foot)
    }

    /// 切手の下の右（明朝）。旅の何日目か、分からなければ出さない
    static func stampCaption(_ texts: Texts) -> String? { dayLabel(texts.tripDay) }

    /// 封筒の下の「石川県より」
    static func from(_ texts: Texts) -> String {
        texts.place.map { L("\($0)より", "From \($0)") } ?? L("旅先より", "From the road")
    }

    /// フィルムの帯の下の2行（題・日付と何日目）。2行目は**欠片のまま返す**——「今日 · 2日目」のように中黒で
    /// つながない（2026-11-12 owner の好み「・」「·」で区切らない）。描く側が字の太さ・色と余白で分ける
    static func filmCaption(_ texts: Texts) -> (title: String, sub: [String]) {
        let sub = [texts.date, dayLabel(texts.tripDay)].compactMap { $0 }
        return (texts.place ?? L("旅の三枚", "Three from the trip"), sub)
    }

    // MARK: - 寸法（1080 × 1920 の画素・章の模型の cqw × 10.8）

    enum Layout {
        static let canvas = CGSize(width: 1080, height: 1920)
        /// 章の模型の 1cqw（幅の 1%）
        static let unit: CGFloat = 10.8
        static func u(_ value: CGFloat) -> CGFloat { value * unit }

        /// インスタの上の帯（名前）と下の送る欄に隠れない所（上 11%・下 12% を空ける）
        static let topSafe: CGFloat = canvas.height * 0.11
        static let bottomSafe: CGFloat = canvas.height * 0.12
        static var safeRect: CGRect {
            CGRect(x: 0, y: topSafe, width: canvas.width, height: canvas.height - topSafe - bottomSafe)
        }

        // 搭乗券
        static let passInset = u(6)
        static let passBottom = u(25)
        static let passStickerWidth = u(84)
        static let passStickerAngle: CGFloat = -4
        static let passCorner = u(3)
        static let passNotch = u(2.6)
        /// 本体（上）と半券（下）の高さ
        static let passBodyHeight = u(37)
        static let passStubHeight = u(17)
        static var passHeight: CGFloat { passBodyHeight + passStubHeight }
        /// 写真に重ねたときの券の枠
        static var passRect: CGRect {
            CGRect(x: passInset, y: canvas.height - passBottom - passHeight,
                   width: canvas.width - passInset * 2, height: passHeight)
        }

        // 切手と消印
        static let stampSize = CGSize(width: u(72), height: u(96))
        static let stampCenterY = canvas.height * 0.46
        static let stampAngle: CGFloat = -3
        static let stampPad = u(4)
        static let stampPerfRadius = u(1.5)
        static let stampPerfStep = u(4)
        static let stampCaptionHeight = u(8.6)
        static var stampRect: CGRect {
            CGRect(x: (canvas.width - stampSize.width) / 2, y: stampCenterY - stampSize.height / 2,
                   width: stampSize.width, height: stampSize.height)
        }
        /// 消印の輪（切手の左上を原点に・写真に重ねたとき右上に掛ける）。
        /// 模型は切手から 15cqw はみ出し、絵の右端で輪が 1cqw 切れていた（試験で分かった）。12cqw にして輪を絵の中に収める
        static let postmarkDiameter = u(31)
        static var postmarkRect: CGRect {
            CGRect(x: stampSize.width + u(12) - postmarkDiameter, y: -u(9),
                   width: postmarkDiameter, height: postmarkDiameter)
        }
        /// ステッカーのときは左下（切手の写真を隠さない）
        static var postmarkStickerRect: CGRect {
            CGRect(x: -u(7), y: stampSize.height + u(9) - postmarkDiameter,
                   width: postmarkDiameter, height: postmarkDiameter)
        }
        /// 封筒の下の行（下から 26cqw）
        static let fromBottom = u(26)
        static let fromInset = u(9)

        // フィルムの帯
        static let filmWidth = u(60)
        static let filmPadX = u(9)
        static let filmPadY = u(3)
        static var filmFrameWidth: CGFloat { filmWidth - filmPadX * 2 }
        static var filmFrameHeight: CGFloat { filmFrameWidth * 3 / 4 }
        /// 縁の番号の行（2.6cqw の字＋上下 1.1）
        static let filmEdgeHeight = u(2.6 + 2.2)
        /// 帯と下の2行の間。模型は 2.3cqw。3コマで隠れない所（高さの 77%）に収まる 2cqw にした
        static let filmCaptionGap = u(2)
        static let filmCaptionHeight = u(7 * 1.3 + 1.4 + 3.4 * 1.3)
        static let filmHoleX = u(2.5)
        static let filmHoleWidth = u(3.6)
        static let filmHoleStep = u(5.8)
        static let filmHoleStart = u(1.5)
        static let filmHoleHeight = u(2.8)

        static func filmHeight(frames: Int) -> CGFloat {
            let n = CGFloat(max(1, min(3, frames)))
            return filmPadY * 2 + filmEdgeHeight * (n + 1) + filmFrameHeight * n
        }

        /// 帯と下の2行の塊を、隠れない所の縦の真ん中に置く。帯の枠を返す
        static func filmRect(frames: Int) -> CGRect {
            let height = filmHeight(frames: frames)
            let block = height + filmCaptionGap + filmCaptionHeight
            let top = max(safeRect.minY, safeRect.midY - block / 2)
            return CGRect(x: (canvas.width - filmWidth) / 2, y: top, width: filmWidth, height: height)
        }

        static func filmCaptionRect(frames: Int) -> CGRect {
            let strip = filmRect(frames: frames)
            return CGRect(x: u(8), y: strip.maxY + filmCaptionGap,
                          width: canvas.width - u(16), height: filmCaptionHeight)
        }

        /// 回した四角が収まる外枠（ステッカーの大きさ・隠れない所の確かめ）
        static func rotatedBounds(_ rect: CGRect, degrees: CGFloat) -> CGRect {
            let radians = degrees * .pi / 180
            let c = abs(cos(radians)), s = abs(sin(radians))
            let width = rect.width * c + rect.height * s
            let height = rect.width * s + rect.height * c
            return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
        }
    }
}
