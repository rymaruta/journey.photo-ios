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

    /// 表に描くもの
    func face(calendar: Calendar = .current) -> PassTicketFace {
        PassTicketFace(photo: photo, kind: kind, number: PassExchange.numberLabel(card.number),
                       origin: PassTicket.origin(fromPrefecture), destination: PassTicket.destination(card.placeName),
                       name: name, distance: PassTicket.distanceLabel(km),
                       date: PassTicket.dateLabel(card.metHour, calendar: calendar),
                       alighting: PassTicket.alighting(card.placeName))
    }

    /// 前の記録（ひとことを伏せた等）を新しい記録に差し替える
    func with(card next: PassEncounter) -> PassCardContent {
        PassCardContent(card: next, photo: photo, owner: owner, fromPrefecture: fromPrefecture, meetingCount: meetingCount)
    }

    static func == (lhs: PassCardContent, rhs: PassCardContent) -> Bool {
        lhs.card == rhs.card && lhs.photo.id == rhs.photo.id && lhs.owner?.userId == rhs.owner?.userId
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

/// きっぷの表に描くもの（見本の名刺も同じ形で作る）
struct PassTicketFace {
    let photo: Photo?
    let kind: PassTicket.Kind
    /// 「No.0087」。決まらないとき（自分の名刺の見本）は nil
    let number: String?
    let origin: String
    let destination: String
    let name: String
    let distance: String?
    let date: String?
    let alighting: String
}

/// カードの見た目の決まり（**2026-10-16 判断（owner が案C を選んだ）**・板 AltC・CardKinds）。テストで見張る
enum PassCardStyle {
    /// 束を開いた画面のカード（板 300×430・角 14・写真 250）
    static let deckSize = CGSize(width: 300, height: 430)
    static let deckCorner: CGFloat = 14
    static let photoHeight: CGFloat = 250
    /// 名刺の一枚の見本（同じきっぷを縮めて出す）
    static let previewScale: CGFloat = 236.0 / 300.0
    /// ホームの束の1枚（板 92×128・角 9・写真 76）
    static let stackSize = CGSize(width: 92, height: 128)
    static let stackCorner: CGFloat = 9
    /// 縁の真鍮の濃さ（板 rgba(201,166,107,.5)）
    static let edgeOpacity = 0.5
    static let footerLineOpacity = 0.35
    /// 破線・改札の穴の縁（板 .5）
    static let dashOpacity = 0.5
    /// きっぷの地（板 #0E0D0B・黒に少し暖色を混ぜた紙）
    static let face = Color(red: 14 / 255, green: 13 / 255, blue: 11 / 255)
    /// 裏の真鍮寄りの帯（板 #2A2418 → #1A160F）
    static let bandTop = Color(red: 42 / 255, green: 36 / 255, blue: 24 / 255)
    static let bandBottom = Color(red: 26 / 255, green: 22 / 255, blue: 15 / 255)
    /// 「遠くから」の縁の沈む側（板 #3A3020）
    static let farEdgeLow = Color(red: 58 / 255, green: 48 / 255, blue: 32 / 255)
    /// 区間の地名（明朝 30）。長い地名は縮める——明朝の下限 18 まで（30 × 0.6）
    static let routeSize: Double = 30
    static let routeMinScale: CGFloat = 0.6
}

/// 種類ごとの縁（板 CardKinds: ふつう＝細い線・はじめて＝光る真鍮・また会えた＝2本線・遠くから＝沈む真鍮）。
/// **色だけで伝えない**: 眉ラベルの言葉（`PassTicket.eyebrow`）と裏の「回数」でも言う
struct PassTicketEdge: View {
    let kind: PassTicket.Kind
    var corner: CGFloat = PassCardStyle.deckCorner

    private var outerCorner: CGFloat { corner + 4 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner)
        switch kind {
        case .plain:
            shape.strokeBorder(WebTheme.accent.opacity(PassCardStyle.edgeOpacity), lineWidth: JPStroke.hairline)
        case .first:
            shape.strokeBorder(LinearGradient(colors: WebTheme.accentMetal + [WebTheme.accentMetal[0]],
                                              startPoint: .topLeading, endPoint: .bottomTrailing),
                               lineWidth: JPStroke.emphasis)
                .shadow(color: WebTheme.accent.opacity(0.28), radius: 12)
        case .again:
            ZStack {
                shape.strokeBorder(WebTheme.accent.opacity(PassCardStyle.edgeOpacity), lineWidth: JPStroke.hairline)
                // 外にもう1本（黒 3 のすき間を空けて）
                RoundedRectangle(cornerRadius: outerCorner)
                    .strokeBorder(WebTheme.accent.opacity(0.45), lineWidth: JPStroke.hairline)
                    .padding(-4)
            }
        case .far:
            shape.strokeBorder(LinearGradient(colors: [WebTheme.accent, PassCardStyle.farEdgeLow],
                                              startPoint: .top, endPoint: .bottom),
                               lineWidth: 1.5)
        }
    }
}

/// 真鍮の破線（板 4 引いて 4 空ける）
struct PassTicketDash: View {
    var body: some View {
        Rectangle()
            .stroke(WebTheme.accent.opacity(PassCardStyle.dashOpacity), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// 改札の穴（板: 14 の黒い丸に真鍮 50% の縁）
struct PassTicketPunch: View {
    var size: CGFloat = 14
    var body: some View {
        Circle()
            .fill(Color.black)
            .overlay(Circle().strokeBorder(WebTheme.accent.opacity(PassCardStyle.dashOpacity), lineWidth: JPStroke.hairline))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// 区間の矢印（板: 56×14 の細い線・真鍮）
struct PassTicketArrow: View {
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 2, y: 7))
            p.addLine(to: CGPoint(x: 50, y: 7))
            p.move(to: CGPoint(x: 44, y: 2))
            p.addLine(to: CGPoint(x: 50, y: 7))
            p.addLine(to: CGPoint(x: 44, y: 12))
        }
        .stroke(WebTheme.accent, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        .frame(width: 56, height: 14)
        .accessibilityHidden(true)
    }
}

/// きっぷの表（板 AltC の左: 上に写真、下に「すれちがい乗車券」と No.・区間・名前と距離と日時・破線・下車と穴）。
///
/// **写真の下は黒い地**なので真鍮が置ける。写真の上には何も置かない（写真を押すと全面で見られる・`onPhotoTap`）
struct PassCardFront: View {

    let face: PassTicketFace
    /// 写真を押した（束の画面: 全面で見る）。nil なら写真も裏返しの一部
    var onPhotoTap: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            photo
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(PassTicket.eyebrow(face.kind))
                        .jpEyebrow()
                        .foregroundStyle(WebTheme.accent)
                        .lineLimit(1)
                    Spacer(minLength: JPSpace.xs)
                    if let number = face.number {
                        Text(number)
                            .font(JPFont.eyebrow)
                            .tracking(JPTypeScale.eyebrowTracking)
                            .foregroundStyle(WebTheme.accent)
                    }
                }
                HStack(alignment: .center, spacing: JPSpace.xs) {
                    routeName(face.origin)
                    Spacer(minLength: 0)
                    PassTicketArrow()
                    Spacer(minLength: 0)
                    routeName(face.destination)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(PassTicket.spokenRoute(origin: face.origin, destination: face.destination))
                HStack(spacing: JPSpace.xs) {
                    Text(face.name).lineLimit(1)
                    Spacer(minLength: 0)
                    if let distance = face.distance { Text(distance).lineLimit(1).fixedSize() }
                    if let date = face.date {
                        Spacer(minLength: 0)
                        Text(date).lineLimit(1).fixedSize()
                    }
                }
                .font(JPFont.meta)
                .foregroundStyle(WebTheme.text2)
                Spacer(minLength: 0)
                PassTicketDash()
                HStack {
                    Text(face.alighting)
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                        .lineLimit(1)
                    Spacer(minLength: JPSpace.xs)
                    PassTicketPunch()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: PassCardStyle.deckSize.width, height: PassCardStyle.deckSize.height)
        .background(PassCardStyle.face)
        .clipShape(RoundedRectangle(cornerRadius: PassCardStyle.deckCorner))
        .overlay(PassTicketEdge(kind: face.kind))
        .shadow(color: Color.black.opacity(0.7), radius: 24, x: 0, y: 24)
    }

    private func routeName(_ text: String) -> some View {
        Text(text)
            .font(JPFont.display(PassCardStyle.routeSize, relativeTo: .title))
            .foregroundStyle(WebTheme.text)
            .lineLimit(1)
            .minimumScaleFactor(PassCardStyle.routeMinScale)
    }

    @ViewBuilder
    private var photo: some View {
        let image = Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: PassCardStyle.photoHeight)
            .overlay {
                if let photo = face.photo {
                    DownsampledRemoteImage(url: photo.gridImageURL, contentMode: .fill,
                                           aspectRatio: photo.aspectRatio.map { CGFloat($0) },
                                           alignment: photo.gridAlignment)
                } else {
                    WebTheme.surface
                }
            }
            .clipped()
        if let onPhotoTap {
            image
                .contentShape(Rectangle())
                .onTapGesture(perform: onPhotoTap)
        } else {
            image
        }
    }
}

/// きっぷの裏（板 AltC の右: 真鍮寄りの帯・「ご案内」・作品名・ひとこと・発行／有効／区間／回数）
struct PassCardBack: View {

    let content: PassCardContent

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [PassCardStyle.bandTop, PassCardStyle.bandBottom], startPoint: .top, endPoint: .bottom)
                .frame(height: 38)
                .padding(.top, 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                Text(L("ご案内", "NOTICE"))
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                Text(content.photo.displayTitle)
                    .font(JPFont.cardTitle)
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(2)
                if !content.card.shownNote.isEmpty {
                    // 🔴 **ひとことには署名が無い**（電波の中身は誰でも書ける）。届いた文だと分かる書き方にする
                    VStack(alignment: .leading, spacing: JPSpace.xxs) {
                        Text(L("「\(content.card.shownNote)」", "\u{201C}\(content.card.shownNote)\u{201D}"))
                            .font(JPFont.body)
                            .lineSpacing(5)
                            .foregroundStyle(WebTheme.text)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(PassPrivacyText.noteSource)
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if content.card.noteHidden == true {
                    Text(L("ひとことは伏せています", "Note hidden"))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        field(L("発行", "Issued by"), PassTicket.issuer(name: content.name, prefecture: content.fromPrefecture))
                        field(L("有効", "Valid"), PassTicket.validity)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        field(L("区間", "Distance"), PassTicket.sectionLabel(content.km), mono: true)
                        field(L("回数", "Times"), PassTicket.countLabel(content.kind, meetingCount: content.card.ownerId == nil ? nil : content.meetingCount))
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: PassCardStyle.deckSize.width, height: PassCardStyle.deckSize.height)
        .background(PassCardStyle.face)
        .clipShape(RoundedRectangle(cornerRadius: PassCardStyle.deckCorner))
        .overlay(PassTicketEdge(kind: content.kind))
        .shadow(color: Color.black.opacity(0.7), radius: 24, x: 0, y: 24)
        .accessibilityElement(children: .combine)
    }

    private func field(_ label: String, _ value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(JPFont.caption).foregroundStyle(WebTheme.text3)
            Text(value)
                .font(mono ? JPFont.mono(14, relativeTo: .subheadline) : .subheadline)
                .foregroundStyle(WebTheme.text)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 帳の綴じの小さなきっぷ（写真・名前・種類の言葉と番号・破線と穴）
struct PassTicketSlot: View {
    let content: PassCardContent

    var body: some View {
        Color.clear
            .aspectRatio(5.0 / 7.0, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        RemoteImage(url: content.photo.gridImageURL, alignment: content.photo.gridAlignment)
                            .frame(height: geo.size.height * 0.6)
                            .clipped()
                        VStack(alignment: .leading, spacing: 3) {
                            Text(content.name)
                                .font(JPFont.caption.weight(.semibold))
                                .foregroundStyle(WebTheme.text)
                                .lineLimit(1)
                            HStack(spacing: 2) {
                                Text(PassTicket.eyebrow(content.kind))
                                    .font(JPFont.eyebrow)
                                    .foregroundStyle(WebTheme.accent)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text(PassExchange.shortNumber(content.card.number))
                                    .font(JPFont.meta)
                                    .foregroundStyle(WebTheme.accent)
                                    .fixedSize()
                            }
                            Spacer(minLength: 0)
                            HStack {
                                PassTicketDash()
                                PassTicketPunch(size: 8)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(PassCardStyle.face)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(PassTicketEdge(kind: content.kind, corner: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// ホームの束（3枚の小さなきっぷを少しずつ傾けて重ねる・板 PassHome）
struct PassMiniStack: View {

    let photos: [Photo]

    private static let tilts: [Double] = [-9, 6, -3]
    private static let lefts: [CGFloat] = [0, 14, 28]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(photos.prefix(3).enumerated()), id: \.offset) { index, photo in
                VStack(spacing: 0) {
                    RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
                        .frame(height: 76)
                        .clipped()
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        HStack(spacing: 4) {
                            PassTicketDash()
                            PassTicketPunch(size: 7)
                        }
                        .padding(.horizontal, 7)
                        .padding(.bottom, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PassCardStyle.face)
                }
                .frame(width: PassCardStyle.stackSize.width, height: PassCardStyle.stackSize.height)
                .clipShape(RoundedRectangle(cornerRadius: PassCardStyle.stackCorner))
                .overlay(RoundedRectangle(cornerRadius: PassCardStyle.stackCorner)
                    .strokeBorder(WebTheme.accent.opacity(0.45), lineWidth: JPStroke.hairline))
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
