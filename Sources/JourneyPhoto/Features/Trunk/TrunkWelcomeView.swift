import SwiftUI

/// 「はじめての硬貨」の案内（全画面・2026-10-18 owner 承認）。硬貨が始まる前から居る人に一度だけ配った回に、
/// `RootView` がほかの案内と重ならない頃合いに1回出す（`TrunkWelcome`・`PostModalGate.welcomeMayShow`）。
///
/// 形は旅のトランクの板の「ラベルが届いた」（LabelArrived）と「カプセルを開けた」（GachaOpen）にそろえる:
/// 右上の「閉じる」→ 眉ラベル（真鍮）→ 明朝の見出し → お礼の一行 → 真鍮の淡い光の上の硬貨（カプセルの機械の
/// `TrunkCoinMark` を重ねたもの）→ 硬貨の数の行（機械の数の行と同じ並び・数は `JPFont.mono`）→
/// もらい方と使い道の札（GachaOpen の #121212 の札）→ 主ボタン「カプセルを回す」（真鍮の塗り＋墨）・「あとで」。
/// 「カプセルを回す」は、この全画面の中でカプセルの機械（`TrunkGachaView`）へ進む
struct TrunkWelcomeView: View {
    let grant: TrunkWelcome.Grant
    /// 実際に出た（`RootView` が端末の控えを消し、出たことを覚える）。カプセルの機械から戻ったときは呼び直さない
    var onShown: () -> Void = {}
    @State private var shown = false

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    /// カプセルの機械へ渡す状態。見本（`-JPPreviewTrunkWelcome`）ではサーバーを読まない
    @StateObject private var model = TrunkViewModel(preview: PreviewSession.trunkWelcomeAdded != nil ? .sample
                                                             : PreviewSession.trunkSample)
    @State private var showGacha = false

    var body: some View {
        NavigationStack {
            content
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: $showGacha) { TrunkGachaView(model: model) }
        }
        .task { model.bind(environment.trunk, userId: auth.userId) }
        .onAppear {
            guard !shown else { return }
            shown = true
            onShown()
        }
        // 全画面の上では `RootView` の知らせが隠れるので、ここにも置く（カプセルの機械の「部品箱に入りました」など）
        .overlay(alignment: .top) { ToastOverlay() }
        // 子の目印（押せるもの）を消さないよう、入れ物の要素にしてから名前を付ける
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.welcome")
    }

    private var content: some View {
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
                    .accessibilityIdentifier("trunk.welcome.close")
                }
                .padding(.horizontal, 8)
                .frame(height: 56)
                ScrollView {
                    VStack(spacing: 0) {
                        heading
                        stage
                        amount
                        explain
                    }
                }
                actions
            }
        }
    }

    private var heading: some View {
        VStack(spacing: 0) {
            Text(TrunkWelcomeText.eyebrow)
                .font(JPFont.eyebrow)
                .tracking(11 * 0.12)
                .foregroundStyle(WebTheme.accent)
                .padding(.top, 18)
            Text(TrunkWelcomeText.title)
                .font(JPFont.display(22, relativeTo: .title2))
                .foregroundStyle(WebTheme.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .accessibilityAddTraits(.isHeader)
            Text(TrunkWelcomeText.thanks)
                .font(.subheadline)
                .foregroundStyle(TrunkStyle.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 6)
        }
    }

    /// 真鍮の淡い光の上に、硬貨を3枚重ねる（後ろ2枚は小さく、前の1枚は大きく）
    private var stage: some View {
        ZStack {
            TrunkStyle.glow(width: 340, height: 250)
            TrunkCoinMark(size: 76)
                .offset(x: -64, y: 20)
            TrunkCoinMark(size: 76)
                .offset(x: 66, y: 26)
            TrunkCoinMark(size: 112)
                .offset(x: 0, y: -4)
        }
        .frame(height: 230)
        .padding(.top, 12)
        .accessibilityHidden(true)
    }

    /// 「硬貨 +10 枚」（カプセルの機械の数の行と同じ並び: 硬貨の印 → 字 → 等幅の数 → 字）と、配ったあとの手持ち
    private var amount: some View {
        let added = TrunkWelcomeText.added(grant.added)
        let total = TrunkWelcomeText.total(grant.coins)
        return VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                TrunkCoinMark(size: 26)
                if !added.before.isEmpty {
                    Text(added.before).font(.title3.weight(.semibold))
                }
                Text(added.number)
                    .font(JPFont.mono(30, medium: true, relativeTo: .title))
                Text(added.after).font(.title3.weight(.semibold))
            }
            .foregroundStyle(WebTheme.text)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(added.joined)
            .accessibilityIdentifier("trunk.welcome.added")
            HStack(spacing: 4) {
                Text(total.before)
                Text(total.number).font(JPFont.mono(13, medium: true, relativeTo: .footnote))
                Text(total.after)
            }
            .font(JPFont.footnote)
            .foregroundStyle(TrunkStyle.faint)
            .accessibilityElement(children: .combine)
            if let note = TrunkWelcomeText.cappedNote(grant.added) {
                Text(note)
                    .font(JPFont.footnote)
                    .foregroundStyle(TrunkStyle.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .accessibilityIdentifier("trunk.welcome.capped")
            }
        }
        .padding(.top, 4)
    }

    /// もらい方と使い道（GachaOpen の札と同じ #121212・角 14）
    private var explain: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(symbol: "photo.on.rectangle", text: TrunkWelcomeText.howToEarn)
            TrunkStyle.line.frame(height: 1).padding(.leading, 46)
            row(symbol: "shippingbox", text: TrunkWelcomeText.whatItDoes)
        }
        .background(TrunkStyle.cell, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private func row(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WebTheme.accent)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(WebTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button { showGacha = true } label: {
                TrunkButtonFace(title: TrunkWelcomeText.turn)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trunk.welcome.turn")
            Button { dismiss() } label: {
                TrunkButtonFace(title: TrunkWelcomeText.later, kind: .secondary, height: 48, size: 15)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trunk.welcome.later")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }
}
