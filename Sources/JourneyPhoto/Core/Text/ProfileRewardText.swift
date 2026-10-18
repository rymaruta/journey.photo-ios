import Foundation

/// 硬貨の全画面（`TrunkWelcomeView`）の言葉と目印。はじめての硬貨と、アイコン・カバーのお礼（#304・板 53）で替える
struct TrunkCoinNoticeCopy: Equatable {
    struct Row: Equatable {
        let symbol: String
        let text: String
    }

    /// 画面と押せるものの目印の頭（`trunk.welcome`・`coinReward`）
    let id: String
    let eyebrow: String
    let title: String
    let thanks: String
    /// 内訳（両方まとめて渡した回の「アイコン +3 · カバー +3」）。無ければ nil
    let breakdown: String?
    /// 上限に当たって少なかった回の一言。無ければ nil
    let cappedNote: String?
    /// もらい方の行（2行目は使い道で共通）
    let firstRow: Row

    /// はじめての硬貨（2026-10-18 owner 承認）
    static func welcome(_ grant: TrunkWelcome.Grant) -> TrunkCoinNoticeCopy {
        TrunkCoinNoticeCopy(id: "trunk.welcome", eyebrow: TrunkWelcomeText.eyebrow, title: TrunkWelcomeText.title,
                            thanks: TrunkWelcomeText.thanks, breakdown: nil,
                            cappedNote: TrunkWelcomeText.cappedNote(grant.added),
                            firstRow: Row(symbol: "photo.on.rectangle", text: TrunkWelcomeText.howToEarn))
    }

    /// アイコン・カバーを初めて設定したお礼（板 53）
    static func reward(_ grant: ProfileReward.Grant) -> TrunkCoinNoticeCopy {
        TrunkCoinNoticeCopy(id: "coinReward", eyebrow: ProfileRewardText.eyebrow, title: ProfileRewardText.title(grant),
                            thanks: ProfileRewardText.thanks(grant), breakdown: ProfileRewardText.breakdown(grant),
                            cappedNote: ProfileRewardText.cappedNote(grant),
                            firstRow: Row(symbol: "person.crop.circle", text: ProfileRewardText.onceEach))
    }
}

/// アイコン・カバーのお礼の言葉（板 53 CoinReward の文言どおり）
enum ProfileRewardText {
    /// 1つ設定したときの枚数（サーバーの `REWARD_COINS`。これより少ない回は上限に当たった）
    static let coinsPerKind = 3

    static var eyebrow: String { L("旅のトランク · 硬貨", "TRAVEL TRUNK · COINS") }

    static func title(_ grant: ProfileReward.Grant) -> String {
        if grant.kinds.count > 1 { return L("アイコンとカバーのお礼", "Thanks for your avatar and cover") }
        return grant.kinds.first == .cover ? L("カバーを設定したお礼", "Thanks for setting a cover")
                                           : L("アイコンを設定したお礼", "Thanks for setting an avatar")
    }

    static func thanks(_ grant: ProfileReward.Grant) -> String {
        if grant.existing { return L("前から設定してくれていたお礼です。", "A thank-you for setting it up already.") }
        if grant.kinds.count > 1 {
            return L("あなたの顔と1枚が、あなたのページに並びます。", "Your face and your photo now lead your page.")
        }
        return grant.kinds.first == .cover
            ? L("あなたのページのいちばん上に、あなたの1枚が出ます。", "Your photo now sits at the top of your page.")
            : L("コメントの横やあなたのページに、あなたの顔が並びます。", "Your face now shows beside your comments and on your page.")
    }

    /// 両方まとめた回だけの内訳
    static func breakdown(_ grant: ProfileReward.Grant) -> String? {
        guard grant.kinds.count > 1 else { return nil }
        return L("アイコン +\(coinsPerKind) · カバー +\(coinsPerKind)", "Avatar +\(coinsPerKind) · Cover +\(coinsPerKind)")
    }

    /// 上限に当たって、決まりの枚数より少なかった回の一言
    static func cappedNote(_ grant: ProfileReward.Grant) -> String? {
        let full = coinsPerKind * max(1, grant.kinds.count)
        guard grant.added > 0, grant.added < full else { return nil }
        return L("硬貨は\(TrunkWelcomeText.coinCap)枚まで持てるので、\(grant.added)枚だけ増えました",
                 "You can hold up to \(TrunkWelcomeText.coinCap) coins, so only \(grant.added) \(grant.added == 1 ? "was" : "were") added")
    }

    static var onceEach: String {
        L("アイコンとカバーで、それぞれ1回だけ。付け直しても、もう一度はもらえません。",
          "Once each for your avatar and cover. Changing them again won't earn more.")
    }
}
