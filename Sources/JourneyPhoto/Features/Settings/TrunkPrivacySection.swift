import SwiftUI

/// 設定の「トランクを見せる」（板 TrunkPrivacy・2026-10-18）。
///
/// - 切り替えは `PUT /user/trunk/settings { showTrunk }`（オフの間は人の口が 404）。**送れたら応答の値を映し、
///   断られた・圏外なら元に戻して一行で知らせる**（嘘の状態を残さない）
/// - わたしの乗車券（端末の中のすれちがいの設定）を、サーバーに置いた1枚と揃える（人のトランクの中に出る1枚）。
///   揃っていれば送らない
/// - 画面写真の見本（`-JPPreviewTrunk`）では、サーバーに何も送らず端末の中だけで切り替える
@MainActor
final class TrunkPrivacyModel: ObservableObject {

    @Published private(set) var state: TrunkState?
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    /// ほかの人から見た姿の見本の数（読めなければ nil・行ごと出さない）
    @Published private(set) var followers: Int?
    @Published private(set) var photos: Int?

    private let preview: PreviewSession.TrunkPreview?

    init(preview: PreviewSession.TrunkPreview? = PreviewSession.trunkSample) {
        self.preview = preview
    }

    var showTrunk: Bool { state?.showTrunk ?? true }

    func load(service: TrunkService, pass: PassSettings) async {
        if let preview {
            if state == nil { state = TrunkSample.state(isPro: PreviewSession.isPro, empty: preview == .empty) }
            return
        }
        guard let fresh = try? await service.state() else { return }
        state = fresh
        // わたしの乗車券を揃える（端末で選んだ1枚があって、サーバーの1枚と違うときだけ）
        guard let mine = TrunkTicket.mine(pass), fresh.ticket != mine else { return }
        let synced = try? await service.setTicket(mine)
        if let synced { state = synced.keepingPosts(from: fresh) }
    }

    /// 見本の数（フォロワー・写真）。読めなければ出さない
    func loadCounts(userId: String, environment: AppEnvironment) async {
        let stats = try? await environment.social.followStats(userId: userId)
        if let stats { followers = stats.followers }
        let all = try? await environment.gallery.fetchPhotos()
        if let all { photos = all.filter { ($0.userId ?? $0.uploadedBy) == userId }.count }
    }

    func setShowTrunk(_ on: Bool, service: TrunkService) async {
        guard !busy, let current = state, current.showTrunk != on else { return }
        busy = true
        error = nil
        defer { busy = false }
        // 押した向きをすぐ映す（送れなければ戻す）
        state = current.copy(showTrunk: on)
        if preview != nil { return }
        do {
            state = try await service.setShowTrunk(on).keepingPosts(from: current)
        } catch {
            state = current
            self.error = TrunkViewModel.message(error)
        }
    }
}

/// 「トランクを見せる」の行（プライバシーの札の中）
struct TrunkShowRow: View {
    @ObservedObject var model: TrunkPrivacyModel
    let service: TrunkService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            JPToggleRow(title: L("トランクを見せる", "Show my trunk"),
                        detail: L("プロフィールにトランクを置き、ほかの人がラベルの写真を開いたり、ふたを開けて中を見たりできます。",
                                  "Put your trunk on your profile so others can open label photos and look inside."),
                        isOn: Binding(get: { model.showTrunk },
                                      set: { on in Task { await model.setShowTrunk(on, service: service) } }))
                .disabled(model.busy)
                .accessibilityIdentifier("settings.showTrunk")
            if let error = model.error {
                Text(error)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
    }
}

/// ほかの人から見た姿と、オンでも出さない物（板 TrunkPrivacy の下の2つの節）
struct TrunkPrivacyPreview: View {
    @ObservedObject var model: TrunkPrivacyModel
    let profile: UserProfile?
    let userId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
            VStack(alignment: .leading, spacing: SettingsLayout.headerSpacing) {
                Text(model.showTrunk ? L("ほかの人から見たあなたのプロフィール（オン）", "Your profile as others see it (on)")
                                     : L("ほかの人から見たあなたのプロフィール（オフ）", "Your profile as others see it (off)"))
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                    .padding(.horizontal, JPSpace.xxs)
                    .accessibilityAddTraits(.isHeader)
                seen
            }
            SettingsGroup(L("オンでも、ほかの人には出さないもの", "Never shown to others, even when on")) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Self.neverShown, id: \.self) { line in
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(WebTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(L("ブロックした人・ブロックされた人には、オンでもトランクを出しません。",
                           "People you\u{2019}ve blocked, or who blocked you, never see your trunk."))
                        .font(.caption)
                        .foregroundStyle(WebTheme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
            }
        }
        .task(id: userId) {
            guard let userId else { return }
            await model.loadCounts(userId: userId, environment: environment)
        }
    }

    @EnvironmentObject private var environment: AppEnvironment

    static var neverShown: [String] {
        [L("サポーター証の番号と、始めた年月", "Your supporter number and start date"),
         L("受け取った乗車券（すれちがった相手の写真と名前）", "Tickets you received (other people\u{2019}s photos and names)"),
         L("硬貨・手持ちのラベル・部品箱・新しいラベルの印", "Coins, labels in your pocket, the parts box, new-label marks"),
         L("公開していない写真（ラベルを押しても出ません）", "Photos that aren\u{2019}t public (labels won\u{2019}t open them)")]
    }

    /// 見本の札（板: #0B0B0B の地・アイコン 40・明朝の名前・数の行・トランクの小さい札）
    private var seen: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RemoteImage(url: profile?.avatarURL(cacheBust: userId.map { ProfileImageVersions.shared.token(for: $0) }))
                    .frame(width: 40, height: 40)
                    .background(WebTheme.card)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile?.name ?? L("あなた", "You"))
                        .font(JPFont.display(17, relativeTo: .headline))
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(1)
                    if let followers = model.followers, let photos = model.photos {
                        Text(L("\(followers) フォロワー · \(photos) 写真",
                               "\(followers) \(followers == 1 ? "follower" : "followers") · \(photos) \(photos == 1 ? "photo" : "photos")"))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(WebTheme.text3)
                    }
                }
            }
            if model.showTrunk, let state = model.state {
                HStack(spacing: 10) {
                    // 板: 360×300 を 0.233 倍（84×70）
                    TrunkFigure(model: state.effectiveModel, posts: state.posts ?? 0, stuck: state.stuck,
                                ownerName: profile?.name, parts: state.equipped, width: 84)
                        .frame(width: 84, height: 70, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(TheirTrunkText.cardEyebrow)
                            .font(JPFont.eyebrow)
                            .tracking(11 * 0.12)
                            .foregroundStyle(WebTheme.accent)
                        Text(TrunkText.info(state.effectiveModel).name)
                            .font(JPFont.display(15, relativeTo: .subheadline))
                            .foregroundStyle(WebTheme.text)
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            } else {
                Text(L("トランクの札は出ません。閉じたトランクも置きません（ラベルの土地が、行った場所の記録になるため）。",
                       "No trunk appears \u{2014} not even a closed one, since label places record where you\u{2019}ve been."))
                    .font(.caption)
                    .foregroundStyle(WebTheme.text3)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 板: #0B0B0B の地・白 8% の縁・角 16（札の地は共通の部品で）
        .jpCardFace(fill: Color(trunk: TrunkRGBA(0x0B0B0B)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.showTrunk.preview")
    }
}
