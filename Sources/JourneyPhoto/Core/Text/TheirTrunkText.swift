import Foundation

// 人のトランクの決まり（板 TheirTrunk・TheirInside・ProfileTrunk・TrunkPrivacy・2026-10-18）。
// **SwiftUI を読まない層**（Linux でテストする）。画面は `Features/Trunk/TheirTrunkView.swift`。
//
// - ラベルを選ぶと、その土地で撮ったその人の写真（`where.location` で公開写真の一覧から引く）
// - 地名の空のラベルは地名なしの形で描く（伏せたか・もともと無いかは区別しない。「非公開」の類の言葉は出さない）
// - 押せる所は 44pt を割らない（板の `max(44, w * 0.8)`。縮めて置いても 44 を保つ）

enum TheirTrunkText {

    /// 名前が読めないときの呼び方
    static func owner(_ name: String?) -> String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? L("この人", "This person") : trimmed
    }

    /// 画面の題（板「[表示名]さんのトランク」）
    static func title(_ name: String?) -> String {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return L("旅のトランク", "Travel trunk")
        }
        return L("\(name)さんのトランク", "\(name)\u{2019}s trunk")
    }

    // MARK: ラベルの写真

    /// 撮影地の文字を割る記号（サーバーの注記 `,、，/()（）`）
    static let separators: Set<Character> = [",", "、", "，", "/", "(", ")", "（", "）"]

    /// 撮影地の文字の先頭の区切り（前後の空白を落とす）
    static func head(_ location: String) -> String {
        let first = location.split(whereSeparator: { separators.contains($0) }).first.map(String.init) ?? ""
        return first.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// その土地で撮った写真（先頭の区切りが同じもの。無ければ撮影地に土地の名前を含むもの）。並びは一覧のまま
    static func photos(at place: String, in photos: [Photo]) -> [Photo] {
        let key = place.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return [] }
        let exact = photos.filter { head($0.location ?? "") == key }
        if !exact.isEmpty { return exact }
        return photos.filter { ($0.location ?? "").contains(key) }
    }

    /// 開いたときに選んでおくラベル（新しい順で、写真を引けるもの。無ければ新しい1枚。トランクに描く物の中から）
    static func defaultSelection(_ trunk: TheirTrunk, drawn: [TrunkLabel]) -> String? {
        let ids = Set(drawn.map(\.id))
        let shown = trunk.stuck.filter { ids.contains($0.id) }
        return (shown.first { trunk.place(of: $0) != nil } ?? shown.first)?.id
    }

    /// 選んだラベルの見出し（「京都 · 桜」・地名の無いラベルは「旅の記録」）
    static func sheetTitle(_ label: TrunkLabel) -> String { TrunkLabelDesign.caption(label) }

    /// 見出しの下の一行。写真を引けるラベルは「[表示名]さんが京都で撮った写真 · 3 枚」（数は読めてから）、
    /// 地名の無いラベルは「[表示名]さんの旅のラベル」（地名が無い訳は言わない）
    static func sheetSubtitle(place: String?, owner name: String?, count: Int?) -> String {
        let who = owner(name)
        guard let place else { return L("\(who)さんの旅のラベル", "A travel label from \(who)") }
        guard let count else { return L("\(who)さんが\(place)で撮った写真", "Photos \(who) took in \(place)") }
        return L("\(who)さんが\(place)で撮った写真 · \(count) 枚", "Photos \(who) took in \(place) · \(count)")
    }

    /// その土地の写真が一覧に無いとき（読み終えて0枚）
    static var noPhotos: String {
        L("この土地の写真は、いまは一覧にありません。", "No photos from this place in the list right now.")
    }

    /// シートの下の注記（板どおり）
    static var sheetNote: String {
        L("ラベルを押すと、その土地で撮った写真に替わります。公開していない写真は出ません。",
          "Tap a label to see the photos taken there. Photos that aren\u{2019}t public don\u{2019}t appear.")
    }

    /// まだ1枚も貼っていないトランク
    static var noLabels: String {
        L("まだラベルが貼られていません。", "No labels on this trunk yet.")
    }

    /// トランクの上のラベルの読み上げ（板「京都 · 桜のラベル。京都で撮った写真を開く」）
    static func labelAccessibility(_ label: TrunkLabel, place: String?) -> String {
        let base = TrunkLabelDesign.accessibilityLabel(label)
        guard let place else { return base }
        return L("\(base)。\(place)で撮った写真を開く", "\(base). Shows photos taken in \(place)")
    }

    /// 写真の読み上げ（板「京都の写真 1」）
    static func photoAccessibility(place: String, index: Int, title: String) -> String {
        L("\(place)の写真 \(index + 1) · \(title)", "Photo \(index + 1) from \(place) · \(title)")
    }

    // MARK: トランクの上の押せる所と選んだ印

    struct Frame: Equatable {
        let x: Double
        let y: Double
        let w: Double
        let h: Double
        let rot: Double
    }

    /// 押せる所（360×300 の絵の座標）。板の `max(44, w * 0.8)` を、置く大きさ `scale` で縮めても 44pt を割らないように
    static func hitFrame(_ p: TrunkSlots.Placed, scale: Double) -> Frame {
        let k = max(0.1, scale)
        let cx = p.x + p.w / 2, cy = p.y + TrunkLooks.bodyTop + p.h / 2
        let w = max(44 / k, p.w * 0.8), h = max(44 / k, p.h * 0.8)
        return Frame(x: cx - w / 2, y: cy - h / 2, w: w, h: h, rot: 0)
    }

    /// 選んだラベルを囲む真鍮の点線（板: ラベルより 5 ずつ外・角 14・ラベルと同じ傾き）
    static func ringFrame(_ p: TrunkSlots.Placed) -> Frame {
        Frame(x: p.x - 5, y: p.y + TrunkLooks.bodyTop - 5, w: p.w + 10, h: p.h + 10, rot: p.rot)
    }

    /// ほかの人から見た形の見本（設定の「ほかの人から見たあなたのプロフィール」）。どのラベルの地名が人に見えるかは
    /// サーバーの確かめの印で決まり iOS では分からないので、**地名も日付・季節・時刻・節目も落とした人の口の形**で描く
    /// （伏せたラベルと同じ `{ kind, seed, foil, pos }` だけ）
    static func asSeenByOthers(_ labels: [TrunkLabel]) -> [TrunkLabel] {
        labels.map {
            TrunkLabel(id: $0.id, photoId: $0.id, kind: $0.kind, place: .init(name: "", latin: nil, country: nil),
                       seed: $0.seed, at: "", foil: $0.foil, pos: $0.pos)
        }
    }

    // MARK: プロフィールの段（板 ProfileTrunk）

    static var cardEyebrow: String { L("旅のトランク", "Travel trunk") }

    static func cardDetail(hasLabels: Bool) -> String {
        hasLabels ? L("ラベルを押すと、その土地で撮った写真が開きます", "Tap a label to open the photos taken there")
                  : L("ふたを開けると、中を見られます", "Open the lid to see what\u{2019}s inside")
    }

    static func cardAccessibility(owner name: String?, model: TrunkModel) -> String {
        let who = owner(name)
        return L("\(who)さんの旅のトランク · \(TrunkText.info(model).name) · 押すと手に取って見られます",
                 "\(who)\u{2019}s travel trunk · \(TrunkText.info(model).name) · Tap to take a look")
    }

    // MARK: 状態

    /// 見られない（404）とき。理由は言わない
    static var hiddenTitle: String { L("このトランクは、いまは見られません", "This trunk can\u{2019}t be viewed right now") }
    static var failedTitle: String { L("トランクを読み込めませんでした", "Couldn\u{2019}t load this trunk") }
    static var offlineMessage: String {
        L("電波のあるところで開くと、トランクを読み込みます。", "Open this again where you have a signal to load the trunk.")
    }

    // MARK: 中（板 TheirInside）

    /// 開け切ったときの一言（板「押すと手に取って、表と裏を回して見られます」）
    static var insideHint: String { L("押すと手に取って、表と裏を回して見られます", "Tap something to pick it up and turn it over") }

    /// 中の注記の2行（太字の頭と本文）
    static var insideNotes: [(head: String, body: String)] {
        [(L("会員証", "Member card"), L("は名前とサポーター証の絵だけ。番号と始めた年月は出しません。",
                                       " shows only the name and the card art \u{2014} never the number or start date.")),
         (L("乗車券", "Ticket"), L("はこの人の「わたしの乗車券」1枚だけ。受け取った乗車券は、すれちがった相手の写真と名前が入るので出しません。",
                                  " is only this person\u{2019}s own ticket. Tickets they received carry other people\u{2019}s photos and names, so they stay private."))]
    }

    /// 人の乗車券に刷る字（区間の発・着とひとこと）。**サーバーから来た字でも連絡先の形は券に出さない**
    /// （送る側と同じ `PassExchange.shareable`）。発に書いた字が落ちたら、居住地か「どこか」に戻す
    struct TicketRoute: Equatable {
        let choice: PassSettings.Origin
        let origin: String
        let destination: String
        let note: String
    }

    static func ticketRoute(_ ticket: TrunkTicket) -> TicketRoute {
        let origin = PassExchange.shareable(ticket.origin)
        let choice: PassSettings.Origin = !origin.isEmpty ? .custom : (ticket.showsFrom ? .home : .hidden)
        return TicketRoute(choice: choice, origin: origin, destination: PassExchange.shareable(ticket.destination),
                           note: PassExchange.shareable(ticket.note))
    }

    /// 乗車券の写真。人の公開写真の一覧から引く（無ければ nil）。画面写真の見本だけ、一覧の先頭を使う
    static func ticketPhoto(_ ticket: TrunkTicket?, in photos: [Photo], preview: Bool) -> Photo? {
        guard let ticket else { return nil }
        if let photo = photos.first(where: { $0.id == ticket.photoId }) { return photo }
        return preview ? photos.first : nil
    }
}

/// 画面写真の見本の人のトランク（`-JPPreviewTheirTrunk`・Debug のみ。サーバーには何も送らない）。
/// 板 TheirTrunk の「星図の鞄」・古びた姿。自分のトランクの見本のラベルを、人の口の形（返答の中の番号・`where`）にし、
/// **地名の無いラベルを2枚**（時刻の札・節目の札。値も地名も無い形）混ぜる
enum TheirTrunkSample {

    static func trunk(userId: String) -> TheirTrunk {
        let source = TrunkSample.stuck
        let n = source.count
        var stuck: [TrunkLabel] = []
        var places: [String: String] = [:]
        for (i, label) in source.enumerated() {
            let id = "s\(n - 1 - i)"
            // 時刻の札（ヘルシンキ）と節目の札（はじめて）は、地名も値も無い形
            if label.id == "s-helsinki" || label.id == "s-first" {
                stuck.append(TrunkLabel(id: id, photoId: id, kind: label.kind, place: .init(name: "", latin: nil, country: nil),
                                        seed: label.seed, at: "", foil: label.foil))
            } else {
                stuck.append(TrunkLabel(id: id, photoId: id, kind: label.kind, place: label.place, season: label.season,
                                        timeslot: label.timeslot, milestone: label.milestone, seed: label.seed,
                                        at: String(label.at.prefix(10)), foil: label.foil))
                places[id] = label.place.name
            }
        }
        let badges = BadgeSet(["supporter", "first", "countries", "night", "seasons", "wish"].map {
            EarnedBadge(key: $0, tier: 1, at: "2026-10-01T09:00:00Z")
        })
        return TheirTrunk(userId: userId, model: .starchart, stuck: stuck, equipped: TrunkSample.equipped.sanitized(owned: nil),
                          posts: 120, places: places, badges: badges, card: .init(pro: true),
                          ticket: TrunkTicket(photoId: "preview", note: "霧の朝が好きです", face: 0))
    }
}
