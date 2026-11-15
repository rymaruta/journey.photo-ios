import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 端末の AI（Apple の Foundation Models・iOS 26 以上・Apple Intelligence の機種）で組む（札 #621）。
///
/// - 使えるかはアプリが自動で決める（`isAvailable`）。設定の行は作らない（案「推奨で決めた既定」）
/// - 答えは `@Generable` の型で受け、候補の番号を 1...20 に縛る（形の崩れた答えを出さない）。
///   候補が 20 件より少ないときの範囲の外の番号は `TripAIPlan.sanitized` が落とす
/// - 文脈は 4,096 トークン。毎回「今の日程と頼み」だけを送る（会話の履歴は持たない）
/// - 2026-11-15: Mac の CI のシミュレーター（macos-15-arm64・Xcode 26.3）では `modelNotReady` で使えなかった
///   （run 1380 の `measured [trip-ai]`）。端末の AI の出来は実機でしか確かめられない
enum TripAIDevice {

    /// この iPhone で端末の AI を使えるか（日本語に対応していることも見る）
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else { return false }
            return model.supportsLocale(Locale(identifier: "ja_JP"))
        }
        #endif
        return false
    }

    /// 指示（サーバーの `SYSTEM_PROMPT` と同じ決まり。答えの形は型で縛るので JSON の説明は要らない）
    static let instructions = """
    あなたは日本の旅行プランを組む係です。利用者の頼みと、番号つきの観光スポットの候補を受け取ります。
    決まり:
    - 場所は候補の番号からだけ選ぶ。候補に無い場所を作らない。同じ番号を2回使わない。
    - 日数が指定されていればそれに従う。
    - 1日に2〜5か所。「ゆっくり」なら1日3か所まで。「半日」なら2〜3か所。
    - 同じ日の場所は近いものでまとめる。日の中は、朝に向く所を先、夕方と夜に向く所を後にする。
    - 時刻は書かない。
    - 頼みの好み（夜景、朝、夕方、雨の日、温泉、季節など）に合う候補を優先する。雨の日は屋内を選ぶ。
    - 今の日程が渡されたら、頼みに合わせて直す。
    - 理由は日本語で1文、40字まで。候補の外の地名を書かない。
    """

    /// 端末の AI で組む。使えない・断られた・時間切れは throw（呼び手は AI なしの組み方へ）
    static func plan(message: String, days: Int?) async throws -> TripAIPlan {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: instructions)
            let answer = try await session.respond(to: message, generating: TripAIDeviceAnswer.self).content
            return TripAIPlan(title: answer.title, days: days ?? answer.days,
                              stops: answer.stops.map { .init(n: $0.n, day: $0.day) }, reason: answer.reason)
        }
        #endif
        throw TripAIService.Failure.unavailable
    }

    /// AI に渡す文（サーバーの `userMessage` と同じ形）
    static func message(request: String, days: Int?, candidates: [OfficialSpot], current: [TripAIPlan.Stop]) -> String {
        var lines = ["頼み: \(request)"]
        if let days { lines.append("日数: \(days)") }
        if !current.isEmpty { lines.append("今の日程: " + current.map { "\($0.day)日目:\($0.n)" }.joined(separator: " ")) }
        lines.append("候補:")
        for (i, s) in candidates.enumerated() {
            let area = [s.region?.prefecture, s.region?.city, s.category].compactMap { $0 }.joined(separator: "、")
            var tags: [String] = []
            let seasons = s.seasonKeys.compactMap(SpotBodyText.seasonLabel)
            let times = s.timeKeys.compactMap(SpotBodyText.timeLabel)
            if !seasons.isEmpty { tags.append("季節:" + seasons.joined(separator: "/")) }
            if !times.isEmpty { tags.append("時間帯:" + times.joined(separator: "/")) }
            lines.append("\(i + 1). \(s.name)（\(area)）" + (tags.isEmpty ? "" : " " + tags.joined(separator: " ")))
        }
        return lines.joined(separator: "\n")
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct TripAIDeviceAnswer {
    @Guide(description: "日数。日帰りは1、1泊2日は2、2泊3日は3")
    var days: Int
    @Guide(description: "短い題。12字まで")
    var title: String
    @Guide(description: "選んだ候補。番号と何日目", .count(1...20))
    var stops: [TripAIDeviceStop]
    @Guide(description: "並べた理由。日本語で1文、40字まで")
    var reason: String
}

@available(iOS 26.0, *)
@Generable
struct TripAIDeviceStop {
    @Guide(description: "候補の番号", .range(1...20))
    var n: Int
    @Guide(description: "何日目", .range(1...7))
    var day: Int
}
#endif
