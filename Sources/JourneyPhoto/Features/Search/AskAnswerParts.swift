import SwiftUI

// 「AI に頼む」の答えの形の部品（札 #675・2026-11-21 判断・Artifact「AI に頼む 独立の案」版3「答えの形 磨いた推奨」）。
// 値は模型どおり（板「journey.photo iOS」の黒塗りの真鍮。DesignSystem 01〜05、Components 01〜06）。
// - 札1枚を広く（`.bcard.wide`: 写真 150、見どころ3つ、小さな地図 76）
// - 流れ（`.tl`: 番号の丸 24 の真鍮の線、写真 44、名前 明朝 16、季節と時間帯の札、移動の目安 12）
// - 一手（`.acts2`: 線のボタン 44、角 22、14 の 600。主は真鍮の塗りに墨）。大きな字では縦に並べる
// - 次に頼めること（`.fchips`: 高さ 34 の札、折り返す。押すと欄に入るだけ）
// - 前の答えを畳んだ1行（`.mini`: 高さ 52 から、surface-2、質問 14 の 600 と中身 12 の text-3）
// - 少しずつ出す（頭の文が先、札と一手はあと・0.35 秒で現れる。動きを減らす設定では待たずに出す）

/// 札1枚を広く（「どんな所？」）。同じ札を広くし、見どころ3つを足すだけ（版3「札　1枚を広く」）
struct AskWideSpotCard: View {
    let spot: OfficialSpot
    let reason: String?
    let showsMap: Bool
    let officialSpots: [OfficialSpot]
    let photos: [Photo]
    let photosKnown: Bool

    static let photoHeight: CGFloat = 150
    static let mapHeight: CGFloat = 76

    /// 見どころ（台帳の季節と時間帯の案内の初めの1文。無ければ概要）。3つまで
    nonisolated static func highlights(_ spot: OfficialSpot, reason: String?) -> [String] {
        var out: [String] = []
        func add(_ raw: String?) {
            guard let raw else { return }
            let first = AskAnswerShape.splitSentences(raw.trimmingCharacters(in: .whitespacesAndNewlines)).first ?? ""
            let line = first.trimmingCharacters(in: CharacterSet(charactersIn: "。 "))
            guard !line.isEmpty, !out.contains(line), out.count < 3 else { return }
            out.append(line)
        }
        add(reason)
        spot.seasons.forEach { add($0.text) }
        spot.times.forEach { add($0.text) }
        if out.isEmpty { add(spot.summary) }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                NavigationLink {
                    OfficialSpotView(spot: spot, spots: officialSpots, photos: photos, photosKnown: photosKnown)
                } label: {
                    ZStack {
                        WebTheme.surface4
                        if let image = spot.photo {
                            SpotThumbImage(image: image, assumedRatioLimit: 3)
                        } else {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 22))
                                .foregroundStyle(WebTheme.accent)
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .frame(height: Self.photoHeight)
                    .clipped()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("\(spot.name)の頁を開く", "Open \(spot.name)"))
                .accessibilityIdentifier("search.ask.spotPhoto")
                VStack(alignment: .leading, spacing: 6) {
                    NavigationLink {
                        OfficialSpotView(spot: spot, spots: officialSpots, photos: photos, photosKnown: photosKnown)
                    } label: {
                        Text(spot.name)
                            .font(JPFont.display(18, relativeTo: .title3))
                            .foregroundStyle(WebTheme.text)
                            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("search.ask.spot")
                    if let region = spot.regionLabel {
                        Text(region)
                            .font(.system(size: 13))
                            .foregroundStyle(WebTheme.text2)
                            .lineLimit(1)
                    }
                    let lines = Self.highlights(spot, reason: reason)
                    if !lines.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(L("見どころ", "Highlights"))
                                .font(JPFont.caption)
                                .foregroundStyle(WebTheme.text3)
                                .padding(.bottom, 2)
                            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                                Text(line)
                                    .font(.system(size: 14))
                                    .foregroundStyle(WebTheme.text)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                                    .overlay(alignment: .bottom) {
                                        if i < lines.count - 1 {
                                            Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
                                        }
                                    }
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("search.ask.highlights")
                    }
                    HStack(alignment: .center, spacing: 8) {
                        AskSpotTags(spot: spot)
                        Spacer(minLength: 0)
                        AskWishButton(spot: spot)
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
            .background(WebTheme.card, in: RoundedRectangle(cornerRadius: AskSpotCarousel.cardRadius))
            .clipShape(RoundedRectangle(cornerRadius: AskSpotCarousel.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: AskSpotCarousel.cardRadius).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("search.ask.card")
            if showsMap, spot.coords != nil {
                AskPinsMap(spots: [spot], officialSpots: officialSpots, photos: photos, photosKnown: photosKnown,
                           current: spot.spotId)
                    .frame(height: Self.mapHeight)
                    .clipShape(RoundedRectangle(cornerRadius: AskSpotCarousel.mapRadius))
                    .overlay(RoundedRectangle(cornerRadius: AskSpotCarousel.mapRadius).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
                    .accessibilityIdentifier("search.ask.map")
            }
        }
    }
}

/// 大きな字の札（横に送らず縦に積む・版3「大きな字」）
struct AskSpotStack: View {
    let spots: [OfficialSpot]
    let reasons: [String: String]
    let officialSpots: [OfficialSpot]
    let photos: [Photo]
    let photosKnown: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(spots) { spot in
                AskSpotCard(spot: spot, reason: reasons[spot.spotId] ?? AskLibrary.guide(for: spot, query: .init()),
                            officialSpots: officialSpots, photos: photos, photosKnown: photosKnown)
            }
        }
    }
}

/// 旅行プランの流れ（番号の線に観光スポットと移動の目安・版3「流れ」）。観光スポットを押すと頁が開く
struct AskPlanTimeline: View {
    let days: [[OfficialSpot]]
    let officialSpots: [OfficialSpot]
    let photos: [Photo]
    let photosKnown: Bool

    var body: some View {
        let numbered = Self.numbers(days)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { d, spots in
                JPEyebrowLine(AskPlanFlowText.dayTitle(d, spots: spots))
                    .padding(.top, d > 0 ? 12 : 0)
                    .padding(.bottom, 4)
                ForEach(Array(spots.enumerated()), id: \.offset) { i, spot in
                    node(spot, number: numbered[d][i], first: i == 0, end: i == spots.count - 1)
                    if i < spots.count - 1, let minutes = AskPlanFlowText.moveMinutes(spot, spots[i + 1]) {
                        Text(AskPlanFlowText.moveLine(minutes))
                            .font(JPFont.caption.monospacedDigit())
                            .foregroundStyle(WebTheme.text3)
                            .padding(.leading, 36)
                            .padding(.top, 2)
                            .padding(.bottom, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(alignment: .leading) { connector }
                            .accessibilityIdentifier("search.ask.move")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.ask.plan")
    }

    /// 通しの番号（1日目から続けて数える）
    nonisolated static func numbers(_ days: [[OfficialSpot]]) -> [[Int]] {
        var n = 0
        return days.map { day in day.map { _ in n += 1; return n } }
    }

    /// 番号の丸をつなぐ線（白 14%・幅 1）
    private var connector: some View {
        Rectangle().fill(WebTheme.line).frame(width: JPStroke.hairline).padding(.leading, 11.5)
    }

    private func node(_ spot: OfficialSpot, number: Int, first: Bool, end: Bool) -> some View {
        NavigationLink {
            OfficialSpotView(spot: spot, spots: officialSpots, photos: photos, photosKnown: photosKnown)
        } label: {
            HStack(spacing: 12) {
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(WebTheme.accent)
                    .frame(width: 24, height: 24)
                    .background(WebTheme.background, in: Circle())
                    .overlay(Circle().strokeBorder(WebTheme.accent, lineWidth: 1.4))
                    .accessibilityHidden(true)
                ZStack {
                    WebTheme.surface4
                    if let image = spot.photo { SpotThumbImage(image: image, assumedRatioLimit: 2) }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(spot.name)
                        .font(JPFont.display(16, relativeTo: .body))
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    AskSpotTags(spot: spot)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 56)
            .background(alignment: .leading) {
                // 丸の上と下に線（日の初めは上なし、日の終わりは下なし）。丸は行の高さの真ん中
                VStack(spacing: 0) {
                    Rectangle().fill(first ? Color.clear : WebTheme.line).frame(width: JPStroke.hairline)
                    Color.clear.frame(width: JPStroke.hairline, height: 24)
                    Rectangle().fill(end ? Color.clear : WebTheme.line).frame(width: JPStroke.hairline)
                }
                .padding(.leading, 11.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("\(number)番目 \(spot.name)", "Stop \(number), \(spot.name)"))
        .accessibilityIdentifier("search.ask.planStop")
    }
}

/// 一手の帯（答えの下・版3「一手」）。大きな字では縦に並べる
struct AskActsRow: View {
    let acts: [AskAct]
    let vertical: Bool
    let busy: Bool
    let onTap: (AskAct) -> Void

    var body: some View {
        if vertical {
            VStack(spacing: 8) { buttons }
        } else {
            HStack(spacing: 8) { buttons }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        ForEach(acts, id: \.self) { act in
            Button { onTap(act) } label: {
                if act == .openPlan {
                    // 主ボタン（写真の無い画面: 真鍮の塗りに墨）
                    Text(act.label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WebTheme.accentText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(WebTheme.accentFill, in: Capsule())
                        .contentShape(Capsule())
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: act.systemImage)
                            .font(.system(size: 14, weight: .semibold))
                            .accessibilityHidden(true)
                        Text(act.label)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    // 線の小ボタン（板 Components 01 の `.bo`・高さ 44、白 14% の縁）
                    .jpOutlineButton(.regular, tone: .plain, fullWidth: true)
                }
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .accessibilityIdentifier("ask.act.\(act.rawValue)")
        }
    }
}

/// 次に頼めること（押すと欄に入るだけ。送るのは送信のボタン・AI は呼ばない）。折り返して並べる
struct AskNextChips: View {
    let chips: [String]
    let onFill: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 0) {
            ForEach(chips, id: \.self) { chip in
                Button { onFill(chip) } label: {
                    Text(chip)
                        .font(.footnote)
                        .foregroundStyle(WebTheme.chipText)
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 34)
                        .background(WebTheme.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
                        // 見た目 34、当たり 44
                        .frame(minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(L("欄に入れます", "Fills the field"))
                .accessibilityIdentifier("ask.next")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ask.nextChips")
    }
}

/// 前の答えを畳んだ1行（押すと開く）
struct AskFoldRow: View {
    let question: String
    let summary: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(question)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(1)
                    Text(summary)
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WebTheme.text3)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 52)
            .background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(question + L("、", ", ") + summary)
        .accessibilityHint(L("開きます", "Opens the answer"))
        .accessibilityIdentifier("ask.fold")
    }
}

/// 少しずつ出す（いま届いた答えだけ。頭の文が先に出て、札と一手は `delay` 秒あとに 0.35 秒で現れる）。
/// 動きを減らす設定と UI テストのときは待たずに出す
struct AskReveal: ViewModifier {
    let active: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(!active || shown ? 1 : 0)
            .offset(y: !active || shown ? 0 : 6)
            .task {
                guard active, !shown else { return }
                if reduceMotion || AskFixture.isOn || PerfRecorder.shared.isEnabled {
                    shown = true
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                withAnimation(.easeOut(duration: 0.35)) { shown = true }
            }
    }
}

/// 一手を押したときの行き先（仲間に送るシート、旅行プランの招待、旅行プランの画面）。**押しても AI は呼ばない**
enum AskActRequest: Identifiable, Equatable {
    /// 観光スポットの札をリンクで送る
    case share(spots: [OfficialSpot])
    /// 保存した旅行プランの招待のリンクを送る（今の旅行プランの共有の形）
    case sharePlan(planId: String, title: String)

    var id: String {
        switch self {
        case .share(let spots): return "share-" + spots.map(\.spotId).joined(separator: ",")
        case .sharePlan(let planId, _): return "plan-" + planId
        }
    }
}

/// 一手の流れ（仲間に送る、旅行プランにする、旅行プランを開く）。写真の詳細と観光スポットの頁の「送る」と同じ部品を使い回す
/// （`SendSheet` と `DMPeopleFacesRow`、`TripInviteSheet`）。**送るのはリンクだけ。画像のファイルは渡さない**
struct AskActFlow: ViewModifier {
    @Binding var request: AskActRequest?
    @Binding var openPlanId: String?

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var messages: DMInboxStore
    @EnvironmentObject private var hidden: ModerationStore

    @State private var faces: [FollowUser] = []
    @State private var facesLoaded = false
    /// 顔の一覧を読んだ人（人が替わったら捨てて読み直す・前の人のフォロー中の顔を出さない）
    @State private var facesOwner: String?
    @State private var sendingTo: String?
    @State private var inviteLink: TripInviteLink?
    @State private var inviteError: String?

    func body(content: Content) -> some View {
        content
            .sheet(item: $request) { req in
                switch req {
                case .share(let spots):
                    spotSheet(spots)
                        .task { await loadFaces() }
                case .sharePlan(let planId, let title):
                    TripInviteSheet(title: title, link: inviteLink, failed: inviteError)
                        .task { await loadInvite(planId) }
                }
            }
            .navigationDestination(isPresented: Binding(get: { openPlanId != nil }, set: { if !$0 { openPlanId = nil } })) {
                if let openPlanId { TripPlanOpenView(planId: openPlanId) }
            }
            .onChange(of: auth.userId) { _, me in
                guard Self.dropsFaces(owner: facesOwner, me: me) else { return }
                faces = []
                facesLoaded = false
                facesOwner = nil
            }
    }

    @ViewBuilder
    private func spotSheet(_ spots: [OfficialSpot]) -> some View {
        let links = AskShareLinks.links(spots, siteBase: AppConfig.siteBaseURL)
        let text = links.map { "\($0.name) \($0.url.absoluteString)" }.joined(separator: "\n")
        let actions: [SendSheetAction] = links.count == 1 ? [.copyLink(links[0].url), .otherAppsText(text)] : [.otherAppsText(text)]
        let what = Text(AskShareLinks.what(links.map(\.name)))
            .font(.system(size: 13))
            .foregroundStyle(WebTheme.text2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, JPSpace.gutter)
            .accessibilityIdentifier("ask.share.what")
        // 何を送るかの1行は題のすぐ下（模型 `.sheet2 .what`）。送る相手の段の頭に置く（シートの高さは段の有無で決まる）
        Group {
            switch SendSheetLayout.peopleRow(loaded: facesLoaded, people: faces, canSend: auth.userId != nil) {
            case .none:
                // 送る相手がいない（フォローしていない・ログインしていない）ときも、何を送るかの1行は出す（回 1658 の絵）
                SendSheet(title: L("仲間に送る", "Send to friends"), actions: actions, people: { what })
            case .placeholder:
                SendSheet(title: L("仲間に送る", "Send to friends"), actions: actions, people: {
                    VStack(spacing: 10) {
                        what
                        SendSheetFacesPlaceholder()
                    }
                })
            case .faces(let list):
                SendSheet(title: L("仲間に送る", "Send to friends"), actions: actions, people: {
                    VStack(spacing: 10) {
                        what
                        DMPeopleFacesRow(people: list,
                                         dimmed: DMSpotShare.unreachablePeers(list, inbox: messages.inbox,
                                                                              inboxLoaded: messages.phase == .loaded)) { user in
                            Task { await send(links: links.map(\.url), to: user) }
                        }
                        .disabled(sendingTo != nil)
                    }
                })
            }
        }
    }

    /// 送る相手（フォローしている人）。シートを開いてから読む（観光スポットの頁の `openSendSheet` と同じ）
    private func loadFaces() async {
        // 2026-11-21 判断（バグ調べ）: 一度読んだ顔をシートを閉じても持ち続けていたので、画面を開いたまま人が替わると
        // 前の人のフォロー中の顔が出ていた。読んだ人と今の人が違えば捨てて読み直す（安全側）
        if Self.dropsFaces(owner: facesOwner, me: auth.userId) {
            faces = []
            facesLoaded = false
            facesOwner = nil
        }
        guard !facesLoaded, let me = auth.userId else { return }
        if messages.phase != .loaded {
            Task { await messages.refresh(service: environment.dm, owner: me) }
        }
        let fetched = try? await environment.social.following(userId: me)
        guard auth.userId == me else { return }
        if let fetched { faces = DMStart.candidates(fetched.users, me: me, blocked: hidden.blockedUserIds) }
        facesLoaded = true
        facesOwner = me
    }

    /// 読んだ顔の一覧を捨てるか（読んだ人と今の人が違う。ログアウトした回も捨てる）
    static func dropsFaces(owner: String?, me: String?) -> Bool {
        owner != nil && owner != me
    }

    /// 顔を押したら、その人へ観光スポットの頁のリンクを1つずつ（`DMSpotShare`・DM では札の形で見える）
    private func send(links: [URL], to user: FollowUser) async {
        guard sendingTo == nil, !links.isEmpty else { return }
        if DMSpotShare.unreachablePeers([user], inbox: messages.inbox, inboxLoaded: messages.phase == .loaded).contains(user.id) {
            toasts.show(DMSpotShare.refusedBeforeAccept, kind: .info)
            return
        }
        sendingTo = user.id
        defer { sendingTo = nil }
        var sent = 0
        for url in links {
            do {
                try await DMSpotShare.send(service: environment.dm, me: auth.userId, peerId: user.id, pageURL: url)
                sent += 1
            } catch {
                toasts.show(DMSpotShare.failureText(error), kind: .failure)
                break
            }
        }
        if sent > 0 {
            request = nil
            toasts.show(AskShareLinks.sentLine(user.displayName, count: sent))
        }
    }

    /// 旅行プランの招待のリンク（旅行プランの詳細の「仲間に見せる」と同じ口）
    private func loadInvite(_ planId: String) async {
        inviteLink = nil
        inviteError = nil
        do {
            inviteLink = try await environment.tripShare.invite(planId: planId)
        } catch {
            inviteError = (error as? LocalizedError)?.errorDescription ?? L("招待のリンクを作れませんでした", "Couldn't make the invite link")
        }
    }
}
