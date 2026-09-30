import Foundation

/// 今日の一問「この写真はどこ？」（Web の `/q` と同じ問題）。
///
/// **出題の規則はアプリに持たない。** Web がビルド時に日ごとのファイル
/// （`/app/data/quiz/<YYYY-MM-DD>.json`・`lib/data/quizFeed.ts`）を書き出し、
/// Web もアプリもそれを読む——同じ規則を2か所に書くと、片方だけ直したときに
/// 同じ日の問題が Web とアプリで割れる。ここにあるのは**読み取りと表示の決まり**だけ。
///
/// ## 決まりごと（Web の `DailyQuizClient` と同じ）
///
///  - **日付は日本時間の暦日**（`timeZone`）。どこで開いても日本の今日のファイルを読む
///  - 答えは1回。選んだものは日付ごとに端末へ残す（`QuizAnswers`）
///  - **順位・連続記録・正解率は出さない**（数えていない・競争の要素は足さない）
///  - 写真の作者とライセンスは**答える前から**出す（CC の表示条件）
///  - 共有する文に**答えの名前は書かない**（受け取った人の問題を潰さない）
struct DailyQuiz: Equatable {

    struct Choice: Equatable, Identifiable {
        let spotId: String
        let slug: String
        let name: String
        let region: OfficialSpot.Region?

        var id: String { spotId }

        /// 「山形県 尾花沢市」。海外は国から（Web の `regionLine` と同じ）
        var regionLine: String? {
            let r = region
            let country = r?.country?.trimmingCharacters(in: .whitespaces)
            let parts: [String?] = (country != nil && country != "" && country != "日本")
                ? [country, r?.prefecture, r?.city]
                : [r?.prefecture, r?.city]
            let kept = parts.compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return kept.isEmpty ? nil : kept.joined(separator: " ")
        }
    }

    /// 日本時間の暦日 "YYYY-MM-DD"
    let date: String
    /// 答えのスポットの写真（作者・ライセンスは必ず一緒に出す）
    let photo: SpotImage
    /// 4つの選択肢（並べる順もこのまま）
    let choices: [Choice]
    /// 正解の `spotId`
    let answer: String

    var answerChoice: Choice { choices.first { $0.spotId == answer } ?? choices[0] }

    /// 出題の日付の時刻帯。**全員が同じ日に同じ問題**を見るので1つに決める（Web の `QUIZ_TIME_ZONE`）
    static let timeZone = TimeZone(identifier: "Asia/Tokyo")!

    /// 日本時間の今日 "YYYY-MM-DD"。**西暦で数える**（和暦・仏暦の端末でも同じ日付）
    static func today(_ now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// "2026-10-01" → "10/1"（共有する文）
    static func shortDate(_ ymd: String) -> String {
        let parts = ymd.split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) else { return ymd }
        return "\(m)/\(d)"
    }

    /// "2026-10-01" → "2026.10.01"（眉ラベル）
    static func dottedDate(_ ymd: String) -> String { ymd.replacingOccurrences(of: "-", with: ".") }

    /// 共有する文。**答えの名前は書かない**（日付と ✓／✗ だけ）
    static func shareText(date: String, correct: Bool, url: URL) -> String {
        let head = correct
            ? L("Journey Photo 今日の一問 \(shortDate(date)) ✓ 正解",
                "Journey Photo · Where is this? \(shortDate(date)) ✓")
            : L("Journey Photo 今日の一問 \(shortDate(date)) ✗",
                "Journey Photo · Where is this? \(shortDate(date)) ✗")
        return "\(head)\n\(url.absoluteString)"
    }

    // MARK: - 読み取り（Web の `parseDailyQuiz` と同じ弾き方）

    private static let slugPattern = try! NSRegularExpression(pattern: "^[a-z0-9]+(?:-[a-z0-9]+)*$")

    private static func isSlug(_ s: String) -> Bool {
        slugPattern.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static func https(_ v: Any?) -> URL? {
        guard let s = v as? String, s.hasPrefix("https://"), let u = URL(string: s) else { return nil }
        return u
    }

    private static func text(_ v: Any?) -> String? {
        guard let s = v as? String, !s.isEmpty else { return nil }
        return s
    }

    /// 日ごとのファイルを画面の形へ。**頼んだ日付と違う・選択肢が4つでない・正解が選択肢に無い・
    /// 同じ選択肢がある・写真が https でない・作者かライセンスが無い**なら nil（その日は「まだありません」）。
    /// ライセンスの文面は http でも残す（写真の台帳に `http://creativecommons.org/…` の行がある）
    static func parse(_ data: Data, date: String) -> DailyQuiz? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let o = object as? [String: Any],
              (o["date"] as? String) == date,
              let answer = text(o["answer"]),
              let p = o["photo"] as? [String: Any],
              let url = https(p["url"]),
              let author = text(p["author"]),
              let license = text(p["license"]),
              let pageUrl = https(p["pageUrl"]),
              let rawChoices = o["choices"] as? [Any], rawChoices.count == 4 else { return nil }

        var choices: [Choice] = []
        for raw in rawChoices {
            guard let c = raw as? [String: Any],
                  let spotId = text(c["spotId"]), let slug = text(c["slug"]), let name = text(c["name"]),
                  isSlug(slug) else { return nil }
            let r = c["region"] as? [String: Any]
            let region = r.map {
                OfficialSpot.Region(prefecture: text($0["prefecture"]), city: text($0["city"]),
                                    country: text($0["country"]))
            }
            choices.append(Choice(spotId: spotId, slug: slug, name: name, region: region))
        }
        guard Set(choices.map(\.spotId)).count == 4, choices.contains(where: { $0.spotId == answer }) else { return nil }

        let licenseUrl: URL? = {
            guard let s = p["licenseUrl"] as? String,
                  s.hasPrefix("https://") || s.hasPrefix("http://") else { return nil }
            return URL(string: s)
        }()
        let photo = SpotImage(url: url, author: author, license: license, pageUrl: pageUrl, licenseUrl: licenseUrl)
        return DailyQuiz(date: date, photo: photo, choices: choices, answer: answer)
    }
}

/// その日に選んだものを端末に残す（日付ごと）。**サーバーには送らない**（数えない）。
/// 鍵は Web と同じ形（`journey-photo:quiz:<日付>`）——端末も入れ物も別なので混ざりはしないが、
/// 読む人が同じものだと分かるように揃える
struct QuizAnswers {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    static func key(_ date: String) -> String { "journey-photo:quiz:\(date)" }

    /// 選んだもの。**その日の選択肢に無ければ答えていない扱い**（問題が差し替わった日）
    func chosen(for quiz: DailyQuiz) -> String? {
        guard let saved = defaults.string(forKey: Self.key(quiz.date)),
              quiz.choices.contains(where: { $0.spotId == saved }) else { return nil }
        return saved
    }

    func save(_ spotId: String, date: String) {
        defaults.set(spotId, forKey: Self.key(date))
    }
}
