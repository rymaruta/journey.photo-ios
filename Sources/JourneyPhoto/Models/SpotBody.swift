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
    /// 公式サイト。**https のものだけ**（写真の出典と違い http を https に上げない——
    /// 上げた先が開けないサイトがある。台帳の公開済み364件は全部 https）
    let officialWebsite: URL?
    let check: Check
    /// 作例（Wikimedia Commons・2026-10-03〜）。出してよい1枚だけ・最大6枚（`SpotSample.list`）。
    /// **後から足された項目**なので、無い本文は空。壊れていても本文ごとは落とさない
    let samples: [SpotSample]

    /// 本文の節が1つでもあるか（無ければ節ごと出さない）
    var hasContent: Bool {
        description != nil || !highlights.isEmpty || !seasonalGuide.isEmpty
            || !timeOfDayGuide.isEmpty || !compositionTips.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case slug, description, highlights, seasonalGuide, timeOfDayGuide, compositionTips,
             officialWebsiteUrl, check, samples
    }

    private enum CheckKeys: String, CodingKey { case kind, verifiedAt, checkedAt, sources }
    /// 出典の生の形（壊れた1本は `Lenient` が落とす）
    private struct RawSource: Decodable { let url: String; let title: String }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decode(String.self, forKey: .slug)
        let text = (try? c.decode(String.self, forKey: .description))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        description = (text?.isEmpty ?? true) ? nil : text
        highlights = Self.strings(c, .highlights)
        compositionTips = Self.strings(c, .compositionTips)
        // **知らない季節・時間帯はここで落とす**（画面は呼び名の無い値を出せない。
        // 残すと `hasContent` が真なのに何も描かれない）
        seasonalGuide = ((try? c.decode([Lenient<Seasonal>].self, forKey: .seasonalGuide)) ?? [])
            .compactMap(\.value)
            .filter { SpotBodyText.seasonOrder.contains($0.season) && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        timeOfDayGuide = ((try? c.decode([Lenient<TimeOfDay>].self, forKey: .timeOfDayGuide)) ?? [])
            .compactMap(\.value)
            .filter { SpotBodyText.timeOrder.contains($0.time) && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        officialWebsite = (try? c.decode(String.self, forKey: .officialWebsiteUrl)).flatMap(Self.httpsURL)
        samples = SpotSample.list(((try? c.decode([Lenient<SpotSample.Raw>].self, forKey: .samples)) ?? []).compactMap(\.value))

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
            let sources = ((try? k.decode([Lenient<RawSource>].self, forKey: .sources)) ?? [])
                .compactMap(\.value)
                .compactMap { raw -> Source? in
                    let title = raw.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let url = Self.httpsURL(raw.url), !title.isEmpty else { return nil }
                    return Source(url: url, title: title)
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
        ((try? c.decode([Lenient<String>].self, forKey: key)) ?? [])
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
