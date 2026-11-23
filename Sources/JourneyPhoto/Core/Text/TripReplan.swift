import Foundation

/// 旅行プランを「雨なら」「もっとゆっくり」で組み直す（札 #667・owner 2026-11-20「1のAI使う案いいとおもう！！」）。
/// 画面を持たない層（Linux の `swift test` で確かめる・`TripReplanTests`）。
///
/// 流れ（案のページ「AI のほかの使いみち」の案1の模型が正）:
/// 1. 日程の上のチップ（`TripAITweak`）を押すか、「書いて頼む」の欄に打つ
/// 2. 打った文は**呼ぶ前に断る**（`AskGuard`・作りやセキュリティの質問は AI を呼ばず、回数も使わない）
/// 3. AI が組んだ案は**すぐ上書きしない**。「今 | 組み直した案」を見比べ、「この案にする」で置き換える（`Proposal`）
/// 4. 置き換えたあとも「元に戻す」で戻せる（画面を開いている間）
///
/// AI に渡すのは、そのプランの観光スポット（公開の台帳）、日付、選んだか打った条件だけ（`request`）。
/// 仲間の名前、会話、ほかの人の情報、ひとこと（メモ）は渡さない
enum TripReplan {

    /// 打った条件の字数（サーバーの頼みの上限 200 から、日付の行の分を残す）
    static let typedMax = 120

    /// 打った条件を AI を呼ぶ前に断るか（`AskGuard` の「先に断る」と命や体の相談。チップは断らない）
    static func refusesTyped(_ text: String) -> Bool {
        AskGuard.declinesBeforeAsking(text) || AskGuard.needsCare(text)
    }

    /// 断ったときの1行（「AI に頼む」と同じ文。命や体の相談には窓口の1行を足す）
    static func refusalLine(_ text: String) -> String {
        AskGuard.needsCare(text) ? AskGuard.refusal + "\n" + AskGuard.careLine : AskGuard.refusal
    }

    /// AI に渡す頼み（条件と日付だけ）。日付の無いプランは条件だけ
    static func request(condition: String, start: String?, end: String?) -> String {
        let cond = String(condition.trimmingCharacters(in: .whitespacesAndNewlines).prefix(typedMax))
        let s = start?.trimmingCharacters(in: .whitespaces) ?? ""
        let e = end?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !s.isEmpty else { return cond }
        return cond + "\n日付: " + (e.isEmpty || e == s ? s : "\(s)〜\(e)")
    }

    /// 答えの題と理由に漏れの形が混じっているか（`AskGuard.leaks`）。混じったら案を出さない
    static func leaks(_ plan: TripAIPlan) -> Bool {
        AskGuard.leaks(plan.title) || AskGuard.leaks(plan.reason)
    }

    // MARK: - 案

    /// 組み直した案。`before` は案を作ったときの今の日程（置き換えるまで画面の日程は変えない）
    struct Proposal: Equatable {
        /// 押したチップか打った条件（「雨なら」）
        let label: String
        let before: [TripDay]
        let after: [TripDay]
        /// この案で外れる場所（置き換えたら日の下の「外しました　戻す」へ）
        let dropped: [TripAIRevise.Dropped]
        /// 並べた理由の1文（無ければ空）
        let reason: String

        /// 入れ替えた行か（その日に前は無かった場所。真鍮の点と淡い地で印を付ける）
        func isChanged(day: Int, index: Int) -> Bool {
            guard after.indices.contains(day), after[day].items.indices.contains(index) else { return false }
            let key = SavedSpotsTrip.itemKey(after[day].items[index])
            guard before.indices.contains(day) else { return true }
            return !before[day].items.contains { SavedSpotsTrip.itemKey($0) == key }
        }

        /// 入れ替えた行の数（読み上げ・UI テストの印）
        var changedCount: Int {
            after.indices.reduce(0) { sum, d in
                sum + after[d].items.indices.filter { isChanged(day: d, index: $0) }.count
            }
        }
    }

    /// AI の答えから案を作る。AI で組めなかった回・見張りで断った回・何も変わらない回は nil
    static func proposal(label: String, before: [TripDay], current: [[OfficialSpot]], result: TripAIResult) -> Proposal? {
        guard result.mode == .ai, !result.refused else { return nil }
        let sent = TripAIRevise.sentIds(current: current, candidates: result.candidates)
        let merged = TripAIRevise.merge(before: before, aiDays: result.days.map { $0.map(\.spotId) }, sent: sent)
        guard merged.days != before else { return nil }
        return Proposal(label: label, before: before, after: merged.days, dropped: merged.dropped, reason: result.reason)
    }

    /// 「この案にする」で置き換える日程。**案を見ている間に日程が変わっていたら**（共有したプランで仲間の変更が届いた）、
    /// 今の日程の上に案で変えた分だけを重ねる（`TripShareText.rebase`・送るときの rev と 409 の道と同じ考え方）
    static func accept(_ proposal: Proposal, current: [TripDay]) -> [TripDay] {
        current == proposal.before ? proposal.after
            : TripShareText.rebase(base: proposal.before, mine: proposal.after, server: current)
    }

    /// 「元に戻す」の控え（置き換える前と、置き換えた直後の日程。棚へ回した場所の番号）
    struct Step: Equatable {
        let before: [TripDay]
        let after: [TripDay]
        /// そのとき「外しました　戻す」の棚へ足した控えの番号（戻すときに棚から外す）
        var shelf: [Int] = []
    }

    /// 「元に戻す」で戻す日程。**置き換えた後に入った変更（共有したプランの仲間の変更など）は残す**:
    /// 置き換えた直後（`after`）から今（`current`）までの変更の上に、置き換えで変えた分だけを戻す
    /// （2026-11-20 判断・札 #667 の確かめ役: 前は置き換える前の日程をそのまま戻し、その後の仲間の変更を消した）
    static func undo(_ step: Step, current: [TripDay]) -> [TripDay] {
        current == step.after ? step.before
            : TripShareText.rebase(base: step.after, mine: step.before, server: current)
    }

    // MARK: - 案にならなかった回の1行

    /// 組み直したあとの札の帯の理由（2026-11-22 判断・Mac run 1729）。
    /// 「AI に送らなかったので」（`.declined`）の札から「AI で整える」を押し、同意して AI に送ったら、もう「送らなかった」とは言わない。
    /// 前は札の理由を「この案にする」を押したときにしか替えず、同意して案が出ても、案が変わらなかった回も、帯が残っていた。
    /// 送った回の結果の理由（AI で組めた、回数、圏外など）に替える。結果が無い、また「やめる」なら今のまま
    static func noteMode(after result: TripAIResult?, current: TripAIResult.Mode) -> TripAIResult.Mode {
        guard current == .declined, let result, result.mode != .declined else { return current }
        return result.mode
    }

    /// 帯から Pro の案内を開けるか（無料の人の、使い切った・端末の AI が無い回だけ。断った回は開かない）
    static func opensPro(_ result: TripAIResult?, isPro: Bool) -> Bool {
        guard let result, !isPro, !result.refused else { return false }
        switch result.mode {
        case .usedUp, .proOnly: return true
        case .limited(let reason): return reason == .day || reason == .month
        default: return false
        }
    }

    /// AI で組めなかった回の帯の文（`nil` は帯を出さない）
    static func failureLine(_ result: TripAIResult?, isPro: Bool) -> String? {
        guard let result else {
            return L("組み直せる観光スポットがありません。", "There are no tourist spots to rearrange.")
        }
        if result.refused { return AskGuard.refusal }
        switch result.mode {
        case .ai:
            return L("今の日程のままがよさそうです。変えるところはありませんでした。", "Your plan already fits. Nothing to change.")
        case .usedUp:
            return isPro ? L("今月の AI の回数を使い切りました。", "You've used all AI tries this month.")
                : L("今月の AI の回数を使い切りました。Pro なら月\(TripAILimits.pro)回", "You've used all AI tries this month. Pro: \(TripAILimits.pro) a month")
        case .limited(let reason):
            let b = AskLimitText.band(reason: reason, usage: nil, answeredByTable: false, kind: .trip, isPro: isPro)
            return [b.title, b.detail].filter { !$0.isEmpty }.joined(separator: "\n")
        case .offline:
            return L("つながっていないため、組み直せませんでした。日程はそのままです。", "You're offline, so the plan wasn't changed.")
        case .silent:
            return L("AI が答えなかったため、組み直せませんでした。日程はそのままです。", "AI didn't answer, so the plan wasn't changed.")
        case .declined:
            return L("AI に送らなかったため、組み直していません。日程はそのままです。", "Not sent to AI, so the plan wasn't changed.")
        case .proOnly:
            return L("この iPhone では AI で組み直せません。Pro ならサーバーの AI で組み直せます。",
                     "AI isn't available on this iPhone. With Pro, our server's AI can do it.")
        }
    }
}
