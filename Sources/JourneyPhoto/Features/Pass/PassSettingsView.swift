import SwiftUI
import UIKit
import CoreBluetooth

/// すれちがいの設定（板 PassSettings）。入口は設定の「すれちがい」の節（板の戻り先が設定）。
///
/// - **既定はオフ。** オンにする時は先に説明（`PassIntroSheet`）を出し、「オンにする」を押してから
///   電波を出す（そこで初めて iPhone が Bluetooth の使用を尋ねる）
/// - 名刺の一枚を選ぶまでは電波を出さない（オンにして選んでいなければ、そのまま選ぶ画面へ進む）
/// - 「いつ」: いつでも／旅のあいだ（家から 50km 以上離れた日だけ）／開いている間
struct PassSettingsView: View {

    @EnvironmentObject private var pass: PassStore
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var push: PushCenter
    @EnvironmentObject private var hidden: ModerationStore
    @Environment(\.openURL) private var openURL
    /// Bluetooth の電源（切れていたら案内を出す・2026-10-16）
    @ObservedObject private var radio = PassRadio.shared

    @State private var showIntro = false
    @State private var showPick = false
    /// 名刺の一枚（公開一覧から引いた自分の写真）
    @State private var cardPhoto: Photo?
    @State private var isTurningOnPush = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JPSpace.xl) {
                Text(L("すれちがい", "Pass"))
                    .font(JPFont.display(SettingsLayout.titleSize, relativeTo: .largeTitle))
                    .foregroundStyle(WebTheme.text)
                    .padding(.horizontal, JPSpace.xxs)
                    .accessibilityAddTraits(.isHeader)
                mainCard
                whenSection
                contentsSection
                privacyNote
                linksCard
            }
            .padding(.horizontal, JPSpace.gutter)
            .padding(.top, 10)
            .padding(.bottom, JPSpace.emptyTop)
        }
        .webScreen()
        .navigationTitle(L("すれちがい", "Pass"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
        }
        .sheet(isPresented: $showIntro) {
            PassIntroSheet {
                showIntro = false
                pass.update { $0.enabled = true }
                PassCoordinator.shared.turnedOn()
                // 名刺を選んでいなければ、そのまま選ぶ画面へ（選ぶまで電波は出さない）
                if pass.settings.cardPhotoId == nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showPick = true }
                }
            }
        }
        .navigationDestination(isPresented: $showPick) { PassCardPickView() }
        .task(id: pass.settings.cardPhotoId) { await loadCard() }
        .task {
            if push.permission == .unknown { await push.refreshAuthorization() }
            let profile = try? await environment.profiles.myProfile()
            if let profile { pass.noteHome(profile.homeLocation) }
        }
    }

    private func loadCard() async {
        guard let id = pass.settings.cardPhotoId else { cardPhoto = nil; return }
        let all = (try? await environment.gallery.fetchPhotos()) ?? []
        cardPhoto = all.first { $0.id == id }
    }

    /// 「すれちがう」の入切。オンは説明を挟む・オフはその場で止める
    private var enabledBinding: Binding<Bool> {
        Binding(get: { pass.settings.enabled }, set: { on in
            if on {
                showIntro = true
            } else {
                pass.update { $0.enabled = false }
                PassCoordinator.shared.refresh()
            }
        })
    }

    private var mainCard: some View {
        JPCard {
            JPToggleRow(title: L("すれちがう", "Pass"),
                        detail: L("近くにいたアプリの人と、名刺の一枚をカードで交換します",
                                  "Swap your calling-card photo with app users you pass nearby"),
                        isOn: enabledBinding)
                .accessibilityIdentifier("pass.settings.toggle")
            JPCardDivider()
            NavigationLink { PassCardPickView() } label: { cardRow }
                .buttonStyle(JPRowButtonStyle())
                .accessibilityIdentifier("pass.settings.card")
            if pass.settings.enabled, CBManager.authorization == .denied || CBManager.authorization == .restricted {
                JPCardDivider()
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    JPRowLabel(title: L("Bluetooth が許可されていません", "Bluetooth isn\u{2019}t allowed"),
                               detail: L("すれちがうには Bluetooth が要ります。設定アプリで許可してください。",
                                         "Pass needs Bluetooth. Allow it in the Settings app."),
                               iconColor: WebTheme.danger)
                }
                .buttonStyle(JPRowButtonStyle())
            }
            // 🔴 **Bluetooth を切ったら、そう言う**（2026-10-16）。オンのまま黙って止まっていた
            if PassRadio.showsPowerOffNotice(enabled: pass.settings.enabled, state: radio.powerState) {
                JPCardDivider()
                powerOffNotice
            }
            if pass.settings.enabled,
               let notice = LightAlertPushNotice.state(wants: true, knownNotPro: false,
                                                       permission: push.permission, enabled: true) {
                JPCardDivider()
                PushOffNoticeRow(notice: notice, isBusy: isTurningOnPush, identifier: "pass.settings.pushOff") {
                    Task { await fixPush(notice) }
                }
            }
        }
    }

    /// 「Bluetooth がオフです」の一行。**「通知がオフのため届きません」の行と同じ見た目**（真鍮 8% の地・
    /// 真鍮の字と印・owner の好み 2026-10-11）。押す所は無い——アプリから Bluetooth の電源は入れられず、
    /// 設定アプリの入口もアプリの設定（Bluetooth の画面ではない）なので、どこで入れるかを言うだけ
    private var powerOffNotice: some View {
        ZStack {
            Rectangle()
                .fill(WebTheme.accentSoft)
                .accessibilityHidden(true)
            HStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 18))
                    .frame(width: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Bluetooth がオフです", "Bluetooth is off"))
                        .font(JPFont.bodyEmphasis)
                    Text(L("オンにするまで、すれちがいは止まっています。コントロールセンターか設定アプリで入れてください。",
                           "Pass is paused until you turn Bluetooth on in Control Center or the Settings app."))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.accent.opacity(LightAlertSettingsStyle.noticeDetailOpacity))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(WebTheme.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("pass.settings.bluetoothOff")
    }

    private var cardRow: some View {
        HStack(spacing: JPSpace.s) {
            Group {
                if let cardPhoto {
                    RemoteImage(url: cardPhoto.gridImageURL, alignment: cardPhoto.gridAlignment)
                } else {
                    WebTheme.surface.overlay {
                        Image(systemName: "rectangle.portrait").foregroundStyle(WebTheme.text3)
                    }
                }
            }
            .frame(width: 40, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: JPRadius.xs))
            .overlay(RoundedRectangle(cornerRadius: JPRadius.xs)
                .strokeBorder(WebTheme.accent.opacity(0.45), lineWidth: JPStroke.hairline))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(L("名刺の一枚", "Your card"))
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.text)
                Text(cardDetail)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.35))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, JPSpace.m)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private var cardDetail: String {
        guard pass.settings.cardPhotoId != nil else { return L("まだ選んでいません", "Not chosen yet") }
        let title = cardPhoto?.displayTitle ?? L("選んだ写真", "Chosen photo")
        let note = pass.settings.note
        return note.isEmpty ? title : L("\(title) · 「\(note)」", "\(title) · \u{201C}\(note)\u{201D}")
    }

    // MARK: - いつ

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: JPSpace.xs) {
            eyebrow(L("いつ", "When"))
            PassSegment(selection: pass.settings.mode) { mode in
                pass.update { $0.mode = mode }
                PassCoordinator.shared.refresh()
            }
            Text(L("「旅のあいだ」は、家から 50km 以上離れた日だけ。家の近所では交換しません",
                   "\u{201C}While traveling\u{201D} works only on days you\u{2019}re 50 km or more from home. Never near home."))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .padding(.horizontal, JPSpace.xxs)
                .fixedSize(horizontal: false, vertical: true)
            if pass.settings.mode == .traveling, let reason = travelUnknownReason {
                Text(reason)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.accent)
                    .padding(.horizontal, JPSpace.xxs)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 「旅のあいだ」で、家からの距離が分からない訳（分からない日は交換しない）
    private var travelUnknownReason: String? {
        if pass.homePrefecture == nil {
            return L("プロフィールの居住地に都道府県が無いため、家からの距離が分かりません。居住地を入れるか、ほかの「いつ」を選んでください。",
                     "Your profile has no prefecture under \u{201C}Where you\u{2019}re based\u{201D}, so distance from home is unknown. Add it, or pick another option.")
        }
        if !PassPlaceFinder.shared.isAuthorized {
            return L("位置情報が許可されていないため、旅のあいだか分かりません。撮影地マップで現在地を許可するか、ほかの「いつ」を選んでください。",
                     "Location isn\u{2019}t allowed, so we can\u{2019}t tell if you\u{2019}re traveling. Allow it on the map, or pick another option.")
        }
        return nil
    }

    // MARK: - カードに載るもの

    private var contentsSection: some View {
        VStack(alignment: .leading, spacing: JPSpace.xs) {
            eyebrow(L("カードに載るもの", "On your card"))
            JPCard {
                JPRowLabel(title: L("名刺の一枚・名前・ひとこと", "Card photo, name and note"),
                           detail: L("いつも載ります", "Always included"), chevron: false)
                JPCardDivider()
                // 乗車券の「発」（2026-10-16）。自分で書く字は名刺の一枚の画面で選ぶ。ここでは居住地を出す／出さない
                NavigationLink { PassCardPickView() } label: {
                    JPRowLabel(title: L("乗車券の区間（発・着）", "Ticket route (from / to)"),
                               detail: PassSettingsText.route(pass.settings))
                }
                .buttonStyle(JPRowButtonStyle())
                JPCardDivider()
                JPRowLabel(title: L("すれちがった場所と時刻", "Where and when you passed"),
                           detail: L("「京都市のあたり · 15 時ごろ」の粒度。番地や分は載せません",
                                     "As rough as \u{201C}around Kyoto · around 3 PM\u{201D}. Never street addresses or minutes."),
                           chevron: false)
            }
        }
    }

    private var privacyNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(PassPrivacyText.noteTitle)
                .font(JPFont.bodyEmphasis)
                .foregroundStyle(WebTheme.accent)
            Text(PassPrivacyText.noteBody)
                .font(JPFont.footnote)
                .lineSpacing(4)
                .foregroundStyle(WebTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(JPSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WebTheme.accentSoft, in: RoundedRectangle(cornerRadius: JPRadius.l))
        .overlay(RoundedRectangle(cornerRadius: JPRadius.l).strokeBorder(WebTheme.accent.opacity(0.3), lineWidth: JPStroke.hairline))
        .accessibilityElement(children: .combine)
    }

    private var linksCard: some View {
        JPCard {
            NavigationLink { BlockedUsersView() } label: {
                JPRowLabel(title: L("ブロックした人", "Blocked people"))
            }
            .buttonStyle(JPRowButtonStyle())
            JPCardDivider()
            NavigationLink { PassBookView(fromSettings: true) } label: {
                JPRowLabel(title: L("すれちがい帳", "Pass book"),
                           detail: L("\(pass.book(hiding: hidden.snapshot).count) 枚",
                                     "\(pass.book(hiding: hidden.snapshot).count) cards"))
            }
            .buttonStyle(JPRowButtonStyle())
        }
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text)
            .jpEyebrow()
            .foregroundStyle(WebTheme.accent)
            .padding(.horizontal, JPSpace.xxs)
            .accessibilityAddTraits(.isHeader)
    }

    private func fixPush(_ notice: LightAlertPushNotice) async {
        switch notice {
        case .openSettings:
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
        case .turnOn:
            guard !isTurningOnPush else { return }
            isTurningOnPush = true
            defer { isTurningOnPush = false }
            await push.enable()
        }
    }
}

/// 「いつ」の3つの切り替え（板 PassSettings の `.seg`: 白 7% の溝・選んだ側は白 14% の地に白の字 600）。
///
/// 見た目の高さは 38＋溝の 3＋3 で 44、**当たりは溝の余白まで含めて 44**（押すのは各ボタンの枠いっぱい）。
/// 選んだことは地と太さ（形）と読み上げで伝える
struct PassSegment: View {

    let selection: PassExchange.Mode
    let select: (PassExchange.Mode) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PassExchange.Mode.allCases) { mode in
                let on = mode == selection
                Button { select(mode) } label: {
                    Text(mode.label)
                        .font(on ? JPFont.footnote.weight(.semibold) : JPFont.footnote)
                        .foregroundStyle(on ? WebTheme.text : WebTheme.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(WebTheme.minimumScale(forTextSize: 13))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(on ? Color.white.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("pass.settings.mode.\(mode.rawValue)")
            }
        }
        .padding(.horizontal, 3)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// オンにする時の説明（写真の無い画面なので、主ボタンは真鍮の塗りに墨）
struct PassIntroSheet: View {

    let confirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JPSpace.l) {
                VStack(alignment: .leading, spacing: JPSpace.xs) {
                    Text(L("すれちがい", "Pass"))
                        .jpEyebrow()
                        .foregroundStyle(WebTheme.accent)
                    Text(L("旅先で、名刺の一枚を交換する", "Swap a calling-card photo on your travels"))
                        .font(JPFont.screenTitle)
                        .foregroundStyle(WebTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                VStack(alignment: .leading, spacing: JPSpace.m) {
                    ForEach(Array(PassPrivacyText.introPoints.enumerated()), id: \.offset) { _, item in
                        point(item.symbol, item.text)
                    }
                }
                Text(L("「オンにする」を押すと、iPhone が Bluetooth の使用を尋ねます。",
                       "After you tap Turn on, iPhone will ask to use Bluetooth."))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: JPSpace.xs) {
                    Button(action: confirm) {
                        Text(L("オンにする", "Turn on")).jpPillButton(.main(onPhoto: false))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pass.intro.confirm")
                    Button { dismiss() } label: {
                        Text(L("やめる", "Not now")).jpPillButton(.outline)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pass.intro.cancel")
                }
            }
            .padding(.horizontal, JPSpace.l)
            .padding(.top, JPSpace.xl)
            .padding(.bottom, JPSpace.l)
        }
        .webScreen()
        .presentationDetents([.large])
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: JPSpace.s) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(WebTheme.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(JPFont.body)
                .foregroundStyle(WebTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 設定の文（テストで見張る）
enum PassSettingsText {
    /// 「乗車券の区間」の行の2行目（いまの発・着）
    static func route(_ settings: PassSettings) -> String {
        let from: String
        switch settings.origin {
        case .home: from = L("発: 居住地から", "From: where I live")
        case .hidden: from = L("発: 出さない", "From: hidden")
        case .custom: from = L("発: 「\(settings.originLabel ?? "")」", "From: \u{201C}\(settings.originLabel ?? "")\u{201D}")
        }
        let to = settings.destinationLabel.map { L("着: 「\($0)」", "To: \u{201C}\($0)\u{201D}") }
            ?? L("着: すれちがった所", "To: where you pass")
        return "\(from) · \(to)"
    }
}
