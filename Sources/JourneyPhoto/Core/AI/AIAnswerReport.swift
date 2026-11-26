import Foundation
import Combine

/// AI の答えの報告（2026-11-26 判断・審査 1.2 と 4.7）。AI の答え（「AI に頼む」）と AI の旅行プランの理由に、
/// 「この答えを報告」の道を置く。
///
/// - **送り先は今ある「意見を送る」の口**（`FeedbackService`・`POST /user/feedback`）。サーバーの DB は変えない。
///   どの答えの報告かは `screen`（`ai-ask-report`・`ai-trip-report`）と本文の頭の印で分ける
/// - **送るのは利用者自身の文（頼んだ文）と AI の答えだけ**（CLAUDE.md の AI の決まり）。ほかの利用者の情報、
///   作りの資料、端末の記録は入れない
/// - 報告した答えはその場で隠す（`AIAnswerReports`）。圏外なら下書きに残り、つながったら送る（`FeedbackOutbox`）
enum AIAnswerReport {

    /// どの AI の答えか
    enum Source: String, Equatable {
        /// 「AI に頼む」の答え
        case ask
        /// AI の旅行プラン（並べた理由）
        case tripPlan

        /// 「意見を送る」の `screen`（サーバーは英数字と `-` だけを受ける・40 字まで）
        var screen: String {
            switch self {
            case .ask: return "ai-ask-report"
            case .tripPlan: return "ai-trip-report"
            }
        }
    }

    /// 報告の理由（選ぶのは1つだけ。確かめの段を挟まない）
    enum Reason: String, CaseIterable, Equatable {
        case wrong, harmful, offensive, other

        var label: String {
            switch self {
            case .wrong: return L("内容がまちがっている", "It's wrong")
            case .harmful: return L("危ない内容がある", "It's unsafe")
            case .offensive: return L("不快な内容がある", "It's offensive")
            case .other: return L("その他", "Something else")
            }
        }
    }

    /// 報告の入口の字（答えの下と「…」の中）
    static var action: String { L("この答えを報告", "Report this answer") }
    /// 理由を選ぶ段の見出し
    static var dialogTitle: String { L("この答えを報告する理由", "Why are you reporting this answer?") }
    /// 理由を選ぶ段の説明（何を送るか）
    static var dialogMessage: String {
        L("あなたが頼んだ文と AI の答えを、運営に送ります。答えはこの画面から隠します。",
          "Your request and the AI's answer are sent to our team. The answer is hidden here.")
    }
    /// 隠した答えの代わりの1行
    static var hiddenLine: String { L("報告した答えは隠しました。", "You reported this answer, so it's hidden.") }
    /// 送ったあとの知らせ
    static var thanks: String { L("報告しました。ありがとうございます", "Reported. Thank you.") }
    /// 圏外で、あとで送るとき
    static var later: String { L("報告は、つながったら送ります", "We'll send the report when you're back online") }

    /// 本文の頭の印（運営が「意見」と見分ける）
    static let marker = "[AI answer report]"

    /// 送る本文。**頼んだ文と AI の答えだけ**。合わせて `FeedbackService.textMax`（UTF-16）に収める（答えから削る）
    static func text(source: Source, reason: Reason, question: String?, answer: String) -> String {
        let q = question?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let a = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        var head = "\(marker) \(source.rawValue) reason=\(reason.rawValue)\n"
        if !q.isEmpty { head += "Q: \(q)\n" }
        head += "A: "
        // 頼んだ文が長すぎるときは、頼んだ文も上限の半分までに縮める（答えが入らなくならない）
        if head.utf16.count > FeedbackService.textMax / 2 {
            let cutQ = fit(q, room: FeedbackService.textMax / 2 - 80) ?? ""
            head = "\(marker) \(source.rawValue) reason=\(reason.rawValue)\nQ: \(cutQ)\nA: "
        }
        let room = FeedbackService.textMax - head.utf16.count
        return head + (fit(a, room: room) ?? "")
    }

    /// 「AI に頼む」の答えのうち、AI が書いた所（頭の文と、観光スポットごとの理由）。観光スポットの名前は公開の台帳の物
    static func askAnswerText(_ answer: AskAnswer, spotName: (String) -> String?) -> String {
        var lines = [answer.text]
        if let title = answer.plan?.title, !title.isEmpty { lines.append(title) }
        for id in answer.spotIds {
            guard let reason = answer.reasons?[id], !reason.isEmpty else { continue }
            lines.append("\(spotName(id) ?? id): \(reason)")
        }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// 報告の道を出す答えか。**AI が書いた答えだけ**（言葉の表で答えた、断った、読めなかった答えには出さない）
    static func offersReport(_ answer: AskAnswer) -> Bool {
        answer.usedAI && (answer.state == .answered || answer.state == .offline)
    }

    /// 送る1件（返事は約束しない。報告は運営が読むだけ）
    static func draft(source: Source, reason: Reason, question: String?, answer: String,
                      userId: String?) -> FeedbackDraft {
        FeedbackDraft(text: text(source: source, reason: reason, question: question, answer: answer),
                      screen: source.screen, wantsReply: false, userId: userId)
    }

    /// 字の区切りで UTF-16 の `room` に収める（`FeedbackSheet.fit` と同じ数え方）
    static func fit(_ text: String, room: Int) -> String? {
        guard room > 0 else { return nil }
        if text.utf16.count <= room { return text }
        var cut = ""
        for character in text {
            if (cut + String(character)).utf16.count > room { break }
            cut.append(character)
        }
        return cut.isEmpty ? nil : cut
    }
}

/// 報告した AI の答え（この端末で隠す）。答えの id（`AskExchange.id`・旅行プランは `planId`）で覚える。
/// 端末の中だけ（`UserDefaults`）。多くなりすぎないよう新しい 200 件まで
@MainActor
final class AIAnswerReports: ObservableObject {

    static let shared = AIAnswerReports()

    static let key = "ai.reportedAnswers.v1"
    static let limit = 200

    @Published private(set) var hidden: [String]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hidden = defaults.stringArray(forKey: Self.key) ?? []
    }

    func isHidden(_ id: String) -> Bool { hidden.contains(id) }

    func hide(_ id: String) {
        guard !id.isEmpty, !hidden.contains(id) else { return }
        hidden = Array((hidden + [id]).suffix(Self.limit))
        defaults.set(hidden, forKey: Self.key)
    }

    /// 旅行プランの理由の印（答えの id と重ならないよう頭を付ける）。**理由の文ごと**に覚える
    /// （組み直して理由が替わったら、新しい理由は出す）。文の印は起動をまたいで同じ値になる数え方（FNV-1a）
    nonisolated static func tripKey(_ planId: String, reason: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in reason.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return "trip:\(planId):" + String(hash, radix: 16)
    }
}
