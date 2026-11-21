import SwiftUI
import UIKit

/// グループの会話（2026-11-20・札 #582・案「グループチャットを簡単に」の推奨 C の画面 2・画面 8）。
///
/// **1対1の会話の部品をそのまま使う**（吹き出し `DMBubble`・日付の区切り・写真の札 `DMPhotoCard`・入力欄 `DMComposer`・
/// 送る1通の控え `DMThreadLog`・圏外の帯）。グループで足したのは:
/// - 見出しに重ねた顔と名前と人数（押すと詳しい画面・右の丸い i も同じ）
/// - 相手の通の上に名前と顔（同じ人が続けて送ったら2通目から省く・`GroupRows`）
/// - 作った・足した・抜けた・名前を変えた、は会話の真ん中に短い1行（`GroupEventLine`）
/// - 空（作った直後）は重ねた顔と「けん、みおと話そう」と、はじめの一言の候補（押すと入力欄に入るだけ・AI ではない）
/// - 外されたグループは、外されるまでの話を読めるが送れない（欄の代わりに理由と「受信箱から消す」）
///
/// 既読の人数・入力中の印は出さない（1対1と同じ）。読み直しは開いている間 15 秒ごと（`GroupRules.pollInterval`）と、
/// この会話の知らせが前面で届いたとき
struct GroupConversationView: View {

    let groupId: String
    /// 読む前の見出し（一覧の行・作った直後の答え）。無ければ読めてから出す
    var seed: GroupInfo? = nil
    /// 開いた直後に1回出す知らせ（「1人は入れられませんでした」など）
    var notice: String? = nil
    /// 抜けた・受信箱から消したあと（呼ぶ側が積みを戻す）。無ければ自分で閉じる
    var onLeft: (() -> Void)? = nil

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var hidden: ModerationStore
    @EnvironmentObject private var connectivity: Connectivity
    @EnvironmentObject private var store: DMInboxStore
    @EnvironmentObject private var push: PushCenter
    @ObservedObject private var router = NotificationRouter.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    enum Phase: Equatable { case loading, loaded, failed, unavailable }

    @State private var phase: Phase = .loading
    @State private var info: GroupInfo?
    @State private var membership: GroupMembership?
    @State private var removed = false
    @State private var canSendHere = false
    /// 名前を引く表（メンバーと、見えている通を書いた人）
    @State private var names: [String: String] = [:]
    @State private var log = DMThreadLog()
    @State private var draft = ""
    @State private var fieldError: String?
    @State private var restoredDraft: String?
    @State private var actionError: String?
    @State private var working = false
    @FocusState private var fieldFocused: Bool
    @State private var threadWidth: CGFloat = 0
    @State private var showDetail = false
    @State private var profileTarget: String?
    @State private var reportTarget: ReportTarget?
    @State private var blockTarget: BlockTarget?
    @State private var openedPhoto: Photo?
    @State private var openedPhotoIsPublic = true
    @State private var openingPhoto = false
    @State private var shownNotice: ShownNotice?
    /// UI テストのときだけ（`-JPPreviewGroups`）: 送った・読み直した回数といまの通の数を見えない要素に出す
    @State private var probe = (sends: 0, loads: 0, details: 0)

    struct ReportTarget: Identifiable, Equatable {
        let report: ReportSheet.GroupReport
        let authorId: String?
        var id: String { report.messageId ?? "group" }
    }

    struct BlockTarget: Identifiable, Equatable {
        let userId: String
        let name: String
        var id: String { userId }
    }

    struct ShownNotice: Equatable {
        let id = UUID()
        let text: String
    }

    private var conversationKey: String { GroupText.conversationId(groupId: groupId) }
    private var shownInfo: GroupInfo? { info ?? seed ?? store.groups.groups.first { $0.id == groupId }?.info }
    private var title: String { shownInfo.map(GroupText.title) ?? L("グループ", "Group") }
    private var canSend: Bool { phase == .loaded && canSendHere && !removed }
    private var sendEnabled: Bool {
        canSend && !connectivity.isOffline && !log.isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    /// 見せる通（ブロックした人の通は外す。真ん中の1行は残す）
    private var visible: [DMMessage] {
        let blocked = hidden.blockedUserIds
        return log.messages.filter { $0.groupEvent != nil || !blocked.contains($0.from) }
    }
    private var photoIsOpen: Binding<Bool> {
        Binding(get: { openedPhoto != nil }, set: { if !$0 { openedPhoto = nil } })
    }

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
                .frame(maxHeight: .infinity)
                composer.disabled(true)
            case .unavailable:
                unavailableState
            case .loaded:
                thread
                footer
            }
        }
        .overlay(alignment: .top) {
            if let shownNotice {
                DMActionToast(text: shownNotice.text)
                    .padding(.top, JPSpace.xs)
                    .transition(.opacity)
                    .accessibilityIdentifier("group.notice")
                    .task(id: shownNotice.id) {
                        try? await Task.sleep(for: DMActionToast.duration)
                        if !Task.isCancelled, self.shownNotice == shownNotice { self.shownNotice = nil }
                    }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if PreviewSession.groups {
                Text(".")
                    .font(.caption2)
                    .foregroundStyle(Color.clear)
                    .accessibilityIdentifier("group.probe")
                    .accessibilityValue("sends=\(probe.sends) loads=\(probe.loads) details=\(probe.details) count=\(log.messages.count)"
                                        + " members=\(shownInfo?.memberCount ?? 0) removed=\(removed)")
            }
        }
        .webScreen()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { header }
            ToolbarItem(placement: .topBarTrailing) {
                if phase == .loaded && !removed { infoButton }
            }
        }
        .navigationDestination(isPresented: $showDetail) {
            GroupDetailView(groupId: groupId, seed: membership, info: shownInfo, names: names,
                            onChange: { changed in
                                membership = changed
                                info = changed.group
                                Task { await load(quiet: true) }
                            },
                            onLeft: left)
        }
        .navigationDestination(item: $profileTarget) { userId in
            UserProfileView(userId: userId)
        }
        .navigationDestination(isPresented: photoIsOpen) {
            if let openedPhoto { PhotoDetailView(photo: openedPhoto, fromPublicFeed: openedPhotoIsPublic) }
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(photoId: "", ownerId: target.authorId, group: target.report)
        }
        .alert(blockTarget.map { DMBlockText.title($0.name) } ?? "",
               isPresented: Binding(get: { blockTarget != nil }, set: { if !$0 { blockTarget = nil } }),
               presenting: blockTarget) { target in
            Button(L("ブロック", "Block"), role: .destructive) { Task { await block(target.userId) } }
            Button(Labels.Common.cancel, role: .cancel) {}
        } message: { _ in
            Text(DMBlockText.message)
        }
        .task(id: groupId) {
            if let notice { shownNotice = ShownNotice(text: notice) }
            await load()
        }
        .task(id: "\(groupId)#\(scenePhase == .active)") { await poll() }
        .onAppear { router.conversationOpened(conversationKey) }
        .onDisappear { router.conversationClosed(conversationKey) }
        // この会話の知らせが前面で届いた: 待たずに読み直す
        .onChange(of: router.dmArrival) { _, arrival in
            guard arrival.conversationId == conversationKey, phase == .loaded else { return }
            Task { await load(quiet: true, withDetail: false) }
        }
        .onChange(of: connectivity.isOffline) { _, offline in
            if !offline, phase == .failed { Task { await load() } }
        }
        .onChange(of: draft) { old, new in
            let kept = PostLimits.limited(old: old, new: new, limit: DMRules.textMax)
            if kept != new { draft = kept }
            if new == restoredDraft { return }
            restoredDraft = nil
            if fieldError != nil, !new.isEmpty, new != old { fieldError = nil }
        }
    }

    // MARK: - 見出し

    /// 重ねた顔 34・名前 17・人数 12（押すと詳しい画面）。1対1の見出し（顔 32・名前 17・@ユーザー名 12）と同じ並び
    private var header: some View {
        Button { if phase == .loaded && !removed { showDetail = true } } label: {
            HStack(spacing: JPSpace.xs) {
                GroupFaces(faces: shownInfo?.faces ?? [], size: GroupLook.headerFaces)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(JPFont.headline)
                        .foregroundStyle(removed ? WebTheme.text3 : WebTheme.text)
                        .lineLimit(1)
                    if let count = shownInfo?.memberCount, count > 0 {
                        Text(GroupText.memberCount(count))
                            .font(JPFont.caption.monospacedDigit())
                            .foregroundStyle(WebTheme.text3)
                            .lineLimit(1)
                    }
                }
            }
            .frame(minHeight: WebTheme.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel([title, shownInfo.map { GroupText.memberCount($0.memberCount) }].compactMap { $0 }.joined(separator: "、"))
        .accessibilityHint(L("グループの詳しい画面を開きます", "Opens the group details"))
        .accessibilityIdentifier("group.header")
    }

    private var infoButton: some View {
        Button { showDetail = true } label: {
            Image(systemName: "info.circle").webToolbarIcon().appHeaderHitArea()
        }
        .accessibilityLabel(L("グループの詳しい画面", "Group details"))
        .accessibilityIdentifier("group.info")
    }

    // MARK: - 会話

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    let rows = GroupRows.build(visible)
                    ForEach(rows) { row in
                        if row.startsDay, let date = NotificationGroups.parse(row.message.t) {
                            DMDayDivider(text: DMText.dayLabel(date))
                        }
                        rowView(row).id(row.id)
                    }
                    if !GroupRows.hasConversation(visible) && log.outgoing.isEmpty && canSend {
                        emptyIntro
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
            .onGeometryChange(for: CGFloat.self) { proxy in proxy.size.width } action: { width in
                threadWidth = width
            }
            .onAppear { proxy.scrollTo(Self.bottomId, anchor: .bottom) }
            .onChange(of: log.messages.count + log.outgoing.count) { old, new in
                if DMBottomScroll.animates(from: old, to: new) {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomId, anchor: .bottom) }
                } else {
                    proxy.scrollTo(Self.bottomId, anchor: .bottom)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityIdentifier("group.conversation")
    }

    private static let bottomId = "group.bottom"

    @ViewBuilder
    private func rowView(_ row: GroupRow) -> some View {
        let message = row.message
        if let event = message.groupEvent {
            GroupEventLine(text: GroupText.event(event, actor: message.from, names: names, me: auth.userId))
        } else if message.mine {
            if message.hasPhoto { photoCard(message) }
            if let text = message.bubbleText {
                DMBubble(text: text, mine: true, time: row.time, joinsPrevious: row.joinsPrevious,
                         maxWidth: DMLook.bubbleMaxWidth(container: threadWidth))
                    .contextMenu {
                        Button { UIPasteboard.general.string = text } label: { Label(L("コピー", "Copy"), systemImage: "doc.on.doc") }
                    }
            } else if let time = row.time {
                DMTimeLabel(text: time, mine: true)
            }
        } else {
            theirs(row)
        }
    }

    /// 相手の通: 上に名前（続きの2通目からは省く）、左に顔（1かたまりの最初の1通だけ・続きは同じ幅を空ける）
    private func theirs(_ row: GroupRow) -> some View {
        let message = row.message
        let name = GroupText.name(message.from, in: names, me: auth.userId)
        return VStack(alignment: .leading, spacing: 2) {
            if row.showsSender {
                Text(name)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .lineLimit(1)
                    .padding(.leading, GroupLook.senderIndent + JPSpace.xxs)
                    .padding(.top, JPSpace.xxs)
                    .accessibilityHidden(true)
            }
            HStack(alignment: .bottom, spacing: GroupLook.senderGap) {
                if row.showsSender {
                    // 見た目は 28、当たりは 44（外へ 8 ずつ広げ、並びの幅は 28 のまま）
                    Button { profileTarget = message.from } label: {
                        DMAvatar(userId: message.from, size: GroupLook.senderAvatar)
                            .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(-GroupLook.senderHitSlack)
                    .accessibilityLabel(L("\(name) のプロフィール", "\(name)'s profile"))
                } else {
                    Color.clear.frame(width: GroupLook.senderAvatar, height: 1)
                }
                VStack(alignment: .leading, spacing: 6) {
                    if message.hasPhoto {
                        // 相手の写真の札にも長押しの通報・ブロック（写真だけの通でも届く・2026-11-20 確かめ役の指摘）
                        DMPhotoCard(message: message, blocked: hidden.blockedUserIds, opening: openingPhoto, menuEnabled: true,
                                    onOpen: { quote in Task { await openPhoto(quote) } },
                                    menu: { theirMenu(message, name: name, text: nil) })
                    }
                    if let text = message.bubbleText {
                        DMBubble(text: text, mine: false, time: row.time, joinsPrevious: row.joinsPrevious,
                                 maxWidth: DMLook.bubbleMaxWidth(container: threadWidth - GroupLook.senderIndent))
                            .contextMenu { theirMenu(message, name: name, text: text) }
                            .accessibilityLabel("\(name): \(text)")
                    } else if let time = row.time {
                        DMTimeLabel(text: time, mine: false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 相手の文の長押し: コピー・通報・ブロック（言葉と印は DM・旅行プランの会話と同じ）
    @ViewBuilder
    private func theirMenu(_ message: DMMessage, name: String, text: String?) -> some View {
        if let text {
            Button { UIPasteboard.general.string = text } label: { Label(L("コピー", "Copy"), systemImage: "doc.on.doc") }
        }
        Button {
            reportTarget = ReportTarget(report: .init(groupId: groupId, messageId: message.id, authorName: name, text: text),
                                        authorId: message.from)
        } label: { Label(L("通報", "Report"), systemImage: "exclamationmark.bubble") }
        Button(role: .destructive) { blockTarget = BlockTarget(userId: message.from, name: name) } label: {
            Label(L("ブロック", "Block"), systemImage: "hand.raised")
        }
    }

    private func photoCard(_ message: DMMessage) -> some View {
        DMPhotoCard(message: message, blocked: hidden.blockedUserIds, opening: openingPhoto) { quote in
            Task { await openPhoto(quote) }
        }
    }

    /// 空の会話（作った直後）: 重ねた顔・「けん、みおと話そう」・はじめの一言の候補（押すと入力欄に入るだけ・送らない）
    private var emptyIntro: some View {
        VStack(spacing: JPSpace.xs) {
            GroupFaces(faces: shownInfo?.faces ?? [], size: GroupLook.largeFaces)
                .padding(.bottom, JPSpace.xxs)
            if let shownInfo {
                Text(GroupText.emptyTitle(shownInfo))
                    .font(JPFont.rowTitle)
                    .foregroundStyle(WebTheme.text)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: JPSpace.xs) {
                ForEach(GroupRules.starters, id: \.self) { phrase in
                    PillChip(title: phrase, selected: false) {
                        draft = GroupRules.starterDraft(current: draft, adding: phrase)
                        fieldFocused = true
                    }
                    .accessibilityIdentifier("group.starter")
                }
            }
            .padding(.top, JPSpace.xxs)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, JPSpace.xl)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("group.empty")
    }

    // MARK: - 下

    @ViewBuilder
    private var footer: some View {
        if removed {
            VStack(spacing: JPSpace.xs) {
                Text(L("グループから外されたため、メッセージを送れません。", "You were removed from this group, so you can't send messages."))
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionError {
                    DMNoteRow(text: actionError, error: true)
                }
                Button { Task { await forget() } } label: {
                    Text(L("受信箱から消す", "Remove from inbox")).jpOutlineButton(.regular, tone: .danger, fullWidth: true)
                }
                .buttonStyle(.plain)
                .disabled(working || connectivity.isOffline)
                .accessibilityIdentifier("group.removed.forget")
            }
            .jpBottomBar()
        } else {
            composer
        }
    }

    private var composer: some View {
        DMComposer(draft: $draft, focus: $fieldFocused, canType: canSend, sendEnabled: sendEnabled,
                   hasError: fieldError != nil,
                   fieldLabel: L("\(title) へのメッセージ", "Message to \(title)"),
                   onSend: { Task { await send() } }) {
            if let actionError {
                DMNoteRow(text: actionError, error: true)
            }
            if let fieldError {
                DMNoteRow(text: fieldError, error: true)
                    .accessibilityIdentifier("group.fieldError")
            }
        }
    }

    // MARK: - 見られない

    private var unavailableState: some View {
        ScrollView {
            EmptyState(icon: nil, title: L("このグループは表示できません", "This group isn't available"),
                       message: L("グループから抜けたか、グループが無くなりました。",
                                  "You left the group, or it no longer exists."),
                       actionTitle: L("受信箱にもどる", "Back to inbox"),
                       actionIdentifier: "group.unavailable.back") {
                dismiss()
            }
            .padding(.top, JPSpace.emptyTop)
        }
    }

    // MARK: - 読む

    /// 読む。`withDetail` が偽（15 秒ごとの読み直し）なら会話だけを読み、メンバーが変わる1行が来たときだけ詳しい中身も読む
    private func load(quiet: Bool = false, withDetail: Bool = true) async {
        if !quiet && phase != .loaded { phase = .loading }
        do {
            let page = try await environment.groups.messages(groupId)
            let fresh = page.messages.map(\.asDM)
            let detail = withDetail || GroupRows.changesMembers(old: log.messages, new: fresh)
                ? try? await environment.groups.detail(groupId) : nil
            if PreviewSession.groups, detail != nil { probe.details += 1 }
            guard !Task.isCancelled else { return }
            if PreviewSession.groups { probe.loads += 1 }
            var known = names
            for face in page.members { known[face.id] = face.name }
            if let detail {
                info = detail.group
                membership = detail.membership
                for m in detail.membership?.members ?? [] { known[m.id] = m.name }
                for f in detail.group.faces { known[f.id] = known[f.id] ?? f.name }
            }
            names = known
            removed = page.state == .removed
            canSendHere = page.canSend
            log.replace(with: fresh)
            phase = .loaded
            // サーバーは読んだ位置を進めた。点と通知センターも合わせる
            store.applyGroups { $0.markingRead(groupId) }
            await push.removeDelivered(conversationId: conversationKey)
        } catch let refused as DMService.Refused where refused.status == 404 {
            guard !Task.isCancelled else { return }
            phase = .unavailable
        } catch {
            guard !Task.isCancelled else { return }
            // 一度読めていれば中身を残す（読み直しの失敗で消さない）
            if phase != .loaded { phase = .failed }
        }
    }

    private func poll() async {
        guard scenePhase == .active else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: GroupRules.pollInterval)
            guard !Task.isCancelled, phase == .loaded, !connectivity.isOffline, !log.isSending else { continue }
            await load(quiet: true, withDetail: false)
        }
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

    private func retry(_ clientId: String) async {
        guard !connectivity.isOffline, !log.isSending, let text = log.retry(clientId) else { return }
        await deliver(text: text, clientId: clientId)
    }

    private func deliver(text: String, clientId: String) async {
        if PreviewSession.groups { probe.sends += 1 }
        do {
            let sent = try await environment.groups.send(groupId, text: text, clientId: clientId)
            log.succeed(clientId, with: sent.asDM)
        } catch let refused as DMService.Refused {
            if refused.status == 404 && refused.code == "notFound" {
                _ = log.withdraw(clientId)
                phase = .unavailable
            } else if GroupText.returnsToField(code: refused.code) {
                if let back = log.withdraw(clientId), draft.isEmpty {
                    restoredDraft = back
                    draft = back
                }
                fieldError = refused.groupMessage
            } else {
                log.fail(clientId, reason: refused.groupMessage)
            }
        } catch {
            log.fail(clientId, reason: (error as? LocalizedError)?.errorDescription ?? L("送れませんでした", "Couldn't send"))
        }
    }

    // MARK: - 操作

    private func openPhoto(_ quote: DMPhotoQuote) async {
        guard !openingPhoto else { return }
        openingPhoto = true
        defer { openingPhoto = false }
        if let found = await DMPhotoOpen.find(quote, environment: environment, me: auth.userId) {
            openedPhotoIsPublic = found.isPublic
            openedPhoto = found.photo
        } else {
            actionError = DMPhotoOpen.notFoundMessage
        }
    }

    private func block(_ userId: String) async {
        actionError = nil
        do {
            try await hidden.blockAndHide(userId, environment: environment)
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? L("ブロックできませんでした", "Couldn't block")
        }
    }

    /// 外されたグループを受信箱から消す（`DELETE …/members/{自分}`）
    private func forget() async {
        guard let me = auth.userId, !working else { return }
        working = true
        defer { working = false }
        actionError = nil
        do {
            try await environment.groups.removeMember(groupId, userId: me)
            left()
        } catch {
            actionError = GroupText.message(for: error, fallback: L("消せませんでした", "Couldn't remove"))
        }
    }

    /// 抜けた・消した: 一覧から外して閉じる
    private func left() {
        store.applyGroups { $0.removing(groupId) }
        showDetail = false
        if let onLeft { onLeft() } else { dismiss() }
    }
}
