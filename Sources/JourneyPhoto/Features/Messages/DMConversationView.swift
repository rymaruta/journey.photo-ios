import SwiftUI
import UIKit

/// 1対1の会話（画面案「会話」「状態（会話）」・札 #505・2026-11-10）。
///
/// - 自分の吹き出しは白（広い面は白）、相手は surface-8。時刻は 12pt。既読・送信済みの表示は出さない
/// - 送る1通には鍵（`clientId`）を1回だけ付け、押し直しも同じ鍵で送る（サーバーが二重に入れない・`DMThreadLog`）
/// - 承認前（自分が始めた・相手がまだ話していない）は残りの通数を欄の上に。3通使い切ったら欄を止める
/// - URL を断られたら入力を残し、欄の上に理由（アイコン＋文・縁も赤。色だけにしない）
/// - リクエストとして届いた会話は、上に案内の帯（承認／削除）。返信した時点で承認になる
/// - 相手が退会: 過去のやりとりは読める。送信欄の代わりに理由と「会話を削除」
/// - ブロック中（した側）は「ブロックを解除」、された側・消えた会話は「この会話は表示できません」
/// - 圏外: 上に帯。送信は押せない。送れなかった1通は破線の縁＋「もう一度送る」
/// - 開いている間は `?since=` で読み直す（`DMRules.pollInterval`・前面にいる間だけ）
/// - **まだ会話が無い相手**（プロフィールの「メッセージ」・受信箱の「新しいメッセージ」から・2026-11-10 判断）は、
///   `GET` の 404 `notFound` を「これから始まる」と読み、空の会話の画面から1通目を送れる（サーバーは送れば会話を作る）。
///   欄の上には送る前に決まり（文字3通まで・リンク不可）を出す（`DMText.firstMessageNote`）
///
/// **2026-11-11 作り直し（札 #541・owner 承認の案C「黒塗りに真鍮の縁」）**:
/// - 自分の吹き出しは accent-soft の塗り＋真鍮 1pt の縁＋白の字（`DMBubbleColors`）。続けて送った吹き出しは付け根の側の角を
///   6 に詰めて1かたまりに（`DMText.joinsPrevious`）。最大幅は会話の幅の 78%（固定の 304 をやめた）
/// - 本文の URL は押せるリンク（真鍮の下線・`DMLinks`・開く先は Safari）。承認前は今までどおりサーバーが URL を断る
/// - 送った写真の札（`DMPhotoQuote`・幅 220 の 4:5・押すと写真の詳細）。ストーリーへの返信の写真は 104×138
/// - 送るボタンは真鍮の塗りに墨（板「写真の無い画面の主ボタン＝送信」・今までは白）。入力欄の縁は outline #666666
///   （白 20% は黒地 1.66:1 で部品の縁の 3:1 に届かなかった）。リクエストの帯の「承認」も真鍮の塗り・「削除」の縁は outline
/// - 日付の区切りは両側に細い線（白 8%）・見出しの顔 32（未見のストーリーは真鍮の輪）・名前 17
struct DMConversationView: View {

    let conversationId: String
    /// 会話を始める相手（プロフィール・新しいメッセージから）。**これがあるときだけ** 404 を空の会話として開く——
    /// 受信箱から開いた会話の 404 は今までどおり「表示できません」（消した・ブロックの関係）
    var startingWith: DMPeerSeed? = nil

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var hidden: ModerationStore
    @EnvironmentObject private var connectivity: Connectivity
    @EnvironmentObject private var store: DMInboxStore
    /// 読んだ会話の通知を通知センターから消す（2026-11-10 札 #505・`PushCenter.removeDelivered`）
    @EnvironmentObject private var push: PushCenter
    /// 前面で届いたこの会話の通知（帯を出さずに読み直す・`NotificationRouter.noteDMArrival`）
    @ObservedObject private var router = NotificationRouter.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    enum Phase: Equatable {
        case loading
        case loaded
        case failed
        /// 404（消した・ブロックされた・ブロックした）。ブロックした側かは `hidden` で見分ける
        case unavailable
    }

    @State private var phase: Phase = .loading
    @State private var meta: DMConversation?
    @State private var log = DMThreadLog()
    @State private var draft = ""
    /// 欄の上の断りの文（URL・上限など）。次に打ち始めたら消す
    @State private var fieldError: String?
    /// 断られて欄に戻した本文。**戻したこと自体は「打ち始めた」に数えない**（2026-11-10 run 937 の数:
    /// 送った 1・断られた 1・断りの文が消えた 1——欄に戻した変化で、出したばかりの断りの文を消していた）
    @State private var restoredDraft: String?
    @State private var working = false
    @State private var showDeleteConfirm = false
    @State private var showBlockConfirm = false
    @State private var showReport = false
    @State private var showProfile = false
    @State private var actionError: String?
    /// 「タップでストーリーを見る」で開いたストーリー（全画面）
    @State private var openedStory: Story?
    @State private var openingStory = false
    /// 写真の札を押して開いた写真（写真の詳細を積む）。一覧に無ければ開けない（単体の口は無い）
    @State private var openedPhoto: Photo?
    @State private var openedPhotoIsPublic = true
    @State private var openingPhoto = false
    /// 会話の幅（吹き出しの最大幅＝この 78%）
    @State private var threadWidth: CGFloat = 0
    /// 引用札の見せ方に使う時刻。**開いている間に期限が来たら進めて描き直す**（「タップで見る」を残さない）
    @State private var cardClock = Date()
    @FocusState private var fieldFocused: Bool
    /// まだ会話が無い（`startingWith` で開き、`GET` が 404 `notFound` だった）。1通目が通って会話を読めたら false
    @State private var isNew = false
    /// まだ会話を読めていない間に送れた通数（承認前の残りを、読めるまで手元で数える）
    @State private var newSent = 0
    /// UI テストのときだけ（`-JPPreviewDM`）: 送った・断られた・断りの文が消えた回数を見えない要素に出す（`dm.probe`）
    @State private var probe = (sends: 0, refusals: 0, errorCleared: 0)
    /// この会話から旅行プランを作る（2026-11-12・資料 2a の段①と段②・`DMTripViews.swift`）
    @StateObject private var trip = DMTripModel()
    @StateObject private var tripPlans = TripPlansModel()
    @State private var showTrip = false
    /// 文から撮影スポットを拾えなかった吹き出し（候補のシートを開く）
    @State private var tripCandidates: DMTripCandidateTarget?
    /// 候補を選んだ: シートが閉じ切ってから下書きを開く
    @State private var openTripAfterSheet = false
    /// 作る流れで保存したプラン。**板が閉じ切ってから積む**（`SavedSpotsMapView` と同じ）
    @State private var pendingTripId: String?
    @State private var createdTripId: String?

    /// 受信箱の行（読み込む前の見出しの名前に使う）
    private var seed: DMThread? { store.inbox.items.first { $0.id == conversationId } }
    private var peerId: String? {
        meta?.peerId ?? seed?.peerId ?? startingWith?.id
            ?? auth.userId.flatMap { DMRules.peer(of: conversationId, me: $0) }
    }
    private var isDeletedPeer: Bool { meta?.deleted == true || seed?.isDeleted == true }
    private var peerName: String {
        DMText.name(meta?.name ?? seed?.name ?? startingWith?.name, deleted: isDeletedPeer)
    }
    private var username: String? {
        isDeletedPeer ? nil : (meta?.username ?? seed?.username ?? startingWith?.username)
    }
    /// 相手からのリクエスト（自分が受け取った・まだ承認していない）
    private var isIncomingRequest: Bool { (meta?.state ?? seed?.state) == .request }
    /// 旅行プランの入口（帯・長押しの「旅行プランに入れる」・索引の読み込み）を出すか。
    /// **承認前のリクエストには出さない**（2026-11-12 確かめ役の指摘・まだ話していない相手の写真や文を集めない）
    private var tripOffered: Bool { !isIncomingRequest }
    /// 承認前の残り（自分が始めて、相手がまだ話していない間だけ）。まだ会話が無い間は手元で数える
    private var remaining: Int? {
        isNew ? max(0, DMRules.requestLimit - newSent) : meta?.requestRemaining
    }
    private var canSend: Bool {
        phase == .loaded && !isDeletedPeer && (meta?.canSend ?? true) && remaining != 0
    }
    /// 写真の札から写真の詳細を積んでいるか（戻ったら開いた写真を外す）
    private var photoIsOpen: Binding<Bool> {
        Binding(get: { openedPhoto != nil }, set: { open in
            if !open { openedPhoto = nil }
        })
    }
    private var iBlockedPeer: Bool { peerId.map { hidden.blockedUserIds.contains($0) } ?? false }

    var body: some View {
        VStack(spacing: 0) {
            if connectivity.isOffline && phase != .unavailable {
                DMOfflineStrip(text: L("圏外です。つながると送れます", "You're offline. You can send once you reconnect."))
                    .padding(.top, JPSpace.xs)
            }
            switch phase {
            case .loading:
                ScrollView { JPLoadingState(kind: .bubbles).padding(.horizontal, JPSpace.gutter) }
                    .frame(maxHeight: .infinity)
                composer.disabled(true)
            case .failed:
                ScrollView {
                    ErrorBanner(title: L("会話を読み込めませんでした", "Couldn't load the conversation"),
                                message: DMText.loadFailedMessage) {
                        Task { await load() }
                    }
                    .padding(.top, JPSpace.emptyTop)
                }
            case .unavailable:
                unavailableState
            case .loaded:
                if isIncomingRequest { requestBand }
                thread
                // 場所が1つでも出た会話にだけ（リクエストの帯と重ねない・送れない会話にも出す——読めた写真から作れる）
                if tripOffered, !tripFound.isEmpty {
                    DMTripBand(count: tripFound.count) { showTrip = true }
                }
                footer
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if PreviewSession.dm {
                Text(".")
                    .font(.caption2)
                    .foregroundStyle(Color.clear)
                    .accessibilityIdentifier("dm.probe")
                    .accessibilityValue("sends=\(probe.sends) refusals=\(probe.refusals) errorCleared=\(probe.errorCleared)")
            }
        }
        .webScreen()
        .navigationTitle(peerName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { header }
            ToolbarItem(placement: .topBarTrailing) {
                // まだ会話が無い間は出さない（通報・削除する会話が無い）
                if phase == .loaded && !isNew { moreMenu }
            }
        }
        .navigationDestination(isPresented: $showProfile) {
            if let peerId { UserProfileView(userId: peerId, fromConversation: true) }
        }
        .navigationDestination(isPresented: photoIsOpen) {
            if let openedPhoto { PhotoDetailView(photo: openedPhoto, fromPublicFeed: openedPhotoIsPublic) }
        }
        .navigationDestination(item: $createdTripId) { planId in
            TripPlanDetailView(planId: planId, model: tripPlans)
        }
        .fullScreenCover(isPresented: $showTrip, onDismiss: {
            guard let planId = pendingTripId else { return }
            pendingTripId = nil
            createdTripId = planId
        }) {
            DMTripCreateView(peerName: peerName, found: tripFound, plans: tripPlans) { planId in
                pendingTripId = planId
                showTrip = false
            }
        }
        .sheet(item: $tripCandidates, onDismiss: {
            if openTripAfterSheet {
                openTripAfterSheet = false
                showTrip = true
            }
        }) { target in
            DMTripCandidatesSheet(text: target.text, trip: trip, near: tripFound.compactMap(\.place.coords).first) { spot in
                trip.add([spot], source: .picked)
                openTripAfterSheet = true
                tripCandidates = nil
            }
        }
        // 写真の撮影地を撮影スポットに当てる索引と、座標を引く公開の写真（写真のある会話だけ・控えを使う口）
        // 読めなかった回は、電波が戻ったら読み直す（id に圏外かどうかを入れる）
        .task(id: "\(tripOffered && log.messages.contains(where: \.hasPhoto))#\(connectivity.isOffline)") {
            if tripOffered, log.messages.contains(where: \.hasPhoto) { await trip.load(environment: environment) }
        }
        .task(id: conversationId) { await load() }
        // 開いている間だけ読み直す（前面・電波あり）
        .task(id: "\(conversationId)#\(scenePhase == .active)") { await poll() }
        // 引用札の期限が来たら描き直す（`since` の読み直しでは古い通の札は届き直さない・2026-11-10 再確認の指摘）
        .task(id: DMStoryCardState.nextExpiry(log.messages, after: cardClock)) {
            guard let at = DMStoryCardState.nextExpiry(log.messages, after: cardClock) else { return }
            try? await Task.sleep(for: .seconds(max(0, at.timeIntervalSinceNow) + 1))
            if !Task.isCancelled { cardClock = Date() }
        }
        // 開いている会話を知らせる（この会話の通知は前面で帯を出さない）
        .onAppear { router.conversationOpened(conversationId) }
        .onDisappear { router.conversationClosed(conversationId) }
        // この会話の通知が前面で届いた: 10秒を待たずに読み直す
        .onChange(of: router.dmArrival) { _, arrival in
            guard arrival.conversationId == conversationId, phase == .loaded else { return }
            Task { await refreshSince() }
        }
        .onChange(of: connectivity.isOffline) { _, offline in
            if !offline, phase == .failed { Task { await load() } }
        }
        .onChange(of: draft) { old, new in
            let kept = PostLimits.limited(old: old, new: new, limit: DMRules.textMax)
            if kept != new { draft = kept }
            if new == restoredDraft { return }
            restoredDraft = nil
            if fieldError != nil, !new.isEmpty, new != old {
                fieldError = nil
                probe.errorCleared += 1
            }
        }
        .alert(L("この会話を削除しますか？", "Delete this conversation?"), isPresented: $showDeleteConfirm) {
            Button(L("会話を削除", "Delete conversation"), role: .destructive) { Task { await removeConversation() } }
            Button(Labels.Common.cancel, role: .cancel) {}
        } message: {
            Text(L("あなたの画面から会話が消えます。相手の画面には残ります。",
                   "The conversation is removed from your screen. It stays on theirs."))
        }
        .alert(DMBlockText.title(peerName), isPresented: $showBlockConfirm) {
            Button(L("ブロック", "Block"), role: .destructive) { Task { await block() } }
            Button(Labels.Common.cancel, role: .cancel) {}
        } message: {
            Text(DMBlockText.message)
        }
        .fullScreenCover(item: $openedStory) { story in
            StoryViewerView(stories: [story], startIndex: 0, viewerId: auth.userId)
        }
        .sheet(isPresented: $showReport, onDismiss: afterReport) {
            ReportSheet(photoId: "", ownerId: peerId,
                        conversation: ReportSheet.Conversation(id: conversationId, name: peerName))
        }
    }

    // MARK: - 見出し

    /// 顔 32（未見のストーリーは真鍮の輪・押すとストーリー）・名前 17・@ユーザー名 12（2026-11-11 案C）。
    /// 名前を押すと相手のプロフィール（退会した人は行かない）。顔と名前は別のボタン（ボタンの中にボタンを入れない）
    private var header: some View {
        HStack(spacing: 6) {
            if let peerId {
                DMStoryFace(userId: peerId, deleted: isDeletedPeer, name: peerName, size: DMLook.headerAvatar) {
                    if !isDeletedPeer { showProfile = true }
                }
            }
            headerName
        }
    }

    private var headerName: some View {
        Button {
            if !isDeletedPeer, peerId != nil { showProfile = true }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(peerName)
                        .font(JPFont.headline)
                        .foregroundStyle(isDeletedPeer ? WebTheme.text3 : WebTheme.text)
                        .lineLimit(1)
                    if let username {
                        Text("@\(username)")
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.text3)
                            .lineLimit(1)
                    }
                }
            }
            .frame(minHeight: WebTheme.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDeletedPeer)
        .accessibilityLabel(isDeletedPeer ? peerName : L("\(peerName) のプロフィール", "\(peerName)'s profile"))
        .accessibilityIdentifier("dm.header")
    }

    /// 「…」: 相手のプロフィール／通報／ブロック／会話を削除（破壊的な2つは系統の赤）
    private var moreMenu: some View {
        Menu {
            if !isDeletedPeer {
                Button { showProfile = true } label: { Label(L("相手のプロフィール", "View profile"), systemImage: "person") }
            }
            Button { showReport = true } label: { Label(L("通報", "Report"), systemImage: "exclamationmark.bubble") }
            if !isDeletedPeer {
                Button(role: .destructive) { showBlockConfirm = true } label: {
                    Label(L("ブロック", "Block"), systemImage: "hand.raised")
                }
            }
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label(L("会話を削除", "Delete conversation"), systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis").webToolbarIcon().appHeaderHitArea()
        }
        .accessibilityLabel(L("その他の操作", "More"))
        .accessibilityIdentifier("dm.more")
    }

    // MARK: - 中身

    /// リクエストの会話の案内の帯（画面案: 真鍮 8% の地・承認／削除）
    private var requestBand: some View {
        VStack(alignment: .leading, spacing: JPSpace.xxs) {
            Text(L("\(peerName) さんからのリクエストです。返信すると承認したことになり、受信箱に移ります。",
                   "\(peerName) sent you a request. Reply to accept it and move it to your inbox."))
                .font(JPFont.footnote)
                .foregroundStyle(WebTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: JPSpace.xs) {
                Button { Task { await accept() } } label: {
                    // 写真の無い画面の主ボタン＝真鍮の塗りに墨（7.11:1・2026-11-11 案C。今までは白）
                    Text(L("承認", "Accept"))
                        .font(JPFont.footnote.weight(.semibold))
                        .foregroundStyle(WebTheme.accentText)
                        .padding(.horizontal, 18)
                        .frame(height: JPHeight.inlineButton)
                        .background(WebTheme.accentFill, in: Capsule())
                        .frame(minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dm.band.accept")
                Button { Task { await declineRequest() } } label: {
                    // 縁は outline（帯の地に 3:1 以上。白 28% は 2.45:1 で部品の縁に届かなかった）
                    Text(Labels.Common.delete)
                        .font(JPFont.footnote.weight(.semibold))
                        .foregroundStyle(WebTheme.foreground)
                        .padding(.horizontal, 18)
                        .frame(height: JPHeight.inlineButton)
                        .overlay(Capsule().strokeBorder(WebTheme.outline, lineWidth: JPStroke.hairline))
                        .frame(minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dm.band.decline")
            }
            .disabled(working || connectivity.isOffline)
        }
        .padding(.horizontal, 14)
        .padding(.top, JPSpace.s)
        .padding(.bottom, JPSpace.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WebTheme.accent.opacity(DMLook.requestBandAccentOpacity), in: RoundedRectangle(cornerRadius: JPRadius.m))
        .padding(.horizontal, JPSpace.gutter)
        .padding(.bottom, JPSpace.xxs)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dm.requestBand")
    }

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if isNew && log.messages.isEmpty && log.outgoing.isEmpty { newIntro }
                    let messages = log.messages
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        let previous = index > 0 ? messages[index - 1] : nil
                        let next = index + 1 < messages.count ? messages[index + 1] : nil
                        if DMText.startsDay(current: message, previous: previous),
                           let date = NotificationGroups.parse(message.t) {
                            DMDayDivider(text: DMText.dayLabel(date))
                        }
                        if message.isStoryReply { unsendMenu(storyCard(for: message), for: message) }
                        if message.hasPhoto { photoCard(for: message) }
                        // 撮影スポットの頁のリンクは札にする（1.1.83・資料⑤・`DMSpotShare`）。吹き出しには残りの文だけ
                        let spotSlug = message.hasPhoto ? nil
                            : DMSpotShare.slug(in: message.text, siteBase: AppConfig.siteBaseURL)
                        if let spotSlug {
                            // 札が作れなかったときは拾ったリンクだけを出す（文全体は下の吹き出しに残る）
                            DMSpotCard(slug: spotSlug, mine: message.mine,
                                       fallback: DMSpotShare.link(in: message.text, siteBase: AppConfig.siteBaseURL)
                                           ?? message.text)
                        }
                        let time = DMText.timeLabel(current: message, next: next)
                        if let text = spotSlug == nil ? message.bubbleText
                            : DMSpotShare.remainder(message.text, siteBase: AppConfig.siteBaseURL) {
                            DMBubble(text: text, mine: message.mine, time: time,
                                     joinsPrevious: DMText.joinsPrevious(current: message, previous: previous),
                                     maxWidth: DMLook.bubbleMaxWidth(container: threadWidth))
                                .contextMenu { bubbleMenu(message, text: text) }
                                .id(message.id)
                        } else if let time {
                            // 写真だけの通は吹き出しを出さず、時刻だけ写真の下に
                            DMTimeLabel(text: time, mine: message.mine).id(message.id)
                        } else {
                            Color.clear.frame(height: 0).id(message.id)
                        }
                    }
                    ForEach(log.outgoing) { item in
                        DMBubble(text: item.text, mine: true, time: nil,
                                 maxWidth: DMLook.bubbleMaxWidth(container: threadWidth), outgoing: item.phase,
                                 onRetry: { Task { await retry(item.clientId) } })
                            .id(item.clientId)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomId)
                }
                .padding(.horizontal, JPSpace.gutter)
                .padding(.top, JPSpace.xxs)
                .padding(.bottom, JPSpace.s)
            }
            .scrollDismissesKeyboard(.interactively)
            // 吹き出しの最大幅（会話の幅の 78%）のために幅を読む
            .onGeometryChange(for: CGFloat.self) { proxy in proxy.size.width } action: { width in
                threadWidth = width
            }
            .onAppear { proxy.scrollTo(Self.bottomId, anchor: .bottom) }
            .onChange(of: log.messages.count + log.outgoing.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomId, anchor: .bottom) }
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityIdentifier("dm.conversation")
    }

    private static let bottomId = "dm.bottom"

    // MARK: - 旅行プラン（2026-11-12・資料 2a）

    /// 下書きに出す場所（写真が先・吹き出しから入れた場所が後）
    private var tripFound: [DMTripPlaces.Found] {
        trip.places(log.messages, blocked: hidden.blockedUserIds)
    }

    /// 吹き出しの長押し（段②）: 「旅行プランに入れる」と「コピー」。自分の通には「送信を取り消す」（2026-11-12）
    @ViewBuilder
    private func bubbleMenu(_ message: DMMessage, text: String) -> some View {
        if tripOffered {
            Button { Task { await addToTrip(text) } } label: {
                Label(L("旅行プランに入れる", "Add to a trip"), systemImage: "plus")
            }
        }
        Button { UIPasteboard.general.string = text } label: {
            Label(L("コピー", "Copy"), systemImage: "doc.on.doc")
        }
        if message.mine { unsendButton(message) }
    }

    /// 「送信を取り消す」（2026-11-12・owner の要望）。**確かめのダイアログは出さない**——押したらすぐ消え、
    /// 文字だけの通は文を入力欄に戻す（`DMUnsend`）。メニューの末尾に置く（よく使うコピーを先に）
    private func unsendButton(_ message: DMMessage) -> some View {
        Button { Task { await unsend(message) } } label: {
            Label(L("送信を取り消す", "Unsend"), systemImage: "arrow.uturn.backward")
        }
        .accessibilityIdentifier("dm.unsend")
    }

    /// 写真・ストーリーへの返信の札の長押し。**自分の通にだけ**メニューを付ける（相手の札は今までどおり押すだけ）
    @ViewBuilder
    private func unsendMenu<Content: View>(_ content: Content, for message: DMMessage) -> some View {
        if message.mine {
            content.contextMenu { unsendButton(message) }
        } else {
            content
        }
    }

    /// 文の中の撮影スポットを索引で拾って下書きに入れ、下書きを開く。拾えなければ候補のシート
    private func addToTrip(_ text: String) async {
        guard tripOffered else { return }
        await trip.load(environment: environment)
        let spots = trip.spots(in: text)
        if spots.isEmpty {
            tripCandidates = DMTripCandidateTarget(text: text)
        } else {
            trip.add(spots, source: .text)
            showTrip = true
        }
    }

    /// まだ会話が無い相手の、空の会話の上（2026-11-10 判断・板の人の行と同じ並び: 顔 64・名前 17・@ユーザー名 12）。
    /// 写真の無い画面なので、字は白と text-3 だけ（真鍮の合図は置かない）
    private var newIntro: some View {
        VStack(spacing: JPSpace.xs) {
            if let peerId {
                DMAvatar(userId: peerId, size: DMLook.newIntroAvatar)
            }
            VStack(spacing: 2) {
                Text(peerName)
                    .font(JPFont.headline)
                    .foregroundStyle(WebTheme.text)
                    .multilineTextAlignment(.center)
                if let username {
                    Text("@\(username)")
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                }
            }
            Text(L("まだメッセージはありません", "No messages yet"))
                .font(JPFont.footnote)
                .foregroundStyle(WebTheme.text2)
                .padding(.top, JPSpace.xxs)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, JPSpace.section)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dm.newIntro")
    }

    /// ストーリーへの返信の引用札（画面案「会話」: 止め絵＋「[名前] さんのストーリー」＋「タップでストーリーを見る」、
    /// 終わっていれば破線の枠＋「ストーリーは終了しました」）。札の中身が分からない通（古い通・口が古い）は
    /// 枠だけ出し、「終了」とは言い切らない（`DMStoryCardState`）
    @ViewBuilder
    private func storyCard(for message: DMMessage) -> some View {
        let state = DMStoryCardState.of(message, now: cardClock)
        if let storyId = state.liveStoryId {
            Button { Task { await openStory(storyId) } } label: { storyCardFace(message, state: state) }
                .buttonStyle(.plain)
                .disabled(openingStory)
                .accessibilityHint(L("ストーリーを開きます", "Opens the story"))
                .accessibilityIdentifier("dm.storyCard.live")
        } else {
            storyCardFace(message, state: state)
        }
    }

    /// 2026-11-11 案C: 眉ラベル（黒地の上なので真鍮）の下に、写真を 104×138（角 14）で大きく。写真の上の名前は白。
    /// 終わった・分からないは破線の枠（終わったときだけ「ストーリーは終了しました」）
    private func storyCardFace(_ message: DMMessage, state: DMStoryCardState) -> some View {
        let owner = message.mine ? peerName : L("あなた", "You")
        return VStack(alignment: message.mine ? .trailing : .leading, spacing: 6) {
            Text(L("ストーリーへの返信", "STORY REPLY"))
                .jpEyebrow()
                .foregroundStyle(WebTheme.accent)
            storyThumb(state, owner: owner)
                .frame(width: DMLook.storyThumbWidth,
                       height: state.liveStoryId != nil ? DMLook.storyThumbHeight : 72)
                .clipShape(RoundedRectangle(cornerRadius: JPRadius.m))
                .contentShape(RoundedRectangle(cornerRadius: JPRadius.m))
        }
        .frame(maxWidth: .infinity, alignment: message.mine ? .trailing : .leading)
        .padding(.top, JPSpace.xxs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DMText.storyCardSpoken(owner: owner, mine: message.mine, state: state))
    }

    /// 札の絵（見られる写真は止め絵＋下に持ち主の名前（白）・動画は再生の印・終わった／分からないは破線の枠）
    @ViewBuilder
    private func storyThumb(_ state: DMStoryCardState, owner: String) -> some View {
        switch state {
        case .live(_, let image, _):
            ZStack(alignment: .bottomLeading) {
                if let image {
                    RemoteImage(url: image)
                } else {
                    WebTheme.surface4
                    Image(systemName: "play.fill")
                        .font(JPFont.headline)
                        .foregroundStyle(WebTheme.foreground)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                Text(owner)
                    .font(JPFont.caption.weight(.semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(1)
                    .padding(JPSpace.xs)
            }
        case .ended:
            RoundedRectangle(cornerRadius: JPRadius.m)
                .strokeBorder(WebTheme.outline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .overlay(
                    Text(L("ストーリーは終了しました", "This story has ended"))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                        .multilineTextAlignment(.center)
                        .padding(6)
                        .accessibilityIdentifier("dm.storyCard.ended")
                )
        case .unknown, .none:
            RoundedRectangle(cornerRadius: JPRadius.m)
                .strokeBorder(WebTheme.outline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .overlay(Image(systemName: "circle.dashed").font(JPFont.footnote).foregroundStyle(WebTheme.text3))
        }
    }

    // MARK: - 送った写真（2026-11-11・札 #541）

    /// 送った写真の札。見られる写真は幅 220・4:5・角 14（縁も真鍮も載せない・写真が主役）で、下の黒地に題と撮影地。
    /// 押すと写真の詳細。見られない（消した・非公開・範囲の外・ブロック）は破線の枠と「写真は表示できません」。
    /// 中身が分からない（古い通・送った直後）は言い切らず「写真を送りました／届きました」（`DMPhotoCardState`）
    @ViewBuilder
    private func photoCard(for message: DMMessage) -> some View {
        let mine = message.mine
        VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
            switch DMPhotoCardState.of(message, blocked: hidden.blockedUserIds) {
            case .live(let quote):
                livePhoto(quote, mine: mine)
            case .gone:
                photoPlaceholder(L("写真は表示できません", "This photo isn't available"), identifier: "dm.photoCard.gone")
            case .unknown, .none:
                photoPlaceholder(DMText.photoOnlyText(mine: mine), identifier: "dm.photoCard.unknown")
            }
        }
        .modifier(DMUnsendMenu(enabled: mine) { unsendButton(message) })
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .padding(.top, JPSpace.xxs)
    }

    @ViewBuilder
    private func livePhoto(_ quote: DMPhotoQuote, mine: Bool) -> some View {
        Button { Task { await openPhoto(quote) } } label: {
            RemoteImage(url: quote.imageURL)
                .frame(width: DMLook.photoWidth, height: DMLook.photoHeight)
                .clipShape(RoundedRectangle(cornerRadius: JPRadius.m))
                .contentShape(RoundedRectangle(cornerRadius: JPRadius.m))
        }
        .buttonStyle(.plain)
        .disabled(openingPhoto)
        .accessibilityLabel(DMText.photoSpoken(title: quote.title, location: quote.location, mine: mine))
        .accessibilityHint(L("写真を開きます", "Opens the photo"))
        .accessibilityIdentifier("dm.photoCard.live")
        if quote.title != nil || quote.location != nil {
            VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                if let title = quote.title {
                    Text(title)
                        .font(JPFont.footnote.weight(.semibold))
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(2)
                }
                if let location = quote.location {
                    Text(L("撮影地 \(location)", "Taken in \(location)"))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                        .lineLimit(1)
                }
            }
            .multilineTextAlignment(mine ? .trailing : .leading)
            .frame(maxWidth: DMLook.photoWidth, alignment: mine ? .trailing : .leading)
            .accessibilityHidden(true)
        }
    }

    /// 写真の代わりの破線の枠（見られない・分からない）
    private func photoPlaceholder(_ text: String, identifier: String) -> some View {
        RoundedRectangle(cornerRadius: JPRadius.m)
            .strokeBorder(WebTheme.outline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .frame(width: DMLook.photoWidth, height: 88)
            .overlay(
                Label(text, systemImage: "photo")
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(identifier)
    }

    /// 写真の札を押した: 公開の一覧（`fetchPhotos`・控えを使う）→ 公開範囲を絞った写真のうち自分に見えるぶん（`/feed/restricted`）→
    /// 自分の写真（自分が送った下書き以外の自分の写真）の順に探す。**単体で写真を読む口は無い**ので、どれにも無ければ開けないと言う
    private func openPhoto(_ quote: DMPhotoQuote) async {
        guard !openingPhoto else { return }
        openingPhoto = true
        defer { openingPhoto = false }
        let feed = (try? await environment.gallery.fetchPhotos()) ?? []
        if let found = feed.first(where: { $0.id == quote.id }) {
            openedPhotoIsPublic = true
            openedPhoto = found
            return
        }
        // 公開範囲を絞った写真（フォロワー・親しい友達）は公開の一覧に無い。自分に見えるぶんを読む（2026-11-11 確かめ役の指摘）
        let restricted = (try? await environment.photos.restrictedFeed()) ?? []
        if let found = restricted.first(where: { $0.id == quote.id }) {
            openedPhotoIsPublic = false
            openedPhoto = found
            return
        }
        let mine = auth.userId != nil && quote.ownerId == auth.userId
        let own: Photo? = mine ? (try? await environment.photos.myPhoto(id: quote.id)) ?? nil : nil
        if let own {
            openedPhotoIsPublic = false
            openedPhoto = own
            return
        }
        actionError = L("この写真はここから開けません", "This photo can't be opened from here")
    }

    /// 「タップでストーリーを見る」: ストーリーの一覧（`GET /stories`）からその1本を探して開く（単体の口は無い）。
    /// 一覧に無ければ（見られなくなった・終わった）札を「終了」に倒す
    private func openStory(_ storyId: String) async {
        guard !openingStory else { return }
        openingStory = true
        defer { openingStory = false }
        guard let stories = try? await environment.stories.list() else {
            actionError = L("ストーリーを開けませんでした", "Couldn't open the story")
            return
        }
        if let found = stories.first(where: { $0.id == storyId }) {
            openedStory = found
        } else {
            log.markStoryEnded(storyId)
        }
    }

    // MARK: - 下（送信欄・退会の理由）

    @ViewBuilder
    private var footer: some View {
        if isDeletedPeer {
            VStack(spacing: JPSpace.xs) {
                Text(L("このユーザーは退会したため、メッセージを送れません。",
                       "This user has deleted their account, so you can't send messages."))
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button { showDeleteConfirm = true } label: {
                    Text(L("会話を削除", "Delete conversation")).jpPillButton(.outline)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dm.deleted.remove")
            }
            .jpBottomBar()
        } else {
            composer
        }
    }

    /// 送信欄（画面案: 欄 44・送る丸 44。承認前の残り・断りの文は欄の上）
    private var composer: some View {
        VStack(alignment: .leading, spacing: JPSpace.xs) {
            if let actionError {
                noteRow(actionError, error: true)
            }
            if let fieldError {
                noteRow(fieldError, error: true)
                    .accessibilityIdentifier("dm.fieldError")
            } else if isNew && newSent == 0 {
                // 1通目を送る前に決まりを言う（通数とリンク・2026-11-10 判断）
                noteRow(DMText.firstMessageNote(name: peerName), error: false)
                    .accessibilityIdentifier("dm.firstNote")
            } else if let note = DMText.requestNote(name: peerName, remaining: remaining) {
                noteRow(note, error: false)
                    .accessibilityIdentifier("dm.requestNote")
            } else if isIncomingRequest {
                noteRow(L("返信すると承認されます", "Replying accepts the request"), error: false)
            }
            HStack(alignment: .bottom, spacing: 6) {
                // 欄は surface-2 に outline の縁（黒地 3.66:1・部品の縁 3:1 以上）。断られたら縁も赤（色だけにしない: 上に印と文）
                TextField(L("メッセージ", "Message"), text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.text)
                    .focused($fieldFocused)
                    .padding(.horizontal, JPSpace.m)
                    .padding(.vertical, 11)
                    .frame(minHeight: DMLook.fieldHeight)
                    .background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: DMLook.fieldHeight / 2))
                    .overlay(RoundedRectangle(cornerRadius: DMLook.fieldHeight / 2)
                        .strokeBorder(fieldError != nil ? WebTheme.danger : WebTheme.outline, lineWidth: JPStroke.hairline))
                    .disabled(!canSend)
                    .accessibilityLabel(remaining == 0 ? L("承認されるまで送れません", "You can't send until they accept")
                                                       : L("\(peerName) さんへのメッセージ", "Message to \(peerName)"))
                    .accessibilityIdentifier("dm.field")
                Button { Task { await send() } } label: {
                    // 送れるときだけ真鍮の塗りに墨の矢印（7.11:1・板「写真の無い画面の主ボタン＝送信」・2026-11-11 案C）
                    Image(systemName: "arrow.up")
                        .font(JPFont.headline)
                        .foregroundStyle(sendEnabled ? WebTheme.accentText : Color.white.opacity(0.5))
                        .frame(width: DMLook.sendSize, height: DMLook.sendSize)
                        .background(sendEnabled ? WebTheme.accentFill : Color.white.opacity(0.16), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!sendEnabled)
                .accessibilityLabel(Labels.Common.send)
                .accessibilityIdentifier("dm.send")
            }
        }
        .padding(.horizontal, JPSpace.s)
        .padding(.top, JPSpace.xs)
        .padding(.bottom, JPSpace.xs)
        .background(WebTheme.background, ignoresSafeAreaEdges: .bottom)
        .overlay(alignment: .top) {
            Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
        }
    }

    private var sendEnabled: Bool {
        canSend && !connectivity.isOffline && !log.isSending
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 欄の上の1行（断りは赤の字＋印、案内は白 82%）。**色だけにしない**（印と文で伝える）
    private func noteRow(_ text: String, error: Bool) -> some View {
        HStack(alignment: .top, spacing: JPSpace.xs) {
            Image(systemName: error ? "exclamationmark.circle" : "info.circle")
                .font(JPFont.footnote)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(text)
                .font(JPFont.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(error ? WebTheme.danger : WebTheme.muted)
        .padding(.horizontal, JPSpace.xxs)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 見られない

    @ViewBuilder
    private var unavailableState: some View {
        ScrollView {
            if iBlockedPeer {
                EmptyState(title: L("ブロック中です", "You've blocked this person"),
                           message: L("\(peerName) さんをブロックしているため、会話は表示されません。解除すると、また見られるようになります。",
                                      "You blocked \(peerName), so this conversation is hidden. Unblock to see it again."),
                           actionTitle: L("ブロックを解除", "Unblock"),
                           actionIdentifier: "dm.unblock") {
                    Task { await unblock() }
                }
                .padding(.top, JPSpace.emptyTop)
            } else if isNew {
                // 1通目が断られた（フォローを外した・退会・ブロックの関係）。**どれかは言わない**（サーバーも同じ 404）
                EmptyState(title: L("メッセージを送れません", "You can't message this person"),
                           message: L("新しくメッセージを送れるのは、フォローしている人だけです。",
                                      "You can only start a conversation with people you follow."),
                           actionTitle: L("もどる", "Go back"),
                           actionIdentifier: "dm.unavailable.back") {
                    dismiss()
                }
                .padding(.top, JPSpace.emptyTop)
            } else {
                // ブロックされた側にも同じ文（ブロックされたと分かる文は出さない）
                EmptyState(title: L("この会話は表示できません", "This conversation isn't available"),
                           message: L("会話が削除されたか、見られない状態になっています。",
                                      "It was deleted or can't be viewed right now."),
                           actionTitle: L("受信箱にもどる", "Back to inbox"),
                           actionIdentifier: "dm.unavailable.back") {
                    dismiss()
                }
                .padding(.top, JPSpace.emptyTop)
            }
            if let actionError {
                Text(actionError).font(JPFont.caption).foregroundStyle(WebTheme.danger)
            }
        }
    }

    // MARK: - 読む

    private func load() async {
        if meta == nil { phase = .loading }
        do {
            let fetched = try await environment.dm.conversation(conversationId)
            guard !Task.isCancelled else { return }
            meta = fetched
            log.replace(with: fetched.items)
            phase = .loaded
            await markRead()
        } catch let refused as DMService.Refused where DMStart.opensEmpty(refused, starting: startingWith != nil) {
            // まだ会話が無い＝これから始まる（会話を始める入口から開いたときだけ）。**道そのものが無い 404** は含めない
            guard !Task.isCancelled else { return }
            isNew = true
            phase = .loaded
        } catch let refused as DMService.Refused where refused.status == 404 {
            phase = .unavailable
        } catch {
            guard !Task.isCancelled else { return }
            // 一度読めていれば中身を残す（読み直しの失敗で消さない）
            if meta == nil { phase = .failed }
        }
    }

    /// 開いている間の読み直し。変化なしは軽い空応答（`unchanged`）
    private func poll() async {
        guard scenePhase == .active else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: DMRules.pollInterval)
            guard !Task.isCancelled, phase == .loaded, !connectivity.isOffline else { continue }
            await refreshSince()
        }
    }

    /// 前に読んだ時刻より後の分だけ読む。相手の新しい1通があれば既読にする
    private func refreshSince() async {
        guard let since = meta?.t else { return }
        let fetched: DMConversation
        do {
            fetched = try await environment.dm.conversation(conversationId, since: since)
        } catch let refused as DMService.Refused where refused.isConversationMissing && !isNew {
            // 相手が送った通が全部取り消され、自分の受信箱から会話が外れた（2026-11-12）。跡を残さない:
            // 開いている画面からも消す（「表示できません」に切り替えない。ブロックの関係でも同じ 404 で、言い分けない）
            log.replace(with: [])
            return
        } catch {
            return
        }
        guard !fetched.unchanged else { return }
        let hadPeer = Set(log.messages.filter { !$0.mine }.map(\.id))
        meta = fetched
        // 前に読んだ後に送信の取り消しがあった: 差分ではなく全部が来るので置き換える（消えた1通を画面から外す）
        if fetched.full {
            log.replace(with: fetched.items)
        } else {
            log.merge(fetched.items)
        }
        if fetched.items.contains(where: { !$0.mine && !hadPeer.contains($0.id) }) {
            await markRead()
        }
    }

    private func markRead() async {
        store.apply { $0.markingRead(conversationId) }
        // 読んだ会話の通知は通知センターに残さない（アイコンの数字は `RootView` が受信箱の控えから合わせる）
        await push.removeDelivered(conversationId: conversationId)
        try? await environment.dm.markRead(conversationId)
    }

    // MARK: - 送る

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sendEnabled, !text.isEmpty else { return }
        let clientId = DMRules.newClientId()
        guard log.begin(text: text, clientId: clientId) else { return }
        draft = ""
        fieldError = nil
        await deliver(text: text, clientId: clientId)
    }

    /// 送れなかった1通を、**同じ鍵のまま**もう一度送る
    private func retry(_ clientId: String) async {
        guard !connectivity.isOffline, !log.isSending, let text = log.retry(clientId) else { return }
        await deliver(text: text, clientId: clientId)
    }

    private func deliver(text: String, clientId: String) async {
        probe.sends += 1
        do {
            let result = try await environment.dm.send(conversationId, text: text, clientId: clientId)
            log.succeed(clientId, with: result.message)
            // 受け取ったリクエストに返信した＝承認（受信箱へ移す）
            if isIncomingRequest { store.apply { $0.accepting(conversationId) } }
            if isNew {
                // 1通目で会話ができた。会話をはじめから読み、受信箱にも出す（`since` はまだ無い）
                newSent += 1
                await adoptCreatedConversation()
            } else {
                // 残りの通数・置き場所はサーバーが正（送ったあとの姿を読み直す）
                await refreshSince()
            }
        } catch let refused as DMService.Refused {
            probe.refusals += 1
            if refused.status == 404 {
                _ = log.withdraw(clientId)
                phase = .unavailable
            } else if DMText.returnsToField(code: refused.code) {
                // 吹き出しにせず、入力に戻す（URL・上限・ブロック中など。押し直しても通らない）
                if let back = log.withdraw(clientId), draft.isEmpty {
                    restoredDraft = back
                    draft = back
                }
                fieldError = refused.errorDescription
                if refused.code == "requestLimit" { await refreshSince() }
            } else {
                log.fail(clientId, reason: refused.errorDescription ?? L("送れませんでした", "Couldn't send"))
            }
        } catch {
            log.fail(clientId, reason: (error as? LocalizedError)?.errorDescription ?? L("送れませんでした", "Couldn't send"))
        }
    }

    /// 1通目のあと、できた会話を読む。読めたら空の会話から抜ける（残りの通数はサーバーの値へ）。
    /// 読めなかった回は手元の数のまま（次に送れたときにもう一度読む）
    private func adoptCreatedConversation() async {
        if let fetched = try? await environment.dm.conversation(conversationId), !fetched.unchanged {
            meta = fetched
            log.merge(fetched.items)
            isNew = false
        }
        await store.refresh(service: environment.dm, owner: auth.userId)
    }

    // MARK: - 送信の取り消し（2026-11-12）

    /// 押したらすぐ消し、文字だけの通は文を入力欄へ（送れる会話だけ）。答えで3つに分ける（`DMUnsend.Outcome`）:
    /// 消えた → そのまま。断られた（ブロックの関係など）→ 1通と欄を戻して赤の一言。分からない（時間切れ）→ 1通は戻すが
    /// 戻した文は欄に残す（サーバーで消えていたら次の読み直しで消え、文は失わない）
    private func unsend(_ message: DMMessage) async {
        guard let removed = log.unsend(message.id) else { return }
        actionError = nil
        let before = draft
        let returned = DMUnsend.returnedText(removed, canSend: canSend).map { DMUnsend.draft(current: draft, returning: $0) }
        if let returned {
            restoredDraft = returned
            draft = returned
            fieldFocused = true
        }
        var failure: Error?
        do {
            try await environment.dm.unsend(conversationId, messageId: removed.id)
        } catch {
            failure = error
        }
        switch DMUnsend.outcome(of: failure) {
        case .gone:
            // 受信箱の抜粋（最後の一言）はサーバーが直した。控えも読み直す
            await store.refresh(service: environment.dm, owner: auth.userId)
        case .refused:
            log.restore(removed)
            if let returned {
                let back = DMUnsend.draftAfterFailure(current: draft, returned: returned, before: before)
                restoredDraft = back
                draft = back
            }
            actionError = L("送信を取り消せませんでした。", "Couldn't unsend.")
        case .unknown:
            log.restore(removed)
            actionError = L("送信を取り消せたか確かめられませんでした。もう一度お試しください。",
                            "Couldn't confirm the unsend. Please try again.")
        }
    }

    // MARK: - 操作

    private func accept() async {
        guard !working else { return }
        working = true
        defer { working = false }
        actionError = nil
        do {
            try await environment.dm.accept(conversationId)
            store.apply { $0.accepting(conversationId) }
            if let meta {
                self.meta = DMConversation(id: meta.id, peerId: meta.peerId, name: meta.name, username: meta.username,
                                           deleted: meta.deleted, state: .inbox, canSend: meta.canSend,
                                           requestRemaining: meta.requestRemaining, t: meta.t, items: meta.items)
            }
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? L("承認できませんでした", "Couldn't accept")
        }
    }

    private func declineRequest() async {
        guard !working else { return }
        working = true
        defer { working = false }
        actionError = nil
        do {
            try await environment.dm.decline(conversationId)
            store.apply { $0.removing(conversationId) }
            dismiss()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? L("削除できませんでした", "Couldn't delete")
        }
    }

    private func removeConversation() async {
        guard !working else { return }
        working = true
        defer { working = false }
        actionError = nil
        do {
            try await environment.dm.remove(conversationId)
            store.apply { $0.removing(conversationId) }
            dismiss()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? L("削除できませんでした", "Couldn't delete")
        }
    }

    private func block() async {
        guard let peerId else { return }
        actionError = nil
        do {
            try await hidden.blockAndHide(peerId, environment: environment)
            store.apply { $0.removing(conversationId) }
            dismiss()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? L("ブロックできませんでした", "Couldn't block")
        }
    }

    private func unblock() async {
        guard let peerId, !working else { return }
        working = true
        defer { working = false }
        actionError = nil
        let owner = hidden.owner
        do {
            try await environment.moderation.unblock(userId: peerId)
            hidden.unblock(peerId, for: owner)
            await environment.gallery.setHidden(hidden.snapshot)
            // 解除で会話が戻る（サーバーは消さずに隠していた）
            meta = nil
            await load()
            await store.refresh(service: environment.dm, owner: auth.userId)
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? L("解除できませんでした", "Couldn't unblock")
        }
    }

    /// 通報と一緒にブロックしたら、会話を閉じる
    private func afterReport() {
        guard iBlockedPeer else { return }
        store.apply { $0.removing(conversationId) }
        dismiss()
    }
}

/// 吹き出し1つ（2026-11-11 案C「黒塗りに真鍮の縁」・`DMBubbleColors`）。
///
/// - 自分は accent-soft の塗り＋真鍮 1pt の縁＋白の字・右下の角 6。相手は surface-8・白の字・左下の角 6
/// - 続けて送った吹き出し（`joinsPrevious`）は、上の付け根の側の角も 6 に詰めて1かたまりに見せる
/// - 最大幅は会話の幅の 78%（`maxWidth`）
/// - 本文の URL は押せるリンク（真鍮・下線・`DMLinks`）。開く先は Safari（SwiftUI のリンクの既定の動き）
/// - 送っている最中は薄く、送れなかったら破線の縁＋「送れませんでした ・ もう一度送る」（真鍮の下線・当たり 44）
struct DMBubble: View {
    let text: String
    let mine: Bool
    let time: String?
    var joinsPrevious = false
    var maxWidth: CGFloat = DMLook.bubbleMaxWidth(container: 0)
    var outgoing: DMOutgoing.Phase? = nil
    var onRetry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
            Text(Self.linked(text))
                .font(JPFont.body)
                .lineSpacing(3)
                .foregroundStyle(DMBubbleColors.text(mine: mine))
                .tint(DMBubbleColors.link)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(DMBubbleColors.fill(mine: mine), in: shape)
                .overlay {
                    if failedReason != nil {
                        shape.stroke(WebTheme.danger, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    } else if mine {
                        shape.stroke(DMBubbleColors.border(mine: true), lineWidth: DMLook.bubbleBorder)
                    }
                }
                .opacity(outgoing == .sending ? 0.6 : 1)
                .frame(maxWidth: maxWidth, alignment: mine ? .trailing : .leading)
                .accessibilityLabel(spokenText)
            if outgoing == .sending {
                Text(L("送信中…", "Sending…"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .padding(.horizontal, JPSpace.xxs)
                    .accessibilityHidden(true)
            }
            if let time {
                Text(time)
                    .font(JPFont.caption.monospacedDigit())
                    .foregroundStyle(WebTheme.text3)
                    .padding(.horizontal, JPSpace.xxs)
                    .accessibilityHidden(true)
            }
            if let reason = failedReason {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(WebTheme.danger)
                        .accessibilityHidden(true)
                    Text(reason)
                    if let onRetry {
                        Button(action: onRetry) {
                            Text(L("もう一度送る", "Send again"))
                                .font(JPFont.caption.weight(.semibold))
                                .underline()
                                .foregroundStyle(WebTheme.accent)
                                .padding(.horizontal, 6)
                                .frame(minHeight: WebTheme.minTapTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("dm.retry")
                    }
                }
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text)
            }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    /// 本文にリンクを付けた形（見つけた URL だけ・http と https だけ）。字の並びはそのまま、リンクの所だけ印を付けてつなぐ
    static func linked(_ text: String) -> AttributedString {
        var out = AttributedString()
        var cursor = text.startIndex
        for link in DMLinks.find(in: text) {
            if cursor < link.range.lowerBound { out += AttributedString(String(text[cursor..<link.range.lowerBound])) }
            var piece = AttributedString(String(text[link.range]))
            piece.link = link.url
            #if os(iOS)
            // 真鍮の字と下線（色だけにしない）。どちらの吹き出しの地も黒地の仲間（#1C170E 7.77:1・#2C2C2E 6.07:1）
            piece[AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self] = .single
            piece[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = DMBubbleColors.link
            #endif
            out += piece
            cursor = link.range.upperBound
        }
        if cursor < text.endIndex { out += AttributedString(String(text[cursor...])) }
        return out
    }

    /// 送れなかった理由（送れなかった1通だけ）
    private var failedReason: String? {
        if case .failed(let reason)? = outgoing { return reason }
        return nil
    }

    private var shape: UnevenRoundedRectangle {
        let r = DMLook.bubbleRadius, tail = DMLook.bubbleTailRadius
        let top = joinsPrevious ? tail : r
        // 付け根の下は、続きがあってもなくても 6（かたまりの最後が付け根）
        let bottom = tail
        return mine
            ? UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r, bottomTrailingRadius: bottom, topTrailingRadius: top)
            : UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom, bottomTrailingRadius: r, topTrailingRadius: r)
    }

    private var spokenText: String {
        let who = mine ? L("あなた", "You") : L("相手", "Them")
        switch outgoing {
        case .sending?: return "\(who): \(text)、" + L("送信中", "sending")
        case .failed?: return "\(who): \(text)、" + L("送れませんでした", "not sent")
        case nil: return "\(who): \(text)" + (time.map { "、\($0)" } ?? "")
        }
    }
}

/// 日付の区切り（「今日」「昨日」「11月3日」）。両側に白 8% の細い線（2026-11-11 案C）
struct DMDayDivider: View {
    let text: String

    var body: some View {
        HStack(spacing: JPSpace.s) {
            Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
            Text(text)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .fixedSize()
            Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
        }
        .padding(.top, JPSpace.s)
        .padding(.bottom, JPSpace.xxs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 写真だけの通の時刻（吹き出しの無い通・写真の下に）
struct DMTimeLabel: View {
    let text: String
    let mine: Bool

    var body: some View {
        Text(text)
            .font(JPFont.caption.monospacedDigit())
            .foregroundStyle(WebTheme.text3)
            .padding(.horizontal, JPSpace.xxs)
            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
            .accessibilityHidden(true)
    }
}

/// 自分の通の札（写真）にだけ「送信を取り消す」の長押しを付ける（相手の札にはメニューを出さない・2026-11-12）
private struct DMUnsendMenu<Menu: View>: ViewModifier {
    let enabled: Bool
    @ViewBuilder let menu: () -> Menu

    func body(content: Content) -> some View {
        if enabled {
            content.contextMenu { menu() }
        } else {
            content
        }
    }
}
