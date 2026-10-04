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

    struct Release: Decodable, Equatable {
        let version: String
        let items: [Item]
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
