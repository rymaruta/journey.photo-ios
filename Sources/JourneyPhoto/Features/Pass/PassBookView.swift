import SwiftUI

/// すれちがい帳（板 PassBook）。受け取ったカードは消えずにここに綴じる。
///
/// 上に3つの数（枚・都道府県・いちばん遠く）、字のタブ（綴じた順・場所ごと・よく会う人）、
/// 節ごとに 3×3 の綴じ（足りない枠は点線の空き）。押すとその節のカードを1枚ずつめくれる。
///
/// **届く前のカードは出さない**（夕方まで「いま近くにいる」を見せない・`PassBook.delivered`）。
/// 写真が公開一覧から消えた（非公開・削除）・持ち主をブロックしたカードも出さない（`PassStore.isVisible`）
struct PassBookView: View {

    @EnvironmentObject private var pass: PassStore
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var hidden: ModerationStore
    @EnvironmentObject private var toasts: ToastCenter
    @State private var reportTarget: PassCardContent?
    @State private var noteReportTarget: PassCardContent?
    @State private var blockTarget: PassCardContent?
    @State private var order: PassBook.Order = .bound
    @State private var opened: PassBookOpen?
    @State private var isLoading = true
    /// 空のときの「すれちがいの設定」（2026-10-16・次の一手）
    @State private var showSettings = false
    /// すれちがいの設定（`PassSettingsView`）から開いたか。**そのときは設定を積み直さず、戻る**
    /// （設定 → 帳 → 設定 → 帳…と同じ画面が重なっていく）
    var fromSettings = false
    @Environment(\.dismiss) private var dismiss

    /// 空のときの次の一手の題
    nonisolated static var settingsTitle: String { L("すれちがい乗車券の設定", "Pass ticket settings") }

    var body: some View {
        let book = pass.book(hiding: hidden.snapshot)
        let contents = pass.contents(book, book: book)
        let byId = Dictionary(uniqueKeysWithValues: contents.map { ($0.id, $0) })
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: JPSpace.xxs) {
                    Text(L("すれちがい帳", "Pass book"))
                        .font(JPFont.display(SettingsLayout.titleSize, relativeTo: .largeTitle))
                        .foregroundStyle(WebTheme.text)
                        .accessibilityAddTraits(.isHeader)
                    Text(L("受け取ったカードは、消えずにここに綴じられます", "Cards you receive stay bound here"))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                }
                .padding(.horizontal, JPSpace.l)
                .padding(.top, 10)

                if contents.isEmpty {
                    if isLoading && pass.hasDelivered() {
                        JPLoadingState(kind: .grid)
                    } else {
                        EmptyState(title: L("まだカードがありません", "No cards yet"),
                                   message: L("すれちがい乗車券をオンにして出かけると、近くにいたアプリの人のカードがその日の夕方に届きます。",
                                              "Turn on Pass tickets and head out — cards from app users you passed arrive that evening."),
                                   actionTitle: Self.settingsTitle, actionIdentifier: "passBook.emptySettings") {
                            if fromSettings { dismiss() } else { showSettings = true }
                        }
                    }
                } else {
                    statsRow(PassBook.stats(book.filter { byId[$0.id] != nil }, prefectures: pass.ownerPrefectures))
                        .padding(.horizontal, JPSpace.l)
                        .padding(.top, 18)
                    tabs.padding(.top, 14)
                    VStack(alignment: .leading, spacing: JPSpace.l) {
                        ForEach(PassBook.sections(book.filter { byId[$0.id] != nil }, order: order,
                                                  names: pass.ownerNames, calendar: .current)) { section in
                            sectionView(section, byId: byId)
                        }
                    }
                    .padding(.horizontal, JPSpace.gutter)
                    .padding(.top, 14)
                    Text(L("場所は「〇〇のあたり」の粒度だけを、この iPhone の中に記録します。",
                           "Places are recorded only roughly (\u{201C}around …\u{201D}), on this iPhone only."))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                        .padding(.horizontal, JPSpace.gutter)
                        .padding(.top, JPSpace.s)
                }
            }
            .padding(.bottom, JPSpace.screenEnd)
        }
        // 設定（設定の画面の「すれちがい」と同じ `PassSettingsView`）
        .navigationDestination(isPresented: $showSettings) { PassSettingsView() }
        .webScreen()
        .navigationTitle(L("すれちがい帳", "Pass book"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
        }
        .task(id: hidden.revision) {
            await pass.resolve(gallery: environment.gallery, profiles: environment.profiles)
            isLoading = false
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(photoId: target.photo.id, ownerId: target.card.ownerId,
                        carriedPassNote: target.card.noteReported == true ? target.card.writtenText : nil)
        }
        .sheet(item: $noteReportTarget) { target in
            ReportSheet(photoId: target.photo.id, ownerId: nil, passNote: target.card.writtenText,
                        onReported: { pass.markNoteReported(target.id) })
        }
        .blockConfirmation(presenting: $blockTarget) { target in
            Task { _ = await PassCardModeration.block(target, hidden: hidden, environment: environment, toasts: toasts) }
        }
        .fullScreenCover(item: $opened) { open in
            PassViewerView(cards: open.cards, mode: .book, start: open.start)
        }
    }

    private func statsRow(_ stats: PassBook.Stats) -> some View {
        HStack(alignment: .top, spacing: JPSpace.xs) {
            stat(PassExchange.grouped(stats.cards), unit: nil,
                 label: L("枚のカード", "cards"))
            stat(String(stats.prefectures), unit: nil, label: L("都道府県から", "prefectures"))
            if let km = stats.farthestKm {
                stat(PassExchange.grouped(km), unit: "km",
                     label: L("いちばん遠く", "farthest"))
            } else {
                stat("—", unit: nil, label: L("いちばん遠く", "farthest"))
            }
        }
    }

    private func stat(_ value: String, unit: String?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(JPFont.number(22, weight: .semibold, relativeTo: .title2))
                    .foregroundStyle(WebTheme.text)
                if let unit {
                    Text(unit).font(JPFont.caption).foregroundStyle(WebTheme.text3)
                }
            }
            Text(label).font(JPFont.caption).foregroundStyle(WebTheme.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// 字のタブ（ホームのフィードの切り替えと同じ形: 選んだタブは真鍮の字と 2 の下線）
    private var tabs: some View {
        VStack(spacing: 0) {
            // 板の間は 22。ホームのフィードの切り替えと同じく 4 の倍数の 24（`GalleryView.feedTabGap`）
            HStack(spacing: JPSpace.xl) {
                ForEach(PassBook.Order.allCases) { item in
                    let selected = order == item
                    Button { order = item } label: {
                        Text(item.label)
                            .font(selected ? JPFont.bodyEmphasis : JPFont.body)
                            .foregroundStyle(selected ? WebTheme.accent : WebTheme.text3)
                            .frame(minHeight: WebTheme.minTapTarget)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(selected ? WebTheme.accent : Color.clear).frame(height: JPStroke.emphasis)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, JPSpace.gutter)
            Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
        }
    }

    private func sectionView(_ section: PassBook.Section, byId: [String: PassCardContent]) -> some View {
        let list = section.cards.compactMap { byId[$0.id] }
        return VStack(alignment: .leading, spacing: JPSpace.xs) {
            JPEyebrowLine(section.title)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(Array(list.enumerated()), id: \.element.id) { offset, content in
                    Button { opened = PassBookOpen(cards: list, start: offset) } label: {
                        PassTicketSlot(content: content)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("\(content.name) のカード", "\(content.name)\u{2019}s card"))
                    // 「…」（通報・ブロック・帳から外す）。写真の上なのでガラスの丸に白
                    .overlay(alignment: .topTrailing) {
                        PassCardMenu(content: content,
                                     report: { reportTarget = content },
                                     reportNote: { noteReportTarget = content },
                                     toggleNote: { pass.setNoteHidden(content.id, content.card.noteHidden != true) },
                                     toggleLabels: { pass.setLabelsHidden(content.id, content.card.labelsHidden != true) },
                                     block: { blockTarget = content },
                                     remove: { pass.remove(content.id) },
                                     onPhoto: true)
                            // 当たり（44）は札の内側に収める（隣のカードにかからない）
                    }
                }
                ForEach(0..<PassBook.emptySlots(for: list.count), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: PassCardStyle.miniCorner)
                        .strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .aspectRatio(5.0 / 7.0, contentMode: .fit)
                        .accessibilityHidden(true)
                }
            }
            .padding(14)
            // 綴じの地は札より一段沈めた #0b0b0c（板 `.bind`）
            .jpCardFace(fill: PassCardStyle.face)
        }
    }

}

/// 帳から開くカード（その節の並びと、押した1枚）
struct PassBookOpen: Identifiable {
    let cards: [PassCardContent]
    let start: Int
    var id: String { (cards.map(\.id) + [String(start)]).joined(separator: ",") }
}
