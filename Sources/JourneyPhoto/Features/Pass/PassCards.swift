import SwiftUI

/// 1枚のカードに描くもの（記録・引けた写真・持ち主）。画面の側で組む
struct PassCardContent: Identifiable, Equatable {
    let card: PassEncounter
    let photo: Photo
    let owner: UserProfile?
    /// 相手が出すと決めた居住地の都道府県
    let fromPrefecture: String?
    /// 同じ人と何回目か
    let meetingCount: Int

    var id: String { card.id }

    var name: String {
        if let owner { return owner.name }
        if let name = photo.displayName, !name.isEmpty { return name }
        return L("名前の無い人", "Unnamed")
    }

    /// 住まい（都道府県庁のあたり）からすれちがった場所までの km。出せなければ nil
    var km: Int? { PassExchange.travelKm(fromPrefecture: fromPrefecture, to: card.place) }

    /// きっぷの種類（持ち主が分からなければ数えない）
    var kind: PassTicket.Kind {
        PassTicket.kind(meetingCount: card.ownerId == nil ? nil : meetingCount, km: km)
    }

    /// 券面（2026-10-17）。**持ち主の公開プロフィールが券面を見せてよいときだけ**相手が選んだ券面、ほかはマルス券。
    /// 決め手は `passFace`（印を外した Pro も立つ）、古いサーバーで無ければ `pro`（`UserProfile.showsPassFace`）。
    /// プロフィールは帳を開くときに引いたもの（`PassStore.resolve` の `owners`）を使い回す——カードごとに引き直さない
    var faceStyle: PassTicketFaceStyle {
        PassTicketFaceStyle.shown(wire: card.face, ownerIsPro: owner?.showsPassFace)
    }

    /// 表に描くもの
    func face(calendar: Calendar = .current) -> PassTicketFace {
        PassTicketFace(photo: photo, kind: kind, number: PassExchange.numberLabel(card.number),
                       origin: PassTicket.origin(fromPrefecture, written: card.shownOrigin),
                       destination: PassTicket.destination(card.placeName, written: card.shownDestination),
                       name: name, distance: PassTicket.distanceLabel(km),
                       date: PassTicket.dateLabel(card.metHour, calendar: calendar),
                       count: count, via: PassTicket.via(card.placeName), style: faceStyle)
    }

    /// 「回数」の欄（表と裏で同じ）
    private var count: String {
        PassTicket.countLabel(kind, meetingCount: card.ownerId == nil ? nil : meetingCount)
    }

    /// 裏に描くもの
    func backFace() -> PassTicketBackFace {
        PassTicketBackFace(kind: kind, number: PassExchange.numberLabel(card.number),
                           title: photo.displayTitle, note: card.shownNote,
                           noteHidden: card.noteHidden == true || card.noteHasContact,
                           issuer: PassTicket.issuer(name: name, prefecture: fromPrefecture),
                           section: PassTicket.sectionLabel(km), count: count,
                           footnote: PassTicket.receivedFootnote, style: faceStyle)
    }

    /// 前の記録（ひとことを伏せた等）を新しい記録に差し替える
    func with(card next: PassEncounter) -> PassCardContent {
        PassCardContent(card: next, photo: photo, owner: owner, fromPrefecture: fromPrefecture, meetingCount: meetingCount)
    }

    static func == (lhs: PassCardContent, rhs: PassCardContent) -> Bool {
        lhs.card == rhs.card && lhs.photo.id == rhs.photo.id && lhs.owner?.userId == rhs.owner?.userId
            && lhs.owner?.showsPassFace == rhs.owner?.showsPassFace
            && lhs.fromPrefecture == rhs.fromPrefecture && lhs.meetingCount == rhs.meetingCount
    }
}

extension PassStore {
    /// 見せてよいカードを、描くものにする（`book` は帳に綴じた全部・同じ人の回数を数える元）
    func contents(_ cards: [PassEncounter], book: [PassEncounter]) -> [PassCardContent] {
        cards.compactMap { card in
            guard let photo = photos[card.photoId] else { return nil }
            return PassCardContent(card: card, photo: photo,
                                   owner: card.ownerId.flatMap { owners[$0] },
                                   fromPrefecture: prefecture(for: card),
                                   meetingCount: PassBook.meetingCount(of: card, in: book))
        }
    }
}

/// きっぷの表に描くもの（見本の乗車券も同じ形で作る）
struct PassTicketFace {
    let photo: Photo?
    let kind: PassTicket.Kind
    /// 「No.0087」。決まらないとき（自分の乗車券の見本）は nil
    let number: String?
    let origin: String
    let destination: String
    let name: String
    /// 「区間」の欄（例「9,712 km」）。出せなければ nil（欄は「—」）
    let distance: String?
    /// 「日付」の欄（例「10.17 14時」）。決まらなければ nil（欄は「—」）
    let date: String?
    /// 「回数」の欄（例「はじめて」・数えられなければ「—」）
    let count: String
    /// 「経由 〇〇」の行。場所の記録が無ければ nil（行ごと出さない）
    let via: String?
    /// 券面（2026-10-17・既定はマルス券）。決め方は `PassTicketFaceStyle.shown`・`own`
    var style: PassTicketFaceStyle = .mars

    /// 左上の種類の名（`PassTicket.headline`）
    var headline: String { PassTicket.headline(kind) }
    /// 日付・区間・回数の3つの欄（`PassTicket.frontFields`）
    var fields: [PassTicket.Field] { PassTicket.frontFields(date: date, distance: distance, count: count) }
}

/// きっぷの裏に描くもの（届いたカードは `PassCardContent.backFace()`・自分のカードの見本は `preview`）。
/// 2026-10-16 判断（owner「自分のカードも回したい」）: 裏を記録（`PassEncounter`）から切り離し、表
/// （`PassTicketFace`）と同じく「描くもの」だけを渡す。自分のカードの見本も同じ裏の部品で描ける
struct PassTicketBackFace: Equatable {
    let kind: PassTicket.Kind
    /// 帯の右の「No.0087」（表と同じ）。決まらないとき（自分のカードの見本）は nil
    let number: String?
    /// 作品名
    let title: String
    /// 見せるひとこと（空なら出さない）
    let note: String
    /// ひとことを伏せている（「ひとことは伏せています」を出す）
    let noteHidden: Bool
    /// 「発行」
    let issuer: String
    /// 「区間」
    let section: String
    /// 「回数」
    let count: String
    /// 裾の一行（届いたカード＝`PassTicket.receivedFootnote`・見本＝`ownFootnote`）
    let footnote: String
    /// 券面（2026-10-18・owner「裏面デザイン変わってなくて悲しいね」）。**表と同じ決め方**で決める——届いたカードは
    /// `PassCardContent.faceStyle`（`PassTicketFaceStyle.shown`）、自分の見本は `PassTicketFaceStyle.own`。
    /// 回す部品（`PassSpinTicket`）は、念のため表の券面で描き直す（`styled`）ので、表と裏が割れることはない
    var style: PassTicketFaceStyle = .mars

    /// 券面だけを替えた写し（`PassSpinTicket` が表の券面にそろえる）
    func styled(_ style: PassTicketFaceStyle) -> PassTicketBackFace {
        var copy = self
        copy.style = style
        return copy
    }

    /// 発行・有効・区間・回数の4つの欄（`PassTicket.backFields`）
    var fields: [PassTicket.Field] { PassTicket.backFields(issuer: issuer, section: section, count: count) }

    /// 自分のカードの見本の裏（**相手の手元に届く形**）。
    /// - ひとことは電波に載る形（整えた字・連絡先の形は載らない＝`PassStore.payload` と同じ）
    /// - 発行の都道府県は「居住地から」を選んだときだけ（相手の端末でもそう読まれる・`PassStore.prefecture(for:)`）
    /// - 区間（km）と回数は会ってから決まるので「—」（表の番号・日付・区間・回数を「—」にするのと同じ扱い）
    static func preview(photoTitle: String?, note: String, name: String,
                        origin: PassSettings.Origin, homePrefecture: String?,
                        style: PassTicketFaceStyle = .mars) -> PassTicketBackFace {
        let cleaned = PassExchange.cleanNote(note)
        return PassTicketBackFace(kind: .plain, number: nil, title: photoTitle ?? L("選んだ写真", "Your photo"),
                                  note: PassExchange.containsContact(cleaned) ? "" : cleaned, noteHidden: false,
                                  issuer: PassTicket.issuer(name: name, prefecture: origin == .home ? homePrefecture : nil),
                                  section: PassTicket.sectionLabel(nil),
                                  count: PassTicket.countLabel(.plain, meetingCount: nil),
                                  footnote: PassTicket.ownFootnote, style: style)
    }
}

/// カードの見た目の決まり（**2026-10-16 判断（owner が案C を選んだ）**・板 AltC・CardKinds。
/// **2026-10-17 判断（owner「マルス券いいね」）**: 表と裏を候補の板 `Plain.dc.html` の「1. マルス券」と「裏」の寸法に
/// した）。テストで見張る
enum PassCardStyle {
    /// 束を開いた画面のカード（板 300×430・角 14・写真 214）
    static let deckSize = CGSize(width: 300, height: 430)
    static let deckCorner: CGFloat = 14
    /// 写真の高さ（マルス券の板 214。案C の 250 から下げて、欄の格子の場所を空けた）
    static let photoHeight: CGFloat = 214
    /// ホームの束の1枚（板 92×128・角 9・写真 76）
    static let stackSize = CGSize(width: 92, height: 128)
    static let stackCorner: CGFloat = 9
    /// 縁の真鍮の濃さ（板 rgba(201,166,107,.5)）
    static let edgeOpacity = 0.5
    static let footerLineOpacity = 0.35
    /// 破線・改札の穴の縁（板 .5）
    static let dashOpacity = 0.5
    /// 写真の下端の細い真鍮の線（マルス券の板 .55）。**写真の下の黒い地に引く**（写真には重ねない）
    static let photoRuleOpacity = 0.55
    /// 裏の帯の下の真鍮の線（板 .45）
    static let bandRuleOpacity = 0.45
    /// 裏の帯の高さ（板 44）。地は `WebTheme.accentSoft`（案内の帯）
    static let bandHeight: CGFloat = 44
    /// きっぷの地（板 #0E0D0B・黒に少し暖色を混ぜた紙）
    static let face = Color(red: 14 / 255, green: 13 / 255, blue: 11 / 255)
    /// 「遠くから」の縁の沈む側（板 #3A3020）
    static let farEdgeLow = Color(red: 58 / 255, green: 48 / 255, blue: 32 / 255)

    // MARK: 字組（マルス券の板）
    //
    // 2026-10-17 判断: きっぷの表と裏の字は**固定の大きさ**で描き、文字を大きくする設定では変わらない（区間の地名と
    // 同じ考え）。札は寸法の決まった物で、字だけ大きくすると欄の格子や裾の行が札からはみ出す。
    // **中身は読み上げで全部読める**（区間・欄・空の欄の「なし」・裏のひとことと裾まで）。だから表と裏には
    // `.dynamicTypeSize` を付けない（固定の字には効かず、効くように見えて紛らわしい）。小さなきっぷも同じ
    // （2026-10-17 判断: マルス券の縮小版にしたので、帳の札も固定の字にした・読み上げは札のボタンの名前）。
    // 板の明朝 15・12 は CLAUDE.md の明朝の下限 18 より小さいが、owner が選んだ板の字組を取った（本文系 12 は割らない）

    /// 内側の余白（板 左右 18・表の上 13・下 12）と、表の行の間（板 9）
    static let inset: CGFloat = 18
    static let frontTop: CGFloat = 13
    static let frontBottom: CGFloat = 12
    static let frontSpacing: CGFloat = 9
    /// 「乗車券」「ご案内」（明朝 15・字間 0.3em・真鍮）
    static let headSize: CGFloat = 15
    static let headTracking: CGFloat = 0.3
    /// No.（SF 600 11・字間 0.12em・等幅数字・真鍮）
    static let numberSize: CGFloat = 11
    static let numberTracking: CGFloat = 0.12
    /// 名前・経由（12）
    static let metaSize: CGFloat = 12
    /// 表の欄（ラベル 11・値 13）と、欄の上下の余白（板 8）
    static let fieldLabelSize: CGFloat = 11
    static let fieldValueSize: CGFloat = 13
    static let fieldPadding: CGFloat = 8
    /// 右下の「ずっと有効」（12・字間 0.04em）。板は 11・0.08em だが、本文系の下限 12 を守る（2026-10-17 判断）。
    /// 大きくした分、字間を詰めて名前の幅を残す
    static let validitySize: CGFloat = 12
    static let validityTracking: CGFloat = 0.04
    /// 裏: 余白と行の間（板 18・14）・作品名（明朝 18）・欄（ラベル 12・値 14）・裾（12・字間 0.06em）。
    /// 裾は板の 11 から本文系の下限 12 に上げ（2026-10-17 判断）、その分の縦を上の余白（18 → 16）から取った
    static let backPadding: CGFloat = 18
    static let backTop: CGFloat = 16
    static let backSpacing: CGFloat = 14
    static let backTitleSize: CGFloat = 18
    static let backLabelSize: CGFloat = 12
    static let backValueSize: CGFloat = 14
    /// 裏の欄の間（板 12）・ひとこと（板 15）
    static let backFieldGap: CGFloat = 12
    static let noteSize: CGFloat = 15
    static let footnoteSize: CGFloat = 12
    static let footnoteTracking: CGFloat = 0.06

    // MARK: 裏の欄の値の行数（2026-10-18）
    //
    // 「有効」の値（`PassTicket.validity`「ずっと（帳に綴じる）」）は 14pt で幅がおよそ 140 あり、欄（126）に1行では
    // 入らず末尾が「…」で切れていた。**字は縮めず、この欄だけ2行まで許す**（日本語は折れ目を改行で決めてある）。行は上でそろえる（`HStack(alignment: .top)`）
    // ので、隣の欄と格子は崩れず、増えた1行ぶんは作品名と欄の間の空き（Spacer）が受け持つ

    /// 欄の値の行数の上限。「有効」だけ2行、ほかは1行（入らなければ末尾を「…」）
    nonisolated static func backValueLines(_ field: PassTicket.Field) -> Int {
        [PassTicket.validityJa, PassTicket.validityEn].contains(field.value) ? 2 : 1
    }

    /// 本文の字（SF・ヒラギノ角ゴ）の幅の見積もり: 和文は1字＝1em、欧文・数字・記号は `bodyLatinEm`
    nonisolated static let bodyLatinEm = 0.56
    nonisolated static func bodyEms(_ text: String) -> Double {
        text.reduce(0) { $0 + ($1.isASCII ? bodyLatinEm : 1) }
    }

    /// 語の切れ目で折った行（見積もり）。改行（`\n`）はそこで折る。欧文は空白で区切った語を詰め、和文の
    /// ひと続き（空白の無いまとまり）は1語として扱う。**1語が幅に入らなければ nil**（＝語の途中で折れる）
    nonisolated static func wrappedLines(_ text: String, size: Double, width: Double) -> [String]? {
        var lines: [String] = []
        for paragraph in text.components(separatedBy: "\n") {
            var line = ""
            for word in paragraph.split(separator: " ").map(String.init) {
                guard bodyEms(word) * size <= width else { return nil }
                let joined = line.isEmpty ? word : line + " " + word
                if bodyEms(joined) * size <= width {
                    line = joined
                } else {
                    lines.append(line)
                    line = word
                }
            }
            lines.append(line)
        }
        return lines
    }

    /// 裏の欄1つの値に使える幅（券面ごと・いちばん狭い欄）。札 300 − 左右の内側 18 × 2 を2つに分け、
    /// 罫で区切る券面は罫の右の字下げ、型押しの欄は箱の内側の余白を引く（`PassBackFields`）
    nonisolated static func backValueWidth(_ style: PassTicketFaceStyle) -> Double {
        let inner = 300 - Double(backPadding) * 2
        let column = (inner - Double(backFieldGap)) / 2
        switch style {
        case .mars, .greatCircle, .urushi: return column
        case .brassPlate, .foilHard: return column - Double(PassBackFields.ruleIndent)
        case .leather: return column - Double(PassBackFields.debossPadding) * 2
        }
    }

    // MARK: 裏の縦の配分（2026-10-18 の見直し・札 #306）
    //
    // 札は 430 で決まっていて、作品名（2行まで）・ひとこと（`PassExchange.noteLimit` 字＝2行）・注記（2行）・
    // 「有効」（2行）・裾（2行）が**全部いちばん長いとき**でも、どれも「…」で切れずに収まるよう縦を配る。
    // 見積もりの行の高さは字の大きさ × `minchoLineHeight`（明朝）・`bodyLineHeight`（本文）。
    // **実機の字の高さでは測っていない**（Linux の見積もり）。画面写真で確かめる

    /// 行の高さの見積もり（字の大きさに掛ける）
    nonisolated static let minchoLineHeight = 1.4
    nonisolated static let bodyLineHeight = 1.25

    /// 裏の縦の寸法（券面ごと）。`PassBackLayout`・`PassBackFields` はこの値で描く（見積もりと描き方を1つにする）
    struct BackMetrics: Equatable {
        /// 帯を札の上から離す（26: ステッチの内側）
        var bandTop: CGFloat = 0
        /// 帯（44）の中で字を下げる（21: 覆輪の内側）
        var bandInnerTop: CGFloat = 0
        /// 帯の下の線の太さ（線が無ければ 0）
        var rule: CGFloat = JPStroke.hairline
        /// 本文の上の余白
        var bodyTop: CGFloat = PassCardStyle.backTop
        /// 本文の段の間
        var spacing: CGFloat = PassCardStyle.backSpacing
        /// 欄の上の余白（上の線から値まで）。型押しの欄は 0（箱の中の余白で取る）
        var fieldTop: CGFloat = PassCardStyle.backFieldGap
        /// 欄の箱の上下の余白（型押しの欄だけ）
        var cellVertical: CGFloat = 0
        /// 破線の太さ
        var dash: CGFloat = 1
    }

    nonisolated static func backMetrics(_ style: PassTicketFaceStyle) -> BackMetrics {
        switch style {
        case .mars, .greatCircle:
            return BackMetrics()
        case .brassPlate:
            return BackMetrics(rule: 2, bodyTop: backTop - 1)
        case .foilHard:
            return BackMetrics(rule: 2, bodyTop: backTop - 1)
        case .urushi:
            return BackMetrics(bandInnerTop: 4, rule: 1.5)
        case .leather:
            // 帯をステッチの内側へ 16 下げ、箱の上下 6 を足した分を、段の間（14 → 10）と本文の上（16 → 12）で返す
            return BackMetrics(bandTop: 16, rule: 0, bodyTop: backTop - 4, spacing: 10, fieldTop: 0, cellVertical: 6,
                               dash: 1.2)
        }
    }

    /// いちばん長い中身のときの裏の高さの見積もり（430 以下なら、どれも切れずに収まる）
    nonisolated static func worstBackHeight(_ style: PassTicketFaceStyle) -> Double {
        let m = backMetrics(style)
        let body = bodyLineHeight
        let label = Double(backLabelSize) * body
        let value = Double(backValueSize) * body
        let title = 2 * Double(backTitleSize) * minchoLineHeight
        let note = 2 * Double(noteSize) * body + 5 + Double(JPSpace.xxs) + 2 * label
        let cell = 2 * Double(m.cellVertical) + label + 2
        let fields = Double(m.fieldTop) + (cell + 2 * value) + Double(backFieldGap) + (cell + value)
        let footnote = 2 * Double(footnoteSize) * body + 4
        let gaps = 5 * Double(m.spacing)
        return Double(m.bandTop) + Double(bandHeight) + Double(m.rule) + Double(m.bodyTop) + title + note + fields
            + Double(m.dash) + footnote + gaps + Double(backPadding)
    }

    /// 区間の地名（明朝 30）。長い地名は縮める——**明朝 13 まで**。
    ///
    /// 2026-10-16 判断（読み直し）: 発・着の両方を自分で書く（6 字＋6 字）と、明朝の下限 18（× 0.6）では片側
    /// 5 字ほどしか入らなかった。区間の地名だけ、明朝の下限を下げる（大きな札の中の見出しで、本文系の
    /// 12pt は割らない）。収まるかは `routeFits` で数えて見張る。
    ///
    /// 2026-10-17 判断（マルス券）: 名の後ろに「発」「着」（明朝 12）を添えるので、片側の欄にその分（`markWidth`）
    /// が要る。矢印と欄の幅は板（98・68・98）のまま、下限を 15 から 13 に下げた（6 字＋「発」が 98 に収まる）
    static let routeSize: Double = 30
    static let routeMinSize: Double = 13
    /// 区間の並びの幅（きっぷ 300 − 左右の内側 18 × 2）・矢印の幅・矢印の左右のすき間
    static let routeWidth: Double = 264
    static let arrowWidth: Double = 56
    static let arrowGap: Double = 6
    /// 「発」「着」の大きさ（明朝 12・text-2）と、名とのすき間（板 2）
    static let markSize: Double = 12
    static let markGap: Double = 2

    /// 明朝は1字がほぼ1字幅（全角）。両側に `chars` 字ずつを、いちばん縮めた大きさで並べて収まるか
    /// （片側の欄 `routeColumnWidth` に `chars` 字と「発」が入るか。左右は同じ幅なので片側で数えれば足りる）
    nonisolated static func routeFits(chars: Int) -> Bool {
        Double(chars) * routeMinSize + markWidth(origin: PassTicket.originMark, destination: PassTicket.destinationMark)
            <= routeColumnWidth
    }

    /// 区間の左右の欄の幅（並びの幅から矢印とすき間を引いて半分）。**矢印をいつもカードの中央に置く**
    nonisolated static var routeColumnWidth: Double { (routeWidth - arrowWidth - arrowGap * 2) / 2 }

    /// 片側の欄で「発」「着」（英語は from / to）とすき間が取る幅。長い方で数える（左右の大きさをそろえるため）
    nonisolated static func markWidth(origin: String, destination: String) -> Double {
        let ems = max(routeEms(origin), routeEms(destination))
        return ems > 0 ? ems * markSize + markGap : 0
    }

    /// 字の幅を全角1字＝1 で数える（明朝の和文は 1・欧文と数字は `latinEm`）。
    /// 欧文は字ごとの幅が違うので少し広めに見積もる
    nonisolated static let latinEm = 0.62
    nonisolated static func routeEms(_ text: String) -> Double {
        text.reduce(0) { $0 + ($1.isASCII ? latinEm : 1) }
    }

    /// 区間の発・着の並べ方（**2026-10-16 判断**・owner「東京 ──→ フランス で左右の幅も字の大きさもそろわない」）。
    ///
    /// 前は発・着がそれぞれ `minimumScaleFactor` で別々に縮み、長い方だけ小さくなり、矢印も中央からずれた。
    /// - 矢印はいつも並びの中央（`arrowCenter` = 並びの幅の半分）
    /// - 発・着は同じ幅の左右の欄。**発は欄の中で右寄せ・着は左寄せ**（矢印に寄せて「東京発 → フランス着」を
    ///   一続きに読ませる）
    /// - 字の大きさは**発・着で同じ**: 長い方が「発」「着」と一緒に欄に収まる大きさ（`routeSize` まで・下限 `routeMinSize`）
    struct RouteLayout: Equatable {
        /// 発・着の両方の字の大きさ
        let fontSize: Double
        /// 左右の欄の幅（同じ）
        let columnWidth: Double
        /// 矢印の中心（並びの左端から）
        let arrowCenter: Double
        /// 片側の欄で「発」「着」が取る幅（名に使えるのは `columnWidth − markWidth`）
        let markWidth: Double
    }

    /// `width` と `maxSize` は特別な券面（2026-10-17・モックの区間は幅 260・明朝 24.5）。マルス券は既定のまま。
    /// `minSize`・`arrow`・`slack` は小さなきっぷ（`PassMiniTicket`・2026-10-17）。並べ方の決まりは大きい札と同じ。
    /// `slack` は欄に残す余裕（字幅の見積もりが外れても「…」で切れないように）
    nonisolated static func routeLayout(origin: String, destination: String,
                                        marks: (origin: String, destination: String) =
                                            (PassTicket.originMark, PassTicket.destinationMark),
                                        width: Double = routeWidth, maxSize: Double = routeSize,
                                        minSize: Double = routeMinSize,
                                        arrow: (width: Double, gap: Double) =
                                            (PassCardStyle.arrowWidth, PassCardStyle.arrowGap),
                                        slack: Double = 0) -> RouteLayout {
        let column = (width - arrow.width - arrow.gap * 2) / 2
        let longest = max(routeEms(origin), routeEms(destination))
        let marked = markWidth(origin: marks.origin, destination: marks.destination)
        let room = column - marked - slack
        let size = longest > 0 ? min(maxSize, max(minSize, room / longest)) : maxSize
        return RouteLayout(fontSize: size, columnWidth: column,
                           arrowCenter: column + arrow.gap + arrow.width / 2, markWidth: marked)
    }

    // MARK: 小さなきっぷ（帳の札・ホームの束・**2026-10-17 判断**: マルス券の縮小版）
    //
    // 地・写真の窓・縁は大きい札と同じ決まり（`PassFaceGround`・`PassTicketEdge`）を縮めて使う。字は縮めない
    // （本文系 12・番号と種類の言葉だけ 11）。入らない欄（経由・日付／区間／回数・ずっと有効）は省く。
    // 「発」「着」の字（12）も 100pt 幅の札には入らないので省き、矢印で向きを言う（読み上げは今と同じ）。
    // 字は表と裏と同じく固定の大きさ（文字を大きくする設定では変わらない・札からはみ出さない）

    /// 左右の内側の余白・行の間
    static let miniInset: CGFloat = 4
    static let miniSpacing: CGFloat = 2
    /// 「乗車券」（明朝 12・字間は表と同じ 0.3em）
    static let miniHeadSize: CGFloat = 12
    /// 区間の地名（明朝 14 から、長い地名は本文系の下限 12 まで。発・着は同じ大きさ）
    static let miniRouteSize: Double = 14
    static let miniRouteMinSize: Double = 12
    /// 区間の矢印（幅 8・左右のすき間 1）。ホームの束（92）でも3字の地名が 12 で、1pt 以上の余裕を持って入る幅を残す
    static let miniArrow: (width: Double, gap: Double) = (8, 1)
    /// 区間の欄に残す余裕（2026-10-17 の見直し: 束の3字がぴったりで余裕が無かった）
    static let miniRouteSlack: Double = 1
    /// 小さなきっぷの角（板の束 9）。特別な券面は表の角の比で（`PassMiniTicket.corner`）
    static let miniCorner: CGFloat = stackCorner

    /// 小さなきっぷの区間（`routeLayout` を幅だけ変えて使う・「発」「着」は省く）
    nonisolated static func miniRoute(origin: String, destination: String, width: Double) -> RouteLayout {
        routeLayout(origin: origin, destination: destination, marks: ("", ""), width: width,
                    maxSize: miniRouteSize, minSize: miniRouteMinSize, arrow: miniArrow, slack: miniRouteSlack)
    }
}

/// 種類ごとの縁（板 CardKinds: ふつう＝細い線・はじめて＝光る真鍮・また会えた＝2本線・遠くから＝沈む真鍮）。
/// **色だけで伝えない**: 眉ラベルの言葉（`PassTicket.eyebrow`）と裏の「回数」でも言う。
///
/// 🔴 **線はカードの外側に描く**（2026-10-16 の読み直し）。`strokeBorder` で内側に引くと、写真の上に真鍮が
/// 重なる（真鍮は黒い地の上だけ）。線の太さの分だけ外へ広げた形に引き、写真には一筋もかけない。
/// 「はじめて」の光も、カードの後ろに敷く（`PassTicketGlow`）——写真の上に光を落とさない
struct PassTicketEdge: View {
    let kind: PassTicket.Kind
    var corner: CGFloat = PassCardStyle.deckCorner
    /// 回しているときの光の位置（`SpinMotion.shine`）。nil なら光らない
    var shine: Double? = nil

    /// 線の太さ（種類ごと）
    nonisolated static func width(_ kind: PassTicket.Kind) -> CGFloat {
        switch kind {
        case .plain, .again: return JPStroke.hairline
        case .first: return JPStroke.emphasis
        case .far: return 1.5
        }
    }

    /// 「また会えた」の外の2本目まで（黒 3 のすき間＋線 1）
    static let secondRingGap: CGFloat = 3

    private var lineWidth: CGFloat { Self.width(kind) }
    private var outer: CGFloat { corner + lineWidth }
    private var secondOuter: CGFloat { corner + lineWidth + Self.secondRingGap + JPStroke.hairline }
    private var secondInset: CGFloat { -(lineWidth + Self.secondRingGap + JPStroke.hairline) }
    private var firstInset: CGFloat { -lineWidth }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: outer)
        Group {
            switch kind {
            case .plain:
                shape.strokeBorder(WebTheme.accent.opacity(PassCardStyle.edgeOpacity), lineWidth: lineWidth)
            case .first:
                shape.strokeBorder(LinearGradient(colors: WebTheme.accentMetal + [WebTheme.accentMetal[0]],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing),
                                   lineWidth: lineWidth)
            case .again:
                shape.strokeBorder(WebTheme.accent.opacity(PassCardStyle.edgeOpacity), lineWidth: lineWidth)
            case .far:
                shape.strokeBorder(LinearGradient(colors: [WebTheme.accent, PassCardStyle.farEdgeLow],
                                                  startPoint: .top, endPoint: .bottom),
                                   lineWidth: lineWidth)
            }
        }
        .overlay {
            if let light = PassTicketShine.style(at: shine) {
                shape.strokeBorder(light, lineWidth: lineWidth)
            }
        }
        .padding(firstInset)
        .overlay {
            if case .again = kind {
                // 外にもう1本（黒 3 のすき間を空けて）
                RoundedRectangle(cornerRadius: secondOuter)
                    .strokeBorder(WebTheme.accent.opacity(0.45), lineWidth: JPStroke.hairline)
                    .padding(secondInset - firstInset)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 回したときに縁と破線を流れる光（`SpinMotion.shine` の位置に細い明るい帯）。**真鍮の線の上だけ**に乗せる
/// （縁はカードの外・破線は黒い地の上。写真には乗せない）。位置が 0〜1 から外れていれば出さない
enum PassTicketShine {
    static let halfWidth = 0.12

    static func stops(at position: Double) -> [Gradient.Stop]? {
        guard position > -halfWidth, position < 1 + halfWidth else { return nil }
        let lo = max(0, position - halfWidth), hi = min(1, position + halfWidth)
        let mid = min(max(position, lo), hi)
        guard lo < mid || mid < hi else { return nil }
        let bright = WebTheme.accentMetal[0]
        return [Gradient.Stop(color: Color.clear, location: lo), Gradient.Stop(color: bright, location: mid),
                Gradient.Stop(color: Color.clear, location: hi)]
    }

    @MainActor
    static func style(at position: Double?) -> LinearGradient? {
        guard let position, let stops = stops(at: position) else { return nil }
        return LinearGradient(stops: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// カードの後ろの地と光（「はじめて」だけ真鍮の光・ほかは黒の影）。**カードの後ろに敷く**ので、
/// 不透明なカードの下に隠れて、光は外側にだけ出る
struct PassTicketGlow: View {
    let kind: PassTicket.Kind
    var corner: CGFloat = PassCardStyle.deckCorner

    var body: some View {
        RoundedRectangle(cornerRadius: corner)
            .fill(PassCardStyle.face)
            .shadow(color: kind == .first ? WebTheme.accent.opacity(0.28) : Color.clear, radius: 12)
            .accessibilityHidden(true)
    }
}

/// 真鍮の破線（板 4 引いて 4 空ける）
struct PassTicketDash: View {
    /// 回しているときの光の位置（縁と同じ流れ）
    var shine: Double? = nil

    var body: some View {
        Rectangle()
            .stroke(WebTheme.accent.opacity(PassCardStyle.dashOpacity), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .overlay {
                if let light = PassTicketShine.style(at: shine) {
                    Rectangle().stroke(light, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// 区間の矢印（板: 56×14 の細い線・真鍮）。01 真鍮の金属板は墨（2026-10-17）
struct PassTicketArrow: View {
    var color: Color = WebTheme.accent
    var lineWidth: CGFloat = 1.6
    /// 幅（大きい札 56・小さなきっぷ `PassCardStyle.miniArrow`）
    var width: CGFloat = CGFloat(PassCardStyle.arrowWidth)

    var body: some View {
        // 大きい札は板の形のまま（2→50・頭 6）。小さなきっぷは幅いっぱいに引き、頭を小さく
        let large = width >= 24
        let start: CGFloat = large ? 2 : 1
        let end: CGFloat = large ? width - 6 : width - 1
        let head: CGFloat = large ? 6 : 3.5
        let half = head * 5 / 6
        return Path { p in
            p.move(to: CGPoint(x: start, y: 7))
            p.addLine(to: CGPoint(x: end, y: 7))
            p.move(to: CGPoint(x: end - head, y: 7 - half))
            p.addLine(to: CGPoint(x: end, y: 7))
            p.addLine(to: CGPoint(x: end - head, y: 7 + half))
        }
        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        .frame(width: width, height: 14)
        .accessibilityHidden(true)
    }
}

/// きっぷの表（**マルス券・2026-10-17 判断**・候補の板 `Plain.dc.html` の「1. マルス券」）: 上に写真と下端の真鍮の線、
/// 種類の名（「乗車券」）と No.・「東京発 → フランス着」・「経由 〇〇」・日付／区間／回数の3つの欄・名前と
/// 「すれちがいの日から ずっと有効」。
///
/// **写真の下は黒い地**なので真鍮が置ける。写真の上には何も置かない（写真を押すと全面で見られる・`onPhotoTap`）
struct PassCardFront: View {

    let face: PassTicketFace
    /// 写真を押した（束の画面: 全面で見る）。nil なら写真も裏返しの一部
    var onPhotoTap: (() -> Void)?
    /// 回しているときの縁と線の光の位置（`SpinMotion.shine`）
    var shine: Double? = nil
    /// 表がいま見えているか（裏を見ている・全面の写真が上にある間は false）。特別な券面の光を止める
    var visible: Bool = true

    /// 券面ごとの角（2026-10-17・モック: 10 箔押しの硬券は 10・26 型押しの革は 16・ほかは 14）
    nonisolated static func corner(_ style: PassTicketFaceStyle) -> CGFloat {
        switch style {
        case .foilHard: return 10
        case .leather: return 16
        case .mars, .brassPlate, .greatCircle, .urushi: return PassCardStyle.deckCorner
        }
    }

    var body: some View {
        let corner = Self.corner(face.style)
        Group {
            if face.style == .mars {
                marsFace
            } else {
                // 特別な券面（Pro・2026-10-17）。縁・後ろの光・影・字の大きさの上限はマルス券と同じものを使う
                PassSpecialFace(face: face, onPhotoTap: onPhotoTap, shine: shine, visible: visible)
            }
        }
        .frame(width: PassCardStyle.deckSize.width, height: PassCardStyle.deckSize.height)
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .background { PassTicketGlow(kind: face.kind, corner: corner) }
        .overlay(PassTicketEdge(kind: face.kind, corner: corner, shine: shine))
        .shadow(color: Color.black.opacity(0.7), radius: 24, x: 0, y: 24)
    }

    /// マルス券（既定の券面）
    private var marsFace: some View {
        VStack(spacing: 0) {
            PassFacePhoto(photo: face.photo, width: PassCardStyle.deckSize.width, height: PassCardStyle.photoHeight,
                          onTap: onPhotoTap)
            // 写真の下端の細い真鍮の線（黒い地の側に引く・写真には重ねない）
            PassTicketRule(opacity: PassCardStyle.photoRuleOpacity, shine: shine)
            VStack(alignment: .leading, spacing: PassCardStyle.frontSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    // 種類の名（ふつう＝「乗車券」・ほか＝「はじめての乗車券」など）。色や縁だけで種類を伝えない
                    PassTicketHead(text: face.headline)
                    Spacer(minLength: JPSpace.xs)
                    if let number = face.number { PassTicketNumber(text: number) }
                }
                route
                if let via = face.via {
                    Text(via)
                        .font(.system(size: PassCardStyle.metaSize))
                        .foregroundStyle(WebTheme.text3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                fieldGrid
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: JPSpace.xs) {
                    Text(face.name)
                        .font(.system(size: PassCardStyle.metaSize))
                        .foregroundStyle(WebTheme.text2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Text(PassTicket.frontValidity)
                        .font(.system(size: PassCardStyle.validitySize))
                        .tracking(PassCardStyle.validitySize * PassCardStyle.validityTracking)
                        .foregroundStyle(WebTheme.text3)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, PassCardStyle.inset)
            .padding(.top, PassCardStyle.frontTop)
            .padding(.bottom, PassCardStyle.frontBottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(PassCardStyle.face)
    }

    /// 区間。矢印はいつも中央・発と着は同じ幅の欄に同じ大きさで（`PassCardStyle.routeLayout`・2026-10-16 判断）。
    /// 名の後ろに小さな「発」「着」（英語は前に from / to・2026-10-17 判断）。読み上げは「東京発、フランス着」
    private var route: some View {
        let route = PassCardStyle.routeLayout(origin: face.origin, destination: face.destination)
        return HStack(alignment: .center, spacing: 0) {
            routeColumn(face.origin, mark: PassTicket.originMark, route)
                .frame(width: CGFloat(route.columnWidth), alignment: .trailing)
            PassTicketArrow()
                .padding(.horizontal, CGFloat(PassCardStyle.arrowGap))
            routeColumn(face.destination, mark: PassTicket.destinationMark, route)
                .frame(width: CGFloat(route.columnWidth), alignment: .leading)
        }
        .frame(width: CGFloat(PassCardStyle.routeWidth))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PassTicket.spokenRoute(origin: face.origin, destination: face.destination))
    }

    /// 片側の欄: 地名と「発」「着」を字の並びの線（下）でそろえる
    private func routeColumn(_ text: String, mark: String, _ route: PassCardStyle.RouteLayout) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: CGFloat(PassCardStyle.markGap)) {
            if PassTicket.marksLead { routeMark(mark) }
            routeName(text, route)
            if !PassTicket.marksLead { routeMark(mark) }
        }
    }

    private func routeMark(_ mark: String) -> some View {
        Text(mark)
            .font(.custom(JPFont.displayName, fixedSize: CGFloat(PassCardStyle.markSize)))
            .foregroundStyle(WebTheme.text2)
            .lineLimit(1)
            .fixedSize()
    }

    /// 区間の地名。**大きさは発・着で同じ**（`route.fontSize`）。札は寸法が決まっていて、字の大きさは並びに
    /// 収まるよう数えて決めるので、文字の大きさの設定では動かさない（動かすと片側だけ欄からはみ出して縮み、
    /// 左右がまたそろわなくなる）。
    ///
    /// 🔴 **`minimumScaleFactor` を付けない**（2026-10-17 判断）。付けていた版では、Mac の画面写真
    /// （「東京 → フランス」）で欄に十分収まる「東京」だけが下限（12pt）まで縮み、発と着がそろわなかった。
    /// 大きさは `routeLayout` で欄に収まるよう数えて決めてあるので、縮めずにその大きさで描く。
    /// 数え方が外れて収まらないときは、縮めずに末尾を「…」で切る（左右の大きさは崩さない）
    private func routeName(_ text: String, _ route: PassCardStyle.RouteLayout) -> some View {
        Text(text)
            .font(.custom(JPFont.displayName, fixedSize: CGFloat(route.fontSize)))
            .foregroundStyle(WebTheme.text)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// 日付・区間・回数の3つの欄（上下に白の細い線・値が無い欄は「—」・`PassTicket.frontFields`）
    private var fieldGrid: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(face.fields.enumerated()), id: \.offset) { _, field in
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.label)
                        .font(.system(size: PassCardStyle.fieldLabelSize))
                        .foregroundStyle(WebTheme.text3)
                        .lineLimit(1)
                    Text(field.value)
                        .font(.system(size: PassCardStyle.fieldValueSize).monospacedDigit())
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(1)
                        // 欄からはみ出しそうなときだけ 12 まで（本文系の最小）
                        .minimumScaleFactor(PassCardStyle.metaSize / PassCardStyle.fieldValueSize)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(PassTicket.spokenField(field))
            }
        }
        .padding(.vertical, PassCardStyle.fieldPadding)
        .overlay(alignment: .top) { PassTicketHairline() }
        .overlay(alignment: .bottom) { PassTicketHairline() }
    }
}

/// 「乗車券」「ご案内」の字組（明朝 15・字間 0.3em・真鍮）。表と裏で同じ
struct PassTicketHead: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.custom(JPFont.displayName, fixedSize: PassCardStyle.headSize))
            .tracking(PassCardStyle.headSize * PassCardStyle.headTracking)
            .foregroundStyle(WebTheme.accent)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// 「No.0087」（SF 600 11・字間 0.12em・等幅数字・真鍮）。表と裏で同じ
struct PassTicketNumber: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: PassCardStyle.numberSize, weight: .semibold).monospacedDigit())
            .tracking(PassCardStyle.numberSize * PassCardStyle.numberTracking)
            .foregroundStyle(WebTheme.accent)
            .lineLimit(1)
            .fixedSize()
    }
}

/// 真鍮の細い線（写真の下端・裏の帯の下）。回しているときは縁と同じ光が流れる
struct PassTicketRule: View {
    let opacity: Double
    var shine: Double? = nil

    var body: some View {
        Rectangle()
            .fill(WebTheme.accent.opacity(opacity))
            .overlay {
                if let light = PassTicketShine.style(at: shine) { Rectangle().fill(light) }
            }
            .frame(height: JPStroke.hairline)
            .accessibilityHidden(true)
    }
}

/// 欄の格子の白の細い線（板は白 10%。アプリの決まりの「札の中の行の間」＝`WebTheme.hairline`（8%）を使う）
struct PassTicketHairline: View {
    var body: some View {
        Rectangle()
            .fill(WebTheme.hairline)
            .frame(height: JPStroke.hairline)
            .accessibilityHidden(true)
    }
}

/// きっぷの裏（**マルス券・2026-10-17 判断**・候補の板 `Plain.dc.html` の「裏」）: 上に高さ 44 の帯
/// （案内の帯の地・下に真鍮の線）に「ご案内」と No.、作品名・ひとこと、発行／有効／区間／回数の4つの欄、
/// 真鍮の破線、裾に由来の一行。
///
/// **2026-10-18（札 #306）: 裏も券面で描き分ける**。マルス券はこのまま、特別な券面（Pro）は `PassSpecialBack`
/// （板「すれちがい乗車券の裏面」https://claude.ai/artifact/BgPadmCAZRPVjoicuTWyJ7）。並び・寸法・字の大きさは
/// どの券面も同じで、地・字の色・飾りだけを表の券面に合わせる。縁・後ろの光・影はマルス券と同じものを使う
struct PassCardBack: View {

    let face: PassTicketBackFace
    /// 回しているときの縁の光の位置
    var shine: Double? = nil
    /// 角の丸み（**表の券面の角に合わせる**・`PassCardFront.corner`・2026-10-17）
    var corner: CGFloat = PassCardStyle.deckCorner
    /// 裏がいま見えているか（表を見ている・全面の写真や Pro の案内が上にある間は false）。特別な券面の光を止める
    var visible: Bool = true

    var body: some View {
        Group {
            if face.style == .mars {
                marsBack
            } else {
                PassSpecialBack(face: face, shine: shine, visible: visible)
            }
        }
        .frame(width: PassCardStyle.deckSize.width, height: PassCardStyle.deckSize.height)
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .background { PassTicketGlow(kind: face.kind, corner: corner) }
        .overlay(PassTicketEdge(kind: face.kind, corner: corner, shine: shine))
        .shadow(color: Color.black.opacity(0.7), radius: 24, x: 0, y: 24)
        .accessibilityElement(children: .combine)
    }

    /// マルス券の裏（既定の券面）
    private var marsBack: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                PassTicketHead(text: L("ご案内", "NOTICE"))
                Spacer(minLength: JPSpace.xs)
                if let number = face.number { PassTicketNumber(text: number) }
            }
            .padding(.horizontal, PassCardStyle.inset)
            .frame(maxWidth: .infinity)
            .frame(height: PassCardStyle.bandHeight)
            .background(WebTheme.accentSoft)
            PassTicketRule(opacity: PassCardStyle.bandRuleOpacity, shine: shine)
            VStack(alignment: .leading, spacing: PassCardStyle.backSpacing) {
                Text(face.title)
                    .font(.custom(JPFont.displayName, fixedSize: PassCardStyle.backTitleSize))
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(2)
                if !face.note.isEmpty {
                    // 🔴 **ひとことには署名が無い**（電波の中身は誰でも書ける）。届いた文だと分かる書き方にする
                    VStack(alignment: .leading, spacing: JPSpace.xxs) {
                        Text(L("「\(face.note)」", "\u{201C}\(face.note)\u{201D}"))
                            .font(.system(size: PassCardStyle.noteSize))
                            .lineSpacing(5)
                            .foregroundStyle(WebTheme.text)
                            .lineLimit(3)
                        Text(PassPrivacyText.noteSource)
                            .font(.system(size: PassCardStyle.backLabelSize))
                            .foregroundStyle(WebTheme.text3)
                            .lineLimit(2)
                    }
                } else if face.noteHidden {
                    Text(L("ひとことは伏せています", "Note hidden"))
                        .font(.system(size: PassCardStyle.backLabelSize))
                        .foregroundStyle(WebTheme.text3)
                }
                Spacer(minLength: 0)
                fieldGrid
                PassTicketDash(shine: shine)
                Text(face.footnote)
                    .font(.system(size: PassCardStyle.footnoteSize))
                    .tracking(PassCardStyle.footnoteSize * PassCardStyle.footnoteTracking)
                    .lineSpacing(4)
                    .foregroundStyle(WebTheme.text3)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, PassCardStyle.backPadding)
            .padding(.top, PassCardStyle.backTop)
            .padding(.bottom, PassCardStyle.backPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: PassCardStyle.deckSize.width, height: PassCardStyle.deckSize.height)
        .background(PassCardStyle.face)
    }

    /// 発行・有効・区間・回数の 2×2（上に白の細い線・`PassTicket.backFields`）
    private var fieldGrid: some View {
        let fields = face.fields
        return VStack(alignment: .leading, spacing: PassCardStyle.backFieldGap) {
            ForEach(Array(stride(from: 0, to: fields.count, by: 2)), id: \.self) { row in
                HStack(alignment: .top, spacing: PassCardStyle.backFieldGap) {
                    field(fields[row])
                    if row + 1 < fields.count { field(fields[row + 1]) }
                }
            }
        }
        .padding(.top, PassCardStyle.backFieldGap)
        .overlay(alignment: .top) { PassTicketHairline() }
    }

    private func field(_ field: PassTicket.Field) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(field.label)
                .font(.system(size: PassCardStyle.backLabelSize))
                .foregroundStyle(WebTheme.text3)
                .lineLimit(1)
            Text(field.value)
                .font(.system(size: PassCardStyle.backValueSize).monospacedDigit())
                .foregroundStyle(WebTheme.text)
                // 「有効」だけ2行まで（字は縮めない・`PassCardStyle.backValueLines`）
                .lineLimit(PassCardStyle.backValueLines(field))
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PassTicket.spokenField(field))
    }
}

/// 小さなきっぷ（**マルス券の縮小版・2026-10-17 判断**）。帳の札（`PassTicketSlot`）とホームの束（`PassMiniStack`）が使う。
///
/// - 地・写真の窓・縁は大きい札と同じ決まり（`PassFaceGround`・`PassTicketEdge`・`PassTicketGlow`）を縮めて使う。
///   特別な券面（Pro）は、その券面の地（真鍮・漆・革など）が分かる。傾きの光・弧をたどる光・細かい地紋は描かない
/// - 字は縮めない: 頭の「乗車券」（明朝 12・真鍮）と番号（11）・「東京 → フランス」（`PassCardStyle.miniRoute`・
///   発と着は同じ大きさ）・名前と種類の言葉（帳の札だけ）。入らない欄（経由・日付／区間／回数・ずっと有効）は省く
/// - 🔴 写真は `PassFacePhoto`（窓に収めて角を丸めるだけ）。写真の上には何も重ねない
struct PassMiniTicket: View {
    let face: PassTicketFace
    let size: CGSize
    /// 頭の右の番号（帳の札は「0087」・ホームの束は nil）
    var number: String? = nil
    /// 名前の行（と種類の言葉）を出すか（ホームの束は高さが足りないので出さない）
    var showsName: Bool = true

    /// 縁と後ろの光の種類（2026-10-17 の見直し）。種類を言葉で言えるとき（名前の行の種類の言葉）だけ種類ごとの縁と
    /// 「はじめて」の光にする。ホームの束は言葉が無いので、**縁の色と光だけで種類を伝えない**よう、ふつうの縁で光らせない
    /// （重ねた束では、上のきっぷの光が下のきっぷの写真にかかるのも避ける）
    nonisolated static func edgeKind(_ kind: PassTicket.Kind, showsName: Bool) -> PassTicket.Kind {
        showsName ? kind : .plain
    }
    private var edgeKind: PassTicket.Kind { Self.edgeKind(face.kind, showsName: showsName) }

    /// 角（板の束 9。特別な券面は表の角の比で: 10 硬券は小さく・26 革は大きく）
    nonisolated static func corner(_ style: PassTicketFaceStyle) -> CGFloat {
        PassCardStyle.miniCorner * PassCardFront.corner(style) / PassCardStyle.deckCorner
    }

    /// 字の色（券面ごと・大きい札と同じ組み合わせ）
    private struct Ink {
        let head: AnyShapeStyle
        let number: AnyShapeStyle
        let names: AnyShapeStyle
        let arrow: Color
        let meta: Color
        let kind: AnyShapeStyle
    }

    private var ink: Ink {
        let accent = AnyShapeStyle(WebTheme.accent)
        let foil = AnyShapeStyle(PassFaceColor.foil(.center))
        let text2 = PassFaceColor.of(PassFacePalette.text2)
        switch face.style {
        case .mars, .greatCircle:
            return Ink(head: accent, number: accent, names: AnyShapeStyle(WebTheme.text), arrow: WebTheme.accent,
                       meta: WebTheme.text2, kind: accent)
        case .brassPlate:
            // 真鍮の板の上は墨（真鍮の面に真鍮・白を置かない）
            let ink = PassFaceColor.of(PassFacePalette.brassInk)
            return Ink(head: AnyShapeStyle(ink), number: AnyShapeStyle(ink), names: AnyShapeStyle(ink), arrow: ink,
                       meta: PassFaceColor.of(PassFacePalette.brassInk, PassFacePalette.brassSmallInkOpacity),
                       kind: AnyShapeStyle(ink))
        case .foilHard:
            return Ink(head: foil, number: AnyShapeStyle(text2), names: foil, arrow: WebTheme.accent, meta: text2, kind: foil)
        case .urushi:
            return Ink(head: foil, number: foil, names: AnyShapeStyle(Color.white), arrow: WebTheme.accent, meta: text2,
                       kind: foil)
        case .leather:
            let number = AnyShapeStyle(PassFaceColor.of(PassFacePalette.leatherNumber))
            return Ink(head: foil, number: number, names: foil, arrow: WebTheme.accent,
                       meta: PassFaceColor.of(PassFacePalette.leatherName), kind: number)
        }
    }

    var body: some View {
        let sx = size.width / PassFaceGround.size.width
        let sy = size.height / PassFaceGround.size.height
        let window = PassFaceGround.window(face.style)
        let corner = Self.corner(face.style)
        let ink = ink
        // 字は窓（と写真の下端の線）の下から
        let textTop: CGFloat = (window.maxY + CGFloat(6)) * sy + CGFloat(2)
        ZStack(alignment: .topLeading) {
            PassFaceGround(style: face.style, behindText: true)
                .scaleEffect(x: sx, y: sy, anchor: .topLeading)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
            PassFacePhoto(photo: face.photo, width: window.width * sx, height: window.height * sy,
                          corner: PassFaceGround.windowCorner(face.style) * sx)
                .offset(x: window.minX * sx, y: window.minY * sy)
            VStack(alignment: .leading, spacing: PassCardStyle.miniSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(PassTicket.headline(.plain))
                        .font(.custom(JPFont.displayName, fixedSize: PassCardStyle.miniHeadSize))
                        .tracking(PassCardStyle.miniHeadSize * PassCardStyle.headTracking)
                        .foregroundStyle(ink.head)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let number {
                        Text(number)
                            .font(.system(size: PassCardStyle.numberSize, weight: .semibold).monospacedDigit())
                            .foregroundStyle(ink.number)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                route(ink)
                if showsName {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(face.name)
                            .font(.system(size: PassCardStyle.metaSize))
                            .foregroundStyle(ink.meta)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                        if let kind = PassTicket.miniKind(face.kind) {
                            Text(kind)
                                .font(.system(size: PassCardStyle.numberSize, weight: .semibold))
                                .foregroundStyle(ink.kind)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                }
            }
            .padding(.horizontal, PassCardStyle.miniInset)
            .frame(width: size.width, alignment: .topLeading)
            .offset(y: textTop)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .background { PassTicketGlow(kind: edgeKind, corner: corner) }
        // 縁は外側に（写真の上に真鍮をかけない）
        .overlay(PassTicketEdge(kind: edgeKind, corner: corner))
    }

    /// 区間（大きい札と同じ並べ方: 矢印は中央・発と着は同じ幅の欄に同じ大きさ。`minimumScaleFactor` を付けない）
    private func route(_ ink: Ink) -> some View {
        let width = Double(size.width - PassCardStyle.miniInset * 2)
        let route = PassCardStyle.miniRoute(origin: face.origin, destination: face.destination, width: width)
        return HStack(alignment: .center, spacing: 0) {
            routeName(face.origin, route, ink)
                .frame(width: CGFloat(route.columnWidth), alignment: .trailing)
            PassTicketArrow(color: ink.arrow, lineWidth: 1.2, width: CGFloat(PassCardStyle.miniArrow.width))
                .padding(.horizontal, CGFloat(PassCardStyle.miniArrow.gap))
            routeName(face.destination, route, ink)
                .frame(width: CGFloat(route.columnWidth), alignment: .leading)
        }
        .frame(width: CGFloat(width))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PassTicket.spokenRoute(origin: face.origin, destination: face.destination))
    }

    private func routeName(_ text: String, _ route: PassCardStyle.RouteLayout, _ ink: Ink) -> some View {
        Text(text)
            .font(.custom(JPFont.displayName, fixedSize: CGFloat(route.fontSize)))
            .foregroundStyle(ink.names)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// 帳の綴じの小さなきっぷ（マルス券の縮小版 `PassMiniTicket`・番号と名前と種類の言葉つき）。
/// 読み上げは札のボタンの名前（`PassBookView`「〇〇 のカード」）
struct PassTicketSlot: View {
    let content: PassCardContent

    var body: some View {
        Color.clear
            .aspectRatio(5.0 / 7.0, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    PassMiniTicket(face: content.face(), size: geo.size,
                                   number: PassExchange.shortNumber(content.card.number))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: PassMiniTicket.corner(content.faceStyle)))
    }
}

/// ホームの束（3枚の小さなきっぷを少しずつ傾けて重ねる・板 PassHome）。1枚ずつ `PassMiniTicket`（名前の行なし）
struct PassMiniStack: View {

    let faces: [PassTicketFace]

    private static let tilts: [Double] = [-9, 6, -3]
    private static let lefts: [CGFloat] = [0, 14, 28]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(faces.prefix(3).enumerated()), id: \.offset) { index, face in
                PassMiniTicket(face: face, size: PassCardStyle.stackSize, showsName: false)
                    .shadow(color: Color.black.opacity(0.6), radius: 9, x: 0, y: 10)
                    .rotationEffect(.degrees(Self.tilts[index]))
                    .offset(x: Self.lefts[index], y: 6)
            }
        }
        .frame(width: 140, height: 144, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

/// 束の画面で写真を押したときの全面（**写真の上は白だけ**）。払う・× で閉じる
struct PassPhotoFullView: View {
    let photo: Photo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            DownsampledRemoteImage(url: photo.detailImageURL ?? photo.gridImageURL, contentMode: .fit,
                                   aspectRatio: photo.aspectRatio.map { CGFloat($0) })
                .ignoresSafeArea()
                .accessibilityLabel(photo.displayTitle)
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.white)
                            .frame(width: 44, height: 44)
                            .jpGlass(in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Labels.Common.close)
                    .accessibilityIdentifier("pass.photo.close")
                }
                .padding(.horizontal, JPSpace.gutter)
                Spacer()
                Text(photo.displayTitle)
                    .font(JPFont.cardTitle)
                    .foregroundStyle(Color.white)
                    .jpPhotoTextShadow()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, JPSpace.gutter)
                    .padding(.bottom, JPSpace.m)
                    .accessibilityHidden(true)
            }
        }
        .preferredColorScheme(.dark)
    }
}
