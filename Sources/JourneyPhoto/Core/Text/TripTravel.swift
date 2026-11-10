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
    }

    /// 場所と場所の間（同じ日の中・前の場所 → 次の場所）
    struct Leg: Identifiable, Equatable {
        let from: Endpoint
        let to: Endpoint
        /// まっすぐの距離（km）。手段の順を決めるだけで、画面には出さない
        var kilometers: Double { TravelDistance.kilometers(from: from.coords, to: to.coords) }
        /// 控えの鍵（同じ区間・同じ座標なら1回だけ聞く）
        var key: String {
            String(format: "%.5f,%.5f>%.5f,%.5f", from.coords.lat, from.coords.lng, to.coords.lat, to.coords.lng)
        }
        var id: String { "\(from.number)>\(to.number):\(key)" }
    }

    /// 同じ日の区間（座標のある前の場所 → 次の場所）。座標の無い場所は飛ばす
    static func legs(_ stops: [(name: String, coords: Photo.Coords?, number: Int)]) -> [Leg] {
        var previous: Endpoint?
        var out: [Leg] = []
        for stop in stops {
            guard let coords = stop.coords else { continue }
            let here = Endpoint(name: stop.name, coords: coords, number: stop.number)
            if let previous, previous.coords != coords || previous.name != here.name {
                out.append(Leg(from: previous, to: here))
            }
            previous = here
        }
        return out
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

    /// 「13:00 ごろに出ると、日の入り 16:47 の前に着く見込み」。行き先に夕方の斜光の案内があれば、
    /// その始まりに間に合う時刻で言う。**地図のアプリには日時を渡せない**ので、合わせる時刻を見せる。
    /// 30分の単位で早めに丸める。日の出より前になるなら、間に合わないと言う
    static func departureHint(travelSeconds: Int, destinationTimes: [String], sun: TripDraft.Sun?)
        -> (text: String, clock: String?)? {
        guard let sun, let set = sun.sunsetDate, let sunsetClock = sun.sunset else { return nil }
        let evening = destinationTimes.contains("goldenHour")
        let target = evening ? (sun.goldenStart ?? set) : set
        let latest = target.addingTimeInterval(-Double(travelSeconds))
        let rounded = Date(timeIntervalSince1970: (latest.timeIntervalSince1970 / 1800).rounded(.down) * 1800)
        if let rise = sun.sunriseDate, rounded < rise {
            return (L("日の出に出ても、日の入り \(sunsetClock) までに着くのは難しい見込みです",
                      "Even leaving at sunrise, you may not arrive before sunset (\(sunsetClock))."), nil)
        }
        guard let clock = SunTimes.clock(rounded, in: sun.zone) else { return nil }
        if evening, let goldenStart = sun.goldenStart, let g = SunTimes.clock(goldenStart, in: sun.zone) {
            return (L("\(clock) ごろに出ると、夕方の斜光（\(g)〜）に間に合う見込み",
                      "Leave around \(clock) to arrive for golden hour (from \(g))."), clock)
        }
        return (L("\(clock) ごろに出ると、日の入り \(sunsetClock) の前に着く見込み",
                  "Leave around \(clock) to arrive before sunset (\(sunsetClock))."), clock)
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
