import Foundation

/// すれちがった1回の記録（端末の中だけ・`PassStore` が JSON で持つ）。
///
/// **持たないもの**: 相手の端末の識別子・分の単位の時刻・細かい位置。持つのは、相手が載せた中身
/// （写真の id・ひとこと・出身を出すか）と、時の単位の時刻と、取れたときだけの粗い場所。
struct PassEncounter: Codable, Equatable, Identifiable {
    var id: String
    /// 相手の名刺の一枚（公開写真の id）
    var photoId: String
    var note: String
    var showsFrom: Bool
    /// すれちがった時（**時の単位に丸めてある**）
    var metHour: Date
    /// 届く時（夕方 18 時・`PassExchange.deliveryDate`）
    var deliverAt: Date
    /// 場所（市区町村の名前。取れたときだけ）
    var placeName: String?
    /// 場所の座標（0.1 度に丸めたもの。取れたときだけ）
    var placeLat: Double?
    var placeLng: Double?
    /// 帳に綴じた順の番号（1から）
    var number: Int
    /// 束を開いて見たか
    var opened: Bool
    /// 写真の持ち主（届いた後、公開一覧から引いたもの）
    var ownerId: String?
    /// ひとことを伏せた（カードの「…」・この端末だけ）。前の版の記録には無いので省略できる形
    var noteHidden: Bool? = nil
    /// ひとことを通報した（写真を通報するときに補足に一緒に入れる・`ReportSheet.carriedPassNote`）
    var noteReported: Bool? = nil
    /// 相手が乗車券の「発」「着」に自分で書いた字（2026-10-16・無ければ自動の形）。署名は無い
    var originLabel: String? = nil
    var destinationLabel: String? = nil
    /// 区間の字を伏せた（伏せたら自動の形に戻す・この端末だけ）
    var labelsHidden: Bool? = nil

    /// 見せるひとこと（伏せていれば空）
    /// 見せるひとこと（伏せていれば空）。**連絡先の形（URL・メール・電話番号）を含む字は出さない**
    /// （2026-10-16 owner の決定・`ContactText`。前のアプリや手を加えた端末からは届きうる）
    var shownNote: String { noteHidden == true || noteHasContact ? "" : note }

    /// 区間に出す、相手が書いた字（伏せた・書いていない・連絡先の形なら nil＝自動の形）

    /// 連絡先の形の印（**受け取った時に一度だけ判定して持つ**・`PassStore.record`）。前の記録には無いので、
    /// 無ければその場で判定する
    var noteContact: Bool? = nil
    var originContact: Bool? = nil
    var destinationContact: Bool? = nil

    var noteHasContact: Bool { noteContact ?? PassExchange.containsContact(note) }
    private var originHasContact: Bool { originContact ?? PassExchange.containsContact(originLabel ?? "") }
    private var destinationHasContact: Bool { destinationContact ?? PassExchange.containsContact(destinationLabel ?? "") }
    var labelsHaveContact: Bool { originHasContact || destinationHasContact }

    var shownOrigin: String? { shownLabel(originLabel, contact: originHasContact) }
    var shownDestination: String? { shownLabel(destinationLabel, contact: destinationHasContact) }

    private func shownLabel(_ label: String?, contact: Bool) -> String? {
        guard labelsHidden != true, let label, !label.isEmpty, !contact else { return nil }
        return label
    }

    /// 相手が書いた字があるか（ひとこと・発・着。通報・伏せるを出すか）
    var hasWrittenText: Bool {
        !note.isEmpty || !(originLabel ?? "").isEmpty || !(destinationLabel ?? "").isEmpty
    }

    /// 通報に入れる、相手が書いた字（伏せていても元の字）
    var writtenText: String {
        PassExchange.writtenText(note: note, origin: originLabel ?? "", destination: destinationLabel ?? "")
    }

    var place: Photo.Coords? {
        guard let placeLat, let placeLng else { return nil }
        return Photo.Coords(lat: placeLat, lng: placeLng)
    }
}

/// すれちがいの設定（端末の中だけ）。**既定はオフ**（オンにする時に説明を出す）
struct PassSettings: Codable, Equatable {
    var enabled = false
    /// 板の既定は「旅のあいだ」
    var mode: PassExchange.Mode = .traveling
    /// 名刺の一枚（自分の公開写真の id）。選ぶまでは電波を出さない
    var cardPhotoId: String?
    var note = ""
    /// どこから来た人か（居住地の都道府県）を載せる
    var showsFrom = true
    /// 乗車券の「発」を自分で書いた字（nil なら自動: `showsFrom` なら居住地・でなければ「どこかから」）。
    /// **2026-10-16 判断**（owner「発・着を自分で決めたい」）。前の版の設定には無いので省略できる形
    var originLabel: String? = nil
    /// 乗車券の「着」を自分で書いた字（nil なら自動: すれちがった所）
    var destinationLabel: String? = nil

    /// 「発」の選び方
    enum Origin: String, CaseIterable, Identifiable {
        /// 居住地から（自動）
        case home
        /// 自分で書く
        case custom
        /// 出さない（どこかから）
        case hidden
        var id: String { rawValue }
    }

    var origin: Origin {
        if originLabel != nil { return .custom }
        return showsFrom ? .home : .hidden
    }

    /// 「発」を選ぶ。自分で書くときは字も（空でも「自分で書く」のまま）
    mutating func setOrigin(_ choice: Origin, text: String = "") {
        switch choice {
        case .home: originLabel = nil; showsFrom = true
        case .hidden: originLabel = nil; showsFrom = false
        // 自分で書いた字があるときは居住地を載せない（前のアプリには居住地も出ない）。
        // **空のままなら「出さない」に戻す**（2026-10-16 の読み直し）
        case .custom:
            let written = PassExchange.cleanLabel(text)
            originLabel = written.isEmpty ? nil : written
            showsFrom = false
        }
    }

    /// 「着」を決める。自分で書く字が空なら「すれちがった所（自動）」に戻す
    mutating func setDestination(custom: Bool, text: String) {
        let written = custom ? PassExchange.cleanLabel(text) : ""
        destinationLabel = written.isEmpty ? nil : written
    }
}

/// すれちがい帳の並べ方と数え方（板 PassBook）。
enum PassBook {

    /// 帳のタブ（板「綴じた順・場所ごと・よく会う人」）
    enum Order: String, CaseIterable, Identifiable {
        case bound, place, person
        var id: String { rawValue }
        var label: String {
            switch self {
            case .bound: return L("綴じた順", "As bound")
            case .place: return L("場所ごと", "By place")
            case .person: return L("よく会う人", "Often met")
            }
        }
    }

    struct Section: Equatable, Identifiable {
        let id: String
        let title: String
        let cards: [PassEncounter]
    }

    /// 1ページの枠の数（板: 3列×3段。足りない枠は点線の空き）
    static let pageSlots = 9

    /// 空きの枠の数。**ページの最後まで埋める**（0枚なら1ページ分）
    static func emptySlots(for count: Int) -> Int {
        guard count > 0 else { return pageSlots }
        let rest = count % pageSlots
        return rest == 0 ? 0 : pageSlots - rest
    }

    /// 届いたものだけ（**届く前のカードは帳にも出さない**——夕方まで「いま近くにいる」を見せない）
    static func delivered(_ cards: [PassEncounter], now: Date) -> [PassEncounter] {
        cards.filter { $0.deliverAt <= now }
    }

    /// 並べる。`names` は持ち主の名前（よく会う人の見出し）
    static func sections(_ cards: [PassEncounter], order: Order, names: [String: String],
                         calendar: Calendar) -> [Section] {
        switch order {
        case .bound:
            let groups = Dictionary(grouping: cards) { PassExchange.dayKey($0.metHour, calendar: calendar) }
            return groups.keys.sorted(by: >).map { key in
                let list = groups[key]!.sorted { $0.number < $1.number }
                return Section(id: "day-\(key)",
                               title: PassExchange.dayLabel(list[0].metHour, place: mostCommonPlace(list), calendar: calendar),
                               cards: list)
            }
        case .place:
            let groups = Dictionary(grouping: cards) { $0.placeName ?? "" }
            let named = groups.keys.filter { !$0.isEmpty }.sorted { lhs, rhs in
                latest(groups[lhs]!) > latest(groups[rhs]!)
            }
            var result = named.map { key in
                Section(id: "place-\(key)", title: key, cards: groups[key]!.sorted { $0.number > $1.number })
            }
            if let unknown = groups[""] {
                result.append(Section(id: "place-unknown", title: L("場所の記録なし", "No place recorded"),
                                      cards: unknown.sorted { $0.number > $1.number }))
            }
            return result
        case .person:
            let known = cards.filter { $0.ownerId != nil }
            let groups = Dictionary(grouping: known) { $0.ownerId! }
            return groups.keys.sorted { lhs, rhs in
                let l = groups[lhs]!, r = groups[rhs]!
                return l.count != r.count ? l.count > r.count : latest(l) > latest(r)
            }.map { owner in
                let list = groups[owner]!.sorted { $0.number > $1.number }
                let name = names[owner] ?? L("名前の無い人", "Unnamed")
                return Section(id: "person-\(owner)", title: L("\(name) · \(list.count) 回", "\(name) · \(list.count)×"),
                               cards: list)
            }
        }
    }

    /// 帳の上の3つの数（板「128 枚のカード・18 都道府県から・1,284 km いちばん遠く」）
    struct Stats: Equatable {
        var cards: Int
        var prefectures: Int
        var farthestKm: Int?
    }

    /// - Parameter prefectures: 持ち主 → 居住地の都道府県（**相手が出すと決めたものだけ**渡す）
    static func stats(_ cards: [PassEncounter], prefectures: [String: String]) -> Stats {
        var seen: Set<String> = []
        var farthest: Int?
        for card in cards {
            guard card.showsFrom, let owner = card.ownerId, let pref = prefectures[owner] else { continue }
            seen.insert(pref)
            if let km = PassExchange.travelKm(fromPrefecture: pref, to: card.place) {
                farthest = max(farthest ?? 0, km)
            }
        }
        return Stats(cards: cards.count, prefectures: seen.count, farthestKm: farthest)
    }

    /// 同じ人と何回すれちがったか（この1枚までを数える）
    static func meetingCount(of card: PassEncounter, in cards: [PassEncounter]) -> Int {
        guard let owner = card.ownerId else { return 1 }
        return cards.filter { $0.ownerId == owner && $0.number <= card.number }.count
    }

    /// 束の札の一行（板「清水寺・祇園のあたりで すれちがい」）。場所が1つも無ければ人数だけ
    static func bundleLine(_ cards: [PassEncounter]) -> String {
        var names: [String] = []
        for card in cards.sorted(by: { $0.number < $1.number }) {
            if let name = card.placeName, !name.isEmpty, !names.contains(name) { names.append(name) }
            if names.count == 2 { break }
        }
        guard !names.isEmpty else {
            return L("\(cards.count) 人とすれちがいました", "You passed \(cards.count) people")
        }
        let joined = names.joined(separator: L("・", " / "))
        return L("\(joined)のあたりで すれちがい", "Passed around \(joined)")
    }

    private static func latest(_ cards: [PassEncounter]) -> Date {
        cards.map(\.metHour).max() ?? .distantPast
    }

    private static func mostCommonPlace(_ cards: [PassEncounter]) -> String? {
        let names = cards.compactMap(\.placeName).filter { !$0.isEmpty }
        let counts = Dictionary(grouping: names) { $0 }.mapValues(\.count)
        return counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
    }
}
