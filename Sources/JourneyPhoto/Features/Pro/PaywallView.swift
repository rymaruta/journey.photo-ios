import SwiftUI

/// Pro の案内（板 63・2026-10-09）。全画面で開き、右上の「閉じる」で戻る。
///
/// 入口: 設定の「Journey Photo Pro」（Pro でないとき）・名前の横の画面の「PRO 限定」。
///
/// 板のとおり: 上に撮影地の写真（朝焼け）と黒への溶け、眉ラベル・明朝の見出し、4つの利点、
/// 1年ごと（選んである・「2か月ぶんお得」）と月ごとの札、白い主ボタン（写真のある画面）、注記。
///
/// **板と変えたところ（報告済み）**
/// - 主ボタンの文言: 板は「7日間 無料で試す」だが、**無料の試用は出さない**（owner の決定）ので「Pro をはじめる」
/// - 注記のリンク: 押せる大きさ（44pt）を取るため、本文の後ろの行に分けた。審査の決まり
///   （定期購入の画面に利用規約とプライバシーポリシーへのリンク・購入の復元）に合わせて
///   「プライバシーポリシー」「購入を復元」を足した
/// - 値段は App Store の字（`Product.displayPrice`）。読めないときだけ板の値段
struct PaywallView: View {

    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// 選んでいるプラン（板: 1年ごとが選んである）
    @State private var plan: ProPlan = .yearly
    @State private var message: String?
    @State private var messageIsError = false
    /// 上の写真（朝に撮った公開写真から1枚）
    @State private var heroURL: URL?

    private var busy: Bool { store.isPurchasing || store.isRestoring }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        hero(width: geo.size.width)
                        content
                            .padding(.horizontal, 24)
                            // 板: 写真の下から 94pt 上に食い込む（写真 330・本文 236 から）
                            .padding(.top, -94)
                            .padding(.bottom, 28)
                    }
                }
                .ignoresSafeArea(edges: .top)
                // 板: 右 8・上 50（時刻の帯 47 のすぐ下）
                closeButton
                    .padding(.trailing, 8)
                    .padding(.top, 3)
            }
        }
        .background { Color.black.ignoresSafeArea() }
        .interactiveDismissDisabled(busy)
        .task {
            await store.loadProducts()
            await loadHero()
        }
    }

    // MARK: - 写真

    /// 板: 画面の上端から高さ 330 の写真（無ければ #34404d）と、下 170pt の黒への溶け。
    /// 時刻の帯の裏まで写真を敷く
    private func hero(width: Double) -> some View {
        ZStack(alignment: .bottom) {
            ProPaywallStyle.heroPlaceholder
            if let heroURL {
                RemoteImage(url: heroURL, contentMode: .fill, placeholderSymbol: "sunrise")
                    .frame(width: width, height: ProPaywallStyle.heroHeight)
                    .clipped()
            }
            LinearGradient(colors: [Color.black, Color.black.opacity(0)], startPoint: .bottom, endPoint: .top)
                .frame(height: ProPaywallStyle.heroFade)
        }
        .frame(width: width, height: ProPaywallStyle.heroHeight)
        .clipped()
        .accessibilityHidden(true)
    }

    /// 朝（5〜9時）に撮った公開写真から1枚。横長を先に
    private func loadHero() async {
        guard heroURL == nil else { return }
        let photos = (try? await environment.gallery.fetchPhotos()) ?? []
        heroURL = ProPaywallStyle.heroPhoto(photos)?.detailImageURL
    }

    // MARK: - 本文

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                // 写真の溶けの上なので白（真鍮は黒地だけ）
                Text("JOURNEY PHOTO PRO")
                    .font(.system(size: 11))
                    .tracking(11 * 0.14)
                    .foregroundStyle(Color.white.opacity(0.85))
                Text(L("行ったその日に、\nいちばんの一枚を。", "The best shot,\non the day you go."))
                    .font(JPFont.display(28, relativeTo: .title))
                    .lineSpacing(28 * 0.35 - 6)
                    .foregroundStyle(WebTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 14) {
                ForEach(ProBenefit.all) { benefit in
                    benefitRow(benefit)
                }
            }
            plans
            purchaseButton
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(messageIsError ? WebTheme.danger : WebTheme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            footnote
        }
    }

    private func benefitRow(_ benefit: ProBenefit) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 板: 40×40・角 12・地 #0B0B0B・真鍮 1.5 の縁・白い線の絵
            ProIconView(icon: benefit.icon, side: 20, color: .white, lineWidth: 1.8)
                .frame(width: 40, height: 40)
                .background(ProPaywallStyle.tile, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WebTheme.accent, lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(benefit.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WebTheme.text)
                Text(benefit.body)
                    .font(.caption)
                    .lineSpacing(12 * 0.6 - 4)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - プラン

    private var plans: some View {
        HStack(spacing: 10) {
            ForEach(ProPlan.allCases) { option in
                planCard(option)
            }
        }
        // 札の上にはみ出す「2か月ぶんお得」の分
        .padding(.top, 9)
    }

    private func planCard(_ option: ProPlan) -> some View {
        let on = plan == option
        let price = option.priceLine(displayPrice: store.product(option)?.displayPrice)
        return Button { plan = option } label: {
            VStack(spacing: 2) {
                Text(option.cycleLabel)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.7))
                Text(price)
                    .font(.system(size: 16, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(ProPaywallStyle.tile, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(on ? WebTheme.accent : ProPaywallStyle.planBorder, lineWidth: on ? 1.5 : 1))
            .overlay(alignment: .top) {
                if option == .yearly {
                    Text(L("2か月ぶんお得", "2 months free"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ProMarkColors.color(ProMarkColors.ink))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                        .background(WebTheme.accent, in: Capsule())
                        .offset(y: -9)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel("\(option.cycleLabel) \(price)" + (option == .yearly ? L("、2か月ぶんお得", ", 2 months free") : ""))
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityIdentifier("paywall.plan.\(option.rawValue)")
    }

    // MARK: - 主ボタン

    private var purchaseButton: some View {
        Button { Task { await purchase() } } label: {
            ZStack {
                Text(L("Pro をはじめる", "Start Pro"))
                    .font(.system(size: 16, weight: .bold))
                    .opacity(store.isPurchasing ? 0 : 1)
                if store.isPurchasing { ProgressView().tint(.black) }
            }
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity, minHeight: 52)
            // 写真のある画面の主ボタンは白（CLAUDE.md）
            .background(Color.white, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityIdentifier("paywall.purchase")
    }

    private func purchase() async {
        message = nil
        switch await store.purchase(plan) {
        case .purchased:
            toasts.show(L("Pro になりました。ありがとうございます", "You're Pro now. Thank you!"))
            dismiss()
        case .purchasedPendingServer:
            show(L("購入は済んでいます。反映に少し時間がかかることがあります（アプリを開いたときに自動でやり直します）。",
                   "Your purchase went through. It may take a moment to show up — we'll retry automatically."), error: false)
        case .pending:
            show(L("承認を待っています。承認されると Pro になります。",
                   "Waiting for approval. You'll become Pro once it's approved."), error: false)
        case .cancelled:
            break
        case .failed(let text):
            show(text, error: true)
        }
    }

    private func restore() async {
        message = nil
        switch await store.restore() {
        case .restored:
            toasts.show(L("購入を復元しました", "Purchase restored"))
            dismiss()
        case .nothing:
            show(L("復元できる購入はありませんでした。", "No purchases to restore."), error: false)
        case .failed(let text):
            show(text, error: true)
        }
    }

    private func show(_ text: String, error: Bool) {
        message = text
        messageIsError = error
    }

    // MARK: - 注記

    private var footnote: some View {
        VStack(spacing: 0) {
            Text(L("サポーターバッジも付きます。App Store でいつでも解約できます。",
                   "Includes the supporter badge. Cancel anytime in the App Store."))
                .font(.caption)
                .lineSpacing(12 * 0.6 - 4)
                .foregroundStyle(WebTheme.faint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            HStack(spacing: 16) {
                footLink(L("利用規約", "Terms of Use")) { openURL(LegalConsent.termsURL) }
                footLink(L("プライバシーポリシー", "Privacy Policy")) { openURL(LegalConsent.privacyURL) }
                footLink(L("購入を復元", "Restore")) { Task { await restore() } }
                    .disabled(busy)
                    .accessibilityIdentifier("paywall.restore")
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// 黒地の上のリンクは真鍮・下線（板の `a`）
    private func footLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .underline()
                .foregroundStyle(WebTheme.accent)
                .frame(minHeight: WebTheme.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 閉じる

    /// 板: 右上 44×44・黒 55% の丸・白 10% の縁・× 18
    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                .background(Color.black.opacity(0.55), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel(Labels.Common.close)
        .accessibilityIdentifier("paywall.close")
    }
}

/// Pro の4つの利点（板 63 の文言そのまま）。
///
/// 🔴 **第3段階の機能が3つ入っている**（作例を重ねて撮る・光と天気の知らせ・電波なしで使える旅）。
/// 2026-10-09 時点で、作例を重ねて撮る・電波なしで使える旅はできた。光と天気の知らせはまだ。
/// 板どおりに出しているが、機能ができる前に App Store へ出すと、無い機能を売ることになる
/// （審査 2.3.1 / 3.1.2）。出す前に owner に確かめる（報告済み）
struct ProBenefit: Identifiable, Equatable {
    let icon: ProIcon
    let title: String
    let body: String

    var id: String { icon.rawValue }

    static var all: [ProBenefit] {
        [
            ProBenefit(icon: .overlay,
                       title: L("作例を重ねて撮る", "Shoot over a reference"),
                       body: L("名作の構図をカメラに重ねて、同じ場所から撮れる",
                               "Overlay a classic composition on your camera and shoot from the same spot")),
            ProBenefit(icon: .light,
                       title: L("光と天気の知らせ", "Light & weather alerts"),
                       body: L("行きたい場所が「明日の朝、晴れて朝焼け」なら前の晩に",
                               "The night before, if a place you want to go will have a clear sunrise")),
            ProBenefit(icon: .offline,
                       title: L("電波なしで使える旅", "Offline trips"),
                       // 2026-10-09 owner: 「迷わない」をやめる（道案内はしない。地図は画像で、拡大も経路も無い）
                       body: L("地図・作例・光の時刻を端末に。圏外でも、どこで何を撮るか分かる",
                               "Maps, references and light times on your device — know where and what to shoot, even with no signal")),
            ProBenefit(icon: .chapter,
                       title: L("Pro マークと Pro 限定の章", "Pro mark & Pro-only chapters"),
                       body: L("名前の横に Pro マーク。季節ごとに届く七宝の章と、道具を使い込んだ証の章",
                               "A Pro mark next to your name, enamel chapters every season, and chapters for using the tools")),
        ]
    }
}

/// 案内の見た目の決まり（板 63 の値）
enum ProPaywallStyle {
    /// 写真の高さ（板: 330）と、下の黒への溶け（170）
    static let heroHeight: Double = 330
    static let heroFade: Double = 170
    /// 写真が無いときの地（板: #34404d）
    static let heroPlaceholder = ProMarkColors.color(0x34404D)
    /// 札・絵の箱の地（板: #0B0B0B）
    static let tile = ProMarkColors.color(0x0B0B0B)
    /// 選んでいない札の縁（板: #333）
    static let planBorder = ProMarkColors.color(0x333333)

    /// 上の写真に使う1枚: 朝（5〜9時）に撮った公開写真。横長を先に、無ければ朝の写真のどれか
    static func heroPhoto(_ photos: [Photo]) -> Photo? {
        let morning = photos.filter { ShootingTime.dayPart(of: $0) == .morning && $0.detailImageURL != nil }
        return morning.first { ($0.width ?? 0) > ($0.height ?? 0) } ?? morning.first
    }
}
