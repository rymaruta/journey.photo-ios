import Foundation

/// バッジ（メダル）の台帳。名前・段・絵の名前・金属・棚の並び（第1段階・2026-10-09）。
///
/// デザインの正はアーティファクト「journey.photo iOS」の 06 バッジ・Pro（板 61〜71）。
/// 絵は `Assets.xcassets` の `medal-<key>-<tier>`（大・棚と手に取って回す画面）と
/// `medal-<key>-<tier>-s`（小・名前の横・選ぶ画面・お知らせ）。初期ユーザーは段が無い。
///
/// **知らない鍵は出さない。** サーバーが先に新しいバッジを足しても、絵の無いものを
/// 空の丸で出すより、出さない方がまし（お知らせの種類と同じ判断）。
///
/// ## Pro 限定（第2段階・2026-10-09）
///
/// - `supporter`（サポーター章・羅針盤）・`supporterYear`（続けた年のメダル。段 1/2/3 ＝ 1年目/2年目/3年目）
/// - 季節の章は**年ごとの鍵** `pro<Spring|Summer|Autumn|Winter><西暦>`（例 `proAutumn2026`）。
///   サーバーの `badgeKeys.ts` と同じ形。**絵のある年だけ**出す（`ProChapters.artYears`）
/// - 縁と裏は真鍮。名前の横では円の 91%（季節の章）
/// - 機能の章（暁・構図・圏外）は第3段階で配る。鍵はまだ無いので、PRO 限定の段の「まだ」の絵だけ
///
/// 画面に依らない計算だけを持つ（Linux の模型でもテストできるように）。
enum BadgeCatalog {

    /// バッジの種類1つ
    struct Kind: Equatable {
        let key: String
        let ja: String
        let en: String
        /// いちばん上の段（最初の一枚・初期ユーザーは 1）
        let maxTier: Int
        /// 棚の「あと◯で次」の単位（無ければ数だけ）
        let unitJa: String
        let unitEn: String
        /// 後から取れない（初期ユーザー）。**持っていない人の棚には出さない**
        let closed: Bool

        var name: String { L(ja, en) }
    }

    /// 棚・選ぶ画面の並び（板 Shelf の順に寄せた）
    static let kinds: [Kind] = [
        Kind(key: "earlyUser", ja: "初期ユーザー", en: "Early user", maxTier: 1, unitJa: "", unitEn: "", closed: true),
        Kind(key: "first", ja: "最初の一枚", en: "First photo", maxTier: 1, unitJa: "枚", unitEn: "photo", closed: false),
        Kind(key: "prefectures", ja: "都道府県", en: "Prefectures", maxTier: 3, unitJa: "", unitEn: "", closed: false),
        Kind(key: "countries", ja: "国・地域", en: "Countries", maxTier: 3, unitJa: "", unitEn: "", closed: false),
        Kind(key: "seasons", ja: "四季", en: "Four seasons", maxTier: 3, unitJa: "年", unitEn: "year", closed: false),
        Kind(key: "morning", ja: "朝の光", en: "Morning light", maxTier: 3, unitJa: "枚", unitEn: "photo", closed: false),
        Kind(key: "night", ja: "夜の光", en: "Night light", maxTier: 3, unitJa: "枚", unitEn: "photo", closed: false),
        Kind(key: "books", ja: "旅の一冊", en: "Trip books", maxTier: 3, unitJa: "冊", unitEn: "book", closed: false),
        Kind(key: "wish", ja: "行けた場所", en: "Wishes visited", maxTier: 3, unitJa: "", unitEn: "", closed: false),
        // Pro 限定（第2段階）。**後から取れない扱い**（持っていない人の棚には出さない）
        Kind(key: "supporter", ja: "サポーター", en: "Supporter", maxTier: 1, unitJa: "", unitEn: "", closed: true),
        Kind(key: "supporterYear", ja: "続けた年", en: "Years of support", maxTier: 3, unitJa: "", unitEn: "", closed: true),
    ]

    /// Pro 限定の決まった鍵
    static let proKeys: Set<String> = ["supporter", "supporterYear"]

    static func kind(_ key: String) -> Kind? { kinds.first { $0.key == key } }

    /// 絵のあるバッジか（決まった鍵か、絵のある年の季節の章）
    static func isKnown(_ key: String) -> Bool {
        if kind(key) != nil { return true }
        guard let chapter = ProChapters.parse(key) else { return false }
        return ProChapters.hasArt(chapter)
    }

    /// Pro 限定のバッジか（縁と裏が真鍮・名前の横の画面の「PRO 限定」）
    static func isPro(_ key: String) -> Bool { proKeys.contains(key) || ProChapters.parse(key) != nil }

    /// 画面に出す名前（「朝の光」「秋 2026」）。知らない鍵は鍵のまま（出す前に `isKnown` で落とす）
    static func name(_ key: String) -> String {
        if let chapter = ProChapters.parse(key) { return chapter.shortName }
        return kind(key)?.name ?? key
    }

    /// 段の呼び名（1 銅・2 銀・3 白金）
    static func tierWord(_ tier: Int) -> String {
        switch tier {
        case ...1: return L("銅", "Bronze")
        case 2: return L("銀", "Silver")
        default: return L("白金", "Platinum")
        }
    }

    /// その鍵の段の呼び名。続けた年のメダルは「1年目」、ほかは金属
    static func tierWord(_ key: String, _ tier: Int) -> String {
        key == "supporterYear" ? SupporterText.yearLabel(clampedTier(key, tier)) : tierWord(clampedTier(key, tier))
    }

    /// 段を台帳の範囲に収める（サーバーが上の段を先に足しても絵の無い名前を引かない）
    static func clampedTier(_ key: String, _ tier: Int) -> Int {
        min(max(1, tier), kind(key)?.maxTier ?? 1)
    }

    /// 段のあるバッジか（読み上げ・お知らせに「· 銅」を付けるか）
    static func hasTiers(_ key: String) -> Bool { (kind(key)?.maxTier ?? 1) > 1 }

    /// 読み上げ・お知らせに使う名前（「都道府県 · 銀」「続けた年 · 1年目」「秋の章 2026」）。段の無いものは名前だけ
    static func fullName(_ key: String, tier: Int) -> String {
        if let chapter = ProChapters.parse(key) { return chapter.fullName }
        return hasTiers(key) ? "\(name(key)) · \(tierWord(key, tier))" : name(key)
    }

    /// 名前の横のバッジの読み上げ（「名前の横のバッジ: 都道府県 · 銀」）
    static func nameSideLabel(_ badge: EarnedBadge) -> String {
        let name = fullName(badge.key, tier: badge.tier)
        return L("名前の横のバッジ: \(name)", "Badge: \(name)")
    }

    // MARK: - 絵の名前

    private static func baseImage(_ key: String, _ tier: Int) -> String {
        if let chapter = ProChapters.parse(key) { return chapter.imageBase }
        switch key {
        case "earlyUser": return "medal-earlyUser"
        case "supporter": return "medal-supporter"
        case "supporterYear": return SupporterText.yearImage(clampedTier(key, tier))
        default: return "medal-\(key)-\(clampedTier(key, tier))"
        }
    }

    /// 小（192px・Pro の章は 128px）。**名前の横・選ぶ画面の格子・棚の「名前の横に飾る」・お知らせには
    /// 使わない**（2026-10-09 判断: 大きい絵を `RasterBadgeArt` で表示の画素ちょうどに縮める。`-s` は
    /// 引き伸ばしでぼやけ、図柄も簡略版だった）。
    /// 続けた年のメダルは小さい絵を持たないので大きい絵を縮めて使う
    static func smallImage(_ key: String, tier: Int) -> String {
        key == "supporterYear" ? baseImage(key, tier) : baseImage(key, tier) + "-s"
    }

    /// 大（780px・Pro の章 600px・サポーター 520px）。棚・手に取って回す画面の表
    static func largeImage(_ key: String, tier: Int) -> String { baseImage(key, tier) }

    /// 名前の横（`NameBadgeImage`）の絵。**大きい絵をそのまま縮める**（案 C・2026-10-09 owner
    /// 「そのままがいい」）。文字の帯を省いた小さい絵（`-s`）は使わない
    static func nameSideImage(_ key: String, tier: Int) -> String { largeImage(key, tier: tier) }

    // MARK: - 金属（手に取って回す画面の裏と縁）

    enum Metal: String, CaseIterable {
        case bronze, silver, platinum, brass

        var reverseImage: String { "reverse-\(rawValue)" }
        var edgeImage: String { "edge-\(rawValue)" }
    }

    /// 段ごとの金属。初期ユーザー・サポーター・続けた年・Pro の章は真鍮
    static func metal(_ key: String, tier: Int) -> Metal {
        if key == "earlyUser" || isPro(key) { return .brass }
        switch clampedTier(key, tier) {
        case 1: return .bronze
        case 2: return .silver
        default: return .platinum
        }
    }

    /// 表の絵のうち、硬貨の円が占める割合（直径）。素材の README の値。
    /// 無料のメダル・サポーター・続けた年は画像の 98.4%、初期ユーザーは後光の余白があるので 71.5%、
    /// Pro の章は 91%。
    ///
    /// **大きい絵（名前の横・棚・手に取って回す画面が使う絵）を測って確かめた**（2026-10-09）:
    /// 円の縁（不透明が切れるところ）は 無料のメダル 98.2%・サポーター／続けた年 98.1%・
    /// Pro の章 91.2%・初期ユーザー 71.0%（その外は後光で、絵の 94% まで薄く広がる）。
    /// 小さい絵（`-s`）も同じ割合で描かれているので、名前の横を大きい絵に替えても値は変わらない
    static func discRatio(_ key: String) -> Double {
        if key == "earlyUser" { return 0.715 }
        if ProChapters.parse(key) != nil { return ProChapters.discRatio }
        return 0.984
    }

    // MARK: - 棚

    /// 棚の1枚
    struct ShelfItem: Equatable, Identifiable {
        let key: String
        /// 絵に使う段（持っていなければ 1 の絵を暗くして出す）
        let tier: Int
        let earned: EarnedBadge?
        /// 「あと◯で次」（人の棚・進み具合の無いときは nil）
        let progress: String?

        var id: String { key }
        var isEarned: Bool { earned != nil }
    }

    /// 棚の並び。
    ///
    /// - 自分の棚（`progress` あり）: 持っているもの＋まだのもの（暗く）。
    ///   後から取れないもの（初期ユーザー）は持っているときだけ
    /// - 人の棚（`progress` が nil）: **持っているものだけ**。進み具合は出さない
    static func shelf(badges: BadgeSet, progress: [String: BadgeProgress]?) -> [ShelfItem] {
        let fixed: [ShelfItem] = kinds.compactMap { kind in
            let earned = badges[kind.key]
            guard earned != nil || (progress != nil && !kind.closed) else { return nil }
            let tier = earned.map { clampedTier(kind.key, $0.tier) } ?? 1
            let text = progress.flatMap { map in
                progressText(kind.key, progress: map[kind.key], earned: earned != nil)
            }
            return ShelfItem(key: kind.key, tier: tier, earned: earned, progress: text)
        }
        // 季節の章は持っているものだけ（後から取れない）。年 → 春夏秋冬の順
        let chapters = ProChapters.owned(badges).map {
            ShelfItem(key: $0.key, tier: 1, earned: $0, progress: nil)
        }
        return fixed + chapters
    }

    /// 棚の数（「7 / 9」）。持っている数と、その人の棚に並ぶ数
    static func shelfCount(_ items: [ShelfItem]) -> (earned: Int, total: Int) {
        (items.filter(\.isEarned).count, items.count)
    }

    /// 「あと17で次」「あと25枚で次」「達成」「あと5枚」（板 Shelf）。
    ///
    /// - 持っていて上の段が無い → 達成
    /// - 持っていて次がある → あと◯で次
    /// - まだ持っていない → あと◯（最初の段まで）
    /// - 進み具合が無い（古いサーバー） → 持っていれば何も出さない・まだなら nil
    static func progressText(_ key: String, progress: BadgeProgress?, earned: Bool) -> String? {
        guard let kind = kind(key) else { return nil }
        if earned, progress?.next == nil || (progress?.tier ?? 0) >= kind.maxTier {
            // 進み具合が無くても、上の段の無いもの（最初の一枚・初期ユーザー）は達成と言える
            if progress == nil && kind.maxTier > 1 { return nil }
            return L("達成", "Complete")
        }
        guard let progress, let next = progress.next else { return nil }
        let left = max(1, next - progress.count)
        let unitEn = kind.unitEn.isEmpty ? "" : " " + (left == 1 ? kind.unitEn : kind.unitEn + "s")
        if earned {
            return L("あと\(left)\(kind.unitJa)で次", "\(left) more\(unitEn) to next")
        }
        return L("あと\(left)\(kind.unitJa)", "\(left) more\(unitEn) to earn")
    }

    /// 名前の横の画面に並べる、持っているバッジ（台帳の順・知らない鍵は落とす）
    static func owned(_ badges: BadgeSet) -> [EarnedBadge] {
        kinds.compactMap { badges[$0.key] } + ProChapters.owned(badges)
    }

    // MARK: - 日付（裏に刻む）

    /// 受け取った日（「2026.10.09」）。読めなければ nil
    static func awardDate(_ iso: String?, timeZone: TimeZone = .current) -> String? {
        guard let iso, let date = parse(iso) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { return nil }
        return String(format: "%04d.%02d.%02d", y, m, d)
    }

    private static func parse(_ iso: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: iso) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: iso) { return date }
        // 日付だけ（「2026-10-09」）
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        return day.date(from: iso)
    }
}

/// 名前の横のバッジの大きさ（板 BadgePicker・MyPage）。
///
/// **バッジの円の部分を、公式の封印（`VerifiedBadge`）と同じ見た目の大きさにそろえる**
/// ——明朝 26 の名前で円が 22pt。名前の字の大きさに比例させる。
/// 絵（大きいメダルの絵を縮めたもの・`BadgeCatalog.nameSideImage`）には円の外に余白があるので、
/// 絵はそのぶん大きく置き、はみ出した分は負の余白で打ち消して**行の高さを変えない**
/// （初期ユーザーは後光ごと描くので、後光の分だけ大きい）
enum BadgeFit {
    /// 基準: 明朝 26 の名前のとき、円は 22pt
    static let referenceNameSize: Double = 26
    static let referenceCircle: Double = 22

    /// 円の直径
    static func circle(nameSize: Double) -> Double {
        nameSize * referenceCircle / referenceNameSize
    }

    /// 絵の一辺（無料のメダル 22.4・初期ユーザー 30.8 @ 名前 26）。0.1pt に丸める
    static func imageSide(_ key: String, nameSize: Double) -> Double {
        ((circle(nameSize: nameSize) / BadgeCatalog.discRatio(key)) * 10).rounded() / 10
    }

    /// 上下左右にはみ出す量（負の余白に使う。初期ユーザー 4.4 @ 名前 26）
    static func overhang(_ key: String, nameSize: Double) -> Double {
        ((imageSide(key, nameSize: nameSize) - circle(nameSize: nameSize)) / 2 * 10).rounded() / 10
    }
}

/// Pro マークの大きさ（板 ProMarkOptions）。
///
/// **公式の封印（`VerifiedBadge`）と同じ見た目の大きさ。** 明朝の名前では字の 0.835 倍
/// （26 → 21.7）、本文の書体（写真の詳細の作者・13）では板の 11.5 に合わせて 0.885 倍。
/// 15pt を切ったら線を太らせた小さい版にする（細い羽根の線は小さいと潰れる）
enum ProMarkFit {
    static let minchoRatio: Double = 0.835
    static let systemRatio: Double = 0.885
    /// これより小さいときは小さい版
    static let smallBelow: Double = 15

    /// 印の高さ（絞り羽根は一辺）
    static func side(nameSize: Double, mincho: Bool) -> Double {
        ((nameSize * (mincho ? minchoRatio : systemRatio)) * 10).rounded() / 10
    }

    static func isSmall(side: Double) -> Bool { side < smallBelow }

    /// 印の幅。札（PRO）は横長（大 42:24・小 36:24）
    static func width(side: Double, style: ProMarkStyle) -> Double {
        switch style {
        case .iris: return side
        case .plate: return side * (isSmall(side: side) ? 36 : 42) / 24
        }
    }
}
