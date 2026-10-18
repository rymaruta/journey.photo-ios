import Foundation

/// 「新しくなったこと」の中身と、出すかどうかの決まり（2026-10-04）。
///
/// 中身は `Resources/WhatsNew.json`（版ごとに配列）。**次の版からは JSON に1つ足すだけで出る**
/// ——画面もこの型も触らない。
///
/// 出す決まり（`WhatsNew.pending`）:
/// - **新しくインストールした人には出さない。** 前の版を開いたことがある人だけ
/// - 見た版（`MARKETING_VERSION`）を UserDefaults に覚え、版が変わった最初の起動で1回だけ
/// - 2026-10-04 判断: この仕組みより前の版の人は「見た版」を持っていない。そこで
///   **規約に同意済みか**（`legal.consent.version`・起動した時点の値）で「前に開いたことがある」と見る。
///   新しくインストールした人はこの起動で同意するので、起動した時点では 0 のまま
enum WhatsNew {

    /// 押したときに行ける先。下の札（`TabRouter`）で行ける所だけ。無い項目は説明だけ
    enum Destination: String, Equatable {
        case home, search, map, mypage
    }

    struct Localized: Decodable, Equatable {
        let ja: String
        let en: String
        var localized: String { L(ja, en) }
    }

    struct Item: Decodable, Equatable {
        let symbol: String
        let title: Localized
        let detail: Localized
        /// 知らない値は nil（説明だけ）。古いアプリが新しい JSON を読んでも落ちない
        let destination: Destination?

        private enum CodingKeys: String, CodingKey { case symbol, title, detail, destination }

        init(symbol: String, title: Localized, detail: Localized, destination: Destination?) {
            self.symbol = symbol
            self.title = title
            self.detail = detail
            self.destination = destination
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            symbol = try c.decode(String.self, forKey: .symbol)
            title = try c.decode(Localized.self, forKey: .title)
            detail = try c.decode(Localized.self, forKey: .detail)
            destination = (try? c.decodeIfPresent(String.self, forKey: .destination))
                .flatMap { $0 }.flatMap(Destination.init(rawValue:))
        }
    }

    /// 版を出した日（"YYYY-MM-DD"）。時刻と時差を持たない暦の日だけ——日付をまたいで1日ずれないように
    struct Day: Equatable {
        let year: Int
        let month: Int
        let day: Int

        /// "2026-10-04" だけを読む。形が違う・暦に無い日（2026-02-30）は nil
        init?(_ text: String) {
            let parts = text.split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
                  parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
                  let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
            self.init(year: y, month: m, day: d)
        }

        /// 暦に無い日（月 0・13、2026-02-30）は nil。**作る口はどれもここを通る**ので、
        /// `dayText` の月の表を範囲の外で引かない
        init?(year: Int, month: Int, day: Int) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
            guard (1...12).contains(month), (1...31).contains(day),
                  DateComponents(year: year, month: month, day: day).isValidDate(in: calendar) else { return nil }
            self.year = year
            self.month = month
            self.day = day
        }
    }

    struct Release: Decodable, Equatable {
        let version: String
        let items: [Item]
        /// 任意。無い・壊れた値は nil（見出しは版だけになる）。古い JSON もそのまま読める
        let date: Day?

        private enum CodingKeys: String, CodingKey { case version, items, date }

        init(version: String, items: [Item], date: Day? = nil) {
            self.version = version
            self.items = items
            self.date = date
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decode(String.self, forKey: .version)
            items = try c.decode([Item].self, forKey: .items)
            // 文字でない値（数・null）も、形の違う文字も、版ごと捨てずに日付だけ無視する
            date = (try? c.decodeIfPresent(String.self, forKey: .date)).flatMap { $0 }.flatMap(Day.init)
        }
    }

    /// 画面の出し方。**起動時のシートは `.launch`**（新しい分を平らに並べる・2026-10-04 から同じ見た目）、
    /// **設定から開いたときは `.history`**（最新の版を上に、その下に「これまでのお知らせ」と版ごとの区切り）
    enum Mode: Equatable {
        case launch, history
    }

    /// 画面の1かたまり。`heading` があれば区切りの見出し（「1.0.82 · 10月10日」）を上に出す。
    /// `spokenHeading` はその読み上げ（「バージョン 1.0.82、10月10日」）
    struct Section: Equatable {
        let id: String
        let heading: String?
        var spokenHeading: String? = nil
        let items: [Item]
    }

    /// 並べ方の決まり（画面は描くだけ）。
    /// - `.launch`: 渡された版の項目を全部、見出し無しの1かたまりに（今までどおり）
    /// - `.history`: 1つ目（いちばん新しい版）は見出し無しで上に。2つ目からは版ごとに見出し付き
    static func sections(_ releases: [Release], mode: Mode, now: Date = Date()) -> [Section] {
        switch mode {
        case .launch:
            let items = releases.flatMap(\.items)
            return items.isEmpty ? [] : [Section(id: "all", heading: nil, items: items)]
        case .history:
            return releases.enumerated().map { index, release in
                Section(id: release.version,
                        heading: index == 0 ? nil : heading(for: release, now: now),
                        spokenHeading: index == 0 ? nil : spokenHeading(for: release, now: now),
                        items: release.items)
            }
        }
    }

    /// 版の区切りの見出し: 「1.0.82 · 10月10日」（英語 "1.0.82 · Oct 10"）。日付が無ければ版だけ。
    /// 今年でない日は年も付ける（「2025年12月1日」・"Dec 1, 2025"）——履歴が年をまたいでも読み違えない
    static func heading(for release: Release, now: Date = Date(),
                        english: Bool = Locale.preferredAppLanguage == "en") -> String {
        guard let date = release.date else { return release.version }
        return "\(release.version)\(PhotoMetaLine.separator)\(dayText(date, now: now, english: english))"
    }

    /// 見出しの読み上げ: 「バージョン 1.0.82、10月10日」・"Version 1.0.82, October 10"。
    /// 「·」や "Oct" を読ませない
    static func spokenHeading(for release: Release, now: Date = Date(),
                              english: Bool = Locale.preferredAppLanguage == "en") -> String {
        let version = english ? "Version \(release.version)" : "バージョン \(release.version)"
        guard let date = release.date else { return version }
        return version + (english ? ", " : "、") + dayText(date, now: now, english: english, spoken: true)
    }

    /// `english` は試験のため（画面の言語はいま日本語で固定・`Locale.preferredAppLanguage`）
    static func dayText(_ date: Day, now: Date = Date(),
                        english: Bool = Locale.preferredAppLanguage == "en", spoken: Bool = false) -> String {
        let thisYear = Calendar(identifier: .gregorian).component(.year, from: now)
        let showYear = date.year != thisYear
        let months = spoken
            ? ["January", "February", "March", "April", "May", "June", "July",
               "August", "September", "October", "November", "December"]
            : ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        // `Day` は作る時点で 1〜12 に収めてあるが、表を範囲の外で引かないよう念のため収める
        let month = months[min(max(date.month, 1), 12) - 1]
        let en = "\(month) \(date.day)" + (showYear ? ", \(date.year)" : "")
        let ja = (showYear ? "\(date.year)年" : "") + "\(date.month)月\(date.day)日"
        return english ? en : ja
    }

    private struct File: Decodable {
        let releases: [Release]
    }

    /// JSON を読む。読めなければ空（画面を出さないだけで、起動は止めない）。
    /// 新しい版が上に来るよう、版で並べ直す（JSON の並びに頼らない）
    static func decode(_ data: Data) -> [Release] {
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.releases
            .filter { !$0.items.isEmpty }
            .sorted { isNewer($0.version, than: $1.version) }
    }

    /// アプリに同梱した `WhatsNew.json`
    static func bundled(_ bundle: Bundle = .main) -> [Release] {
        guard let url = bundle.url(forResource: "WhatsNew", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return decode(data)
    }

    /// `1.0.10` は `1.0.9` より新しい（文字の比較ではなく数の比較）。足りない桁は 0
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    private static func parts(_ v: String) -> [Int] {
        v.split(separator: ".").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
    }

    /// 起動したときに出す版（新しい順）。空なら出さない。
    ///
    /// - Parameters:
    ///   - seen: 前に見た版（UserDefaults）。この仕組みより前の版・新しいインストールでは nil
    ///   - current: いまの版（`CFBundleShortVersionString` ＝ `MARKETING_VERSION`）
    ///   - usedBefore: 起動した時点で規約に同意済みだったか（＝前の版を開いたことがある）
    static func pending(releases: [Release], seen: String?, current: String, usedBefore: Bool) -> [Release] {
        guard let seen else {
            // 見た版が無い: 新しいインストールなら出さない。前の版を使っていた人には一番新しい版だけ
            // （何版前から来たか分からないので、昔の項目まで並べない）
            guard usedBefore, let latest = releases.first else { return [] }
            return [latest]
        }
        // 同じ版をもう一度開いた: 出さない（2回目は出ない）
        guard seen != current else { return [] }
        // 前に見た版より後の分だけ（飛ばして更新した人には、飛ばした版の分もまとめて）
        return releases.filter { isNewer($0.version, than: seen) }
    }
}
