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

/// 札の見た目。**#417 ①（2026-10-30 owner 採用・板 Main の `passArrived`）: 低い帯にした。**
/// 高さ 76・角 16・地は札の面（#0E0E0F）・縁は真鍮 35%。左に束の絵（44×54）、真ん中に眉「カードが届きました」（11）・
/// 明朝 18 の「今日 N 枚」（数は SF の等幅数字）・12 の地名、右に「束を開く ›」（13・真鍮・当たり 44）。
/// 以前は高さ 176（束の絵 140×144・明朝 22）で、下の中身が 100pt 下がっていた。位置は見出しのすぐ下のまま（板 PassHome）
struct PassHomeCard: View {

    let cards: [PassCardContent]
    let isToday: Bool
    let open: () -> Void

    /// 帯の高さ（板 76）
    nonisolated static let height: CGFloat = 76
    /// 帯の内側（板 padding: 0 4 0 12）。右は「束を開く ›」の当たり 44 が端まで届くよう 4 だけ
    nonisolated static let leadingInset: CGFloat = 12
    nonisolated static let trailingInset: CGFloat = 4
    /// 絵・字・「束を開く」の間（板 gap 12）
    nonisolated static let gap: CGFloat = 12

    var body: some View {
        Button(action: open) {
            HStack(spacing: Self.gap) {
                PassMiniStack(faces: cards.prefix(3).map { $0.face() }, compact: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("カードが届きました", "Cards have arrived"))
                        .jpEyebrow()
                        .foregroundStyle(WebTheme.accent)
                        .lineLimit(1)
                    countTitle
                        .font(JPFont.rowTitle)
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(1)
                    Text(PassBook.bundleLine(cards.map(\.card)))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(L("束を開く ›", "Open ›"))
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.accent)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, JPSpace.xs)
                    .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
            }
            .padding(.leading, Self.leadingInset)
            .padding(.trailing, Self.trailingInset)
            // 字を大きくする設定では帯が伸びる（字を切らない）。ふだんは板の 76
            .frame(minHeight: Self.height)
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

    /// 「今日 N 枚」。**数だけ SF の等幅数字**（板: 明朝の中の数は system・tabular-nums。CLAUDE.md の数字の決まり）
    private var countTitle: Text {
        let parts = Self.countParts(count: cards.count, isToday: isToday)
        return Text(parts.prefix)
            + Text("\(cards.count)").font(JPFont.number(JPTypeScale.title3, weight: .semibold, relativeTo: .title3))
            + Text(parts.suffix)
    }

    /// 数の前後の字（「今日 」「 枚」）。英語は「N today」「N cards」
    nonisolated static func countParts(count: Int, isToday: Bool) -> (prefix: String, suffix: String) {
        isToday ? (L("今日 ", ""), L(" 枚", " today")) : ("", L(" 枚", count == 1 ? " card" : " cards"))
    }
}
