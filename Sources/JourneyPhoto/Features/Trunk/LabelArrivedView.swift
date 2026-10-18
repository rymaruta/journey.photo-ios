import SwiftUI

/// 投稿してラベルが届いた（モック LabelArrived.dc.html・全画面・2026-10-17）。
///
/// 投稿が全部上がったあと、投稿の画面と共有の画面が閉じてから `RootView` が出す（`TrunkArrivals`）。
/// 眉ラベル → 明朝の見出し「京都のラベルが届きました」→ お礼の一行 → 大きいラベル（後ろに真鍮の淡い光）→
/// どんな図柄かの札 → 手持ちの棒 → 「トランクに貼る」「手持ちに入れておく」「図柄を作り直す PRO」。
struct LabelArrivedView: View {
    let batch: TrunkArrivals.Batch

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var toasts: ToastCenter
    /// 画面写真の見本（`-JPPreviewTrunkArrived`）ではサーバーを読まず、見本の手持ちを出す
    @StateObject private var model = TrunkViewModel(preview: PreviewSession.opensTrunkArrived ? .sample
                                                             : PreviewSession.trunkSample)
    @State private var showReroll = false
    @State private var showPaywall = false
    /// 作り直しで替わった種（届いた1枚の図柄を、選んだ候補に描き替える）
    @State private var seed: Int?

    private var arrival: TrunkArrivals.Arrival { batch.first }
    private var label: TrunkLabel {
        let base = model.state?.pocket.first { $0.id == arrival.label.id } ?? arrival.label
        return seed.map { base.withSeed($0) } ?? base
    }

    var body: some View {
        ZStack(alignment: .top) {
            TrunkStyle.stageBackground(centerY: 0.32)
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Text(Labels.Common.close)
                            .font(.body)
                            .foregroundStyle(WebTheme.text)
                            .padding(.horizontal, 10)
                            .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("trunk.arrived.close")
                }
                .padding(.horizontal, 8)
                .frame(height: 56)
                ScrollView {
                    VStack(spacing: 0) {
                        heading
                        stage
                        chips
                        pocket
                    }
                }
                actions
            }
        }
        .statusBarHidden(false)
        .task {
            model.bind(environment.trunk, userId: auth.userId)
            await model.load(offline: false)
        }
        .fullScreenCover(isPresented: $showReroll, onDismiss: {
            // 作り直しで決めた図柄に描き替える（手持ちの状態は作り直しの画面が読み直している）
            if let chosen = model.state?.pocket.first(where: { $0.id == arrival.label.id }) { seed = chosen.seed }
        }) {
            TrunkRerollView(model: model, labelId: arrival.label.id)
        }
        .fullScreenCover(isPresented: $showPaywall, onDismiss: {
            // 買えたかもしれない: 作り直せるか読み直す
            Task { await model.refreshAfterPaywall() }
        }) { PaywallView(origin: .trunk) }
        // 全画面の上では `RootView` の知らせが隠れるので、ここにも置く（作り直しの「図柄を決めました」・
        // 貼れなかったときの知らせ。`NameSideBadgeView` と同じ）
        .overlay(alignment: .top) { ToastOverlay() }
        // 子の目印（押せるもの）を消さないよう、入れ物の要素にしてから名前を付ける（2026-10-17・run 464）
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.arrived")
    }

    private var heading: some View {
        VStack(spacing: 0) {
            Text("NEW LABEL · " + L("投稿のお礼", "THANK YOU"))
                .font(JPFont.eyebrow)
                .tracking(11 * 0.12)
                .foregroundStyle(WebTheme.accent)
                .padding(.top, 18)
            Text(arrival.label.place.name.isEmpty
                 ? L("ラベルが届きました", "A label arrived")
                 : L("\(arrival.label.place.name)のラベルが届きました", "A label from \(arrival.label.place.name)"))
                .font(JPFont.display(22, relativeTo: .title2))
                .foregroundStyle(WebTheme.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .accessibilityAddTraits(.isHeader)
            Text(arrival.photoTitle.isEmpty
                 ? L("写真を投稿したお礼です", "Thank you for posting a photo")
                 : L("「\(arrival.photoTitle)」を投稿したお礼です", "Thank you for posting \u{201C}\(arrival.photoTitle)\u{201D}"))
                .font(.subheadline)
                .foregroundStyle(TrunkStyle.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 6)
            if batch.othersCount > 0 {
                Text(L("ほかに \(batch.othersCount) 枚、手持ちに届いています", "\(batch.othersCount) more arrived in your pocket"))
                    .font(JPFont.footnote)
                    .foregroundStyle(TrunkStyle.muted)
                    .padding(.top, 4)
            }
        }
    }

    /// 大きいラベル（260×176 の枠に形の比で収める・後ろに 340×250 の光）
    private var stage: some View {
        ZStack {
            TrunkStyle.glow(width: 340, height: 250)
            TrunkLabelThumb(label: label, maxWidth: 260, maxHeight: 176, rot: -4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(TrunkLabelDesign.accessibilityLabel(label))
                .accessibilityAddTraits(.isImage)
        }
        .frame(height: 270)
        .padding(.top, 16)
    }

    /// どんな図柄か（真鍮の字の札）
    private var chips: some View {
        let items = TrunkArrivalText.chips(label)
        return HStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(item.text)
                        .font(JPFont.footnote.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .foregroundStyle(WebTheme.accent)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(TrunkStyle.chip, in: Capsule())
            }
            // 一緒に届いた硬貨（公開の投稿1件で1枚・2026-10-17 次の版）
            if batch.coins > 0 {
                HStack(spacing: 6) {
                    TrunkCoinMark(size: 14)
                    Text(TrunkText.coinChip(batch.coins))
                        .font(JPFont.footnote.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(WebTheme.accent)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(TrunkStyle.chip, in: Capsule())
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("trunk.arrived.coin")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    /// 手持ちの棒（読めたときだけ）
    @ViewBuilder
    private var pocket: some View {
        if let state = model.state {
            HStack(spacing: 8) {
                Text(L("手持ち", "Pocket"))
                TrunkPocketBar(count: state.pocket.count, limit: state.limit)
                    .frame(width: 120)
                Text(TrunkText.pocketCounter(count: state.pocket.count, limit: state.limit))
                    .font(JPFont.mono(13, relativeTo: .footnote))
                    .foregroundStyle(WebTheme.text)
                Text("· " + TrunkText.remaining(count: state.pocket.count, limit: state.limit))
            }
            .font(JPFont.footnote)
            .foregroundStyle(TrunkStyle.muted)
            .padding(.top, 18)
            .accessibilityElement(children: .combine)
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            if let error = model.actionError {
                Text(error)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.danger)
                    .multilineTextAlignment(.center)
            }
            Button {
                Task {
                    // まだ読めていなければ読んでから貼る。それでも読めなければ一言を出す（`stickEnsuringLoaded`）
                    if await model.stickEnsuringLoaded(arrival.label.id) {
                        // 知らせは閉じ切ってから全体で1つだけ（ここで出すと、閉じる間に届いた画面と全体で2つ見える）
                        TrunkArrivals.shared.noteStuckFromArrival()
                        dismiss()
                    }
                }
            } label: {
                TrunkButtonFace(title: L("トランクに貼る", "Stick on my trunk"))
            }
            .buttonStyle(.plain)
            .disabled(model.busy)
            .accessibilityIdentifier("trunk.arrived.stick")
            Button { dismiss() } label: {
                TrunkButtonFace(title: L("手持ちに入れておく", "Keep it in my pocket"), kind: .secondary, height: 48, size: 15)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trunk.arrived.keep")
            Button {
                if model.state?.isPro == true { showReroll = true } else { showPaywall = true }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "dice")
                        .font(.system(size: 16))
                        .accessibilityHidden(true)
                    Text(L("図柄を作り直す", "Redo the design"))
                        .font(.subheadline)
                        .underline()
                    TrunkProTag()
                }
                .foregroundStyle(WebTheme.accent)
                .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("図柄を作り直す（Pro）", "Redo the design (Pro)"))
            .accessibilityIdentifier("trunk.arrived.reroll")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }
}

/// 届いた画面の札の言葉（モック: 「その場で撮った写真」「桜の時季だけの図柄」）
enum TrunkArrivalText {
    struct Chip: Equatable {
        let symbol: String
        let text: String
    }

    static func chips(_ label: TrunkLabel) -> [Chip] {
        var out: [Chip] = []
        if label.kind == .milestone, let m = label.milestone {
            out.append(Chip(symbol: "star", text: L("節目のラベル · \(TrunkLabelDesign.milestoneWords(m).ja)",
                                                    "Milestone · \(TrunkLabelDesign.milestoneWords(m).en.capitalized)")))
        } else if label.kind == .timeslot, let t = label.timeslot {
            out.append(Chip(symbol: "clock", text: L("\(TrunkLabelDesign.timeslotWords(t).ja)に撮った図柄",
                                                     "\(TrunkLabelDesign.timeslotWords(t).en.capitalized) design")))
        } else if let s = label.season {
            out.append(Chip(symbol: "clock", text: L("\(TrunkLabelDesign.seasonWords(s).ja)の時季だけの図柄",
                                                     "\(TrunkLabelDesign.seasonWords(s).en.capitalized)-only design")))
        }
        if !label.place.name.isEmpty {
            out.append(Chip(symbol: "mappin.and.ellipse", text: L("\(label.place.name)の図柄", "\(label.place.name) design")))
        }
        if label.foil {
            out.append(Chip(symbol: "sparkles", text: L("箔押し（まれに）", "Gold foil (rare)")))
        }
        return Array(out.prefix(2))
    }
}
