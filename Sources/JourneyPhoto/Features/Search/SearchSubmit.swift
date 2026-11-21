import Foundation

/// 探すの欄の字を、いつ結果に渡すか（画面を持たない層・`SearchSubmitTests`）。
///
/// 2026-11-21 判断（札 #675・owner「検索窓は基本的に、観光スポットやユーザが投稿した写真に機能したら嬉しくて、
/// AIに頼むは完全に独立して」）: **探すの欄は探すだけに戻す。** 打つたびに結果を出し（人は 0.3 秒待ってから・`SearchViewModel.search`）、
/// AI は呼ばない。AI に頼むは別の画面（`AskScreen`）。#662 の「送信を押すまで結果を出さない」は AI の回数を守るための決まりで、
/// 探すが AI を呼ばなくなったので要らない。
/// - 頼みの形（`AskQuery.form == .ask`）を打ったときは、結果のいちばん上に「✦ AI に頼む」の1行（押すと AI の画面へ字を持って移る。
///   押すまで AI は呼ばない）
/// - キーボードの「検索」は、語を並べた文を言葉の表で読む（「こう読みました」・AI は使わない）とキーボードを閉じるだけ
enum SearchSubmit {

    enum Trigger: Equatable {
        /// 欄の字が変わった（打った・消した）
        case typed
        /// 欄の × で全部消した
        case cleared
        /// キーボードの「検索」
        case keyboard
        /// 最近の語を押した
        case recent
    }

    struct Plan: Equatable {
        /// 新しい探す字（nil は今のまま）
        var searched: String?
        /// 言葉の表で読む（「こう読みました」・AI は呼ばない）
        var readsSentence = false

        static let none = Plan()
    }

    static func plan(_ trigger: Trigger, text: String, scope: SearchScope, searched: String) -> Plan {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trigger {
        case .typed:
            // 打つたびに探す（2026-11-21 判断）
            return text == searched ? .none : Plan(searched: text)
        case .cleared:
            return Plan(searched: "")
        case .keyboard, .recent:
            guard !trimmed.isEmpty else { return .none }
            return Plan(searched: text, readsSentence: scope != .people)
        }
    }

    /// 結果のいちばん上に「✦ AI に頼む」の1行を出すか（頼みの形の字のとき。人を探すときは出さない）
    static func showsAskRow(text: String, scope: SearchScope) -> Bool {
        AskQuery.form(text, scope: scope) == .ask
    }
}

/// 「AI に頼む」の入口と画面の言葉と決まり（札 #675・2026-11-21 判断・画面を持たない層・`AskEntryTests`）
enum AskEntry {

    static var title: String { L("AI に頼む", "Ask AI") }
    /// 入口のボタンの読み上げ（字を出さない形でも同じ名前）
    static var buttonLabel: String { title }
    static var fieldPrompt: String { L("AI に頼む", "Ask AI") }
    /// 送信のボタンの読み上げ
    static var sendLabel: String { L("AI に送る", "Send to AI") }
    static var startersLead: String { L("旅のことを、何でも頼めます", "Ask anything about your trip") }
    /// 探すの結果の上の1行の題
    static var askRowTitle: String { L("AI に頼む", "Ask AI") }
    static func askRowDetail(_ text: String) -> String { L("「\(text)」", "\"\(text)\"") }

    /// 頼む先。旅行プランを作る頼みは旅行プランの AI（`TripAIAskSheet` → `TripAIJobs`）、それ以外は AI に頼む（`AskEngine`）
    enum Route: Equatable { case ask, tripPlan }

    static func route(_ text: String) -> Route {
        let reading = SearchSentence.readByTable(text)
        return AskQuery.intent(text, reading: reading).plan ? .tripPlan : .ask
    }

    /// 送信のボタンで送れるか。AI の画面では、打った字はどれも AI に頼む字（探すの語の形でもよい）。
    /// 途中の字（「おすすめの」「京都で」）だけは送らない（#662 の決まり・回数を使わない）
    static func sendEnabled(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count >= 2 && !AskQuery.isUnfinished(t)
    }

    /// 欄の下に「続けて打つと AI に聞けます」を出すか
    static func showsKeepTyping(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && AskQuery.isUnfinished(t)
    }

    /// 例の頼みの札（押すと欄に入るだけ）
    struct Starter: Identifiable, Equatable {
        var id: String { kind }
        let kind: String
        let text: String
    }

    /// 例は観光スポット、近くで、旅行プラン、使い方だけ（アプリの作りに触れる例は置かない・CLAUDE.md）
    static func starters(month: Int) -> [Starter] {
        let examples = AskQuery.examples(month: month)
        return [
            Starter(kind: L("観光スポットを探す", "Find spots"), text: examples[1]),
            Starter(kind: L("近くで探す", "Nearby"), text: examples[0]),
            Starter(kind: L("旅行プランを作る", "Make a trip plan"), text: examples[3]),
            Starter(kind: L("使い方を聞く", "How to"), text: L("ストーリーに曲を付けるには", "How do I add music to a story?")),
        ]
    }
}
