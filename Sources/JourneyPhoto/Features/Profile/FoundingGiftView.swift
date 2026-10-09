import SwiftUI

/// 初期ユーザー章を贈る全画面（板 65 `FoundingGift`・2026-10-09）。
///
/// 初期ユーザー章を持っていて、まだ名前の横に飾っていない人に、起動のあとで1回出す
/// （出す・出さないは `FoundingGiftGate`）。「受け取って、プロフィールに飾る」で名前の横の
/// バッジを初期ユーザー章にする（プロフィールの部分更新の `displayBadge`）。「あとで」は閉じるだけ
struct FoundingGiftView: View {

    /// 贈る相手の名前（表示名、無ければ @ユーザー名）
    let name: String
    /// 飾ったら呼ぶ（マイページを読み直す合図など）
    var onAccepted: () -> Void = {}

    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        GeometryReader { geo in
            let medal = FoundingGiftLayout.medalSide(screenWidth: Double(geo.size.width))
            VStack(spacing: 0) {
                Text("FOR OUR FIRST MEMBERS")
                    .font(.system(size: 11, weight: .regular))
                    .tracking(11 * 0.2)
                    .foregroundStyle(WebTheme.accent)
                    .padding(.top, 52)
                Image(BadgeCatalog.largeImage("earlyUser", tier: 1))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: medal, height: medal)
                    .accessibilityLabel(L("初期ユーザー章", "Founding member medal"))
                VStack(spacing: 14) {
                    Text(L("初期ユーザー章を\nお贈りします", "A founding member\nmedal for you"))
                        .font(JPFont.display(26))
                        .lineSpacing(26 * 0.4 - 6)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.white)
                    if !name.isEmpty {
                        Text(L("\(name) さんへ", "For \(name)"))
                            .font(.system(size: 13))
                            .tracking(13 * 0.1)
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    Text(L("Journey Photo を最初から使ってくださった方だけの章です。この先に登録する方には贈られません。",
                           "This medal is only for people who have used Journey Photo from the start. It won't be given to anyone who joins later."))
                        .font(.system(size: 13))
                        .lineSpacing(13 * 0.8 - 4)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)
                Spacer(minLength: 16)
                VStack(spacing: 14) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(WebTheme.danger)
                            .multilineTextAlignment(.center)
                    }
                    Button { Task { await accept() } } label: {
                        ZStack {
                            if saving {
                                ProgressView().tint(FoundingGiftLayout.buttonText)
                            } else {
                                Text(L("受け取って、プロフィールに飾る", "Accept and show on my profile"))
                                    .font(.system(size: 16, weight: .bold))
                            }
                        }
                        .foregroundStyle(FoundingGiftLayout.buttonText)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(WebTheme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(saving)
                    Button { dismiss() } label: {
                        Text(L("あとで", "Later"))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                    }
                    .buttonStyle(.plain)
                    .disabled(saving)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 34)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background { background }
        .interactiveDismissDisabled(saving)
    }

    /// 地（板: 中心 50% 36% の丸いグラデーション #1A1D21 → #070708 42% → 黒 68%）
    private var background: some View {
        GeometryReader { geo in
            let reach = Double(max(geo.size.width, geo.size.height))
            RadialGradient(stops: [
                .init(color: ProMarkColors.color(0x1A1D21), location: 0),
                .init(color: ProMarkColors.color(0x070708), location: 0.42),
                .init(color: Color.black, location: 0.68),
            ], center: UnitPoint(x: 0.5, y: 0.36), startRadius: 0, endRadius: reach)
        }
        .ignoresSafeArea()
    }

    private func accept() async {
        guard !saving else { return }
        saving = true
        errorMessage = nil
        do {
            var patch = ProfilePatch()
            patch.displayBadge = Clearable(FoundingGiftGate.badgeKey)
            try await environment.profiles.update(patch)
            saving = false
            onAccepted()
            dismiss()
        } catch {
            saving = false
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? L("飾れませんでした。時間をおいてもう一度お試しください。プロフィールの編集の「名前の横のバッジ」からも飾れます。",
                     "Couldn't save. Please try again later. You can also choose it from \"Badge beside your name\" in Edit profile.")
        }
    }
}

/// 板 65 の寸法と色（画面に依らない・テストで見張る）
enum FoundingGiftLayout {
    /// 主ボタンの字の色（板: #1A140A・真鍮の地に墨）
    static let buttonText = ProMarkColors.color(0x1A140A)
    /// メダルの一辺（板: 390pt の画面で 360pt＝左右 15pt）。小さい画面では縮める
    static func medalSide(screenWidth: Double) -> Double {
        max(200, min(screenWidth - 30, 360))
    }
}
