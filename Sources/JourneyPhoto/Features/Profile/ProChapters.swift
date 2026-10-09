import Foundation

/// Pro 限定の章（板 ProBadges・BadgePicker の「PRO 限定」・第2段階・2026-10-09）。
///
/// ## 季節の章
///
/// 鍵は年ごと: `pro<Spring|Summer|Autumn|Winter><西暦4桁>`（例 `proAutumn2026`）。サーバーの
/// `api-user/src/badgeKeys.ts`（`parseProSeasonKey`）と同じ読み方。**冬は12月の年**
/// （`proWinter2026` は 2026年12月〜2027年2月）。月は日本時間で見る。
///
/// **絵は年ごと**（表に「AUTUMN · 2026」と刻んである）。いま絵があるのは板と同じ4枚
/// （春 2027・夏 2027・秋 2026・冬 2026）だけで、**絵の無い年の章は出さない**
/// （`BadgeCatalog` の「知らない鍵は出さない」と同じ判断）。新しい年の絵が届いたら
/// `artYears` と絵（`medal-pro-<季節>-<年>`）を足す。
///
/// ## 機能の章（暁・構図・圏外）
///
/// 第3段階（機能ができてから）配る。鍵はまだ無い——名前の横の画面の「PRO 限定」に
/// 「まだ持っていない」絵として並べるだけ（板 BadgePicker のとおり）。
enum ProChapters {

    /// 名前の横で円が占める割合（素材の README: 91%）
    static let discRatio: Double = 0.91

    enum Season: String, CaseIterable {
        case spring, summer, autumn, winter

        /// 鍵の中の綴り（`Spring`）
        var keyName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

        var ja: String {
            switch self {
            case .spring: return "春"
            case .summer: return "夏"
            case .autumn: return "秋"
            case .winter: return "冬"
            }
        }

        var en: String { keyName }

        var label: String { L(ja, en) }
    }

    /// 季節の章1つ
    struct Chapter: Equatable {
        let season: Season
        let year: Int

        var key: String { "pro\(season.keyName)\(year)" }
        /// 名前の横の画面の札（板: 「秋 2026」）
        var shortName: String { "\(season.label) \(year)" }
        /// 読み上げ・お知らせ（「秋の章 2026」）
        var fullName: String { L("\(season.ja)の章 \(year)", "\(season.en) chapter \(year)") }
        /// 絵の名前（`medal-pro-autumn-2026`。小さい絵は `-s`）
        var imageBase: String { "medal-pro-\(season.rawValue)-\(year)" }
    }

    /// 絵のある年（季節ごと）
    static let artYears: [Season: Set<Int>] = [
        .spring: [2027], .summer: [2027], .autumn: [2026], .winter: [2026],
    ]

    static func hasArt(_ chapter: Chapter) -> Bool {
        artYears[chapter.season]?.contains(chapter.year) ?? false
    }

    /// 鍵を読む。違えば nil。年は 2026〜2999（サーバーと同じ）
    static func parse(_ key: String) -> Chapter? {
        guard key.hasPrefix("pro") else { return nil }
        let body = key.dropFirst(3)
        for season in Season.allCases where body.hasPrefix(season.keyName) {
            let digits = body.dropFirst(season.keyName.count)
            guard digits.count == 4, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let year = Int(digits), (2026...2999).contains(year) else { return nil }
            return Chapter(season: season, year: year)
        }
        return nil
    }

    /// 持っている季節の章（絵のあるものだけ）。年 → 春夏秋冬の順（冬は12月の年なので、これが時間の順）
    static func owned(_ badges: BadgeSet) -> [EarnedBadge] {
        badges.byKey.values
            .compactMap { badge -> (Chapter, EarnedBadge)? in
                guard let chapter = parse(badge.key), hasArt(chapter) else { return nil }
                return (chapter, EarnedBadge(key: badge.key, tier: 1, at: badge.at))
            }
            .sorted { a, b in
                a.0.year != b.0.year ? a.0.year < b.0.year
                    : Season.allCases.firstIndex(of: a.0.season)! < Season.allCases.firstIndex(of: b.0.season)!
            }
            .map(\.1)
    }

    /// 日本時間
    static let japan = TimeZone(identifier: "Asia/Tokyo") ?? TimeZone(secondsFromGMT: 9 * 3600)!

    /// これから届く（いまの季節を含む）4つの季節の章。並びは春夏秋冬（板 BadgePicker:
    /// 2026年10月なら 春 2027・夏 2027・秋 2026・冬 2026）
    static func upcoming(now: Date = Date(), timeZone: TimeZone = japan) -> [Chapter] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month], from: now)
        let y = c.year ?? 2026
        let m = c.month ?? 1
        return Season.allCases.map { season in
            let year: Int
            switch season {
            case .spring: year = m <= 5 ? y : y + 1
            case .summer: year = m <= 8 ? y : y + 1
            case .autumn: year = m <= 11 ? y : y + 1
            // 冬は12月の年。1〜2月はいまの冬（前の年の鍵）
            case .winter: year = m <= 2 ? y - 1 : y
            }
            return Chapter(season: season, year: year)
        }
    }

    /// 機能の章（第3段階で配る）。名前と絵だけ
    struct FeatureChapter: Equatable {
        let id: String
        let ja: String
        let en: String
        var name: String { L(ja, en) }
        var smallImage: String { "medal-pro-\(id)-s" }
    }

    static let featureChapters: [FeatureChapter] = [
        FeatureChapter(id: "dawn", ja: "暁", en: "Dawn"),
        FeatureChapter(id: "compose", ja: "構図", en: "Composition"),
        FeatureChapter(id: "summit", ja: "圏外", en: "Off-grid"),
    ]

    /// 名前の横の画面の「PRO 限定」に並べる1つ
    struct LockedItem: Equatable, Identifiable {
        let id: String
        let name: String
        let smallImage: String
    }

    /// 「PRO 限定」の並び（板 BadgePicker: サポーター → 季節の章4つ → 機能の章3つ）。
    /// **持っているものは外す**（それは「持っているバッジ」に並ぶ）。絵の無い季節の章は出さない
    static func lockedItems(owned badges: BadgeSet, now: Date = Date()) -> [LockedItem] {
        var items: [LockedItem] = []
        if badges["supporter"] == nil {
            items.append(LockedItem(id: "supporter", name: BadgeCatalog.name("supporter"),
                                    smallImage: BadgeCatalog.smallImage("supporter", tier: 1)))
        }
        for chapter in upcoming(now: now) where hasArt(chapter) && badges[chapter.key] == nil {
            items.append(LockedItem(id: chapter.key, name: chapter.shortName, smallImage: chapter.imageBase + "-s"))
        }
        for feature in featureChapters {
            items.append(LockedItem(id: feature.id, name: feature.name, smallImage: feature.smallImage))
        }
        return items
    }
}
