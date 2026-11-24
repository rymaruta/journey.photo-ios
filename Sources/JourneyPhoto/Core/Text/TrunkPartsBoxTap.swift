import Foundation

/// 部品箱の言葉（押すとその場で付く・2026-11-23 判断・札 #711）
extension TrunkPartsBoxText {

    /// 付けた・外した知らせの「元に戻す」と、出している時間（案: 3 秒）
    static var undoTitle: String { L("元に戻す", "Undo") }
    static let undoSeconds: TimeInterval = 3

    static func equippedNotice(_ part: TrunkPart, on: Bool) -> String {
        on ? L("「\(part.name)」を付けました", "Put on \u{201C}\(part.name)\u{201D}")
            : L("「\(part.name)」を外しました", "Took off \u{201C}\(part.name)\u{201D}")
    }

    /// 上の小さいトランクの左上（「9 / 108 集めました」）
    static func collectedCaption(owned: Int, total: Int) -> String {
        L("\(owned) / \(total) 集めました", "\(owned) / \(total) collected")
    }

    /// 格子の下の一行
    static var tapHint: String { L("押すと付けます。もう一度押すと外します。", "Tap to put it on. Tap again to take it off.") }

    /// 持っていない部品を押したシート
    static var missingTitle: String { L("まだ持っていない部品です", "You don\u{2019}t have this part yet") }

    static func missingNote(fragments: Int) -> String {
        let need = fragmentsPerExchange
        let gacha = L("カプセルを回すと出ることがあります。", "It may come out of the capsule machine.")
        if canExchange(fragments: fragments) {
            return gacha + L("かけらが\(need)つあるので、この部品と交換できます。",
                             " You have \(need) fragments, so you can exchange them for this part.")
        }
        let left = need - max(0, fragments)
        return gacha + L("かけらがあと\(left)つたまると、好きな部品と交換できます。",
                         " \(left) more fragments and you can exchange them for any part.")
    }

    /// 交換のボタン。**何と交換するかを部品の名前で言う**（2026-11-23 確かめ役の指摘: 「かけら5つで交換する」だけでは、
    /// 確かめを出さずに押す決まりなのに、何が手に入るかがボタンから読めなかった）
    static func exchangeTitle(_ part: TrunkPart) -> String {
        let need = fragmentsPerExchange
        return L("かけら\(need)つで「\(part.name)」と交換する",
                 "Exchange \(need) fragments for \u{201C}\(part.name)\u{201D}")
    }

    /// 交換のボタンを押せないか（頼んでいる間・通って閉じるまで）
    static func exchangeLocked(busy: Bool, exchanging: Bool) -> Bool { busy || exchanging }

    static func exchangedNotice(_ part: TrunkPart) -> String {
        L("「\(part.name)」を部品箱に入れました", "\u{201C}\(part.name)\u{201D} is in your parts box")
    }

    /// 下の帯の硬貨（押すとカプセルの機械）
    static func coinsTitle(_ coins: Int) -> String { L("硬貨 \(coins) 枚", Plural.count(coins, "coin")) }
    static var fragmentsCaption: String { L("かけら", "Fragments") }
}
