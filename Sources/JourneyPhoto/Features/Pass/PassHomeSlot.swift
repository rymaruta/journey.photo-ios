import SwiftUI

/// ホームのいちばん上の「カードが届きました」の札（板 PassHome）。
///
/// **入口の判断（2026-10-16）**: 板 PassHome はホームの見出しのすぐ下に札を置き、「ここから下はいつもの
/// ホーム」と書いている。だからストーリーの輪より上に置く。札が出るのは**届いた束をまだ開いていない
/// ときだけ**（誰ともすれちがわない日・開き終えた束は何も出さない）。帳はマイページの旅の記録の札
/// （`MyPageView.tripToolsCard`・板 PassBook の戻り先がマイページ）、設定は設定の「すれちがい」の節から。
///
/// 札を押すと束を開く（`PassViewerView`）。夕方の知らせを押したとき（`PassStore.requestOpen`）も同じ
struct PassHomeSlot: View {

    /// 出す束（`GalleryView` が「いま」で決めて渡す）。空なら何も描かない
    let cards: [PassCardContent]
    /// 束を決めた「いま」（今日の束か）
    let now: Date
    /// 束を開く（シートと帳への押し込みは `GalleryView` が持つ）
    let open: () -> Void

    /// 🔴 **この部品は中身だけ。** 写真を引く `.task`・「いま」を入れ直す処理は `GalleryView`
    /// （`LazyVStack` の外）が持つ——札が空の間は子が無く、ここに付けた `.task` が走らないことがあった
    /// （2026-10-16 の読み直し）
    var body: some View {
        if !cards.isEmpty {
            PassHomeCard(cards: cards, isToday: PassHomeSlot.isToday(cards, now: now), open: open)
                .padding(.horizontal, JPSpace.gutter)
        }
    }

    static func isToday(_ cards: [PassCardContent], now: Date, calendar: Calendar = .current) -> Bool {
        let today = PassExchange.dayKey(now, calendar: calendar)
        return cards.allSatisfy { PassExchange.dayKey($0.card.deliverAt, calendar: calendar) == today }
    }
}

/// 開く束（`fullScreenCover(item:)` に渡す）
struct PassDeck: Identifiable {
    let cards: [PassCardContent]
    var id: String { cards.map(\.id).joined(separator: ",") }
}

/// 札の見た目（板 PassHome の `.card`: 真鍮 35% の縁・左に3枚の束・右に眉・明朝 22・一行・「束を開く ›」）
struct PassHomeCard: View {

    let cards: [PassCardContent]
    let isToday: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: JPSpace.m) {
                PassMiniStack(faces: cards.prefix(3).map { $0.face() })
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("カードが届きました", "Cards have arrived"))
                        .jpEyebrow()
                        .foregroundStyle(WebTheme.accent)
                    Text(countTitle)
                        .font(JPFont.cardTitle)
                        .foregroundStyle(WebTheme.text)
                    Text(PassBook.bundleLine(cards.map(\.card)))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("束を開く ›", "Open the bundle ›"))
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(JPSpace.m)
            .background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.l))
            .overlay(RoundedRectangle(cornerRadius: JPRadius.l)
                .strokeBorder(WebTheme.accent.opacity(PassCardStyle.footerLineOpacity), lineWidth: JPStroke.hairline))
            .contentShape(RoundedRectangle(cornerRadius: JPRadius.l))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isToday
            ? L("今日すれちがった \(cards.count)人のカードを開く", "Open cards from \(cards.count) people you passed today")
            : L("届いた \(cards.count)人のカードを開く", "Open \(cards.count) cards that arrived"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("pass.home.open")
    }

    private var countTitle: String {
        isToday ? L("今日 \(cards.count) 枚", "\(cards.count) today") : L("\(cards.count) 枚", "\(cards.count) cards")
    }
}
