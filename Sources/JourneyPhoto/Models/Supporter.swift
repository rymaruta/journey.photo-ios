import Foundation

/// サポーター（Pro を申し込んだ人）の印（第2段階・2026-10-09）。プロフィールの `supporter`。
///
///     supporter: { number: 1, since: "2026-10-09T…", months: 12 }   公開
///
/// - `number`: 申し込んだ順の番号。**同じ番号は二度と出ない**（板 64）。やめても残る
/// - `since`: 最初に申し込んだ日（ISO8601）。サポーター証の MEMBER SINCE
/// - `months`: Pro だった月の数（続けた年のメダルを数える。やめても残り、再開すると続きから）
///
/// **投げない形で読む**（`Badge.swift` と同じ理由）。番号の無いものは「サポーターではない」に倒す
struct SupporterInfo: Decodable, Equatable {
    let number: Int
    let since: String?
    let months: Int

    init(number: Int, since: String?, months: Int) {
        self.number = number
        self.since = since
        self.months = months
    }

    private enum CodingKeys: String, CodingKey { case number, since, months }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let number = LenientInt.read(c, .number), number >= 1 else {
            throw DecodingError.dataCorruptedError(forKey: .number, in: c, debugDescription: "番号が無い")
        }
        self.number = number
        since = try? c.decodeIfPresent(String.self, forKey: .since)
        months = max(0, LenientInt.read(c, .months) ?? 0)
    }
}

/// `supporter` を**投げずに**読む入れ物。形が違えば nil
struct LenientSupporter: Decodable, Equatable {
    let value: SupporterInfo?

    init(_ value: SupporterInfo?) { self.value = value }

    init(from decoder: Decoder) throws {
        value = try? SupporterInfo(from: decoder)
    }
}

/// サポーター証の文字（画面に依らない・テストで見張る）
enum SupporterText {

    /// 「0001」（4桁にそろえる。1万人を超えたら桁が増える）
    static func number(_ number: Int) -> String {
        String(format: "%04d", max(0, number))
    }

    /// 「No. 0001」
    static func numberLabel(_ number: Int) -> String { "No. \(self.number(number))" }

    /// MEMBER SINCE の値（「2026.10」）。読めなければ nil
    static func since(_ iso: String?, timeZone: TimeZone = .current) -> String? {
        guard let day = BadgeCatalog.awardDate(iso, timeZone: timeZone) else { return nil }
        // 「2026.10.09」→「2026.10」
        return String(day.prefix(7))
    }

    /// サポーター証の下の注記（板 64 の文言）。**値段は App Store の字**（読めなければ板の値段）——
    /// 2026-10-09 判断: 「月 ¥500。」と書き込んでいたので、日本以外の App Store でも円で出ていた
    static func note(monthlyPrice: String?) -> String {
        let price = monthlyPrice ?? ProPlan.monthly.fallbackPrice
        return L("番号は申し込んだ順で、同じ番号は二度と出ません。やめても番号とメダルは残り、再開すると続きから数えます。月 \(price)。",
                 "Numbers are given in the order people joined and are never reused. If you stop, your number and medals stay; when you come back, the count continues. \(price) a month.")
    }

    /// 「12 か月目」の数。0 か月（申し込んだ直後でサーバーがまだ数えていない）は 1 か月目
    static func monthOrdinal(_ months: Int) -> Int { max(1, months) }

    /// 続けた年のメダル（1年目・2年目・3年目）のうち、届いている数。
    ///
    /// **12・24・36 か月で1つずつ**（サーバーの `proBadges.ts` の `supporterYearTier` と同じ線。
    /// 板 64: 12か月目で1年目が灯り、2年目・3年目は暗い）。11か月目までは 0
    static let yearThresholds = [12, 24, 36]

    static func yearsReached(months: Int) -> Int {
        yearThresholds.filter { months >= $0 }.count
    }

    /// サーバーが付けた `supporterYear` の段も見る（段は下がらないので、月の数より先に進んでいることがある）
    static func yearsReached(months: Int, badgeTier: Int?) -> Int {
        min(yearThresholds.count, max(yearsReached(months: months), badgeTier ?? 0))
    }

    /// 年のメダルの名前（「1年目」）
    static func yearLabel(_ year: Int) -> String {
        L("\(year)年目", year == 1 ? "Year 1" : "Year \(year)")
    }

    /// 年のメダルの絵（素材 `pro/medal-year-<n>.png`）
    static func yearImage(_ year: Int) -> String { "medal-year-\(min(3, max(1, year)))" }
}
