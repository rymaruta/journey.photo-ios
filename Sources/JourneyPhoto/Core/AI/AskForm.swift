import Foundation

// 「AI に頼む」の答えの形の最初の版（札 #675・2026-11-21 判断・Artifact「AI に頼む 独立の案」版3「答えの形 磨いた推奨」）。
// owner「ブラッシュアップしてから推奨でお願い」で決まった形。画面を持たない層（`AskFormTests`）。
//
// - AI は決まった形（種類 → 頭の文 → 札）で返し、アプリが形を選ぶ（札を横に送る、札1枚を広く、流れ、頭の文だけ）
// - 答えの下はいつも「頭の文 → 形 → 一手 → 次に頼めること → どこで答えたか」の順
// - **一手と次に頼めることはアプリが決める（AI は書かない）。** 押しても AI は呼ばない（次に頼めることは欄に入るだけ）
// - 形が読めなかったときは頭の文だけにし、次に頼めることはアプリの決まった3つ
// - 札と流れの場所は台帳からだけ。頭の文に台帳に無い場所らしい名前があれば、アプリの決まり文に替える

/// 答えの種類（AI が最初に返す欄。字から分かるときはアプリが先に決める）
enum AskAnswerKind: String, Codable, CaseIterable, Equatable {
    /// 観光スポットの札（横に送る・1枚を広く）
    case cards
    /// 札を並べる（「どっち」）。最初の版は札の形で見せる（並べる形は次の版）
    case compare
    /// 旅行プランの流れ
    case plan
    /// 使い方の手順（最初の版は文で見せる。手順の形は次の版）
    case steps
    /// みんなの写真（最初の版は札の形の下の写真のまま。写真の形は次の版）
    case photos
    /// 文だけ
    case text

    /// 端末の AI に選ばせる種類（旅行プランは旅行プランの AI が作るので入れない）
    static let deviceChoices = ["cards", "compare", "steps", "photos", "text"]

    /// AI が返した字を種類に戻す。知らない字は nil（形が読めなかった）
    static func parse(_ raw: String?) -> AskAnswerKind? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else { return nil }
        return AskAnswerKind(rawValue: raw)
    }

    /// 字から分かる種類（押した瞬間から形の骨格を出す）。分からなければ nil（頭の文の骨格だけ）。
    /// 「プラン」「泊」は流れ、「どっち」は並べる、「写真を見せて」は写真、「〜には」「やり方」は手順。
    /// 観光スポットを探す頼み（`AskQuery.intent.spots`）は札
    static func byWords(_ question: String) -> AskAnswerKind? {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        if AskEntry.route(q) == .tripPlan { return .plan }
        if ["どっち", "どちらがいい", "比べ", "違いは"].contains(where: q.contains) { return .compare }
        if q.contains("写真") && ["見せ", "見たい", "見る"].contains(where: q.contains) { return .photos }
        let bare = q.trimmingCharacters(in: CharacterSet(charactersIn: "？?。 "))
        if bare.hasSuffix("には") || ["やり方", "方法は", "どうやって", "使い方"].contains(where: q.contains) { return .steps }
        let intent = AskQuery.intent(q, reading: SearchSentence.readByTable(q))
        if intent.spots { return .cards }
        return nil
    }
}

/// 旅行プランの答え（流れ）。保存したプランの番号と、日ごとの観光スポット（台帳の番号だけ）
struct AskPlanAnswer: Codable, Equatable {
    var title: String
    /// 保存した旅行プラン（旅行プランの AI はできたら保存する・札 #621）。保存できなければ nil
    var planId: String?
    var days: [[String]]
}

/// 答えの種類ごとに部品を選ぶ所（2026-11-21 判断）。最初の版は札を横に送る、札を縦に積む（大きな字）、札1枚を広く、流れ、頭の文だけ
enum AskAnswerLayout: Equatable {
    /// 写真の札を横に送る並びと地図（`AskSpotCarousel`・#663 の案A）
    case spotCarousel
    /// 大きな字: 札を縦に積む
    case spotStack
    /// 1か所: 札を広く、見どころ3つと小さな地図
    case spotWide
    /// 旅行プラン: 番号の線に観光スポットと移動の目安
    case planFlow
    /// 頭の文だけ（断った、形が読めなかった、文だけの答え）
    case leadOnly

    /// 大きな字（およそ 1.3 倍から）で札を縦に積む
    static func layout(for answer: AskAnswer, largeText: Bool = false) -> AskAnswerLayout {
        if answer.engine == .refused { return .leadOnly }
        if answer.kind == .plan, let plan = answer.plan, plan.days.contains(where: { !$0.isEmpty }) { return .planFlow }
        if answer.unreadable == true { return .leadOnly }
        switch answer.spotIds.count {
        case 0: return .leadOnly
        case 1: return .spotWide
        default: return largeText ? .spotStack : .spotCarousel
        }
    }
}

/// 形と中身を突き合わせる（形が読めなかったときは頭の文だけ・版3「形が読めなかったとき」）
enum AskFormCheck {

    /// 答えの種類。AI が返した種類 → 字から分かる種類 → 札があれば札、無ければ文
    static func kind(ai: AskAnswerKind?, words: AskAnswerKind?, spotCount: Int) -> AskAnswerKind {
        if let ai { return ai }
        if let words, words != .plan { return words }
        return spotCount > 0 ? .cards : .text
    }

    /// 形が読めなかったか: AI が札か流れと言ったのに、台帳に戻る番号が1つも無い。
    /// AI が種類を返さなかった（前の版の答え、今のサーバーの答え）は読めなかったとしない（札の有無でアプリが決める）
    static func unreadable(ai: AskAnswerKind?, spotCount: Int) -> Bool {
        guard let ai else { return false }
        return [.cards, .compare, .plan].contains(ai) && spotCount == 0
    }
}

/// 頭の文に、台帳に無い場所らしい名前が混じっていないか（札は台帳からだけ・版3「台帳に無い場所を出さない仕組み」）。
/// 場所らしい名前（漢字かカタカナに「寺」「神社」「城」「公園」「滝」「温泉」などが付いた語）が、答えの札、台帳の観光スポット、
/// 地域の名前のどれにも合わなければ、アプリの決まり文（「秋に向く所を2つ選びました。」）に替える
enum AskLeadCheck {

    static let placeSuffixes = ["神社", "神宮", "大社", "寺", "城", "公園", "庭園", "滝", "温泉", "岬", "渓谷", "峡", "海岸", "高原", "駅"]

    /// 頭の文の中の、場所らしい名前
    static func placeNames(in text: String) -> [String] {
        let suffix = placeSuffixes.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        // 前に漢字かカタカナが1字以上（「お寺」「古い城」は場所の名前としない）
        guard let re = try? NSRegularExpression(pattern: "[\\p{Han}\\p{Katakana}ー]{1,12}(?:\(suffix))") else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    /// 台帳に無い名前があるか
    static func hasUnknownPlace(_ text: String, shown: [OfficialSpot], ledger: [OfficialSpot]) -> Bool {
        let names = placeNames(in: text)
        guard !names.isEmpty else { return false }
        let known = (shown + ledger).map { AskAnswerShape.normalized($0.name) }.filter { $0.count >= 2 }
        let regions = (shown + ledger).flatMap { [$0.region?.prefecture, $0.region?.city] }.compactMap { $0 }
            .map(AskAnswerShape.normalized).filter { $0.count >= 2 }
        return names.contains { raw in
            let n = AskAnswerShape.normalized(raw)
            let matchesSpot = known.contains { $0.contains(n) || n.contains($0) }
            let matchesRegion = regions.contains { n == $0 }
            return !matchesSpot && !matchesRegion
        }
    }

    /// 出す頭の文。台帳に無い名前が混じれば決まり文
    /// 2026-11-21 判断（確かめ役の指摘）: 札の無い答え（文だけ、形が読めなかった）も台帳全体と照らす。
    /// 合わない名前があれば、札のある答えは「〜を2つ選びました。」、札の無い答えは `unknownPlaceLine`
    static func safeLead(_ lead: String, shown: [OfficialSpot], ledger: [OfficialSpot], season: String?) -> String {
        guard hasUnknownPlace(lead, shown: shown, ledger: ledger) else { return lead }
        return shown.isEmpty ? unknownPlaceLine : pickedLine(count: shown.count, season: season)
    }

    /// 札の無い答えの頭の文に台帳に無い場所の名前があったとき
    static var unknownPlaceLine: String {
        L("観光スポットの情報に無い場所なので、ここでは答えられません。", "That place isn't in our spot info, so we can't answer here.")
    }

    /// 決まり文（「秋に向く所を2つ選びました。」・圏外と使い切ったときの頭の文と同じ形）
    static func pickedLine(count: Int, season: String?) -> String {
        if let season, !season.isEmpty {
            return L("\(season)に向く所を\(count)つ選びました。", "Picked \(count) spots for \(season).")
        }
        return L("合う所を\(count)つ選びました。", "Picked \(count) matching spots.")
    }
}

/// 一手（答えの下のボタン・アプリが決める）。押しても AI は呼ばない
enum AskAct: String, Equatable, CaseIterable {
    /// 札の観光スポットから旅行プランを作る（並べ方は座標で決める・AI を使わない）
    case makePlan
    /// 札の観光スポットのリンクを仲間に送る（DM。画像は渡さない）
    case share
    /// 旅行プランの招待のリンクを送る（今の旅行プランの共有の形）
    case sharePlan
    /// 保存した旅行プランを開く
    case openPlan

    static func acts(for answer: AskAnswer, layout: AskAnswerLayout, signedIn: Bool, offline: Bool) -> [AskAct] {
        guard answer.engine != .refused, answer.state != .failed, answer.state != .empty else { return [] }
        switch layout {
        case .spotCarousel, .spotStack, .spotWide:
            var out: [AskAct] = []
            if signedIn { out.append(.makePlan) }
            // 圏外では仲間に送るを出さない（送れない）
            if !offline && answer.state != .offline { out.append(.share) }
            return out
        case .planFlow:
            guard let planId = answer.plan?.planId, !planId.isEmpty else { return [] }
            var out: [AskAct] = []
            if signedIn && !offline { out.append(.sharePlan) }
            out.append(.openPlan)
            return out
        case .leadOnly:
            return []
        }
    }

    var label: String {
        switch self {
        case .makePlan: return AskText.makePlan
        case .share, .sharePlan: return L("仲間に送る", "Send to friends")
        case .openPlan: return L("旅行プランを開く", "Open the trip")
        }
    }

    var systemImage: String {
        switch self {
        case .makePlan: return "calendar"
        case .share, .sharePlan: return "paperplane"
        case .openPlan: return "chevron.right"
        }
    }
}

/// 次に頼めること（答えの下のチップ）。**AI に書かせず、答えの形と台帳からアプリが作る。** 押すと欄に入るだけ（送るのは送信のボタン）。
/// 台帳に無いこと（宿、店、混み具合、雨の日）は出さない
enum AskNextAsks {

    /// 形が読めなかったときの決まった3つ
    static var fixed: [String] {
        [L("近くの観光スポットは？", "Spots near me?"), L("旅行プランを作る", "Make a trip plan"), L("写真を見る", "See photos")]
    }

    static func make(for answer: AskAnswer, layout: AskAnswerLayout, spots: [OfficialSpot]) -> [String] {
        guard answer.engine != .refused, answer.state != .failed else { return [] }
        if answer.state == .empty { return [] }
        switch layout {
        case .leadOnly:
            return fixed
        case .spotCarousel, .spotStack:
            var out: [String] = []
            if let time = commonTime(spots) {
                out.append(L("この中で\(time)に向く所は？", "Which of these suit \(time)?"))
            }
            out.append(L("近くの観光スポットは？", "Spots near me?"))
            if let place = mainPlace(spots) {
                out.append(L("\(place)で2日の旅行プランにして", "Make a 2-day trip plan in \(place)"))
            }
            return out
        case .spotWide:
            guard let spot = spots.first else { return fixed }
            var out = [L("近くの観光スポットは？", "Spots near me?"), L("\(spot.name)の写真を見せて", "Show photos of \(spot.name)")]
            if let place = mainPlace(spots) {
                out.append(L("\(place)で2日の旅行プランにして", "Make a 2-day trip plan in \(place)"))
            }
            return out
        case .planFlow:
            // 組み直し（「雨ならどうする？」「1日目を短くして」）は次の版（組み直しの形と一緒に）。今は流れの場所を聞く
            return Array(spots.prefix(2).map { L("\($0.name)ってどんな所？", "What is \($0.name) like?") })
        }
    }

    /// 札の観光スポットの半分以上に案内がある時間帯（朝、夕方…）。無ければ nil
    static func commonTime(_ spots: [OfficialSpot]) -> String? {
        guard spots.count >= 2 else { return nil }
        for key in SpotBodyText.timeOrder {
            let n = spots.filter { $0.timeKeys.contains(key) }.count
            if n >= 1, n * 2 >= spots.count, let label = SpotBodyText.timeLabel(key) {
                return label
            }
        }
        return nil
    }

    /// 札の観光スポットのいちばん多い県（短い名前「京都」）。無ければ nil
    static func mainPlace(_ spots: [OfficialSpot]) -> String? {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for s in spots {
            guard let p = s.region?.prefecture, !p.isEmpty, s.region?.country == nil else { continue }
            if counts[p] == nil { order.append(p) }
            counts[p, default: 0] += 1
        }
        guard let best = order.max(by: { counts[$0, default: 0] < counts[$1, default: 0] }) else { return nil }
        return TripAIDestination.prefectureShort(best)
    }
}

/// 前の答えを畳んだ1行（「質問と中身の1行」・押すと開く）
enum AskFold {
    static func summary(_ answer: AskAnswer, names: [String]) -> String {
        if answer.engine == .refused { return L("お答えできない質問", "A question we can't answer") }
        if answer.state == .empty { return AskText.emptyTitle }
        if answer.state == .failed { return answer.kind == .plan ? L("旅行プランを作れませんでした", "Couldn't make the trip") : AskText.failedTitle }
        if answer.kind == .plan, let plan = answer.plan {
            let days = plan.days.filter { !$0.isEmpty }
            return L("旅行プラン \(days.count)日（\(days.joined().count)か所）", "Trip plan, \(days.count) days (\(days.joined().count) spots)")
        }
        if !names.isEmpty {
            let head = names.prefix(2).joined(separator: L("、", ", "))
            let more = names.count > 2 ? L("ほか", " and more") : ""
            // 2026-11-21 判断（確かめ役の指摘）: 「札」は中の言葉。呼び名は「観光スポット」
            return L("観光スポット\(names.count)つ（\(head)\(more)）", "\(names.count) spots (\(head)\(more))")
        }
        let lead = AskAnswerShape.lead(answer.text)
        return lead.count > 28 ? String(lead.prefix(27)) + "…" : lead
    }
}

/// 旅行プランの流れの部品（日の見出し、移動の目安）
enum AskPlanFlowText {
    /// 「1日目　東山」（その日にいちばん多い市区町村。無ければ日だけ）
    static func dayTitle(_ index: Int, spots: [OfficialSpot]) -> String {
        let day = L("\(index + 1)日目", "Day \(index + 1)")
        var counts: [String: Int] = [:]
        var order: [String] = []
        for s in spots {
            guard let c = s.region?.city?.trimmingCharacters(in: .whitespaces), !c.isEmpty else { continue }
            if counts[c] == nil { order.append(c) }
            counts[c, default: 0] += 1
        }
        guard let area = order.max(by: { counts[$0, default: 0] < counts[$1, default: 0] }) else { return day }
        return day + "\u{3000}" + area
    }

    /// 移動の目安（分）。座標の直線距離を、道のり 1.3 倍、時速 30km（町の中を車か電車）で見積もる。座標が無ければ nil
    static func moveMinutes(_ a: OfficialSpot, _ b: OfficialSpot) -> Int? {
        guard let ca = a.coords, let cb = b.coords else { return nil }
        let km = TripAICandidates.km(ca, cb) * 1.3
        let minutes = Int((km / 30 * 60).rounded())
        return max(5, Int((Double(minutes) / 5).rounded()) * 5)
    }

    ///
    /// 2026-11-21 判断（バグ調べ）: 英語でも、ちょうどの時間は分を付けない（前は「About 1h 0m」）。
    /// `TripTravel.duration` は日本語の形（「約 1 時間」の空き）と丸め（10 分単位）が違うので使い回さず、英語の形だけそろえる
    static func moveLine(_ minutes: Int, language: String = Locale.preferredAppLanguage) -> String {
        let h = minutes / 60, m = minutes % 60
        if minutes >= 60 {
            return L("移動の目安 約\(h)時間\(m == 0 ? "" : "\(m)分")",
                     m == 0 ? "About \(h)h to move" : "About \(h)h \(m)m to move", language: language)
        }
        return L("移動の目安 約\(minutes)分", "About \(minutes) min to move", language: language)
    }

    /// 頭の文（旅行プランの AI の理由の1文。AI を使わなかったときは決まり文）
    static func lead(reason: String, usedAI: Bool, days: Int) -> String {
        let shaped = AskAnswerShape.lead(reason)
        if usedAI, !shaped.isEmpty { return shaped }
        return L("観光スポットの位置で、\(days)日に並べました。", "Arranged by location into \(days) days.")
    }

    /// AI を使わずに組んだときの1行
    static func modeNote(_ mode: TripAIResult.Mode) -> String? {
        switch mode {
        case .ai: return nil
        case .usedUp, .limited: return L("旅行プランの AI の回数を使い切ったので、AI を使わずに組みました", "Trip AI is used up, so we arranged it without AI.")
        case .offline: return L("電波が届かないので、AI を使わずに組みました", "No signal, so we arranged it without AI.")
        case .silent: return L("AI が答えなかったので、AI を使わずに組みました", "AI didn't answer, so we arranged it without AI.")
        case .proOnly: return L("この iPhone では AI を使えないので、AI を使わずに組みました", "AI isn't available on this iPhone, so we arranged it without AI.")
        }
    }
}

/// 札の観光スポットから、AI を使わずに旅行プランの日を作る（座標で並べる・`TripDraft.plan`）。
/// 「旅行プランにする」を押したとき（版3: 1回で旅行プランの画面へ。並べ方は座標で決める）
enum AskQuickPlan {
    static func days(_ spots: [OfficialSpot]) -> [[TripDraft.Place]] {
        TripDraft.plan(spots.map(TripDraft.place(spot:)), dayCount: nil)
    }

    static func title(_ days: [[TripDraft.Place]]) -> String {
        TripPicker.defaultTitle(days)
    }
}

/// 仲間に送るリンク（観光スポットの頁。画像のファイルは渡さない・CLAUDE.md「他人の写真は、その人のもの」）
enum AskShareLinks {
    /// 一度に送るのは3か所まで（DM に何通も続けて届かないように）
    static let maxLinks = 3

    static func links(_ spots: [OfficialSpot], siteBase: URL) -> [(name: String, url: URL)] {
        spots.compactMap { s in
            SpotScreen.pageURL(slug: s.slug, isDraft: s.isDraft, siteBase: siteBase).map { (s.name, $0) }
        }
        .prefix(maxLinks)
        .map { $0 }
    }

    /// シートの説明の1行（「観光スポット 2つ（永観堂、東福寺）をリンクで送ります」）
    static func what(_ names: [String]) -> String {
        L("観光スポット \(names.count)つ（\(names.joined(separator: "、"))）をリンクで送ります",
          "Sends \(names.count) spot link(s): \(names.joined(separator: ", "))")
    }

    static func sentLine(_ name: String, count: Int) -> String {
        L("\(name)さんに観光スポットを\(count)つ送りました", "Sent \(count) spot(s) to \(name)")
    }
}
