import Foundation

/// **みんなの「行きたい」**（2026-11-11・撮影スポットを払うの②・サーバーは Web の `api-user/src/spotWants.ts`）。
///
/// - 送る: 右へ払った「行きたい」と、撮影スポットの頁の「行きたい」を、**端末ごとのでたらめな ID** と一緒に
///   `POST /spots/wants`。名前・メール・利用者の ID は送らない（ログイン中も端末の ID だけ・`SpotWantQueue`）
/// - 読む: 毎日1回の集計が置く `app/data/spot-wants.json`（今月の数が10以上の撮影スポットだけ・多い順・順位）。
///   無い・読めないときは何も出さない（数が無いことを「0」と言わない）
///
/// ここは画面を持たない計算だけ（読む形・文・県の上位）。Linux で試験する
enum SpotWants {

    struct Entry: Decodable, Equatable {
        let slug: String
        let name: String
        let nameEn: String?
        let n: Int
        let rank: Int
    }

    struct File: Decodable, Equatable {
        let month: String
        let spots: [Entry]

        /// 10未満は配られない決まり。紛れ込んでも出さない
        var shown: [Entry] { spots.filter { $0.n >= SpotWants.minShown } }

        func entry(slug: String) -> Entry? { shown.first { $0.slug == slug } }
    }

    static let minShown = 10
    /// 何件たまったら送るか（Web と同じ）
    static let batch = 5
    /// 1回に送る上限（サーバーの `MAX_PER_REQUEST`）
    static let sendMax = 10

    static func decode(_ data: Data) -> File? {
        try? JSONDecoder().decode(File.self, from: data)
    }

    /// 「1,284」（3桁ごとにカンマ）。
    /// 🔴 `NumberFormatter` に en_US_POSIX を渡すと、Apple の端末では区切りが付かない（Mac の単体テストの実測
    /// 「1284」・run 43063948534。Linux の Foundation では付くので手元の試験は通っていた）。端末の言語で変えないよう自分で区切る
    static func count(_ n: Int) -> String {
        let plain = String(abs(n))
        var out = ""
        for (i, ch) in plain.enumerated() {
            if i > 0, (plain.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return n < 0 ? "-" + out : out
    }

    /// 撮影スポットの頁の題の下の1行「今月の行きたい 1,284 · 全国1位」
    static func line(_ e: Entry) -> String {
        L("今月の行きたい \(count(e.n)) · 全国\(e.rank)位", "Want to go this month \(count(e.n)) · #\(e.rank) overall")
    }

    /// 撮影スポットの頁の「行きたい」を押した結果が、数える「行きたい」か（入れた・端末に入れた）。外した・失敗は数えない
    static func counts(_ outcome: WishlistSync.Outcome) -> Bool {
        switch outcome {
        case .synced(let wanted), .local(let wanted): return wanted
        default: return false
        }
    }

    /// 県の一覧の頭の「今月いちばん行きたい」3つ（その県の撮影スポットのうち、数の多い順）
    static func areaTop(_ file: File?, slugs: [String], limit: Int = 3) -> [Entry] {
        guard let file else { return [] }
        let here = Set(slugs)
        return Array(file.shown.filter { here.contains($0.slug) }.prefix(limit))
    }
}
