import Foundation

/// 探すの欄の字を、いつ結果と AI の答えに渡すか（2026-11-20 判断・札 #662）。画面を持たない層（`SearchSubmitTests`）。
///
/// owner「AIに聞く機能は、送信ボタン押すまで結果でてきて欲しくない」「文字打つだけでAI使われると結構すぐ上限きてしんどい」（2026-11-20）。
/// - ✦ の欄（人を探す以外）は、**打っている間は結果を変えない**。今の画面（空なら最近の検索と発見、前に送った結果があればその結果）のまま
/// - 結果に使う字は「送った字」（`searched`）。欄の字（`query`）とは別に持つ
/// - **AI を呼ぶのは欄の右の送信のボタンだけ**。キーボードの「検索」は言葉の検索（言葉の表の読み取り）とキーボードを閉じるだけ
///   （日本語のキーボードは変換を確定したあと同じ場所のキーが「検索」になり、確定のつもりで押すと送ってしまう）
/// - 途中の字（「おすすめの」）はボタンを押しても AI を呼ばない（`AskQuery.isUnfinished`）
/// - 打ち替えても前の結果と答えは残し、次に送ったときに入れ替える。欄を空にしたときだけ最初の画面に戻す
/// - 「人」の切り替えでは、今のまま打つたびに探す
/// - 最近の語、タグのチップは送ったのと同じ（すぐ結果）。最近の語は、今日答えた控えがあるときだけ答えを出す（AI は呼ばない）
enum SearchSubmit {

    enum Trigger: Equatable {
        /// 欄の字が変わった（打った・消した）
        case typed
        /// 欄の × で全部消した
        case cleared
        /// キーボードの「検索」
        case keyboard
        /// 欄の右の送信のボタン
        case sendButton
        /// 最近の語を押した。`cachedToday` は今日すでに答えた控えがあるか
        case recent(cachedToday: Bool)
        /// 「人」に切り替えた
        case peopleScope
    }

    struct Plan: Equatable {
        /// 新しい送った字（nil は今のまま＝結果を変えない）
        var searched: String?
        /// AI の答えを始める（`AskEngine.start`。控えがあれば控えから出す）
        var asks = false
        /// 言葉の表で読む（「こう読みました」・AI は呼ばない）
        var readsSentence = false
        /// 出している答えを閉じる
        var closesAnswer = false

        static let none = Plan()
    }

    static func plan(_ trigger: Trigger, text: String, scope: SearchScope, searched: String) -> Plan {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trigger {
        case .typed:
            // 人は今のまま打つたびに探す
            if scope == .people { return text == searched ? .none : Plan(searched: text) }
            // 欄を空にした（× と同じ）: 最初の画面に戻す
            if trimmed.isEmpty { return searched.isEmpty ? Plan(closesAnswer: true) : Plan(searched: "", closesAnswer: true) }
            // 打っている間は結果も答えも変えない
            return .none
        case .cleared:
            return Plan(searched: "", closesAnswer: true)
        case .peopleScope:
            return text == searched ? .none : Plan(searched: text)
        case .keyboard:
            // AI は呼ばない。言葉の検索に入れ替える（答えは閉じる）
            guard !trimmed.isEmpty else { return .none }
            return Plan(searched: text, readsSentence: scope != .people, closesAnswer: true)
        case .sendButton:
            guard AskQuery.sendsToAI(text, scope: scope) else { return .none }
            return Plan(searched: text, asks: true)
        case .recent(let cachedToday):
            guard !trimmed.isEmpty else { return .none }
            if cachedToday, AskQuery.form(text, scope: scope) == .ask { return Plan(searched: text, asks: true) }
            return Plan(searched: text, readsSentence: scope != .people, closesAnswer: true)
        }
    }

    /// 欄の右の送信のボタンを出すか（字があり、頼みと質問の形のときだけ）。
    /// 2026-11-20 判断: 頼みの形でない字（「京都 紅葉」）にはボタンを出さない。言葉の検索はキーボードの「検索」で足りて、
    /// 同じ場所に形の違う2つのボタン（AI に送る／探す）を出し分けると、押す前に何が起きるか分からなくなる
    static func showsSendButton(text: String, scope: SearchScope) -> Bool {
        AskQuery.form(text, scope: scope) == .ask
    }

    /// 送信のボタンを押せるか（途中の字では押せない形で出す）
    static func sendEnabled(text: String, scope: SearchScope) -> Bool {
        AskQuery.sendsToAI(text, scope: scope)
    }

    /// 欄の下の「続けて打つと AI に聞けます」を出すか
    static func showsKeepTyping(text: String, scope: SearchScope) -> Bool {
        showsSendButton(text: text, scope: scope) && !sendEnabled(text: text, scope: scope)
    }

    /// 送信のボタンの読み上げ
    static var sendLabel: String { L("AI に送る", "Send to AI") }
}
