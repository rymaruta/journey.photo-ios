import SwiftUI

/// 設定の「トランクを見せる」（板 TrunkPrivacy・2026-10-18）。
///
/// - 切り替えは `PUT /user/trunk/settings { showTrunk }`（オフの間は人の口が 404）。**送れたら応答の値を映し、
///   断られた・圏外なら元に戻して一行で知らせる**（嘘の状態を残さない）。送れたら入口の店（`TrunkEntryStore`）の中身も直す
/// - 自分の中身は入口の店の読みを通す（`GET /user/trunk` を1本にまとめる・読めていればそれを使う）
/// - 「わたしの乗車券もトランクに入れる」（**既定はオフ**・端末の中のすれちがいの設定 `ticketInTrunk`）。
///   揃えるのはすれちがいの設定が変わった後ろ（`PassStore.onSettingsChanged` → `TrunkTicketSync`）と、この画面を開いたとき
///   （写真が公開でない、の断りはこのときに1回だけ送り直す）。断りの訳は人ごとに覚えていて、開くたびに出す
/// - ほかの人から見た姿の見本は、人と同じ口（`GET /users/<自分>/trunk`）を描く。読めないときだけ地名なしの形。
///   見せる設定がオフの間は読まない（人には出ていない）
/// - 入っている人が替わったら、前の人の設定・見本の札を消す
/// - 画面写真の見本（`-JPPreviewTrunk`）では、サーバーに何も送らず端末の中だけで切り替える
@MainActor
final class TrunkPrivacyModel: ObservableObject {

    @Published private(set) var state: TrunkState?
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    /// ほかの人から見た自分のトランク（人の口で読んだもの）。読めなければ nil（地名なしの形で描く）
    @Published private(set) var seen: TheirTrunk?
    /// ほかの人から見た姿の見本のフォロワー数（読めなければ nil・数の行ごと出さない）。
    /// **写真の数のためだけに一覧を丸ごと取らない**（2026-10-18 見直し）ので、写真の数は出さない
    @Published private(set) var followers: Int?

    private let preview: PreviewSession.TrunkPreview?
    private let sync: TrunkTicketSync
    private let entry: TrunkEntryStore
    private var userId: String?

    init(preview: PreviewSession.TrunkPreview? = PreviewSession.trunkSample, sync: TrunkTicketSync? = nil,
         entry: TrunkEntryStore? = nil) {
        self.preview = preview
        self.sync = sync ?? .shared
        self.entry = entry ?? .shared
    }

    var showTrunk: Bool { state?.showTrunk ?? true }

    /// 節を出すか（読めて、サーバーが人のトランクに対応しているとき）
    var supported: Bool { state?.supportsSharing == true }

    /// 入っている人に合わせる。替わったら（ログアウトも）前の人の中身を消す
    func reset(for userId: String?) {
        guard self.userId != userId else { return }
        self.userId = userId
        state = nil
        error = nil
        seen = nil
        followers = nil
    }

    func load(userId: String, service: TrunkService, pass: PassSettings, available: Bool = true) async {
        reset(for: userId)
        if let preview {
            if state == nil { state = TrunkSample.state(isPro: PreviewSession.isPro, empty: preview == .empty) }
            return
        }
        // 入口の店が読めていればそれを使い、無ければ店の読みを通す（`GET /user/trunk` を1本に）
        let cached = entry.state(for: userId)
        let read: TrunkState?
        if let cached { read = cached } else { read = try? await entry.read(userId: userId, service: service) }
        guard let fresh = read, self.userId == userId else { return }
        state = fresh
        // サーバーが対応していない間は、乗車券を揃えず・人の口も読まない（節ごと出さない・`supported`）
        guard fresh.supportsSharing else { return }
        // 店の中身を入れた時刻で覚える（置けた・外せた記憶より古い中身なら、記憶を戻さない）
        sync.note(server: fresh.ticket, userId: userId, at: entry.changedAt(for: userId) ?? .distantPast)
        // 開いたとき: 写真が公開でない、で断られた1枚は1回だけ送り直す（本人があとで公開にしたかもしれない）
        await sync.sync(userId: userId, settings: pass, service: service, available: available,
                        preview: false, retryRefused: true)
        guard self.userId == userId else { return }
        if let current = state { state = current.copy(ticket: .some(sync.known(userId))) }
        // ほかの人から見た姿（自分を読むと、見せない設定でも人と同じ形が返る）。見せていない間は読まない
        guard state?.showTrunk == true else { seen = nil; return }
        let theirs = try? await service.theirs(userId)
        guard self.userId == userId else { return }
        seen = theirs ?? nil
    }

    /// 見本のフォロワー数。読めなければ出さない
    func loadCounts(userId: String, environment: AppEnvironment) async {
        let stats = try? await environment.social.followStats(userId: userId)
        guard self.userId == nil || self.userId == userId else { return }
        if let stats { followers = stats.followers }
    }

    func setShowTrunk(_ on: Bool, service: TrunkService) async {
        guard !busy, let current = state, current.supportsSharing, current.showTrunk != on else { return }
        busy = true
        error = nil
        defer { busy = false }
        // 押した向きをすぐ映す（送れなければ戻す）
        state = current.copy(showTrunk: on)
        if preview != nil { return }
        do {
            let next = try await service.setShowTrunk(on).keepingPosts(from: current)
            state = next
            if let userId { entry.apply(next, userId: userId) }
        } catch {
            state = current
            self.error = TrunkViewModel.message(error)
        }
    }
}

/// 「トランクを見せる」と「わたしの乗車券もトランクに入れる」の行（プライバシーの札の中）
struct TrunkShowRow: View {
    @ObservedObject var model: TrunkPrivacyModel
    let service: TrunkService

    @EnvironmentObject private var pass: PassStore
    @EnvironmentObject private var auth: AuthStore
    /// 断りの記憶（起動し直しても訳を出す）
    @ObservedObject private var sync = TrunkTicketSync.shared

    var body: some View {
        let refusal = sync.refusalReason(auth.userId, settings: pass.settings)
        VStack(alignment: .leading, spacing: 0) {
            JPToggleRow(title: L("トランクを見せる", "Show my trunk"),
                        detail: L("プロフィールにトランクを置き、ほかの人がラベルの写真を開いたり、ふたを開けて中を見たりできます。",
                                  "Put your trunk on your profile so others can open label photos and look inside."),
                        isOn: Binding(get: { model.showTrunk },
                                      set: { on in Task { await model.setShowTrunk(on, service: service) } }))
                .disabled(model.busy)
                .accessibilityIdentifier("settings.showTrunk")
            if let error = model.error { note(error, color: WebTheme.danger) }
            JPCardDivider()
            // 揃えるのは `PassStore.update` の後ろ（`onSettingsChanged`）。ここでは設定を変えるだけ
            JPToggleRow(title: L("わたしの乗車券もトランクに入れる", "Put my ticket in the trunk too"),
                        detail: TrunkPrivacyText.ticketDetail(pass.settings, refusal: refusal),
                        isOn: Binding(get: { pass.settings.ticketInTrunk == true },
                                      set: { on in pass.update { $0.ticketInTrunk = on ? true : nil } }))
                .disabled(!model.showTrunk)
                .accessibilityIdentifier("settings.ticketInTrunk")
        }
        // 出ている間は断りの訳をこの行に出す（知らせの帯は出さない・`TrunkTicketSync.shouldToast`）
        .onAppear { sync.setInline("settings.ticketInTrunk", shown: true) }
        .onDisappear { sync.setInline("settings.ticketInTrunk", shown: false) }
    }

    private func note(_ text: String, color: Color) -> some View {
        Text(text)
            .font(JPFont.caption)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
    }
}

/// 設定の文言（`SwiftUI` を読まない部分・テストで見る）
enum TrunkPrivacyText {
    /// 乗車券の切り替えの説明。入らない訳（すれちがいがオフ・乗車券を選んでいない）があればそれを言う
    static func ticketDetail(_ settings: PassSettings, refusal: String? = nil) -> String {
        let base = L("オンにすると、すれちがいのわたしの乗車券1枚がトランクの中に入り、ほかの人も見られます。",
                     "When on, your pass ticket goes inside your trunk where others can see it.")
        guard settings.ticketInTrunk == true else { return base }
        // 断られていれば、入っていないことと訳を言う（「入ります」のまま黙らない）
        if let refusal { return base + L("いまは入っていません: \(refusal)", " It isn\u{2019}t in the trunk now: \(refusal)") }
        if !settings.enabled {
            return base + L("いまはすれちがいがオフなので入りません。", " Pass is off, so it isn\u{2019}t in the trunk now.")
        }
        if settings.cardPhotoId == nil {
            return base + L("乗車券を選ぶと入ります。", " Choose a ticket to put it in.")
        }
        return base
    }

    /// ほかの人から見た姿の見本に添える一言
    static var seenNote: String {
        L("地名は、公開の写真と同じ撮影地のときだけ出ます。乗車券は「わたしの乗車券もトランクに入れる」をオンにしたときだけ入ります。",
          "Place names appear only when they match a public photo\u{2019}s location. Your ticket goes in only when \u{201C}Put my ticket in the trunk too\u{201D} is on.")
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
                    if let followers = model.followers {
                        Text(L("\(followers) フォロワー", followers == 1 ? "1 follower" : "\(followers) followers"))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(WebTheme.text3)
                    }
                }
            }
            if model.showTrunk, let state = model.state {
                // ほかの人から見た形: 人と同じ口で読めたらそれを、読めなければ地名なしの形で描く
                let figure = TheirTrunkText.seenFigure(seen: model.seen, own: state)
                HStack(spacing: 10) {
                    // 板: 360×300 を 0.233 倍（84×70）
                    TrunkFigure(model: figure.model, posts: figure.posts, stuck: figure.stuck,
                                ownerName: profile?.name, parts: figure.parts, width: 84)
                        .frame(width: 84, height: 70, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(TheirTrunkText.cardEyebrow)
                            .font(JPFont.eyebrow)
                            .tracking(11 * 0.12)
                            .foregroundStyle(WebTheme.accent)
                        Text(TrunkText.info(figure.model).name)
                            .font(JPFont.display(15, relativeTo: .subheadline))
                            .foregroundStyle(WebTheme.text)
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                Text(TrunkPrivacyText.seenNote)
                    .font(.caption)
                    .foregroundStyle(WebTheme.text3)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
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
