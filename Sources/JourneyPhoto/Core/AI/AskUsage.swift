import Foundation

/// AI の回数（札 #652・2026-11-20 owner 承認）。**どの道で読んでも、答える前にサーバーで1回取る**
/// （`POST /user/trip-ai` `{"action":"reserve","kind":"ask"|"trip","via":"device"|"server"}`）。
///
/// 上限（サーバーが決める。ここの数は返事が無いときの表示だけ・`AskLimits`）:
/// - AI に頼む: 無料 1日3回かつ月10回、Pro 1日20回かつ月300回
/// - 旅行プランの AI: 無料 1日5回かつ月30回、Pro 1日20回かつ月300回
///
/// 取れないとき（429）の `reason`: `day`（今日の分）、`month`（今月の分）、`userCost`（1人ごとの推定金額の止め・月90円）、
/// `global`（アプリ全体の止め・見積もり月400円を1日ごとに割った分）
struct AskUsage: Decodable, Equatable {

    struct Count: Decodable, Equatable {
        let used: Int
        let limit: Int
        let remaining: Int
        /// 月の数だけ持つ（`YYYY-MM-DD`・日本時間の翌月1日）
        var resetsOn: String? = nil
    }

    /// free | pro | admin
    let tier: String
    /// ask | trip
    let kind: String
    let day: Count
    let month: Count
    /// サーバーの AI を使ってよいか（Pro で、1人の止めと全体の止めに達していない）
    let serverAllowed: Bool

    var isPro: Bool { tier == "pro" || tier == "admin" }

    /// 残りの小さな1行（「今日はあと2回、今月はあと7回」）。**少ない方を先に**書く（Artifact 7「残り少ない」）。
    /// 同じ数なら今日を先に
    var remainingLine: String {
        let d = max(day.remaining, 0), m = max(month.remaining, 0)
        let today = L("今日はあと\(d)回", "\(d) left today")
        let thisMonth = L("今月はあと\(m)回", "\(m) left this month")
        return m < d ? L("\(thisMonth)、\(today)", "\(thisMonth), \(today)") : L("\(today)、\(thisMonth)", "\(today), \(thisMonth)")
    }
}

/// 回数の数（返事が無いときの表示だけ。正はサーバーの `tripAiConfig.ts`）
enum AskLimits {
    static let freeDay = 3
    static let freeMonth = 10
    static let proDay = 20
    static let proMonth = 300
    /// 旅行プランの AI の1日の数（月はサーバーの `TRIP_AI_LIMITS` と同じ `TripAILimits`）
    static let tripFreeDay = 5
    static let tripProDay = 20
}

/// 取れなかった理由（429 の `reason`）
enum AskLimitReason: String, Equatable, Codable {
    case day, month, userCost, global
}

/// 回数の帯と言葉（Artifact 7「上限の画面」）。**確かめのダイアログは出さない**。帯は答えの上に1本だけ
enum AskLimitText {

    struct Band: Equatable {
        let title: String
        let detail: String
        /// Pro の案内へ連れて行く1行（無料の人で、今日か今月の分を使い切ったときだけ）
        let proLine: String?
    }

    /// 使い切った・休んでいるときの帯。`answeredByTable` は言葉の表で答えを出し続けたか。
    /// 旅行プランの AI（`kind: .trip`）も同じ形で言い分ける。`isPro` は回数が無いときの Pro かどうか
    static func band(reason: AskLimitReason, usage: AskUsage?, answeredByTable: Bool,
                     kind: AskService.Kind = .ask, isPro knownPro: Bool? = nil) -> Band {
        let isPro = usage?.isPro ?? knownPro ?? false
        let trip = kind == .trip
        let fallback = answeredByTable ? L("言葉で読んで探しました。", "Searched by reading your words.")
            : (trip ? L("AI なしで組みました。", "Planned without AI.") : "")
        let what = trip ? L("旅行プランの AI ", "trip-plan AI") : L(" AI ", "AI")
        let pitch = trip ? L("Pro なら1日\(AskLimits.tripProDay)回、月\(TripAILimits.pro)回", "With Pro: \(AskLimits.tripProDay) a day, \(TripAILimits.pro) a month") : proPitch
        switch reason {
        case .day:
            let limit = usage?.day.limit ?? (trip ? (isPro ? AskLimits.tripProDay : AskLimits.tripFreeDay)
                                                  : (isPro ? AskLimits.proDay : AskLimits.freeDay))
            return Band(title: L("今日の\(what)は\(limit)回使いました。明日また使えます", "You've used today's \(limit) \(what) uses. More tomorrow."),
                        detail: fallback,
                        proLine: isPro ? nil : pitch)
        case .month:
            let limit = usage?.month.limit ?? (trip ? (isPro ? TripAILimits.pro : TripAILimits.free)
                                                    : (isPro ? AskLimits.proMonth : AskLimits.freeMonth))
            let when = (usage?.month.resetsOn).flatMap(TripAIText.monthDay) ?? TripAIText.monthDay(TripAIText.nextReset()) ?? ""
            let back = when.isEmpty ? "" : L("\(when)に戻ります", "Resets \(when).")
            return Band(title: L("今月の\(what)は\(limit)回使いました。\(back)", "You've used this month's \(limit) \(what) uses. \(back)"),
                        detail: fallback,
                        proLine: isPro ? nil : pitch)
        case .userCost:
            return Band(title: L("今月はサーバーの AI を休んでいます", "Server AI is paused for you this month"),
                        detail: fallback + L("回数は使っていません", "This didn't use a count."),
                        proLine: nil)
        case .global:
            return Band(title: L("いまはサーバーの AI を休んでいます", "Server AI is resting for now"),
                        detail: fallback + L("明日の朝に戻ります。回数は使っていません", "It'll be back tomorrow morning. This didn't use a count."),
                        proLine: nil)
        }
    }

    /// Pro の案内の1行（数はサーバーと同じ。天気と光はまだ作っていないので書かない）
    static var proPitch: String {
        L("Pro なら1日\(AskLimits.proDay)回、月\(AskLimits.proMonth)回", "With Pro: \(AskLimits.proDay) a day, \(AskLimits.proMonth) a month")
    }
}
