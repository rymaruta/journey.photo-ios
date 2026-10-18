import SwiftUI

/// 「この1枚をカバーにしますか？」（#304・板 51 CoverOffer・51b CoverOfferLiked・2026-10-18）。
///
/// - 51: 初めての投稿の直後に一度だけ。「あとで」は、いいねが集まったときにもう一度聞く。引いて閉じても「あとで」と同じ
/// - 51b: いいねが [N] 件に届いた1枚。カバーを持っている人には「いまのカバーと入れ替わります」の一行
/// - どちらも「もう聞かないで」で二度と出さない（`CoverOfferStore`）
///
/// 見本は「この1枚がカバーになったあなたのページ」。**写真のある画面なので主ボタンは白**（`jpPillButton(.primary)`）。
/// 眉ラベルは黒地の上なので真鍮。硬貨の行は旅のトランクが使えてカバーがまだ無い人だけ（`Offer.showsCoins`）
struct CoverOfferView: View {
    let offer: CoverOfferStore.Offer
    /// 実際に出た（`RootView` が出たことを覚える）
    var onShown: () -> Void = {}

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var applying = false
    @State private var failed = false
    @State private var shown = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(CoverOfferText.eyebrow(offer.kind))
                        .jpEyebrow()
                        .foregroundStyle(WebTheme.accent)
                        .accessibilityIdentifier("coverOffer.eyebrow")
                    Text(CoverOfferText.title)
                        .font(JPFont.display(24, relativeTo: .title2))
                        .foregroundStyle(WebTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(CoverOfferText.body(offer))
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text2)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                sample
                note
                if failed {
                    Text(L("カバーにできませんでした。通信を確かめて、もう一度お試しください。",
                           "Couldn't set the cover. Check your connection and try again."))
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, JPSpace.xl)
            .padding(.top, JPSpace.section)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) { actions }
        .scrollContentBackground(.hidden)
        .background(WebTheme.background, ignoresSafeAreaEdges: .all)
        .presentationBackground(WebTheme.background)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(applying)
        .task {
            let profile = try? await environment.profiles.myProfile()
            name = profile?.name ?? ""
        }
        .onAppear {
            guard !shown else { return }
            shown = true
            onShown()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coverOffer")
    }

    /// 見本: この写真がカバーになったあなたのページ（カバーの帯・下端に重なるアイコン・名前）
    private var sample: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(maxWidth: .infinity).frame(height: 196)
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 128)
                .overlay { RemoteImage(url: offer.imageURL) }
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [WebTheme.background.opacity(0), WebTheme.background],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 70)
                }
            VStack(alignment: .leading, spacing: 6) {
                RemoteImage(url: auth.userId.flatMap {
                    UserProfile.profileAssetURL(userId: $0, suffix: nil,
                                                cacheBust: ProfileImageVersions.shared.token(for: $0)) })
                    .frame(width: 56, height: 56)
                    .background(WebTheme.card)
                    .clipShape(Circle())
                    .coverCutout(true)
                Text(name)
                    .font(JPFont.display(18, relativeTo: .headline))
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(1)
            }
            .padding(.leading, 16)
            .padding(.top, 100)
        }
        .background(WebTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: JPRadius.l))
        .overlay(RoundedRectangle(cornerRadius: JPRadius.l).strokeBorder(WebTheme.hairline, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("見本: この写真がカバーになったあなたのページ", "Preview: your page with this photo as the cover"))
    }

    /// 硬貨の行（まだカバーが無い人）か、入れ替わりの一行（カバーがある人・51b）
    @ViewBuilder
    private var note: some View {
        if offer.hasCover {
            HStack(spacing: 10) {
                RemoteImage(url: auth.userId.flatMap {
                    UserProfile.profileAssetURL(userId: $0, suffix: "cover",
                                                cacheBust: ProfileImageVersions.shared.token(for: $0)) })
                    .frame(width: 40, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .accessibilityHidden(true)
                Text(L("いまのカバーと入れ替わります", "This replaces your current cover"))
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text2)
            }
        } else if offer.showsCoins {
            HStack(spacing: 8) {
                TrunkCoinMark(size: 16)
                    .accessibilityHidden(true)
                Text(L("はじめてのカバーで、トランクの硬貨を", "Your first cover earns trunk coins:"))
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text2)
                Text("\(ProfileRewardText.coinsPerKind)")
                    .font(JPFont.mono(13, medium: true, relativeTo: .footnote))
                    .foregroundStyle(WebTheme.text)
                Text(L("枚", ""))
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("coverOffer.coins")
        }
    }

    private var actions: some View {
        VStack(spacing: 6) {
            Button {
                guard !applying else { return }
                applying = true
                failed = false
                Task {
                    let ok = await apply()
                    applying = false
                    if ok { dismiss() } else { failed = true }
                }
            } label: {
                Group {
                    if applying { ProgressView().tint(WebTheme.accentText) } else { Text(L("カバーにする", "Use as cover")) }
                }
                .jpPillButton(.primary)
            }
            .buttonStyle(.plain)
            .disabled(applying)
            .accessibilityIdentifier("coverOffer.apply")
            HStack(spacing: 8) {
                textButton(offer.kind == .firstPost ? L("あとで", "Later") : L("今のままにする", "Keep as is"),
                           tone: WebTheme.muted, id: "coverOffer.later") { dismiss() }
                textButton(L("もう聞かないで", "Don't ask again"), tone: WebTheme.muted2, id: "coverOffer.never") {
                    CoverOfferStore.shared.chooseNever(userId: auth.userId)
                    dismiss()
                }
            }
            Text(CoverOfferText.footnote(offer.kind))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, JPSpace.xl)
        .padding(.bottom, JPSpace.s)
        .background(WebTheme.background)
    }

    private func textButton(_ title: String, tone: Color, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(JPFont.body)
                .foregroundStyle(tone)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(applying)
        .accessibilityIdentifier(id)
    }

    private func apply() async -> Bool {
        #if DEBUG
        // 画面写真の見本（`-JPPreviewCoverOffer`）では上げない
        if PreviewSession.coverOffer != nil { return true }
        #endif
        guard let url = offer.imageURL else { return false }
        let ok = await ProfileImageFromPhoto.applyCover(photoId: offer.photoId, url: url,
                                                        environment: environment, auth: auth)
        if ok { toasts.show(L("カバーにしました", "Cover updated")) }
        return ok
    }
}

/// 差し出しの言葉（板 51・51b の文言どおり）
enum CoverOfferText {
    static func eyebrow(_ kind: CoverOfferStore.Offer.Kind) -> String {
        switch kind {
        case .firstPost: return L("はじめての1枚", "Your first photo")
        case .liked(let n): return L("いいね \(n) 件", "\(n) \(likes(n))")
        }
    }

    static var title: String { L("この1枚をカバーにしますか？", "Make this your cover?") }

    /// 英語の数の言葉（1件のときは単数）
    static func likes(_ n: Int) -> String { n == 1 ? "like" : "likes" }

    static func body(_ offer: CoverOfferStore.Offer) -> String {
        switch offer.kind {
        case .firstPost:
            return L("あなたのページのいちばん上に出ます。ほかの人があなたのページを開いたときも。",
                     "It shows at the top of your page — including when other people open it.")
        case .liked(let n):
            let title = offer.title.isEmpty ? "" : L("「\(offer.title)」に、", "\u{201C}\(offer.title)\u{201D} got ")
            return offer.title.isEmpty
                ? L("この写真に、いいねが \(n) 件届きました。たくさんの人が足を止めた1枚です。",
                    "This photo got \(n) \(likes(n)). Lots of people stopped to look.")
                : L("\(title)いいねが \(n) 件届きました。たくさんの人が足を止めた1枚です。",
                    "\(title)\(n) \(likes(n)). Lots of people stopped to look.")
        }
    }

    static func footnote(_ kind: CoverOfferStore.Offer.Kind) -> String {
        switch kind {
        case .firstPost:
            // 2026-10-18 見直し: 実装どおりに言う（いいねが決まった件数に届いた写真ごとに1回・`CoverOfferRules.likedCandidate`）
            let n = CoverOfferRules.likedThreshold
            return L("「あとで」なら、いいねが \(n) 件に届いた写真が出たときに、その写真でまた聞きます（写真ごとに1回）。\nプロフィールの編集から、いつでも選べます。",
                     "Choose Later and we'll ask again when a photo reaches \(n) \(likes(n)) (once per photo).\nYou can pick a cover anytime in Edit profile.")
        case .liked:
            return L("プロフィールの編集から、いつでも選び直せます。", "You can change it anytime in Edit profile.")
        }
    }
}
