import Foundation

/// 「はじめての硬貨」の案内の言葉（`TrunkWelcomeView`・2026-10-18 owner 承認）。数は画面で `JPFont.mono` に分けて描くので、
/// 数の前と後ろを別に返す
enum TrunkWelcomeText {
    /// 配る枚数（サーバーの決まり。これより少ない回は上限に当たった）
    static let standardGrant = 10
    /// 持てる硬貨の上限（サーバーの決まり）
    static let coinCap = 99

    static var eyebrow: String { "FIRST COINS · " + L("旅のトランク", "TRAVEL TRUNK") }
    static var title: String { L("はじめての硬貨", "Your first coins") }
    static var thanks: String {
        L("硬貨が始まる前から、写真を投稿してくれたお礼です", "A thank-you for posting before coins began")
    }

    /// 「硬貨 +10 枚」の数の前・数・後ろ（英語は「+10 coins」）
    struct Parts: Equatable {
        let before: String
        let number: String
        let after: String
        var joined: String { [before, number, after].filter { !$0.isEmpty }.joined(separator: " ") }
    }

    static func added(_ n: Int) -> Parts {
        Parts(before: L("硬貨", ""), number: "+\(n)", after: L("枚", n == 1 ? "coin" : "coins"))
    }

    /// 配ったあとの手持ち
    static func total(_ coins: Int) -> Parts {
        Parts(before: L("手持ちの硬貨", "You now have"), number: "\(coins)", after: L("枚", coins == 1 ? "coin" : "coins"))
    }

    /// 上限に当たって 10 枚より少なかった回だけの一言（無ければ nil）
    static func cappedNote(_ added: Int) -> String? {
        guard added > 0, added < standardGrant else { return nil }
        return L("硬貨は\(coinCap)枚まで持てるので、\(added)枚だけ増えました",
                 "You can hold up to \(coinCap) coins, so only \(added) \(added == 1 ? "was" : "were") added")
    }

    /// 硬貨のもらい方と使い道（2行）
    static var howToEarn: String {
        L("公開の投稿1件で、硬貨が1枚もらえます（1日3枚まで）", "Each public post gets you one coin (up to 3 a day)")
    }
    static var whatItDoes: String {
        L("カプセルの機械に入れると、トランクの部品が1つ出てきます", "Put one in the capsule machine to get a part for your trunk")
    }

    static var turn: String { L("カプセルを回す", "Turn the capsule machine") }
    static var later: String { L("あとで", "Later") }
}
