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
        // 板 v2（FoundingGift・2026-10-14）: 章 → 眉ラベル → 明朝 30 の見出し → 宛名 → 説明、下に真鍮の主ボタンと「あとで」。
        // 章の後ろに真鍮のごく弱い光（`FoundingGiftLayout.glowOpacity`）。写真の無い画面なので主ボタンは真鍮の塗りに墨
        GeometryReader { geo in
            let medal = FoundingGiftLayout.medalSide(screenWidth: Double(geo.size.width))
            VStack(spacing: 0) {
                Image(BadgeCatalog.largeImage("earlyUser", tier: 1))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: medal, height: medal)
                    .shadow(color: Color.black.opacity(0.7), radius: 15, x: 0, y: 20)
                    .background {
                        // 章の後ろの真鍮の光（板: 360 の丸・真鍮 22% → 0）。飾りなので読み上げない
                        RadialGradient(colors: [WebTheme.accent.opacity(FoundingGiftLayout.glowOpacity),
                                                WebTheme.accent.opacity(0)],
                                       center: .center, startRadius: 0,
                                       endRadius: FoundingGiftLayout.glowDiameter / 2)
                            .frame(width: FoundingGiftLayout.glowDiameter, height: FoundingGiftLayout.glowDiameter)
                            .accessibilityHidden(true)
                    }
                    .padding(.top, FoundingGiftLayout.topInset)
                    .accessibilityLabel(L("初期ユーザー章", "Founding member medal"))
                Text("FOR OUR FIRST MEMBERS")
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                    .padding(.top, 28)
                VStack(spacing: JPSpace.s) {
                    Text(L("初期ユーザー章を\nお贈りします", "A founding member\nmedal for you"))
                        .font(JPFont.display(FoundingGiftLayout.titleSize, relativeTo: .largeTitle))
                        .lineSpacing(FoundingGiftLayout.titleSize * 0.4 - 6)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(WebTheme.text)
                        .accessibilityAddTraits(.isHeader)
                    if !name.isEmpty {
                        Text(L("\(name) さんへ", "For \(name)"))
                            .font(JPFont.body)
                            .foregroundStyle(WebTheme.text2)
                    }
                    Text(L("Journey Photo を最初から使ってくださった方だけの章です。この先に登録する方には贈られません。",
                           "This medal is only for people who have used Journey Photo from the start. It won't be given to anyone who joins later."))
                        .font(JPFont.body)
                        .lineSpacing(15 * 0.8 - 6)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(WebTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, JPSpace.xxs)
                }
                .padding(.top, JPSpace.s)
                .padding(.horizontal, 28)
                Spacer(minLength: JPSpace.m)
                VStack(spacing: 6) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(JPFont.footnote)
                            .foregroundStyle(WebTheme.danger)
                            .multilineTextAlignment(.center)
                    }
                    Button { Task { await accept() } } label: {
                        ZStack {
                            if saving {
                                ProgressView().tint(WebTheme.accentText)
                            } else {
                                Text(L("受け取って、プロフィールに飾る", "Accept and show on my profile"))
                            }
                        }
                        .jpPillButton(FoundingGiftLayout.acceptStyle)
                    }
                    .buttonStyle(.plain)
                    .disabled(saving)
                    Button { dismiss() } label: {
                        Text(L("あとで", "Later"))
                            .font(JPFont.body)
                            .foregroundStyle(WebTheme.text2)
                            .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(saving)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, JPSpace.l)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // 板 v2: 地は黒（v1 の丸い灰のグラデーションは、章の後ろの真鍮の光に替えた）
        .background { WebTheme.background.ignoresSafeArea() }
        .interactiveDismissDisabled(saving)
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

/// 板の寸法と色（画面に依らない・テストで見張る）。v2（2026-10-14・板 FoundingGift）
enum FoundingGiftLayout {
    /// 主ボタン: 写真の無い画面なので真鍮の塗りに墨（CLAUDE.md・`JPPillStyle.main(onPhoto: false)`）
    static let acceptStyle = JPPillStyle.main(onPhoto: false)
    /// 見出し（明朝 30・板の値）
    static let titleSize: Double = 30
    /// 章の上の余白（板: 画面の上 96 から。安全域の分を引いた 48）
    static let topInset: CGFloat = JPSpace.emptyTop
    /// 章の後ろの真鍮の光（板: 直径 360・中心で真鍮 22%）
    static let glowDiameter: Double = 360
    static let glowOpacity: Double = 0.22
    /// メダルの一辺（v2: 220。v1 は画面の幅いっぱいの 360）。小さい画面では縮める
    static func medalSide(screenWidth: Double) -> Double {
        max(160, min(screenWidth - 56, 220))
    }
}
