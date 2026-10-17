import Foundation

/// すれちがいのカードを「硬券のきっぷ」にする決まり（案C・**2026-10-16 判断（owner が案C を選んだ）**）。
///
/// 見本は Artifact のすれちがいカードの板 `AltC.dc.html`（表: 写真・「すれちがい乗車券」と No.・明朝の
/// 「札幌 → 京都」・名前と距離と日時・真鍮の破線・「〇〇のあたり 下車」と改札の穴／裏: 真鍮寄りの帯・
/// 「ご案内」・作品名・ひとこと・発行／有効／区間／回数）。種類の見分けは同じ板の `CardKinds.dc.html` の考え
/// （縁と眉ラベルの言葉）をきっぷに当てはめ、「回数」の欄にも出す。
///
/// **欠けたときの形**（2026-10-16 判断）:
/// - 出身が無い（相手が出さない・居住地が無い）→ 区間の左は「どこかから」
/// - 場所が取れなかった → 区間の右は「どこか」、下車の行は「下車駅の記録なし」
/// - 距離が出せない（どちらかが無い）→ 表の距離は出さず、裏の「区間」は「—」
/// - 持ち主が分からない → 回数は数えず、種類は「ふつう」
enum PassTicket {

    /// 種類（縁の光り方と眉ラベルの言葉で見分ける・色だけに頼らない）
    enum Kind: Equatable {
        /// 持ち主が分からない（数えられない）: 細い真鍮の線1本
        case plain
        /// その人と初めて: 縁が光る真鍮
        case first
        /// 同じ人と2度目から: 2本線の縁
        case again(Int)
        /// 住まいから `farKm` 以上: 上から下へ沈む真鍮の縁
        case far(Int)
    }

    /// 「遠くから」の線（板 CardKinds「住まいから 500 km 以上」）
    static let farKm = 500

    /// 種類を決める。**また会えた > 遠くから > はじめて > ふつう**（2026-10-16 判断: 同じ人とまた会えたことを
    /// いちばん先に言う。初めての人の多くは「はじめて」なので、遠いときだけ「遠くから」に上げる）
    static func kind(meetingCount: Int?, km: Int?) -> Kind {
        guard let count = meetingCount else { return .plain }
        if count >= 2 { return .again(count) }
        if let km, km >= farKm { return .far(km) }
        return .first
    }

    /// 表の眉ラベル（左）
    static func eyebrow(_ kind: Kind) -> String {
        switch kind {
        case .plain: return L("すれちがい乗車券", "PASS TICKET")
        case .first: return L("はじめての乗車券", "FIRST PASS")
        case .again(let n): return L("\(n) 度目の乗車券", "PASS NO. \(n)")
        case .far: return L("遠くからの乗車券", "FROM AFAR")
        }
    }

    /// 裏の「回数」の欄
    static func countLabel(_ kind: Kind, meetingCount: Int?) -> String {
        switch kind {
        case .plain: return L("—", "—")
        case .again(let n): return L("\(n) 度目", "\(n) times")
        case .first, .far:
            return meetingCount == 1 ? L("はじめて", "First time") : L("—", "—")
        }
    }

    /// 区間の左（出身）。無ければ「どこかから」
    static func origin(_ prefecture: String?) -> String {
        guard let prefecture, !prefecture.isEmpty else { return L("どこかから", "Somewhere") }
        return shortPlace(prefecture)
    }

    /// 区間の左。**相手が自分で書いた字があればそのまま**（縮めない・2026-10-16 判断）、無ければ自動の形
    static func origin(_ prefecture: String?, written: String?) -> String {
        if let written, !written.isEmpty { return written }
        return origin(prefecture)
    }

    /// 区間の右。相手が自分で書いた字（旅先）があればそのまま、無ければすれちがった所（自動）。
    /// **下車の行は書いた字に関わらず、受け取った側の位置で自動**（会った場所の記録は残す・`alighting`）
    static func destination(_ placeName: String?, written: String?) -> String {
        if let written, !written.isEmpty { return written }
        return destination(placeName)
    }

    /// 乗車券選びの見本の区間の左（選んだ発をその場で出す）
    static func previewOrigin(_ choice: PassSettings.Origin, text: String, homePrefecture: String?) -> String {
        switch choice {
        case .home: return origin(homePrefecture)
        case .hidden: return origin(nil)
        case .custom: return origin(nil, written: PassExchange.cleanLabel(text))
        }
    }

    /// 乗車券選びの見本の区間の右（自動はすれちがう所なので「旅先」）
    static func previewDestination(custom: Bool, text: String) -> String {
        let written = custom ? PassExchange.cleanLabel(text) : ""
        return written.isEmpty ? L("旅先", "Your trip") : written
    }

    /// 区間の右（すれちがった場所）。無ければ「どこか」
    static func destination(_ placeName: String?) -> String {
        guard let name = placeName?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
            return L("どこか", "Somewhere")
        }
        return shortPlace(name)
    }

    /// きっぷに載せる短い地名: 都府県の「都・府・県」と、市の「市」を落とす（北海道・区・町・村はそのまま）。
    /// 残りが1字になるときは落とさない
    static func shortPlace(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed != "北海道" else { return trimmed }
        for suffix in ["都", "府", "県", "市"] where trimmed.hasSuffix(suffix) && trimmed.count >= 3 {
            return String(trimmed.dropLast())
        }
        return trimmed
    }

    /// 表の日時（板「26.10.16 15時」）。**分は出さない**
    static func dateLabel(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.gregorianKeepingZone.dateComponents([.year, .month, .day, .hour], from: date)
        let y = (c.year ?? 0) % 100, h = c.hour ?? 0
        let day = String(format: "%02d.%02d.%02d", y, c.month ?? 0, c.day ?? 0)
        let hour12 = h % 12 == 0 ? 12 : h % 12
        return L("\(day) \(h)時", "\(day) \(hour12) \(h < 12 ? "AM" : "PM")")
    }

    /// 表の下の行（板「清水寺のあたり 下車」）
    static func alighting(_ placeName: String?) -> String {
        guard let label = PassExchange.placeLabel(placeName) else { return L("下車駅の記録なし", "No stop recorded") }
        return L("\(label) 下車", "Got off \(label)")
    }

    /// 表の距離（板「1,047 km」）。出せなければ nil（行から外す）
    static func distanceLabel(_ km: Int?) -> String? {
        guard let km, km >= 1 else { return nil }
        return "\(PassExchange.grouped(km)) km"
    }

    /// 裏の「区間」
    static func sectionLabel(_ km: Int?) -> String { distanceLabel(km) ?? L("—", "—") }

    /// 裏の「発行」（板「札幌の mio.k」）。出身が無ければ名前だけ
    static func issuer(name: String, prefecture: String?) -> String {
        guard let prefecture, !prefecture.isEmpty else { return name }
        return L("\(shortPlace(prefecture))の \(name)", "\(name) of \(prefecture)")
    }

    /// 裏の「有効」
    static var validity: String { L("ずっと（帳に綴じる）", "Forever (kept in your book)") }

    /// 読み上げ: 表の区間（矢印は「から」と読む）
    static func spokenRoute(origin: String, destination: String) -> String {
        let from = origin.hasSuffix("から") ? origin : origin + "から"
        return L("\(from)\(destination)", "\(origin) to \(destination)")
    }
}
