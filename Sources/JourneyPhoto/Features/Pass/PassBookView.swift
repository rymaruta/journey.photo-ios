import SwiftUI
import CoreBluetooth

/// すれちがい帳（板 PassBook）。受け取ったカードは消えずにここに綴じる。
///
/// 上に3つの数（枚・都道府県・いちばん遠く）、字のタブ（綴じた順・場所ごと・よく会う人）、
/// 節ごとに 3×3 の綴じ（足りない枠は点線の空き）。押すとその節のカードを1枚ずつめくれる。
///
/// **届く前のカードは出さない**（「夕方にまとめて受け取る」の人には夕方まで見せない・`PassBook.delivered`）。
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
    /// 見えている高さ（札の中身の最低の高さ・`ProfileTabSection`）
    @State private var viewport: CGFloat = 0
    @State private var opened: PassBookOpen?
    @State private var isLoading = true
    /// すれちがい乗車券の設定を積む（頭の行・空の状態の主ボタン。2026-10-16・次の一手）
    @State private var showSettings = false
    /// 積む設定で、はじめから「オンにする」前の説明を出すか（空の状態の「説明を読んでオンにする」・札 #519）
    @State private var settingsIntro = false
    /// Bluetooth の電源（頭の行の「Bluetooth がオフ」・`PassSettingsView` と同じ読み方）
    @ObservedObject private var radio = PassRadio.shared
    /// すれちがいの設定（`PassSettingsView`）から開いたか。**そのときは設定を積み直さず、戻る**
    /// （設定 → 帳 → 設定 → 帳…と同じ画面が重なっていく）
    var fromSettings = false
    @Environment(\.dismiss) private var dismiss

    /// 頭の行の状態（`PassBookStatus`）。読むのは今の状態だけで、OS の許可は求めない
    private var status: PassBookStatus {
        let auth = CBManager.authorization
        return PassBookStatus.resolve(.init(
            enabled: pass.settings.enabled,
            ticketChosen: pass.settings.cardPhotoId != nil,
            bluetoothPoweredOff: PassRadio.showsPowerOffNotice(enabled: pass.settings.enabled, state: radio.powerState),
            bluetoothDenied: auth == .denied || auth == .restricted || radio.powerState == .unauthorized,
            mode: pass.settings.mode,
            distanceReasonExists: PassSettingsText.travelUnknownReason(
                homePrefecture: pass.homePrefecture, locationAuthorized: PassPlaceFinder.shared.isAuthorized) != nil,
            awayToday: pass.awayToday(),
            delivery: pass.settings.deliveryMode))
    }

    /// 設定へ。**設定から積まれた帳では積まずに戻る**（設定 → 帳 → 設定 → 帳…と重ねない・頭の行も主ボタンも同じ）
    private func openSettings(intro: Bool) {
        if fromSettings {
            dismiss()
        } else {
            settingsIntro = intro
            showSettings = true
        }
    }

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
                    Text(L("受け取った乗車券は、消えずにここに残ります", "Tickets you receive stay here"))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                }
                .padding(.horizontal, JPSpace.l)
                .padding(.top, 10)

                let status = self.status
                statusRow(status)
                    .padding(.horizontal, JPSpace.l)
                    .padding(.top, 14)

                if contents.isEmpty {
                    if isLoading && pass.hasDelivered() {
                        JPLoadingState(kind: .grid)
                    } else if let actionTitle = status.emptyActionTitle {
                        // オフ: 主ボタン1つ。押すと設定を積み、まず「オンにする」前の説明（札 #519）
                        EmptyState(title: L("まだ乗車券がありません", "No tickets yet"), message: status.emptyMessage,
                                   actionTitle: actionTitle, actionIdentifier: PassBookStatus.emptyActionIdentifier) {
                            openSettings(intro: true)
                        }
                    } else {
                        // オン: ボタンは出さない（止まっている訳は頭の行が言う）
                        EmptyState(title: L("まだ乗車券がありません", "No tickets yet"), message: status.emptyMessage)
                    }
                } else {
                    statsRow(PassBook.stats(book.filter { byId[$0.id] != nil }, prefectures: pass.ownerPrefectures))
                        .padding(.horizontal, JPSpace.l)
                        .padding(.top, 18)
                    // 綴じた順 / 場所ごと / よく会う人。2026-10-31 判断（#426）: マイページと同じ札（下線が滑る・
                    // 当たりが広い・中身を横にめくる）。**同じカードを並べ直すだけ**なので、めくった先もすぐ出る
                    ProfileTabSection(tabs: PassBook.Order.allCases, selection: $order, viewport: viewport,
                                      spacing: 14) { option in
                        VStack(alignment: .leading, spacing: JPSpace.l) {
                            ForEach(PassBook.sections(book.filter { byId[$0.id] != nil }, order: option,
                                                      names: pass.ownerNames, calendar: .current)) { section in
                                sectionView(section, byId: byId)
                            }
                        }
                        .padding(.horizontal, JPSpace.gutter)
                    }
                    .padding(.top, 14)
                    Text(L("場所は「〇〇のあたり」くらいの大まかさで、この iPhone の中にだけ記録します。",
                           "Places are recorded only roughly (\u{201C}around …\u{201D}), on this iPhone only."))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                        .padding(.horizontal, JPSpace.gutter)
                        .padding(.top, JPSpace.s)
                }
            }
            .padding(.bottom, JPSpace.screenEnd)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            if height != viewport { viewport = height }
        }
        // 設定（設定の画面の「すれちがい」と同じ `PassSettingsView`）
        .navigationDestination(isPresented: $showSettings) { PassSettingsView(startsWithIntro: settingsIntro) }
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

    /// 頭の1行（板の行 `JPRowLabel`・札 `JPCard`・押す間は白 6%）。読み上げは名前＝題・値＝2行目
    private func statusRow(_ status: PassBookStatus) -> some View {
        JPCard {
            Button { openSettings(intro: false) } label: {
                JPRowLabel(title: status.title, systemImage: "ticket", detail: status.detail)
            }
            .buttonStyle(JPRowButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status.title)
            .accessibilityValue(status.detail)
            .accessibilityHint(PassBookStatus.hint(fromSettings: fromSettings))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(PassBookStatus.statusIdentifier)
        }
    }

    private func statsRow(_ stats: PassBook.Stats) -> some View {
        // 見せ方（分からない値は「—」・読み上げは「まだ分かりません」）は `PassBook.statItems`（2026-11-10）
        HStack(alignment: .top, spacing: JPSpace.xs) {
            ForEach(Array(PassBook.statItems(stats).enumerated()), id: \.offset) { _, item in
                stat(item.value, unit: item.unit, label: item.label)
                    .accessibilityLabel(item.spoken)
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
                    .accessibilityLabel(content.ticketTitle)
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
