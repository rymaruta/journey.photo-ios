import Foundation

/// とおまわり号の第2段の言葉（友達の車・贈る・薪・届いた・断り。2026-10-19）
extension CamperText {

    // MARK: 断り（`CamperService.Refused`）

    /// サーバーの断りの印（`code`）ごとの一言。知らない印は状態の数で選び、それも無ければサーバーの言い分
    static func refusal(code: String?, status: Int, fallback: String) -> String {
        switch code {
        case "self": return L("自分の車には使えません。", "You can\u{2019}t do this on your own camper.")
        case "notFriend":
            return L("互いにフォローしている友達の車だけです。", "Only for friends who follow each other.")
        case "blocked": return L("この人の車には使えません。", "You can\u{2019}t do this for this person.")
        case "newAccount": return L("登録から7日たつと贈れます。", "You can give gifts 7 days after signing up.")
        case "noPost": return L("公開の投稿を1件してから贈れます。", "Post a public photo first, then you can give gifts.")
        case "notFound": return L("車が見つかりませんでした。", "We couldn\u{2019}t find this camper.")
        case "tombstone": return L("このアカウントは削除されています。", "This account has been deleted.")
        case "already": return L("この友達にはもう贈りました。贈れるのは一人に一度だけです。",
                                 "You\u{2019}ve already given this friend a gift. One gift per friend.")
        case "notLaunched": return L("まだ始まっていません。もうしばらくお待ちください。", "This hasn\u{2019}t started yet. Please check back soon.")
        case "storage": return L("車がいっぱいで、受け取れませんでした。", "The camper is full, so it couldn\u{2019}t be received.")
        case "deleted": return L("あなたのアカウントは削除されています。", "Your account has been deleted.")
        case "daily": return L("贈れるのは1日1回です。また明日どうぞ。", "You can give one gift a day. Try again tomorrow.")
        case "busy": return L("混み合っています。もう一度お試しください。", "It\u{2019}s busy right now. Please try again.")
        default:
            switch status {
            case 429: return L("今日はもうできません。また明日どうぞ。", "You can\u{2019}t do this again today. Try tomorrow.")
            case 410: return L("あなたのアカウントは削除されています。", "Your account has been deleted.")
            case 404: return L("車が見つかりませんでした。", "We couldn\u{2019}t find this camper.")
            case 403: return L("この人の車には使えません。", "You can\u{2019}t do this for this person.")
            default: return fallback.isEmpty ? Labels.Common.loadFailed : fallback
            }
        }
    }

    /// 失敗の一言（断りはその訳・圏外などは `APIError` の言い方）
    static func failure(_ error: Error) -> String {
        if let refused = error as? CamperService.Refused { return refused.errorDescription ?? Labels.Common.loadFailed }
        if case APIError.server(503, _) = error { return refusal(code: "busy", status: 503, fallback: "") }
        return (error as? LocalizedError)?.errorDescription ?? Labels.Common.loadFailed
    }

    // MARK: 友達の車（板 CamperVisit）

    /// 眉ラベル「mio の車 · 訪ねています」
    static func visitEyebrow(owner: String?) -> String {
        let name = owner?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty, name != Labels.Common.unnamedUser, name != "ユーザー", name != "User" else {
            return L("友達の車 · 訪ねています", "A friend\u{2019}s camper · Visiting")
        }
        return L("\(name)の車 · 訪ねています", "\(name)\u{2019}s camper · Visiting")
    }

    /// 車の下の一行（2026-10-19 判断: 飾りのサーバー保存は別の札なので、相手が集めた要サーバーの部品を付けた姿で見せる）
    static func visitCaption(owner: String?) -> String {
        let name = owner?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else {
            return L("友達が集めた部品を付けた姿です", "Shown with the parts your friend has collected")
        }
        return L("\(name)が集めた部品を付けた姿です", "Shown with the parts \(name) has collected")
    }

    /// 訪ねた回が数えられた・訪ねて部品が届いたときの控えめな一言
    static func visitCounted(added: Int) -> String {
        added > 0
            ? L("訪ねた記録を残しました。あなたの車に部品が届きました", "Visit recorded. A part arrived for your camper")
            : L("訪ねた記録を残しました", "Visit recorded")
    }

    /// 友達の車の札の名前「mio が集めた部品」（2026-10-21・全画面の点検 run 609）。
    /// 前は「集めた部品（要サーバー）」と開発の言葉が画面に出ていた。名前が無ければ「友達が集めた部品」
    static func visitPartsTitle(owner: String?) -> String {
        let name = owner?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty, name != Labels.Common.unnamedUser, name != "ユーザー", name != "User" else {
            return L("友達が集めた部品", "Parts your friend collected")
        }
        return L("\(name) が集めた部品", "Parts \(name) collected")
    }

    /// 友達の車の部品の数（0 個は「なし」。相手がトランクを見せない設定でもサーバーは空で返すので、区別しない）
    static func visitParts(_ n: Int) -> String {
        n > 0 ? L("\(n) 個", "\(n)") : L("なし", "None")
    }

    static var giveLabel: String { L("部品を贈る", "Give a part") }
    static var firewoodLabel: String { L("焚き火に薪をくべる", "Add wood to the fire") }

    /// 贈った結果（`part` は相手に届いた部品）
    static func gifted(part: CamperPart?, to owner: String?) -> String {
        let name = owner?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let who = name.isEmpty ? L("友達", "your friend") : name
        guard let part else { return L("\(who)に贈りました", "Sent to \(who)") }
        return L("\(who)に贈りました。「\(part.name)」が届きました", "Sent to \(who). \(part.name) arrived on their camper")
    }

    /// 薪をくべた結果（今日もうくべていた回は数だけ）
    static func firewood(added: Bool, count: Int) -> String {
        added ? L("薪をくべました（\(count) 回目）", "You added wood (\(count) so far)")
            : L("今日はもうくべました（\(count) 回）。また明日どうぞ", "Already added today (\(count) so far). Come back tomorrow")
    }

    // MARK: 届いた（板 CamperGet）

    /// 届いた理由。贈り物は贈ってくれた人の名前（名前の無い人・退会した人は「友達から」）
    static func because(_ part: CamperPart, giver: String?) -> String {
        guard let giver else { return part.unlock.because }
        let name = giver.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? L("友達から贈られました", "A gift from a friend") : L("\(name)から贈られました", "A gift from \(name)")
    }

    /// 一度に届いた他の部品の見出し「ほかに 2 個届きました」
    static func alsoArrived(_ n: Int) -> String { L("ほかに \(n) 個届きました", "\(n) more arrived") }
}
