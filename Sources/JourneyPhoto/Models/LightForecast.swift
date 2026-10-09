import Foundation

/// 光と天気の知らせ（Pro・2026-10-09）。`GET /user/light-forecast` の応答。
///
/// 形はサーバーの `api-user/src/lightForecast.ts`（`getLightForecast`）と `lightOutlook.ts`（`DayLight`）:
///
///     { "places": [{ "key", "slug", "name", "nameEn"?, "timeZone", "forecast",
///                    "days": [{ "date", "sunrise": {at, clock}|null, "sunset", "morningBlue": {start, end},
///                               "eveningBlue": {start, end}, "morning": {weather, chance}|null, "evening", "night" }] }],
///       "note": "…", "attribution": { "serviceName": "Apple Weather", "legalUrl": "…" } }
///
/// **壊れた1か所で全体を落とさない**（場所・日・見込みはそれぞれ読めなければ落とす）。
/// ただし `places` そのものが無い応答は投げる——形の違う応答を「行きたい場所が無い」と混ぜない
/// （`TripPlanList` と同じ考え）。
struct LightForecast: Decodable, Equatable {

    /// 天気の言葉（窓の平均の雲量と降水確率から・サーバーが決める）
    enum Weather: String, Decodable, Equatable {
        case clear, partlyCloudy, cloudy, rain
    }

    /// 見込み 高 / 中 / 低。**並べるときは高いほど前**（`rank`）
    enum Chance: String, Decodable, Equatable {
        case high, mid, low

        /// 大きいほど良い
        var rank: Int {
            switch self {
            case .high: return 2
            case .mid: return 1
            case .low: return 0
            }
        }
    }

    /// 1つの時間帯の見込み（朝焼け・夕焼け・夜景のそれぞれ）
    struct Outlook: Decodable, Equatable {
        let weather: Weather
        let chance: Chance
    }

    /// 時刻。`clock` はその土地の時計（"05:42"）、`at` は瞬間（ISO）
    struct Clock: Decodable, Equatable {
        let at: String
        let clock: String
    }

    struct Span: Decodable, Equatable {
        let start: Clock?
        let end: Clock?

        init(start: Clock?, end: Clock?) {
            self.start = start
            self.end = end
        }

        private enum CodingKeys: String, CodingKey { case start, end }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            start = (try? c.decodeIfPresent(Clock.self, forKey: .start)) ?? nil
            end = (try? c.decodeIfPresent(Clock.self, forKey: .end)) ?? nil
        }
    }

    /// その土地の1日
    struct Day: Decodable, Equatable {
        /// その土地の暦日 "YYYY-MM-DD"
        let date: String
        let sunrise: Clock?
        let sunset: Clock?
        let morningBlue: Span?
        let eveningBlue: Span?
        /// 朝焼け。予報の届かない日・日が昇らない日は nil
        let morning: Outlook?
        /// 夕焼け
        let evening: Outlook?
        /// 夜景（夕方のブルーアワーから2時間）
        let night: Outlook?

        init(date: String, sunrise: Clock? = nil, sunset: Clock? = nil,
             morningBlue: Span? = nil, eveningBlue: Span? = nil,
             morning: Outlook? = nil, evening: Outlook? = nil, night: Outlook? = nil) {
            self.date = date
            self.sunrise = sunrise
            self.sunset = sunset
            self.morningBlue = morningBlue
            self.eveningBlue = eveningBlue
            self.morning = morning
            self.evening = evening
            self.night = night
        }

        private enum CodingKeys: String, CodingKey {
            case date, sunrise, sunset, morningBlue, eveningBlue, morning, evening, night
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // 日付が無い日は意味を持たないので、この日だけ落とす（`Lenient`）
            date = try c.decode(String.self, forKey: .date)
            // 知らない天気・見込みの言葉（サーバーが足した）は、その時間帯だけ「見込み無し」にする
            sunrise = (try? c.decodeIfPresent(Clock.self, forKey: .sunrise)) ?? nil
            sunset = (try? c.decodeIfPresent(Clock.self, forKey: .sunset)) ?? nil
            morningBlue = (try? c.decodeIfPresent(Span.self, forKey: .morningBlue)) ?? nil
            eveningBlue = (try? c.decodeIfPresent(Span.self, forKey: .eveningBlue)) ?? nil
            morning = (try? c.decodeIfPresent(Outlook.self, forKey: .morning)) ?? nil
            evening = (try? c.decodeIfPresent(Outlook.self, forKey: .evening)) ?? nil
            night = (try? c.decodeIfPresent(Outlook.self, forKey: .night)) ?? nil
        }
    }

    /// 行きたい場所（台帳の撮影スポット）1か所
    struct Place: Decodable, Equatable, Identifiable {
        /// `SPOT-<slug>`
        let key: String
        let slug: String
        let name: String
        let nameEn: String?
        /// IANA の時刻帯（日付の「今日・明日」をその土地の暦で決める）
        let timeZone: String?
        /// 予報が読めたか。false なら光の時刻だけ（見込みは全部 nil）
        let forecast: Bool
        let days: [Day]

        var id: String { key }

        /// 画面に出す名前（英語の端末で英名があれば英名）
        var shownName: String {
            if let nameEn, !nameEn.isEmpty { return L(name, nameEn) }
            return name
        }

        init(key: String, slug: String, name: String, nameEn: String? = nil, timeZone: String?,
             forecast: Bool, days: [Day]) {
            self.key = key
            self.slug = slug
            self.name = name
            self.nameEn = nameEn
            self.timeZone = timeZone
            self.forecast = forecast
            self.days = days
        }

        private enum CodingKeys: String, CodingKey {
            case key, slug, name, nameEn, timeZone, forecast, days
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // 名前の無い場所は出しようがないので、この場所だけ落とす（`Lenient`）
            name = try c.decode(String.self, forKey: .name)
            slug = (try? c.decodeIfPresent(String.self, forKey: .slug)) ?? ""
            key = (try? c.decodeIfPresent(String.self, forKey: .key)) ?? SavedSpotKey.official(slug)
            nameEn = (try? c.decodeIfPresent(String.self, forKey: .nameEn)) ?? nil
            timeZone = (try? c.decodeIfPresent(String.self, forKey: .timeZone)) ?? nil
            forecast = (try? c.decodeIfPresent(Bool.self, forKey: .forecast)) ?? false
            days = ((try? c.decodeIfPresent([Lenient<Day>].self, forKey: .days)) ?? nil)?
                .compactMap(\.value) ?? []
        }
    }

    /// 出典（Apple が表示を求めている・`weatherKit.ts` の `WEATHER_ATTRIBUTION`）
    struct Attribution: Decodable, Equatable {
        let serviceName: String
        let legalURL: URL

        init(serviceName: String, legalURL: URL) {
            self.serviceName = serviceName
            self.legalURL = legalURL
        }

        private enum CodingKeys: String, CodingKey {
            case serviceName
            case legalURL = "legalUrl"
        }

        /// 応答に無い・読めないときの出典。**出典を出さずに天気を出さない**（Apple の求め）ので、
        /// サーバーと同じ値を手元にも持つ
        static let appleWeather = Attribution(
            serviceName: "Apple Weather",
            legalURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!
        )
    }

    let places: [Place]
    /// 画面に出す注記（サーバーの `LIGHT_NOTE`）。無ければ画面が板の文言を出す
    let note: String?
    let attribution: Attribution

    init(places: [Place], note: String? = nil, attribution: Attribution = .appleWeather) {
        self.places = places
        self.note = note
        self.attribution = attribution
    }

    private enum CodingKeys: String, CodingKey { case places, note, attribution }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        places = try c.decode([Lenient<Place>].self, forKey: .places).compactMap(\.value)
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? nil
        // 出典の URL は https だけ受ける（読めなければ手元の値）
        let read = (try? c.decodeIfPresent(Attribution.self, forKey: .attribution)) ?? nil
        if let read, read.legalURL.scheme == "https", !read.serviceName.isEmpty {
            attribution = read
        } else {
            attribution = .appleWeather
        }
    }
}
