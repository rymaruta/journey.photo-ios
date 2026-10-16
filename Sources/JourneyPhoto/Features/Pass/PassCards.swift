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

/// カードの見た目の決まり（板 PassViewer・PassCardPick・PassHome）。テストで見張る
enum PassCardStyle {
    /// 束を開いた画面のカード（板 `.deck` 300×430・角 18・写真 360・下の帯 70）
    static let deckSize = CGSize(width: 300, height: 430)
    static let deckCorner: CGFloat = 18
    static let deckFooter: CGFloat = 70
    /// 名刺の一枚の見本（板 `.pc` 236×330・角 14・下の帯 60）
    static let previewSize = CGSize(width: 236, height: 330)
    static let previewCorner: CGFloat = 14
    static let previewFooter: CGFloat = 60
    /// ホームの束の1枚（板 92×128・角 9・写真 104）
    static let stackSize = CGSize(width: 92, height: 128)
    static let stackCorner: CGFloat = 9
    /// カードの縁の真鍮の濃さ（板 rgba(201,166,107,.5) / .45）・帯の上の線（.35）
    static let edgeOpacity = 0.5
    static let footerLineOpacity = 0.35
    /// カードの地（板 #0b0b0c）
    static let face = Color(red: 11 / 255, green: 11 / 255, blue: 12 / 255)
    /// 裏の地の光（板 #1d1810 → #0b0b0c）
    static let backGlow = Color(red: 29 / 255, green: 24 / 255, blue: 16 / 255)
}

/// カードの表（写真＋下の帯: アイコン・名前・「〇〇から」・番号）。
///
/// **帯は黒地**（写真の上ではない）なので、番号は真鍮で置ける（板）
struct PassCardFront: View {

    let photo: Photo?
    let name: String
    var avatarURL: URL?
    var from: String?
    var number: String?
    var size: CGSize = PassCardStyle.deckSize
    var corner: CGFloat = PassCardStyle.deckCorner
    var footer: CGFloat = PassCardStyle.deckFooter

    private var compact: Bool { footer < PassCardStyle.deckFooter }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if let photo {
                        DownsampledRemoteImage(url: photo.gridImageURL, contentMode: .fill,
                                               aspectRatio: photo.aspectRatio.map { CGFloat($0) },
                                               alignment: photo.gridAlignment)
                    } else {
                        WebTheme.surface
                    }
                }
                .clipped()
            HStack(spacing: compact ? 8 : 10) {
                RemoteImage(url: avatarURL, placeholderSymbol: "person.fill")
                    .frame(width: compact ? 28 : 36, height: compact ? 28 : 36)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name)
                        .font(compact ? JPFont.footnote.weight(.semibold) : JPFont.bodyEmphasis)
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(1)
                    if let from {
                        Text(from)
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.text3)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let number {
                    Text(number)
                        .font(JPFont.meta)
                        .foregroundStyle(WebTheme.accent)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, compact ? 12 : 14)
            .frame(height: footer)
            .frame(maxWidth: .infinity)
            .background(PassCardStyle.face)
            .overlay(alignment: .top) {
                Rectangle().fill(WebTheme.accent.opacity(PassCardStyle.footerLineOpacity)).frame(height: JPStroke.hairline)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(PassCardStyle.face)
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .overlay(RoundedRectangle(cornerRadius: corner)
            .strokeBorder(WebTheme.accent.opacity(PassCardStyle.edgeOpacity), lineWidth: JPStroke.hairline))
        .shadow(color: Color.black.opacity(0.6), radius: 20, x: 0, y: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("\(name) のカード", "\(name)\u{2019}s card"))
    }
}

/// カードの裏（板 PassViewer の `.back`: すれちがった記録）。**時刻は時の単位、場所は「〇〇のあたり」**
struct PassCardBack: View {

    let content: PassCardContent

    private var calendar: Calendar { .current }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            JPEyebrowLine(L("すれちがった記録", "Where you passed"))
            Text(content.photo.displayTitle)
                .font(JPFont.display(24, relativeTo: .title2))
                .foregroundStyle(WebTheme.text)
                .lineLimit(2)
            if !content.card.note.isEmpty {
                Text(L("「\(content.card.note)」", "\u{201C}\(content.card.note)\u{201D}"))
                    .font(.callout)
                    .lineSpacing(6)
                    .foregroundStyle(WebTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let place = PassExchange.placeLabel(content.card.placeName) {
                row("mappin", place)
            }
            row("clock", PassExchange.timeLabel(content.card.metHour, calendar: calendar), mono: true)
            row("arrow.left.arrow.right", PassExchange.meetingLabel(content.meetingCount))
            Spacer(minLength: 0)
            if let pref = content.fromPrefecture,
               let km = PassExchange.travelKm(fromPrefecture: pref, to: content.card.place),
               let route = PassExchange.routeLabel(fromPrefecture: pref, placeName: content.card.placeName, km: km) {
                HStack(spacing: 10) {
                    Rectangle().fill(WebTheme.accent.opacity(0.3)).frame(height: JPStroke.hairline)
                        .accessibilityHidden(true)
                    Text(route)
                        .font(JPFont.meta)
                        .foregroundStyle(WebTheme.accent)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 26)
        .frame(width: PassCardStyle.deckSize.width, height: PassCardStyle.deckSize.height, alignment: .topLeading)
        .background(RadialGradient(colors: [PassCardStyle.backGlow, PassCardStyle.face],
                                   center: UnitPoint(x: 0.5, y: 0.2), startRadius: 0, endRadius: 300))
        .clipShape(RoundedRectangle(cornerRadius: PassCardStyle.deckCorner))
        .overlay(RoundedRectangle(cornerRadius: PassCardStyle.deckCorner)
            .strokeBorder(WebTheme.accent.opacity(PassCardStyle.edgeOpacity), lineWidth: JPStroke.hairline))
        .shadow(color: Color.black.opacity(0.6), radius: 20, x: 0, y: 18)
        .accessibilityElement(children: .combine)
    }

    private func row(_ symbol: String, _ text: String, mono: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(text)
                .font(mono ? JPFont.mono(14, relativeTo: .subheadline) : .subheadline)
                .lineLimit(2)
        }
        .foregroundStyle(WebTheme.text2)
    }
}

/// ホームの束（3枚を少しずつ傾けて重ねる・板 PassHome）
struct PassMiniStack: View {

    let photos: [Photo]

    private static let tilts: [Double] = [-9, 6, -3]
    private static let lefts: [CGFloat] = [0, 14, 28]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(photos.prefix(3).enumerated()), id: \.offset) { index, photo in
                VStack(spacing: 0) {
                    RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
                        .frame(height: 104)
                        .clipped()
                    PassCardStyle.face
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
