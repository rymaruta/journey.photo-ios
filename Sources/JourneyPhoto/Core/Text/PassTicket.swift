import Foundation

/// すれちがいのカードを「硬券のきっぷ」にする決まり（案C・**2026-10-16 判断（owner が案C を選んだ）**）。
///
/// 見本は Artifact のすれちがいカードの板 `AltC.dc.html`（表: 写真・「すれちがい乗車券」と No.・明朝の
/// 「札幌 → 京都」・名前と距離と日時・真鍮の破線・「〇〇のあたり 下車」と改札の穴／裏: 真鍮寄りの帯・
/// 「ご案内」・作品名・ひとこと・発行／有効／区間／回数）。種類の見分けは同じ板の `CardKinds.dc.html` の考え
/// （縁と眉ラベルの言葉）をきっぷに当てはめ、「回数」の欄にも出す。
///
/// **2026-10-17 判断（owner「マルス券いいね」）: 表と裏を「マルス券」（日本のきっぷ）の形にした**。見本は Artifact の
/// 候補の板 `Plain.dc.html` の「1. マルス券」と「裏」。表: 写真・種類の名（「乗車券」）と No.・「東京発 → フランス着」・
/// 「経由 〇〇」・日付／区間／回数の3つの欄・名前と「すれちがいの日から ずっと有効」。裏: 真鍮寄りの帯に「ご案内」と
/// No.・作品名・ひとこと・発行／有効／区間／回数・破線・由来の一行。
///
/// **欠けたときの形**（2026-10-16 判断・2026-10-17 にマルス券へ合わせて直した）:
/// - 出身が無い（相手が出さない・居住地が無い）→ 区間の左は「どこか」（「発」を添えるので「どこかから」は
///   「どこかから発」と重なる・2026-10-17 判断）
/// - 場所が取れなかった → 区間の右は「どこか」、「経由」の行は出さない
/// - 距離・日付・回数が出せない → その欄は「—」（欄の並びは崩さない）
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

    /// 帳の小さなきっぷの眉ラベル（`PassTicketSlot`）
    static func eyebrow(_ kind: Kind) -> String {
        switch kind {
        case .plain: return L("すれちがい乗車券", "PASS TICKET")
        case .first: return L("はじめての乗車券", "FIRST PASS")
        // 英語は「PASS」＋番号の形だと右上の番号「No.0002」と数字が並んで紛れるので、回数の言い方にする（2026-10-17 判断）
        case .again(let n): return L("\(n) 度目の乗車券", "AGAIN ×\(n)")
        case .far: return L("遠くからの乗車券", "FROM AFAR")
        }
    }

    /// 小さなきっぷ（帳の札）の名前の行の右に添える種類の言葉（2026-10-17 判断）。小さな札の頭は「乗車券」だけで
    /// 種類の名（`headline`）は入らないので、**色や縁だけで種類を伝えない**ためにここで言う。ふつうは nil（何も添えない）
    static func miniKind(_ kind: Kind) -> String? {
        switch kind {
        case .plain: return nil
        case .first: return L("はじめて", "FIRST")
        case .again(let n): return L("\(n) 度目", "×\(n)")
        case .far: return L("遠くから", "AFAR")
        }
    }

    /// 表の左上（「乗車券」の位置・明朝で字間を空けて真鍮）。**2026-10-17 判断**: 板の「乗車券」の位置に種類の名を
    /// 同じ字組で出す（ふつう＝「乗車券」・ほか＝「はじめての乗車券」など）。**色や縁だけで種類を伝えない**
    /// （眉ラベルの役目をここが引き継ぐ）。ふつうは板どおり「乗車券」だけ
    static func headline(_ kind: Kind) -> String {
        if case .plain = kind { return L("乗車券", "TICKET") }
        return eyebrow(kind)
    }

    /// 欄が空のときの印
    static var blank: String { L("—", "—") }

    /// 欄を読み上げる言葉（「日付 10.17 3時」）。空の印「—」は「ダッシュ」と読まれ得るので、**読み上げだけ「なし」**
    static func spokenField(_ field: Field) -> String {
        "\(field.label) \(field.value == blank ? L("なし", "none") : field.value)"
    }

    /// きっぷの欄（ラベルと値）
    struct Field: Equatable {
        let label: String
        let value: String
    }

    static var dateTitle: String { L("日付", "Date") }
    static var sectionTitle: String { L("区間", "Distance") }
    static var countTitle: String { L("回数", "Times") }

    /// 表の3つの欄（日付・区間・回数）。**値が無い欄は「—」**で、欄は抜かない（格子が崩れない）
    static func frontFields(date: String?, distance: String?, count: String) -> [Field] {
        func filled(_ value: String?) -> String {
            guard let value, !value.isEmpty else { return blank }
            return value
        }
        return [Field(label: dateTitle, value: filled(date)),
                Field(label: sectionTitle, value: filled(distance)),
                Field(label: countTitle, value: filled(count))]
    }

    /// 裏の4つの欄（発行・有効・区間・回数）
    static func backFields(issuer: String, section: String, count: String) -> [Field] {
        [Field(label: L("発行", "Issued by"), value: issuer),
         Field(label: L("有効", "Valid"), value: validity),
         Field(label: sectionTitle, value: section.isEmpty ? blank : section),
         Field(label: countTitle, value: count.isEmpty ? blank : count)]
    }

    /// 表の「経由 〇〇」（〇〇は受け取った側がすれちがった所・前の「〇〇のあたり 下車」の元）。
    /// 場所の記録が無ければ nil（行ごと出さない）
    static func via(_ placeName: String?) -> String? {
        guard let name = placeName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return L("経由 \(name)のあたり", "via \(name)")
    }

    /// 区間の発・着に添える小さな字（明朝 12・text-2）。日本語は名の後ろ（「東京発」）、英語は前（「from Tokyo」）
    static var originMark: String { L("発", "from") }
    static var destinationMark: String { L("着", "to") }
    /// 添える字を名の前に置くか（英語）
    static var marksLead: Bool { Locale.preferredAppLanguage == "en" }

    /// 表の右下（板「すれちがいの日から ずっと有効」）
    static var frontValidity: String { L("すれちがいの日から ずっと有効", "Valid forever") }

    /// 特別な券面の右下（モック「ずっと有効」・2026-10-17）
    static var shortValidity: String { L("ずっと有効", "Valid forever") }

    /// 06 大圏航路の左上（モック「航路乗車券」）。ふつう以外は種類の名（`headline` と同じく種類を言葉で伝える）
    static func routeHeadline(_ kind: Kind) -> String {
        if case .plain = kind { return L("航路乗車券", "ROUTE TICKET") }
        return eyebrow(kind)
    }

    /// 10 箔押しの硬券の空押しの番号（モック「87」）: 「No.0087」から頭の 0 を落とした数。決まらなければ nil
    static func embossedNumber(_ label: String?) -> String? {
        guard let label else { return nil }
        let digits = label.filter(\.isNumber)
        guard let value = Int(digits) else { return nil }
        return String(value)
    }

    /// 裏の裾の一行（届いたカード）
    static var receivedFootnote: String {
        L("この券は、旅先ですれちがった Journey Photo の人から届きました。",
          "This ticket came from a Journey Photo traveler you passed on your trip.")
    }

    /// 裏の裾の一行（自分のカードの見本: 相手の手元に届く側の言い方）
    static var ownFootnote: String {
        L("この券は、旅先ですれちがった人の手元に届きます。",
          "This ticket reaches the people you pass on your trip.")
    }

    /// 表と裏の「回数」の欄
    static func countLabel(_ kind: Kind, meetingCount: Int?) -> String {
        switch kind {
        case .plain: return blank
        case .again(let n): return L("\(n) 度目", "\(n) times")
        case .first, .far:
            return meetingCount == 1 ? L("はじめて", "First time") : blank
        }
    }

    /// 区間の左（出身）。無ければ「どこか」（「発」を添える・2026-10-17 判断）
    static func origin(_ prefecture: String?) -> String {
        guard let prefecture, !prefecture.isEmpty else { return L("どこか", "Somewhere") }
        return shortPlace(prefecture)
    }

    /// 区間の左。**相手が自分で書いた字があればそのまま**（縮めない・2026-10-16 判断）、無ければ自動の形
    static func origin(_ prefecture: String?, written: String?) -> String {
        if let written, !written.isEmpty { return written }
        return origin(prefecture)
    }

    /// 区間の右。相手が自分で書いた字（旅先）があればそのまま、無ければすれちがった所（自動）。
    /// **「経由」の行は書いた字に関わらず、受け取った側の位置で自動**（会った場所の記録は残す・`via`）
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

    /// 表の「日付」の欄（板「10.17 14時」）。**分は出さない**。
    ///
    /// 2026-10-17 判断（マルス券）: 年を落とした。日付の欄は札の幅の 1/3（88pt）で、年まで入れると英語
    /// （「26.10.17 2 PM」）が欄からはみ出す。年は帳の順で分かる
    static func dateLabel(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.gregorianKeepingZone.dateComponents([.month, .day, .hour], from: date)
        let h = c.hour ?? 0
        let day = String(format: "%02d.%02d", c.month ?? 0, c.day ?? 0)
        let hour12 = h % 12 == 0 ? 12 : h % 12
        return L("\(day) \(h)時", "\(day) \(hour12) \(h < 12 ? "AM" : "PM")")
    }

    /// 表の距離（板「1,047 km」）。出せなければ nil（行から外す）
    static func distanceLabel(_ km: Int?) -> String? {
        guard let km, km >= 1 else { return nil }
        return "\(PassExchange.grouped(km)) km"
    }

    /// 裏の「区間」
    static func sectionLabel(_ km: Int?) -> String { distanceLabel(km) ?? blank }

    /// 裏の「発行」（板「札幌の mio.k」）。出身が無ければ名前だけ
    static func issuer(name: String, prefecture: String?) -> String {
        guard let prefecture, !prefecture.isEmpty else { return name }
        return L("\(shortPlace(prefecture))の \(name)", "\(name) of \(prefecture)")
    }

    /// 裏の「有効」
    static var validity: String { L("ずっと（帳に綴じる）", "Forever (kept in your book)") }

    /// 読み上げ: 表の区間（2026-10-17 判断: 札の字と同じく「東京発、フランス着」と読む）
    static func spokenRoute(origin: String, destination: String) -> String {
        L("\(origin)発、\(destination)着", "From \(origin) to \(destination)")
    }
}
