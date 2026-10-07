import Foundation

/// App Store の評価をお願いしてよいか（画面を持たない決まり・2026-10-07）。
///
/// 全国の戦略（`Journey Photo 全国で人気になるための戦略`）の「評価を集める」から。
/// 2026-09-28 から App Store で公開しているが**評価が0件**で、ストアで見つけてもらいにくい。
///
/// **うれしい瞬間のあとにだけ、控えめに**:
///  - 投稿が全部上がった・「行きたい」に入れた、を数え、`happyMomentsNeeded` 回たまったら1回だけ
///  - **同じ版では二度お願いしない**（版が上がって使い続けてくれた人にだけ、もう一度）
///  - 前にお願いしてから `minimumDaysBetween` 日は空ける
/// 本当に出すかどうかは OS が決める（年に3回まで・TestFlight では出ない）。
/// こちらの決まりは「OS に頼む回数をさらに絞る」ためのもの
enum ReviewPrompt {

    /// お願いするまでに要る、うれしい瞬間の数
    static let happyMomentsNeeded = 3
    /// 前にお願いしてから空ける日数
    static let minimumDaysBetween = 90

    static func shouldAsk(happyMoments: Int, currentVersion: String,
                          lastAskedVersion: String?, lastAskedAt: Date?, now: Date) -> Bool {
        let version = currentVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard happyMoments >= happyMomentsNeeded, !version.isEmpty else { return false }
        if let lastAskedVersion, lastAskedVersion == version { return false }
        if let lastAskedAt, now.timeIntervalSince(lastAskedAt) < Double(minimumDaysBetween) * 86_400 {
            return false
        }
        return true
    }
}
