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

    /// 束を開く（シートと帳への押し込みは `GalleryView` が持つ——ここは `LazyVStack` の中なので、
    /// 出す口（`fullScreenCover`・`navigationDestination`）を置かない）
    let open: ([PassCardContent]) -> Void

    @EnvironmentObject private var pass: PassStore
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var hidden: ModerationStore
    @State private var now = Date()

    var body: some View {
        let blocked = hidden.snapshot.blocked
        let cards = pass.contents(pass.unopened(blocked: blocked, now: now), book: pass.book(blocked: blocked, now: now))
        Group {
            if !cards.isEmpty {
                PassHomeCard(cards: cards, isToday: isToday(cards)) { open(cards) }
                    .padding(.horizontal, JPSpace.gutter)
            }
        }
        // 届いた束の写真を引く（届いた数・ブロックが変わったら引き直す）
        .task(id: ResolveKey(due: pass.encounters.filter { $0.deliverAt <= now }.count, blocked: hidden.revision)) {
            guard pass.hasDelivered(now: now) else { return }
            await pass.resolve(gallery: environment.gallery, profiles: environment.profiles, now: now)
        }
        // 開いている間に夕方 18 時を過ぎたら、その時に札を出す
        .task(id: nextDelivery) {
            guard let next = nextDelivery else { return }
            let wait = next.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(min(wait, 86_400) * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            now = Date()
        }
        .onAppear { now = Date() }
    }

    private var nextDelivery: Date? {
        pass.encounters.map(\.deliverAt).filter { $0 > now }.min()
    }

    private func isToday(_ cards: [PassCardContent]) -> Bool {
        let today = PassExchange.dayKey(now, calendar: .current)
        return cards.allSatisfy { PassExchange.dayKey($0.card.deliverAt, calendar: .current) == today }
    }

    private struct ResolveKey: Equatable {
        let due: Int
        let blocked: Int
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
                PassMiniStack(photos: cards.map(\.photo))
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
