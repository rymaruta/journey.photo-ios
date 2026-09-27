import Foundation

/// 撮影スポットの**本文**（`/app/data/spots/<slug>.json`・Web の `lib/data/spotBody.ts`）。
///
/// 索引（`OfficialSpot`）には載らない本文・見どころ・季節・時間帯・構図・公式サイトと、
/// **確かめた印**（`check`）を持つ。Web のスポットページと同じ出し分けで、
/// 人が確かめた行は「情報の最終確認（運営）」、AI 照合の行は「出典: …（AI 照合）」と出す。
///
/// 🔴 **印の無い本文は読まない**（`check` が読めなければ全体を捨てる）。
/// 出典の無い事実を画面に置かない。項目の中の壊れた1つは、その1つだけ落とす。
struct SpotBody: Decodable, Equatable {

    struct Seasonal: Decodable, Equatable {
        let season: String
        let text: String
    }

    struct TimeOfDay: Decodable, Equatable {
        let time: String
        let text: String
    }

    struct Source: Equatable {
        let url: URL
        let title: String
    }

    enum Check: Equatable {
        /// 人が確かめた日（`YYYY-MM-DD`）
        case human(verifiedAt: String)
        /// AI が出典と照らした日と、その出典（https・題つきのものだけ・1本以上）
        case ai(checkedAt: String, sources: [Source])
    }

    let slug: String
    let description: String?
    let highlights: [String]
    let seasonalGuide: [Seasonal]
    let timeOfDayGuide: [TimeOfDay]
    let compositionTips: [String]
    /// 公式サイト。**https のものだけ**
    let officialWebsite: URL?
    let check: Check

    /// 本文の節が1つでもあるか（無ければ節ごと出さない）
    var hasContent: Bool {
        description != nil || !highlights.isEmpty || !seasonalGuide.isEmpty
            || !timeOfDayGuide.isEmpty || !compositionTips.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case slug, description, highlights, seasonalGuide, timeOfDayGuide, compositionTips,
             officialWebsiteUrl, check
    }

    private enum CheckKeys: String, CodingKey { case kind, verifiedAt, checkedAt, sources }
    private enum SourceKeys: String, CodingKey { case url, title }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decode(String.self, forKey: .slug)
        let text = (try? c.decode(String.self, forKey: .description))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        description = (text?.isEmpty ?? true) ? nil : text
        highlights = Self.strings(c, .highlights)
        compositionTips = Self.strings(c, .compositionTips)
        seasonalGuide = ((try? c.decode([LenientItem<Seasonal>].self, forKey: .seasonalGuide)) ?? [])
            .compactMap(\.value).filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        timeOfDayGuide = ((try? c.decode([LenientItem<TimeOfDay>].self, forKey: .timeOfDayGuide)) ?? [])
            .compactMap(\.value).filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        officialWebsite = (try? c.decode(String.self, forKey: .officialWebsiteUrl)).flatMap(Self.httpsURL)

        // **印は必ず要る。** 読めなければ投げる（本文ごと出さない）
        let k = try c.nestedContainer(keyedBy: CheckKeys.self, forKey: .check)
        switch try k.decode(String.self, forKey: .kind) {
        case "human":
            let day = String(try k.decode(String.self, forKey: .verifiedAt).prefix(10))
            guard TripPlanText.date(fromYMD: day) != nil else {
                throw DecodingError.dataCorruptedError(forKey: .verifiedAt, in: k, debugDescription: "確認日が読めない")
            }
            check = .human(verifiedAt: day)
        case "ai":
            let day = String(try k.decode(String.self, forKey: .checkedAt).prefix(10))
            var list = try k.nestedUnkeyedContainer(forKey: .sources)
            var sources: [Source] = []
            while !list.isAtEnd {
                guard let s = try? list.nestedContainer(keyedBy: SourceKeys.self) else {
                    _ = try? list.decode(Ignored.self)
                    continue
                }
                let title = ((try? s.decode(String.self, forKey: .title)) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let raw = try? s.decode(String.self, forKey: .url), let url = Self.httpsURL(raw), !title.isEmpty {
                    sources.append(Source(url: url, title: title))
                }
            }
            guard TripPlanText.date(fromYMD: day) != nil, !sources.isEmpty else {
                throw DecodingError.dataCorruptedError(forKey: .sources, in: k, debugDescription: "出典か照合日が無い")
            }
            check = .ai(checkedAt: day, sources: sources)
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: k, debugDescription: "知らない印")
        }
    }

    private static func strings(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [String] {
        ((try? c.decode([LenientItem<String>].self, forKey: key)) ?? [])
            .compactMap(\.value)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func httpsURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }
}

/// 読めない要素を `nil` にして、配列の残りを生かす包み
private struct LenientItem<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// 読み飛ばすための空の型（配列の中の壊れた要素を1つ進める）
private struct Ignored: Decodable {
    init(from decoder: Decoder) throws {}
}
