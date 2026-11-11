import Foundation

/// 旅行プランの**移動の見込み**（2026-11-10 owner の要望「移動に何を使うとどれくらいかかるかもプランに入れたい」・札 #521）。
///
/// 9 月の「移動時間は出さない」（`TripPlan` の注記）は owner が緩めた。出すのは **Apple の地図が返した数だけ**
/// （`MKDirections.calculateETA`・端末から Apple のサーバーへ）。こちらで速さを仮定した数は作らない。
///
/// - **区間は1つの型**（`Leg`）で持つ。場所と場所の間の1行（`TripLegRow`）も、押して開く区間のシート
///   （`TripLegSheet`）もこれを受け取る——第2段で「どの電車・バスか」を出すときは、シートの中身だけを差し替える
/// - **選ばせない。** まっすぐの距離が 1.5km 以内なら歩きを先に、遠ければ車を先に聞く。もう1つの手段も聞き、
///   返った手段だけ並べる（最大2つ）。手段を選ぶ設定は作らない
/// - 返らない手段は出さない。どれも返らなければ「経路を地図で開く」だけ
/// - 圏外では聞かない（「電波が戻ると移動の見込みが出ます」）。見込みはサーバーに保存しない（プランの形を変えない）
/// - 位置は今いる場所を取らない。送るのは日程の場所の座標（公開の座標・約1kmに丸めたもの）だけ
enum TripTravel {

    enum Mode: String, CaseIterable, Hashable {
        case walking, automobile, transit

        var label: String {
            switch self {
            case .walking: return L("歩き", "Walk")
            case .automobile: return L("車", "Car")
            case .transit: return L("電車など", "Transit")
            }
        }

        /// 手段の印（SF Symbols）
        var symbol: String {
            switch self {
            case .walking: return "figure.walk"
            case .automobile: return "car"
            case .transit: return "tram"
            }
        }

        /// Google マップの URL の `travelmode`
        var googleMode: String {
            switch self {
            case .walking: return "walking"
            case .automobile: return "driving"
            case .transit: return "transit"
            }
        }
    }

    /// 区間の端。日程の場所（名前と座標）
    struct Endpoint: Equatable {
        let name: String
        let coords: Photo.Coords
        /// 日程の通し番号（1から）
        let number: Int
        /// 国（台帳の撮影スポットだけ分かる。日本の行は「日本」）。行きたい場所・撮影地は nil（座標の距離だけで決める）
        var country: String? = nil
        /// 都市の名前（台帳の市区町村・都道府県・国。Google フライトに渡す）。無ければ場所の名前
        var place: String? = nil
    }

    /// 場所と場所の間（同じ日の中・前の場所 → 次の場所）
    struct Leg: Identifiable, Equatable {
        let from: Endpoint
        let to: Endpoint
        /// 前の日の最後の場所から、この日の最初の場所へ（日をまたぐ区間・2026-11-11 札 #521 の続き）
        var crossesDay = false
        /// まっすぐの距離（km）。手段の順を決めるだけで、画面には出さない
        var kilometers: Double { TravelDistance.kilometers(from: from.coords, to: to.coords) }
        /// 控えの鍵（同じ区間・同じ座標なら1回だけ聞く）
        var key: String {
            String(format: "%.5f,%.5f>%.5f,%.5f", from.coords.lat, from.coords.lng, to.coords.lat, to.coords.lng)
        }
        var id: String { "\(from.number)>\(to.number):\(key)" }
    }

    /// 日程の1か所（区間を作る材料）
    struct Stop: Equatable {
        let name: String
        let coords: Photo.Coords?
        let number: Int
        var country: String? = nil
        var place: String? = nil

        init(_ name: String, _ coords: Photo.Coords?, _ number: Int, country: String? = nil, place: String? = nil) {
            self.name = name
            self.coords = coords
            self.number = number
            self.country = country
            self.place = place
        }

        var endpoint: Endpoint? {
            coords.map { Endpoint(name: name, coords: $0, number: number, country: country, place: place) }
        }
    }

    /// 同じ日の区間（座標のある前の場所 → 次の場所）。座標の無い場所は飛ばす。
    /// **同じ座標の2か所の間は出さない**（見込みは 0 分で、出しても読み違えるだけ・2026-11-11）
    static func legs(_ stops: [Stop]) -> [Leg] {
        var previous: Endpoint?
        var out: [Leg] = []
        for stop in stops {
            guard let here = stop.endpoint else { continue }
            if let previous, previous.coords != here.coords {
                out.append(Leg(from: previous, to: here))
            }
            previous = here
        }
        return out
    }

    /// プラン全体の区間を日ごとに。**2 日目以降は「前の日の最後の場所 → この日の最初の場所」も出す**
    /// （2026-11-11 owner の実機「バスとか出てこないよ」: 1 日 1 か所のプランでは同じ日の区間が 0 で、
    /// 移動の目安が1つも出なかった）。空の日・座標の無い日は飛ばし、その前の場所から。返すのは日の数と同じ長さ
    static func planLegs(_ days: [[Stop]]) -> [[Leg]] {
        var lastOfEarlierDays: Endpoint?
        return days.map { stops in
            var out: [Leg] = []
            if let previous = lastOfEarlierDays,
               let first = stops.first(where: { $0.coords != nil })?.endpoint,
               previous.coords != first.coords {
                out.append(Leg(from: previous, to: first, crossesDay: true))
            }
            out += legs(stops)
            if let last = stops.last(where: { $0.coords != nil })?.endpoint {
                lastOfEarlierDays = last
            }
            return out
        }
    }

    // MARK: - 長い移動（国をまたぐ・海を越える・2026-11-11 owner「日本からブラジルとか無理じゃん」）

    /// これより遠い区間は、国が分からなければ Apple の地図に聞かない（km・まっすぐの距離）。
    ///
    /// 2026-11-11 判断: **500km**。日本の主な区間のまっすぐの距離は 東京–大阪 約 400km・東京–広島 約 680km・
    /// 東京–福岡 約 880km・東京–札幌 約 830km（どれも国内）。国が両方とも日本と分かる区間は、500km を越えても
    /// 聞く（新幹線・車の見込みが返るなら出す。返らなければ長い移動に倒す）。国が分からない場所（行きたい場所・
    /// 撮影地）どうしで 500km を越えると、海を越える区間が混ざる（東京–ソウル 約 1,150km）ので聞かない
    static let longKm = 500.0

    static let japan = "日本"

    /// 撮影スポットの国（索引は日本の外の行だけ `country` を持つ。持たなければ日本）
    static func country(of spot: OfficialSpot) -> String {
        let c = spot.region?.country?.trimmingCharacters(in: .whitespaces) ?? ""
        return c.isEmpty ? japan : c
    }

    /// 区間の両端の国が分かっていて、違う
    static func crossesBorder(_ leg: Leg) -> Bool {
        guard let a = leg.from.country, let b = leg.to.country else { return false }
        return a != b
    }

    /// 両端とも日本と分かる
    static func bothInJapan(_ leg: Leg) -> Bool {
        leg.from.country == japan && leg.to.country == japan
    }

    /// Apple の地図に聞かない区間（国が違う・国が分からないまま 500km 以上）
    static func skipsDirections(_ leg: Leg) -> Bool {
        if crossesBorder(leg) { return true }
        return leg.kilometers >= longKm && !bothInJapan(leg)
    }

    /// 長い移動の形で出すか。聞かない区間はいつも。日本の中の 500km 以上は、聞き終えて何も返らなかったときだけ
    static func showsAsLong(_ leg: Leg, estimates: [Estimate], settled: Bool) -> Bool {
        if skipsDirections(leg) { return true }
        return leg.kilometers >= longKm && settled && estimates.isEmpty
    }

    /// 「約 18,600km」。1,000km 以上は 100km、それより短いと 10km の単位に丸める（概数）
    static func roughDistance(_ km: Double) -> String {
        let unit = km >= 1000 ? 100.0 : 10.0
        let rounded = max(unit, (km / unit).rounded() * unit)
        return L("約 \(TravelDistance.formatted(rounded))km", "about \(TravelDistance.formatted(rounded)) km")
    }

    /// 行の字（「飛行機などの長い移動・約 18,600km」）。**所要時間は出さない**（推定の数を作らない）
    static func longLine(_ leg: Leg) -> String {
        L("飛行機などの長い移動・\(roughDistance(leg.kilometers))",
          "Long trip (flight etc.) · \(roughDistance(leg.kilometers))")
    }

    /// Google フライトの URL（鍵の要らない検索の URL・出発と到着の都市名・日付は分かれば）
    static func googleFlightsURL(_ leg: Leg, date: String?) -> URL? {
        let from = leg.from.place ?? leg.from.name
        let to = leg.to.place ?? leg.to.name
        var q = "Flights from \(from) to \(to)"
        if let date, TripPlanText.date(fromYMD: date) != nil { q += " on \(date)" }
        var c = URLComponents(string: "https://www.google.com/travel/flights")
        c?.queryItems = [URLQueryItem(name: "q", value: q)]
        return c?.url
    }

    /// 区間が1つも作れないときの1行（**場所が1か所だけ**のとき）。何も出ない理由を、押す前に分かるように。
    /// 0 か所のときは日の「まだ何も入っていません」が言うので出さない。2 か所以上なら区間が出るので出さない
    static func singlePlaceHint(locatedPlaces: Int) -> String? {
        guard locatedPlaces == 1 else { return nil }
        return L("場所が 2 つ以上になると、間の移動の目安（車・歩き・電車など）が出ます",
                 "Add another place to see travel times (car, walking, transit) between them.")
    }

    /// 日をまたぐ区間の行の頭（「前の日の伏見稲荷大社から」）
    static func crossDayLabel(_ leg: Leg) -> String {
        L("前の日の\(leg.from.name)から", "From \(leg.from.name) (previous day)")
    }

    /// 歩きを先に出す距離（km）
    static let walkFirstKm = 1.5

    /// 聞く手段（先に出す順・最大2つ）。**公共交通が使えない（`transitAvailable == false`）ときは車と歩きだけ**
    static func modes(for leg: Leg, transitAvailable: Bool) -> [Mode] {
        if leg.kilometers <= walkFirstKm { return [.walking, .automobile] }
        return transitAvailable ? [.automobile, .transit] : [.automobile, .walking]
    }

    /// 歩きは遠いと出さない（返っても、遠い区間に歩きの時間を並べると読み違える）。分
    static let walkingMaxMinutes = 90

    struct Estimate: Equatable {
        let mode: Mode
        let seconds: Int
    }

    /// 返った手段だけ、聞いた順で（最大2つ）。遠すぎる歩きは落とす
    static func shown(_ modes: [Mode], results: [Mode: Int]) -> [Estimate] {
        modes.compactMap { mode in
            guard let s = results[mode], s > 0 else { return nil }
            if mode == .walking && s > walkingMaxMinutes * 60 && modes.first != .walking { return nil }
            return Estimate(mode: mode, seconds: s)
        }.prefix(2).map { $0 }
    }

    /// 「約 15 分」「約 1 時間 20 分」。1時間を越えたら10分の単位に丸める（見込みなので細かく言わない）
    static func duration(_ seconds: Int) -> String {
        let minutes = max(1, Int((Double(seconds) / 60).rounded()))
        if minutes < 60 { return L("約 \(minutes) 分", "about \(minutes) min") }
        let rounded = Int((Double(minutes) / 10).rounded()) * 10
        let h = rounded / 60, m = rounded % 60
        if m == 0 { return L("約 \(h) 時間", "about \(h) h") }
        return L("約 \(h) 時間 \(m) 分", "about \(h) h \(m) min")
    }

    /// 1行の読み上げ（「歩き 約 15 分、車 約 6 分」）
    static func spoken(_ estimates: [Estimate]) -> String {
        estimates.map { "\($0.mode.label) \(duration($0.seconds))" }.joined(separator: L("、", ", "))
    }

    // MARK: - 間に合わないとき

    /// 日の移動が長すぎる・夕方の場所に日の入りまでに着けないときの1行。**計算した数だけで言う**
    /// （Apple の見込みと端末で計算した日の出・日の入り）。滞在の時間は足さない（こちらで仮定しない）。
    ///
    /// 仕様（提案の版4「間に合わないときの一言」）と照らした式（2026-11-10 判断）:
    /// - 「その日の移動（先に出した手段の合計）が、日の出から日の入りまでの長さに対して長すぎるとき」
    ///   → `合計 × 2 ≥ 日の出から日の入りまで`（昼の半分以上を移動に使う）。
    ///   **2026-11-10 判断（札 #521・秘書室）: 半分のまま。昼の長さの半分以上の移動は撮る時間が足りない**
    /// - 「『夕方の斜光』『日没後』の場所に着くのが日の入りより後になりそうなとき」
    ///   → `日の出 ＋ その場所までの移動の合計 > 日の入り`（日の出に出て、移動だけで着く最も早い時刻でも日の入りを過ぎる）。
    ///   行き先の時間帯の案内に夕方の斜光か日没後があれば数える（`lateNames`）。返らない区間は 0 秒で数える（数を作らない）
    ///
    /// - `travel`: 区間ごとに先に出した手段の秒数（返らない区間は nil・数えない）
    /// - `arrivals`: 各区間の行き先が「夕方の斜光」「日没後」の案内を持つか、その名前
    static func dayWarning(travel: [Int?], lateNames: [String?], sun: TripDraft.Sun?) -> String? {
        let known = travel.compactMap { $0 }
        guard !known.isEmpty, let sun, let rise = sun.sunriseDate, let set = sun.sunsetDate, set > rise else { return nil }
        let total = known.reduce(0, +)
        let daylight = Int(set.timeIntervalSince(rise))
        // 夕方の場所: 日の出に出て移動だけで着いても、日の入りより後になる
        var cumulative = 0
        var late: String?
        for (i, seconds) in travel.enumerated() {
            cumulative += seconds ?? 0
            if late == nil, lateNames.indices.contains(i), let name = lateNames[i], cumulative > daylight {
                late = name
            }
        }
        let tooLong = total * 2 >= daylight
        guard tooLong || late != nil else { return nil }
        var parts: [String] = []
        if tooLong {
            parts.append(L("移動だけで\(duration(total))。日の出から日の入りまでは\(duration(daylight))です",
                           "Travel alone takes \(duration(total)); daylight is \(duration(daylight))"))
        }
        if let late {
            parts.append(L("\(late)は夕方の案内があり、日の入りに間に合わないかもしれません",
                           "\(late) is best in the evening and you may not arrive before sunset"))
        }
        return parts.joined(separator: L("。", ". "))
    }

    // MARK: - 出る時刻の目安（区間のシート）

    struct Departure: Equatable {
        let text: String
        /// 地図のアプリで合わせる時刻（間に合わない日は nil）
        let clock: String?
        /// 前の場所の時間帯の案内と合わないときの一言（「金沢城公園の夕方の斜光を見てからだと間に合わない見込み」）
        var caution: String? = nil
    }

    /// 前の場所の時間帯が始まる時刻（夕方の斜光 → その始まり・日没後と夜 → 日の入り）。朝・日中は出る時刻を縛らない
    static func windowStart(_ time: String, sun: TripDraft.Sun) -> Date? {
        switch time {
        case "goldenHour": return sun.goldenStart
        case "dusk", "night": return sun.sunsetDate
        default: return nil
        }
    }

    /// 「13:00 ごろに出ると、日の入り 16:47 の前に着く見込み」。行き先に夕方の斜光の案内があれば、
    /// その始まりに間に合う時刻で言う。**地図のアプリには日時を渡せない**ので、合わせる時刻を見せる。
    /// 30分の単位で早めに丸める。日の出より前になるなら、間に合わないと言う。
    ///
    /// **前の場所の時間帯**（提案の版4「前の場所の時間帯の案内と、行き先の日の入りと、所要時間から」）:
    /// 前の場所に夕方の斜光・日没後・夜の案内があり、その時間帯が始まるのが出る時刻より後なら、
    /// 「見てからだと間に合わない」と添える（出る時刻そのものは行き先の日の入りで決める）
    static func departureHint(travelSeconds: Int, destinationTimes: [String], sun: TripDraft.Sun?,
                              previous: (name: String, times: [String])? = nil) -> Departure? {
        guard let sun, let set = sun.sunsetDate, let sunsetClock = sun.sunset else { return nil }
        let evening = destinationTimes.contains("goldenHour")
        let target = evening ? (sun.goldenStart ?? set) : set
        let latest = target.addingTimeInterval(-Double(travelSeconds))
        let rounded = Date(timeIntervalSince1970: (latest.timeIntervalSince1970 / 1800).rounded(.down) * 1800)
        if let rise = sun.sunriseDate, rounded < rise {
            return Departure(text: L("日の出に出ても、日の入り \(sunsetClock) までに着くのは難しい見込みです",
                                     "Even leaving at sunrise, you may not arrive before sunset (\(sunsetClock))."), clock: nil)
        }
        guard let clock = SunTimes.clock(rounded, in: sun.zone) else { return nil }
        var caution: String?
        if let previous {
            // 前の場所の時間帯のうち、出る時刻より後に始まるもの（いちばん早いもの）
            let late = SpotBodyText.timeOrder.filter(previous.times.contains)
                .compactMap { t in windowStart(t, sun: sun).map { (t, $0) } }
                .first { $0.1 > rounded }
            if let (time, _) = late, let label = SpotBodyText.timeLabel(time) {
                caution = L("\(previous.name)の\(label)を見てからだと、間に合わない見込みです",
                            "If you stay at \(previous.name) for \(label.lowercased()), you may not make it.")
            }
        }
        if evening, let goldenStart = sun.goldenStart, let g = SunTimes.clock(goldenStart, in: sun.zone) {
            return Departure(text: L("\(clock) ごろに出ると、夕方の斜光（\(g)〜）に間に合う見込み",
                                     "Leave around \(clock) to arrive for golden hour (from \(g))."),
                             clock: clock, caution: caution)
        }
        return Departure(text: L("\(clock) ごろに出ると、日の入り \(sunsetClock) の前に着く見込み",
                                 "Leave around \(clock) to arrive before sunset (\(sunsetClock))."),
                         clock: clock, caution: caution)
    }

    /// 地図のアプリで時刻を合わせる一言
    static func setTimeNote(_ clock: String) -> String {
        L("地図のアプリでは出発の時刻を「\(clock)」に合わせてください（日時はアプリから渡せません）",
          "Set the departure time to \(clock) in the maps app (the app can't pass the time).")
    }

    // MARK: - 地図のアプリへ

    /// Google マップの経路の URL（Maps URLs・鍵は要らない）。出発の時刻は渡せない
    static func googleURL(from: Photo.Coords, to: Photo.Coords, mode: Mode) -> URL? {
        var c = URLComponents(string: "https://www.google.com/maps/dir/")
        c?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "origin", value: String(format: "%.6f,%.6f", from.lat, from.lng)),
            URLQueryItem(name: "destination", value: String(format: "%.6f,%.6f", to.lat, to.lng)),
            URLQueryItem(name: "travelmode", value: mode.googleMode),
        ]
        return c?.url
    }

    /// 区間のシートで開く手段。**電車などが返った区間は電車など**（どの電車・バスかを地図のアプリで見る）、
    /// 無ければ先に出した手段。何も返らなければ距離で決めた先の手段
    static func openMode(_ estimates: [Estimate], modes: [Mode]) -> Mode {
        if estimates.contains(where: { $0.mode == .transit }) { return .transit }
        return estimates.first?.mode ?? modes.first ?? .automobile
    }

    // MARK: - 言葉

    static var sourceNote: String {
        L("移動の見込みは Apple のマップによるもの。道の混み具合で変わります",
          "Travel estimates are from Apple Maps and change with traffic.")
    }

    static var offlineNote: String {
        L("電波が戻ると移動の見込みが出ます", "Travel estimates appear when you're back online.")
    }

    static var throttledNote: String {
        L("移動の見込みを続けて聞いたため、少し待ってから開き直すと出ます",
          "Too many estimates in a row. Reopen in a little while to see them.")
    }

    static var openInMaps: String { L("経路を地図で開く", "Open route in Maps") }
}
