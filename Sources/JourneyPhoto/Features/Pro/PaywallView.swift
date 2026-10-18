import SwiftUI

/// Pro の案内（板 63・2026-10-09）。全画面で開き、右上の「閉じる」で戻る。
///
/// 入口: 設定の「Journey Photo Pro」（Pro でないとき）・名前の横の画面の「PRO 限定」・旅のトランクの Pro の口。
///
/// **どこから開いたか（`PaywallOrigin`・2026-10-18 判断）**: 旅のトランクの口（作り直す・特別なトランク・
/// 手持ちの上限）から開いたときは、トランクの利点をいちばん上に出す。押した物の答えが最初に見えるように。
/// 並びを変えるだけで、文言・見た目・ほかの利点は同じ（案内を長くしない）。
///
/// 板のとおり: 上に撮影地の写真（朝焼け）と黒への溶け、眉ラベル・明朝の見出し、利点（2026-10-18 から5つ・`ProBenefit`）、
/// 1年ごと（選んである・「2か月ぶんお得」）と月ごとの札、白い主ボタン（写真のある画面）、注記。
///
/// **板と変えたところ（報告済み）**
/// - 主ボタンの文言: 板は「7日間 無料で試す」だが、**無料の試用は出さない**（owner の決定）ので「Pro をはじめる」
/// - 注記のリンク: 押せる大きさ（44pt）を取るため、本文の後ろの行に分けた。審査の決まり
///   （定期購入の画面に利用規約とプライバシーポリシーへのリンク・購入の復元）に合わせて
///   「プライバシーポリシー」「購入を復元」を足した
/// - 値段は App Store の字（`Product.displayPrice`）。読めないときだけ板の値段
///
/// **v2（2026-10-14・板 Paywall）**: 写真 300・溶け 160・本文は写真へ 40 だけ食い込む。眉ラベルは真鍮
/// （溶けの下端＝ほぼ黒の上）。利点は箱を外して真鍮の線の絵 20 だけ、題 15 semibold・説明 13 の text-2。
/// プランの札は左寄せの縁 1（白 14%）、選んだ札は真鍮 2 の縁と真鍮のごく暗い地、値段は SF の等幅数字 20。
/// 主ボタンは白（写真のある画面・`JPPillStyle.main(onPhoto: true)`）。閉じるはガラスの丸
struct PaywallView: View {

    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// どこから開いたか（利点の並びだけを変える・2026-10-18）
    var origin: PaywallOrigin = .general

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
                            .padding(.horizontal, JPSpace.l)
                            // 板 v2: 写真の下から 40pt 上に食い込む（写真 300・本文は 260 から）
                            .padding(.top, -ProPaywallStyle.contentOverlap)
                            .padding(.bottom, JPSpace.section)
                    }
                }
                .ignoresSafeArea(edges: .top)
                // 板 v2: 右 12・上 54（時刻の帯のすぐ下）
                closeButton
                    .padding(.trailing, JPSpace.s)
                    .padding(.top, JPSpace.xs)
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

    /// 板 v2: 画面の上端から高さ 300 の写真（無ければ #34404d）と、下 160pt の黒への溶け。
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
        VStack(alignment: .leading, spacing: JPSpace.m) {
            VStack(alignment: .leading, spacing: JPSpace.xs) {
                // 2026-10-14 判断: 板は真鍮だが、眉は写真が黒へ溶ける帯の上に乗る（純粋な黒地ではない）。
                // 「真鍮は黒地の上だけ」（CLAUDE.md）に従い、写真の上の眉と同じ白 88% にする
                Text("JOURNEY PHOTO PRO")
                    .jpEyebrow()
                    .foregroundStyle(Color.white.opacity(0.88))
                Text(L("行ったその日に、\nいちばんの一枚を。", "The best shot,\non the day you go."))
                    .font(JPFont.display(ProPaywallStyle.titleSize, relativeTo: .title))
                    .lineSpacing(ProPaywallStyle.titleSize * 0.35 - 6)
                    .foregroundStyle(WebTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: JPSpace.s) {
                ForEach(ProBenefit.ordered(for: origin)) { benefit in
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
        HStack(alignment: .top, spacing: JPSpace.s) {
            // 板 v2: 箱を外し、真鍮の線の絵 20（線 1.6）だけ。黒地の上の手がかりなので真鍮
            ProIconView(icon: benefit.icon, side: ProPaywallStyle.benefitIconSide, color: WebTheme.accent, lineWidth: 1.6)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 0) {
                Text(benefit.title)
                    .font(JPFont.bodyEmphasis)
                    .foregroundStyle(WebTheme.text)
                Text(benefit.body)
                    .font(JPFont.footnote)
                    .lineSpacing(3)
                    .foregroundStyle(WebTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("paywall.benefit.\(benefit.id)")
    }

    // MARK: - プラン

    private var plans: some View {
        HStack(spacing: JPSpace.xs) {
            ForEach(ProPlan.allCases) { option in
                planCard(option)
            }
        }
        // 札の上にはみ出す「2か月ぶんお得」の分
        .padding(.top, 10)
    }

    private func planCard(_ option: ProPlan) -> some View {
        let on = plan == option
        let price = option.priceLine(displayPrice: store.product(option)?.displayPrice)
        return Button { plan = option } label: {
            // 板 v2: 左寄せ。上に支払いの間隔（注記 12・text-3）、下に値段（SF の等幅数字 20）
            VStack(alignment: .leading, spacing: 2) {
                Text(option.cycleLabel)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                Text(price)
                    .font(JPFont.number(JPTypeScale.figureMedium, weight: .semibold, relativeTo: .title3))
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, JPSpace.s)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(on ? ProPaywallStyle.selectedPlanFill : Color.clear, in: RoundedRectangle(cornerRadius: JPRadius.m))
            .overlay(RoundedRectangle(cornerRadius: JPRadius.m)
                .strokeBorder(on ? WebTheme.accent : WebTheme.line,
                              lineWidth: on ? JPStroke.emphasis : JPStroke.hairline))
            .overlay(alignment: .topTrailing) {
                if option == .yearly {
                    // 板 v2: 右上にはみ出す真鍮の札に墨の字。黒 2 の縁で札の縁から切り離す（件数バッジと同じ作り）
                    Text(L("2か月ぶんお得", "2 months free"))
                        .font(JPFont.eyebrow)
                        .foregroundStyle(WebTheme.accentText)
                        .padding(.horizontal, JPSpace.xs)
                        .padding(.vertical, 1)
                        .background(WebTheme.accent, in: RoundedRectangle(cornerRadius: JPSpace.xs))
                        .padding(JPStroke.emphasis)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: JPSpace.xs + JPStroke.emphasis))
                        .offset(x: -10, y: -10)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: JPRadius.m))
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
                    .opacity(store.isPurchasing ? 0 : 1)
                if store.isPurchasing { ProgressView().tint(WebTheme.accentText) }
            }
            // 写真のある画面の主ボタンは白（CLAUDE.md・v2 の板も白）。高さ・字は土台の主ボタン
            .jpPillButton(ProPaywallStyle.purchaseStyle)
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
        case .refused(let refusal):
            // 失敗の赤ではなく、ふつうの補足の字で（owner 2026-10-09）。Pro にはしない
            show(PurchaseDelivery.message(for: refusal), error: false)
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
        case .refused(let refusal):
            show(PurchaseDelivery.message(for: refusal), error: false)
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
                .font(JPFont.caption)
                .lineSpacing(2)
                .foregroundStyle(WebTheme.text3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            // 自動更新の一文（審査 3.1.2・2026-10-16）。値段と期間はプランの札にある。
            // 色・大きさは上の注記と同じ（黒地の上の注記 12・text-3）
            Text(ProPaywallText.autoRenewNotice)
                .font(JPFont.caption)
                .lineSpacing(2)
                .foregroundStyle(WebTheme.text3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.top, JPSpace.xs)
                .accessibilityIdentifier("paywall.autoRenew")
            HStack(spacing: JPSpace.m) {
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
                .font(JPFont.caption)
                .underline()
                .foregroundStyle(WebTheme.accent)
                .frame(minHeight: WebTheme.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 閉じる

    /// 板 v2: 右上 44×44 のガラスの丸・× 18（写真の上に置くものは白とガラス・`jpGlass`）
    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                .jpGlass(in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel(Labels.Common.close)
        .accessibilityIdentifier("paywall.close")
    }
}

/// Pro の利点（板 63 の文言そのまま）。
///
/// 2026-10-17 判断（owner）: **「作例を重ねて撮る」（構図を重ねて撮るを含む）は全員無料にしたので、利点から外した。**
/// 板 63 は4つだが、残りは3つ（光と天気の知らせ・電波なしで使える旅・Pro マークと Pro 限定の章）。
/// 2026-10-17: 特別な乗車券（すれちがいの券面を選べる）を足して4つ。
/// 2026-10-18 判断: 旅のトランクを足して5つ（特別な乗車券の次＝ふだんはいちばん下。トランクから開いたときは上）。
/// 中身はサーバー（photo-gallery `api-user/src/trunk.ts`）で確かめた: Pro の型6つ（`PRO_MODELS`）・
/// 作り直しは Pro だけ月3回で繰り越しなし（`REROLLS_PER_MONTH`）・手持ちの上限 無料 30／Pro 150
/// （`POCKET_LIMIT_FREE`・`POCKET_LIMIT_PRO`）。**硬貨・カプセル・部品は Pro と関係ない（買えない・Pro でも増えない）
/// ので書かない。** 「必ず」「確定」「捨てる」は言わない（トランクの説明の決まり・テストで見張る）
///
/// 第3段階の機能が2つ入っている（光と天気の知らせ・電波なしで使える旅）。**どちらもできている。**
/// 2026-10-17 判断（確かめた）: 光と天気の知らせは、アプリ側＝一覧 `LightForecastView`
/// （設定の Pro の節・前の晩のプッシュ `type: "light"` から開く）と入切 `LightAlertSettingsRows`、
/// サーバー側＝`GET /user/light-forecast` と毎日 20:00（日本時間）の `sendLightAlerts`
/// （photo-gallery `api-user/src/lightForecast.ts`・main に入っている）。
/// 🔴 **本番の WeatherKit の鍵（SSM）が無いと、一覧は 503・知らせは送られない**——出す前に
/// 本番で一覧が開けることを確かめる（無い機能を売らない・審査 2.3.1 / 3.1.2）
struct ProBenefit: Identifiable, Equatable {
    let icon: ProIcon
    let title: String
    let body: String

    var id: String { icon.rawValue }

    static var all: [ProBenefit] {
        [
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
            // 2026-10-17: すれちがいの「特別な乗車券」（券面を選べる・`PassTicketFaceStyle`）
            ProBenefit(icon: .card,
                       title: L("特別な乗車券", "Special Pass tickets"),
                       body: L("すれちがい乗車券を、真鍮・漆・革などの券面で。表も裏も、その券面で相手に届く",
                               "Pick a brass, lacquer, leather or other design for your Pass ticket — front and back, it reaches others that way")),
            trunk,
        ]
    }

    /// 旅のトランク（2026-10-18）。数はアプリの決まり（`TrunkModel.pro`・`TrunkState`）から読み、サーバーとずれないようにする。
    /// 2026-10-18 判断（見直し）: 説明は3つを「・」で並べた短い形にする。幅 375 の iPhone でも2行に収め、
    /// プランの札と主ボタンを最初の画面から押し出さない（`ProPaywallStyle.benefitBodyMaxUnits` をテストで見張る）
    static var trunk: ProBenefit {
        let models = TrunkModel.pro.count
        let rerolls = trunkRerollsPerMonth
        let pro = TrunkState.proLimit
        let free = TrunkState.freeLimit
        return ProBenefit(icon: .trunk,
                          title: L("旅のトランクをもっと", "More from your Travel trunk"),
                          body: L("特別なトランク \(models) 型・ラベルの図柄の作り直し 月 \(rerolls) 回・手持ち \(pro) 枚（無料は \(free) 枚）",
                                  "\(models) special trunks · \(rerolls) label redesigns a month · hold \(pro) labels (\(free) free)"))
    }

    /// 作り直しの月の回数（サーバーの `REROLLS_PER_MONTH`。繰り越しなし）。
    /// 2026-10-18 判断（見直し）: 同じ数がトランクの作り直しの画面（`TrunkRerollView` の「毎月 3 回」）と
    /// `TrunkText` の断り（「来月また3回」）にも直に書かれている。トランクの画面は別の担当が作業中なので、
    /// いまは触らずテストで一致を見張る（`PaywallTrunkBenefitTests`）。**数の元を1つにするのは、トランク担当と合わせて後で行う**
    static let trunkRerollsPerMonth = 3

    /// 開いた口に合わせた並び。口に合う利点をいちばん上に、残りはふだんの順のまま（2026-10-18 判断）
    static func ordered(for origin: PaywallOrigin) -> [ProBenefit] {
        var list = all
        guard let lead = origin.leadingBenefit,
              let index = list.firstIndex(where: { $0.icon == lead }) else { return list }
        list.insert(list.remove(at: index), at: 0)
        return list
    }
}

/// Pro の案内をどこから開いたか（2026-10-18 判断）。利点の並びだけに使う。
/// 新しい口を足すときは、ここに1つ足して `leadingBenefit` を返す
enum PaywallOrigin: Equatable {
    /// 設定・名前の横・光の知らせなど（ふだんの並び）
    case general
    /// 旅のトランク（作り直す・特別なトランク・手持ちの上限）
    case trunk

    /// いちばん上に出す利点。nil ならふだんの並び
    var leadingBenefit: ProIcon? {
        switch self {
        case .general: return nil
        case .trunk: return .trunk
        }
    }
}

/// 案内の見た目の決まり（v2 の板 Paywall の値・2026-10-14）
enum ProPaywallStyle {
    /// 写真の高さ（v2: 300・v1 は 330）と、下の黒への溶け（v2: 160・v1 は 170）
    static let heroHeight: Double = 300
    static let heroFade: Double = 160
    /// 本文が写真へ食い込む量（v2: 40・v1 は 94）。眉ラベルは溶けの下端のこの幅の中に乗る
    static let contentOverlap: Double = 40
    /// 見出し（明朝 28・板の値。2行の見出しで、段の 26 と 32 の間を板のまま使う）
    static let titleSize: Double = 28
    /// 利点の線の絵の大きさ（v2: 箱なしの 20）
    static let benefitIconSide: Double = 20
    /// 利点の説明（13pt）の長さの上限（2026-10-18 判断）。全角 1・空白 0.3・ほかの半角 0.6 で数える（`benefitBodyUnits`）。
    /// 幅 375 の iPhone では説明の幅が 303pt（左右 20・絵 20・間 12）＝1行に全角 23 字ほど。
    /// 折り返しの余りを見て、2行に収まる 40 までにする
    static let benefitBodyMaxUnits: Double = 40

    /// 説明の長さの目安（全角 1・空白 0.3・ほかの半角 0.6）
    static func benefitBodyUnits(_ text: String) -> Double {
        text.unicodeScalars.reduce(0) { sum, c in
            sum + (c == " " ? 0.3 : c.isASCII ? 0.6 : 1)
        }
    }
    /// 主ボタン: 写真のある画面なので白（CLAUDE.md の owner の好み）
    static let purchaseStyle = JPPillStyle.main(onPhoto: true)
    /// 写真が無いときの地（板: #34404d）
    static let heroPlaceholder = ProMarkColors.color(0x34404D)
    /// 選んだプランの札の地（v2: #14110B・真鍮のごく暗い地）
    static let selectedPlanFillHex: UInt32 = 0x14110B
    static let selectedPlanFill = ProMarkColors.color(selectedPlanFillHex)

    /// 眉ラベルの下に来うるいちばん明るい地: 白い写真に、溶けの下端 40pt の黒（75% 以上）を重ねた値。
    /// 眉ラベルは白 88%（真鍮は黒地の上だけ）。この地の上でも白が読めることをテストで見張る
    static var eyebrowFloorHex: UInt32 {
        let white = contentOverlap / heroFade
        let level = UInt32((white * 255).rounded())
        return (level << 16) | (level << 8) | level
    }

    /// 上の写真に使う1枚: 朝（5〜9時）に撮った公開写真。横長を先に、無ければ朝の写真のどれか。
    /// **朝の写真が1枚も無ければ、時間帯を問わず**同じ順で選ぶ（撮影時刻の無い写真が多く、
    /// 朝に絞ると地の色だけになりやすい・2026-10-10 owner 承認）
    static func heroPhoto(_ photos: [Photo]) -> Photo? {
        let usable = photos.filter { $0.detailImageURL != nil }
        let morning = usable.filter { ShootingTime.dayPart(of: $0) == .morning }
        return pick(morning) ?? pick(usable)
    }

    /// 横長を先に、無ければ最初の1枚
    private static func pick(_ photos: [Photo]) -> Photo? {
        photos.first { ($0.width ?? 0) > ($0.height ?? 0) } ?? photos.first
    }
}
