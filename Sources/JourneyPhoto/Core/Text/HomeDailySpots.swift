import Foundation

/// ホームの撮影スポットの**日替わりの選び方**（2026-10-18）。上の季節の札（`HomeTopCard.inSeason`）と
/// 「いまの季節の撮影スポット」の段（`HomeSpotShelf.shelf`）が同じ並びから選ぶ。
///
/// 🔴 owner・2026-10-18「今の季節の撮影スポットが毎日同じにみえる」→「日替わりだね」（2026-09-30 の
/// 「ホームのスポットは週替わり」を覆した）。**同じ日なら何度開いても同じ・端末の暦の 0 時で替わる・
/// 3日続けて同じスポットを出さない**（今日出たものは、明日にも明後日にも出ない）。
///
/// ## 選び方（履歴は持たない——日の番号だけで決まる・どの端末でも同じ）
///
/// 1. 季節の候補（`HomeTopCard.seasonGuides`・`spotId` の順）を、**行の番号を3で割った余りで3つの組**に
///    分ける。日の番号（`HomeTopCard.dayNumber`）を3で割った余りの組が今日の組——**隣り合う3日は
///    必ず別の組**なので、組の中から選ぶかぎり重ならない
/// 2. 組の中は1日ぶんの窓（上の札1件＋段 `HomeSpotShelf.count` 件＝`window`）に区切り、その組が
///    回ってくるたび（3日ごと）に1窓ずつ先へ進む。上の札は窓の中で写真のある最初の1件、段は窓の残り
/// 3. 都道府県で散らすときに窓の外の行を拾うことがある。拾う順は**次の窓を最後に回す**——次の窓は
///    3日後の札と段なので、今日拾うと3日後にまた出る
/// 4. 段が今日の組で足りない（候補の少ない季節）ときだけ、ほかの組で埋める（数を減らさない）
/// 5. 上の札は、**写真のある候補が無い組が1つでもあれば**（候補の少ない季節）組を使わず、写真のある候補を
///    `spotId` の順に1日1件ずつ回す——組から借りると、借りた札が前後の日の札と同じになる道があった
///    （96e499b7 のレビュー）。1日1件ずつなら、2件あれば翌日は別、3件あれば3日続けて別
///
/// 2026-10-18 判断（photo-gallery の台帳 `content/spots.json` の公開済み行で数えた・上の札＋段・今日の一問は無し）:
///
///     翌日 / 2日後 / 3日後と同じスポットが出た日（365日中）
///                  週替わり(9/30〜)   単位を日にしただけ   偶奇の2組   3組＋窓（いま）
///       春 201件    329/293/256        87/20/18             0/111/0     0/0/0
///       夏 147件    332/299/265       115/24/28             0/118/0     0/0/0
///       秋 194件    331/297/262       105/21/22             0/126/0     0/0/0
///       冬 202件    323/281/238        84/22/17             0/100/0     0/0/0
///
///   いまの形は4日後・5日後も0日で、6日後（同じ組の次の次の窓）から重なり始める
///
/// ⚠️ **例外**（注記として残す・2026-10-18 判断）:
/// - 候補が3日ぶん（窓3つ・18件）に満たない季節の段は、続けて出ることがある（出せる物がそれしか無い）
/// - 候補が窓6つぶん（約36件）に満たない季節は、3日後・6日後にも同じスポットが出る（組の中の窓が
///   2つ以下で、すぐ一周する）。上の「6日後から重なり始める」は候補の多い季節の話
/// - 今日の一問の4件を除く日は、候補が18〜19件でも段が翌日と重なることがある（除いた分を
///   ほかの組で埋めるため。本番の台帳の 147〜202件では当たらない）
/// - 上の札は、写真のある候補が1件なら毎日それ、2件なら1日おきに同じ
/// - 今日の一問の選択肢（毎日替わる）を除くと、候補の少ない季節の札の回し（上の 5.）は1件ずれて、
///   続けて同じ札になる日がある。候補の多い季節は組が違うので重ならない（毎日4件を除いて数えても
///   翌日〜5日後は0日）
enum HomeDailySpots {

    typealias Row = (spot: OfficialSpot, guide: String)

    /// 組の数。隣り合う何日を重ねないか
    static let groupCount = 3
    /// 1日ぶんの窓（上の札1件＋段）
    static var window: Int { HomeSpotShelf.count + 1 }

    /// 組の中で何回目か（日の番号を3で割って切り下げ）
    static func groupStep(_ day: Int) -> Int {
        let n = groupCount
        return day >= 0 ? day / n : (day - n + 1) / n
    }

    /// 今日の並び: 今日の組を `groupStep × window` 件先から一周（**次の窓は最後**）、続けてほかの組を同じく。
    /// `window` は段だけを見るときに変えられる（試験・`limit` を変えた段）
    static func order<T>(_ rows: [T], day: Int, window: Int = window) -> (own: [T], others: [T]) {
        let n = groupCount
        let group = ((day % n) + n) % n
        var own: [T] = [], others: [T] = []
        for (index, row) in rows.enumerated() {
            if index % n == group { own.append(row) } else { others.append(row) }
        }
        let step = groupStep(day)
        return (rotate(own, step: step, window: window), rotate(others, step: step, window: window))
    }

    /// `step × window` 件先から一周させ、すぐ次の窓（`window` 件）を最後に回す
    private static func rotate<T>(_ rows: [T], step: Int, window: Int) -> [T] {
        guard !rows.isEmpty, window > 0 else { return rows }
        // 組が窓より小さいときは1件ずつ回す（窓の幅で回すと、同じ所から始まり続けることがある）
        let stride = rows.count > window ? window : 1
        let start = (((step * stride) % rows.count) + rows.count) % rows.count
        let turned = Array(rows[start...] + rows[..<start])
        guard turned.count > 2 * window else { return turned }
        return Array(turned[..<window] + turned[(2 * window)...] + turned[window..<(2 * window)])
    }

    // MARK: - 上の札

    /// 上の札（写真のある1件）。組がそろっていれば今日の並びで写真のある最初の1件、
    /// 写真のある候補の無い組があれば、写真のある候補を `spotId` の順に1日1件ずつ（上の 5.）
    static func top(_ rows: [Row], day: Int, excluding: Set<String>) -> Row? {
        let usable: (Row) -> Bool = { $0.spot.hasPhoto && !excluding.contains($0.spot.spotId) }
        let n = groupCount
        let groupsFilled = (0..<n).allSatisfy { group in
            rows.enumerated().contains { $0.offset % n == group && usable($0.element) }
        }
        guard groupsFilled else {
            let candidates = rows.filter(usable)
            guard !candidates.isEmpty else { return nil }
            return candidates[((day % candidates.count) + candidates.count) % candidates.count]
        }
        let ordered = order(rows, day: day)
        return ordered.own.first(where: usable)
    }

    // MARK: - 段

    /// 段（`limit` 件まで・都道府県で散らす）。今日の組を先に、足りなければほかの組
    static func shelf(_ rows: [Row], day: Int, excluding: Set<String>, limit: Int) -> [Row] {
        let ordered = order(rows, day: day, window: limit + 1)
        return scattered((ordered.own + ordered.others).filter { !excluding.contains($0.spot.spotId) }, limit: limit)
    }

    /// 都道府県で散らして `limit` 件まで選ぶ。1周目は同じ県（国外は国）を飛ばし、足りなければ飛ばした行で埋める
    static func scattered(_ rows: [Row], limit: Int) -> [Row] {
        var picked: [Row] = []
        var skipped: [Row] = []
        var regions = Set<String>()
        for row in rows where picked.count < limit {
            let key = HomeSpotShelf.Entry(spot: row.spot, guide: row.guide).regionLabel
            // 地域の分からない行は散らす対象にしない（どれとも重ならない）
            if let key, !regions.insert(key).inserted {
                skipped.append(row)
            } else {
                picked.append(row)
            }
        }
        return picked + skipped.prefix(max(limit - picked.count, 0))
    }

    // MARK: - 画面の「今日」を進める

    /// 画面が持っている「今日」（`shown`）を今（`now`）へ進めるか。**端末の時刻帯の暦日**が違えば進める
    /// （今日の一問は日本時間で替わるが、札と段は端末の暦——日本の外では一問と別の時刻に替わる）
    static func shouldAdvance(shown: Date, now: Date, in zone: TimeZone) -> Bool {
        TripPlanText.ymd(pickedIn: zone, shown) != TripPlanText.ymd(pickedIn: zone, now)
    }

    /// ホームのまま待つときに、次に壁時計を確かめ直すまでの秒数。次の 0 時（端末の時刻帯）の1秒後まで、
    /// ただし `maxWait` を超えない——端末が眠っている間は待ちが進まない見込みで、時計や時刻帯が
    /// 変わることもあるので、起きるたびに今の時刻で日を確かめ直す
    static func secondsUntilRecheck(now: Date, in zone: TimeZone, maxWait: TimeInterval = 15 * 60) -> TimeInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let next = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0),
                                           matchingPolicy: .nextTime) else { return maxWait }
        return min(max(next.timeIntervalSince(now), 0) + 1, maxWait)
    }
}
