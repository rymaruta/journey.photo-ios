import Foundation

/// 「AI に頼む」の1往復（札 #652）。答えは**アプリの部品**で返す（観光スポットの札、地図のピン、みんなの写真、
/// 行きたい、旅行プランにする）。文は短い1かたまりだけ。
///
/// 端末の中だけに置く（`AskHistoryStore`）。サーバーに残さない。
struct AskExchange: Identifiable, Equatable, Codable {
    var id: String = UUID().uuidString
    let question: String
    var answer: AskAnswer
    /// 頼んだ時刻（AI に渡す直前のやりとりを今日のものだけにする・札 #678。前の版の控えには無い）
    var askedAt: Date? = nil
}

struct AskAnswer: Equatable, Codable {

    /// どこで答えたか（答えの下の1行に出す）
    enum Engine: String, Codable {
        /// この iPhone の中の AI（Foundation Models）
        case device
        /// サーバー（東京）の AI。Pro で、端末の AI が無い iPhone だけ
        case server
        /// AI を使わず、言葉の表と観光スポットの台帳で答えた
        case table
        /// 断った（AI を呼んでいない・回数も使っていない）
        case refused
    }

    /// 答えの状態（Components 06 の4つの状態に合わせる）
    enum State: String, Codable {
        case answered
        /// 合う観光スポットが無い
        case empty
        /// 台帳を読めなかった
        case failed
        /// 圏外（前に見た分だけで答えた）
        case offline
    }

    /// 引いたもの（答えの下の札。押しても使い方の頁は開かない・入口は設定の1か所だけ `HelpLink`）
    struct Source: Equatable, Codable, Hashable {
        enum Kind: String, Codable { case spots, photos, wishlist, trips, help }
        let kind: Kind
        let label: String
    }

    var engine: Engine
    var state: State = .answered
    /// 答えの文。観光スポットの札だけの答えでは空
    var text: String = ""
    /// 引けるものが無い質問に、一般的な知識で答えた（「一般的な答え」の印）
    var general = false
    /// 札に出す観光スポット（`spotId`・アプリが選んだ順）
    var spotIds: [String] = []
    /// 観光スポットごとの AI の理由（`spotId` → 1行・札の名前の下に出す）。AI の答えの「- 名前: 説明」の行を札に振り分けたもの
    /// （`AskAnswerShape`・札 #663）。前の版の控えには無いので nil を許す
    var reasons: [String: String]? = nil
    /// 観光スポットごとの現在地からの距離（km・近さで探したときだけ）
    var distances: [String: Double] = [:]
    /// みんなの写真（`Photo.id`・公開の写真だけ。押すと持ち主の写真の詳細へ）
    var photoIds: [String] = []
    var sources: [Source] = []
    /// 読み取りの札（「現在地から 30km」「夕方」）
    var chips: [String] = []
    /// 札の上の見出し（「夕方の案内がある観光スポット（3か所）」）
    var heading: String? = nil
    /// 1行の添え書き（台帳に無いこと、近さを使えなかったこと、AI を使えなかった理由）
    var note: String? = nil
    /// 「旅行プランにする」を出すか
    var offersPlan = false
    /// 答えの上の帯（回数を使い切った・サーバーの AI を休んでいる）
    var limit: AskLimitReason? = nil
    /// 空のときの言い替え（押すと条件を1つ外して、アプリが選び直す。AI は呼ばない）
    var relaxedQuery: String? = nil
    /// 答えの種類（2026-11-21 判断・札 #675 の答えの形）。前の版の控えには無いので nil を許す（札の有無でアプリが決める）
    var kind: AskAnswerKind? = nil
    /// 形が読めなかった（AI が札と言ったのに台帳に戻る番号が無い）。頭の文だけにし、次に頼めることは決まった3つ
    var unreadable: Bool? = nil
    /// 旅行プランの答え（流れ）。旅行プランの AI が作って保存したもの
    var plan: AskPlanAnswer? = nil

    /// AI を使った答えか（「AI の答えは間違うことがあります」を出す）
    var usedAI: Bool { engine == .device || engine == .server }

    /// 答えの下の1行（どこで答えたか）
    var engineLine: String {
        switch engine {
        case .device:
            return L("この iPhone の中で答えました", "Answered on this iPhone")
        case .server:
            return L("サーバー（東京）で答えました。送ったのは、打った文と直前の2往復、引いた観光スポットの行と使い方の頁の抜き書きだけです",
                     "Answered on our server in Tokyo. Only your words, the last two exchanges, the spot rows and help excerpts were sent.")
        case .table:
            return L("この iPhone の中で言葉を読み、観光スポットから選びました", "Read your words on this iPhone and picked from the spots")
        case .refused:
            return ""
        }
    }

    /// 断りの答え（回数を使わない・何も引かない）
    static func refused(care: Bool) -> AskAnswer {
        AskAnswer(engine: .refused, text: care ? AskGuard.refusal + "\n" + AskGuard.careLine : AskGuard.refusal)
    }
}

/// 「AI の答えは間違うことがあります」（答えの下にいつも）
enum AskText {
    static var disclaimer: String { L("AI の答えは間違うことがあります", "AI answers can be wrong") }
    static var generalBadge: String { L("一般的な答え", "General answer") }
    /// 答えのもとの1行（「観光スポットの情報から」・2026-11-20 判断 札 #663）。「台帳」は中の言葉なので利用者に見せない。
    /// 前の版の控え（label が「観光スポットの台帳」）も種類で言い替える
    static func sourcesLine(_ sources: [AskAnswer.Source]) -> String {
        var names: [String] = []
        for s in sources {
            let name = s.kind == .spots ? spotsSource : s.label
            if !names.contains(name) { names.append(name) }
        }
        return L("\(names.joined(separator: "、"))から", "From \(names.joined(separator: ", "))")
    }
    static var spotsSource: String { L("観光スポットの情報", "tourist spot info") }
    static var followUp: String { L("続けて聞く", "Ask a follow-up") }
    static var makePlan: String { L("旅行プランにする", "Make a trip plan") }
    static var loading: String { L("答えを用意しています", "Preparing an answer") }
    static var emptyTitle: String { L("合う観光スポットがありません", "No matching spots") }
    static var failedTitle: String { L("観光スポットを読み込めませんでした", "Couldn't load the spots") }
    static var failedDetail: String { L("通信が途切れたようです。前に見た分はそのまま残っています。", "The connection seems to have dropped. What you've seen is still here.") }
    static var offlineLine: String { L("圏外なので AI に聞けません。言葉で読んで、前に見た観光スポットから選びました", "You're offline, so AI isn't available. Picked from spots you've already seen.") }
    static var signedOutLine: String { L("ログインすると AI に聞けます。いまは言葉で読んで探しました", "Sign in to ask AI. This time we searched by reading your words.") }
    static var noDeviceAILine: String { L("この iPhone では AI に聞けないため、言葉で探しました", "AI isn't available on this iPhone, so we searched by your words.") }
    static var unansweredLine: String { L("この質問は AI でないと答えられません。", "Only AI can answer this question.") }
    static var silentLine: String { L("AI が答えなかったので、言葉で読んで探しました", "AI didn't answer, so we searched by reading your words.") }
    static var noLocationLine: String { L("現在地が分からないので、近さでは絞っていません", "Couldn't get your location, so results aren't sorted by distance.") }
    static var weeklyLine: String { L("観光スポットの情報に週ごとの見頃は無いので、季節の案内がある所を出しました", "Spot info has no weekly timing, so these have notes for the season.") }

    /// 「現在地から 30km」
    static func nearChip(km: Int) -> String { L("現在地から \(km)km", "Within \(km) km") }
    /// 「8km」（札の距離）
    static func distance(_ km: Double) -> String {
        km < 1 ? L("1km 未満", "< 1 km") : L("\(Int(km.rounded()))km", "\(Int(km.rounded())) km")
    }
}

/// AI の答えの文を、短い文と札の理由に分ける（2026-11-20 判断・札 #663）。
///
/// owner「結果が見づらいな。。」（1.1.107 の実機）: 「おすすめの」と頼むと、答えの欄に「- 愛知県庁本庁舎: 秋や冬の朝に…」の行が
/// 8行、ひとかたまりの文で出ていた。決まりは「答えは部品（札）で返す。文は短い1かたまりだけ」。
/// - 文は**はじめの1〜2文、80字まで**。超えたら文の切れ目（。！？、なければ「、」）で切る
/// - 「- 名前: 説明」（「・」「•」「*」、番号付きも）の行は、名前が札の観光スポットに合えば、その札の理由（1行）にする
/// - **札に無い名前の行は出さない**（台帳に無い所を AI が作った恐れがある）
/// - 端末の AI の答えにもサーバーの答えにも使う（サーバーは変えない）
enum AskAnswerShape {

    static let leadLimit = 80

    // MARK: - 案A の頭の1〜2文（2026-11-20 owner 承認・Artifact「AI に頼む 答えの見た目」）

    /// 明朝の大きさ。ふだんは 20pt、20pt で4行を超える長さ（約68字・390pt の画面で1行約17字）なら 18pt
    static let leadLargeSize: Double = 20
    static let leadSmallSize: Double = 18
    static let leadLargeMaxChars = 68

    static func leadPointSize(_ text: String, small: Bool = false) -> Double {
        small || text.count > leadLargeMaxChars ? leadSmallSize : leadLargeSize
    }

    /// 観光スポットの札のある答えの、札の上の明朝の1〜2文。AI の答えは文（20pt か 18pt）、
    /// AI を使わない答え（使い切った、圏外）は見出し（「冬の案内がある観光スポット（6か所）」）を 18pt で
    static func leadLine(_ a: AskAnswer) -> (text: String, small: Bool)? {
        // 2026-11-21 判断（札 #675 の答えの形・版3「圏外と使い切った」）: AI を使わずに札を選んだ答え（圏外、使い切った、
        // ログインしていない）は、形はそのまま、頭の文はアプリの決まり文（「秋に向く所を2つ選びました。」）
        if !a.usedAI, a.engine != .refused, !a.spotIds.isEmpty, a.kind != .plan {
            let labels = ShootingTime.Season.allCases.map(\.label)
            let season = a.chips.first { labels.contains($0) }
            return (AskLeadCheck.pickedLine(count: a.spotIds.count, season: season), true)
        }
        if a.usedAI, !a.text.isEmpty { return (a.text, leadPointSize(a.text) < leadLargeSize) }
        if let heading = a.heading, !heading.isEmpty { return (heading, true) }
        if !a.text.isEmpty { return (a.text, true) }
        return nil
    }

    struct Shaped: Equatable {
        var lead: String
        var reasons: [String: String]
    }

    static func shape(_ text: String, spots: [OfficialSpot]) -> Shaped {
        var leadLines: [String] = []
        var reasons: [String: String] = [:]
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let item = listItem(line) {
                if let spot = match(item.name, in: spots), reasons[spot.spotId] == nil, !item.reason.isEmpty {
                    reasons[spot.spotId] = item.reason
                }
                continue
            }
            // 印の無い行でも「名前: 説明」で名前が札に合えば理由にする（AI が印を付け忘れた形）
            if let pair = namePair(line), let spot = match(pair.name, in: spots) {
                if reasons[spot.spotId] == nil, !pair.reason.isEmpty { reasons[spot.spotId] = pair.reason }
                continue
            }
            // 箇条の印だけ付いた行（名前と説明に分かれない）は文に混ぜない
            if hasListMark(line) { continue }
            leadLines.append(line)
        }
        return Shaped(lead: lead(leadLines.joined()), reasons: reasons)
    }

    /// はじめの1〜2文（80字まで）
    static func lead(_ text: String) -> String {
        var t = stripMarkup(text).trimmingCharacters(in: .whitespacesAndNewlines)
        // 「おすすめは次の通りです:」のように箇条へつなぐ終わりは句点にする
        if t.hasSuffix(":") || t.hasSuffix("：") { t = String(t.dropLast()) + "。" }
        guard !t.isEmpty else { return "" }
        let sentences = splitSentences(t)
        var out = sentences.first ?? t
        if out.count > leadLimit { return cut(out) }
        if sentences.count > 1, out.count + sentences[1].count <= leadLimit { out += sentences[1] }
        return out
    }

    static func splitSentences(_ t: String) -> [String] {
        var out: [String] = []
        var cur = ""
        for ch in t {
            cur.append(ch)
            if "。！？!?".contains(ch) {
                out.append(cur.trimmingCharacters(in: .whitespaces))
                cur = ""
            }
        }
        let rest = cur.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { out.append(rest) }
        return out
    }

    /// 1文が80字を超えたら、80字までの最後の「、」で切って「…」
    static func cut(_ sentence: String) -> String {
        let head = String(sentence.prefix(leadLimit))
        if let comma = head.lastIndex(where: { $0 == "、" || $0 == "," }), head.distance(from: head.startIndex, to: comma) >= 10 {
            return String(head[..<comma]) + "…"
        }
        return String(sentence.prefix(leadLimit - 1)) + "…"
    }

    /// 箇条の行（「- 名前: 説明」「・名前：説明」「1. 名前: 説明」）
    static func listItem(_ line: String) -> (name: String, reason: String)? {
        guard hasListMark(line) else { return nil }
        return namePair(dropListMark(line))
    }

    static func hasListMark(_ line: String) -> Bool {
        dropListMark(line) != line
    }

    static func dropListMark(_ line: String) -> String {
        var t = Substring(line)
        if let first = t.first, "-・•*●○◆■▪︎–—".contains(first) {
            t = t.dropFirst()
            // 「**名前**」の頭の「*」は印ではない
            if first == "*", t.first == "*" { return line }
        } else {
            let digits = t.prefix { $0.isNumber }
            guard !digits.isEmpty else { return line }
            let after = t.dropFirst(digits.count)
            guard let mark = after.first, ".)．、）".contains(mark) else { return line }
            t = after.dropFirst()
        }
        return String(t).trimmingCharacters(in: .whitespaces)
    }

    /// 「名前: 説明」（半角、全角のコロン）。名前は40字まで
    static func namePair(_ line: String) -> (name: String, reason: String)? {
        guard let colon = line.firstIndex(where: { $0 == ":" || $0 == "：" }) else { return nil }
        let name = stripMarkup(String(line[..<colon])).trimmingCharacters(in: .whitespaces)
        let reason = stripMarkup(String(line[line.index(after: colon)...])).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.count <= 40 else { return nil }
        return (name, reason)
    }

    static func stripMarkup(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "「", with: "").replacingOccurrences(of: "」", with: "")
    }

    /// 名前を札の観光スポットに当てる（字の幅と空白をそろえて同じ、無ければ2字以上でどちらかがもう片方を含む）
    static func match(_ name: String, in spots: [OfficialSpot]) -> OfficialSpot? {
        let key = normalized(name)
        guard key.count >= 2 else { return nil }
        if let exact = spots.first(where: { normalized($0.name) == key }) { return exact }
        let partial = spots.filter {
            let n = normalized($0.name)
            return n.count >= 2 && (n.contains(key) || key.contains(n))
        }
        return partial.max { normalized($0.name).count < normalized($1.name).count }
    }

    static func normalized(_ s: String) -> String {
        SearchSentence.fold(stripMarkup(s)).lowercased().filter { !$0.isWhitespace }
    }
}
