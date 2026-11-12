import SwiftUI
import UIKit

/// 旅行プランを仲間と使う画面の部品（2026-11-12・資料「SNS をもっと SNS に」2b・札 #553）。
///
/// 旅行プランの詳細（`TripPlanDetailView`）の題・日付の下に置く:
///   - 共有していないプラン: 「仲間を誘う」（DM から作ったプランは「[名前] と共有する」）
///   - 共有したプラン: 「N人」と顔の段・「仲間を誘う」・「日程 | 会話」の切り替え
/// 新しいタブ・設定の行は足さない（「直感的で簡単に」）。誘うのは 2 回（仲間を誘う → LINE で送る）。
///
/// 色（2026-11-12 判断・板 DesignSystem「黒塗りの真鍮」）: 写真の無い画面なので、主ボタン（共有する・LINE で送る）は
/// 真鍮の塗りに墨。誘うの丸ボタンは線のボタン。選んでいる切り替えは面の段 `surface8`（`VisitedMapScreen` と同じ形）、
/// 会話の未読は真鍮の点（受信箱と同じ `BrassDot`）。吹き出しは DM と同じ（`DMBubble`）

/// DM の会話から作ったプランを共有する相手（2a の流れの最後）
struct TripSharePeer: Equatable {
    let id: String
    let name: String
}

/// 共有の段（題・日付の下）
struct TripShareStrip: View {
    let plan: TripPlan
    let members: [TripMember]
    /// DM から作ったプランの相手（まだ共有していなければ「[名前] と共有する」を出す）
    let peer: TripSharePeer?
    let working: Bool
    @Binding var tab: TripShareText.Tab
    let chatUnread: Bool
    let onShareWithPeer: () -> Void
    let onInvite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JPSpace.s) {
            if let peer, !(plan.share?.memberIds.contains(peer.id) ?? false) {
                peerCard(peer)
            }
            HStack(spacing: JPSpace.s) {
                if let share = plan.share {
                    Text(TripShareText.memberCount(share.memberIds.count))
                        .font(JPFont.footnote.monospacedDigit())
                        .foregroundStyle(WebTheme.text2)
                    faces(share.memberIds)
                } else if let peer, plan.share == nil {
                    Text(TripShareText.shareNote)
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(peer.id.isEmpty)
                }
                Spacer(minLength: 0)
                Button(action: onInvite) {
                    Label(TripShareText.invite, systemImage: "person.badge.plus")
                        .font(JPFont.footnote.weight(.semibold))
                        .jpOutlineButton(.regular, tone: .plain, fullWidth: false)
                }
                .buttonStyle(.plain)
                .disabled(working)
                .accessibilityIdentifier("tripShare.invite")
            }
            if plan.share != nil {
                tabPicker
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tripShare.strip")
    }

    private func peerCard(_ peer: TripSharePeer) -> some View {
        Button(action: onShareWithPeer) {
            HStack(spacing: JPSpace.xs) {
                DMAvatar(userId: peer.id, size: 28)
                Text(TripShareText.shareWith(peer.name))
                    .font(JPFont.bodyEmphasis)
                    .foregroundStyle(WebTheme.accentText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if working { ProgressView().tint(WebTheme.accentText) }
            }
            .padding(.horizontal, JPSpace.m)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(WebTheme.accentFill, in: RoundedRectangle(cornerRadius: JPRadius.m))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(working)
        .accessibilityHint(TripShareText.shareNote)
        .accessibilityIdentifier("tripShare.withPeer")
    }

    private func faces(_ ids: [String]) -> some View {
        HStack(spacing: -8) {
            ForEach(Array(ids.prefix(5)), id: \.self) { id in
                let member = members.first { $0.id == id }
                DMAvatar(userId: id, deleted: member?.deleted == true, size: 28)
                    .overlay(Circle().strokeBorder(WebTheme.background, lineWidth: 2))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(members.map(\.name).joined(separator: "、"))
        .accessibilityIdentifier("tripShare.faces")
    }

    /// 「日程 | 会話」（板「表示の切替」）。会話に未読があれば真鍮の点
    private var tabPicker: some View {
        HStack(spacing: 2) {
            segment(.days, title: L("日程", "Plan"), id: "tripShare.tab.days", dot: false)
            segment(.chat, title: L("会話", "Chat"), id: "tripShare.tab.chat", dot: chatUnread)
        }
        .padding(3)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: JPRadius.field))
    }

    private func segment(_ value: TripShareText.Tab, title: String, id: String, dot: Bool) -> some View {
        Button { tab = value } label: {
            HStack(spacing: 6) {
                Text(title)
                if dot { BrassDot().accessibilityHidden(true) }
            }
            .font(tab == value ? JPFont.bodyEmphasis : JPFont.body)
            .foregroundStyle(tab == value ? WebTheme.foreground : WebTheme.text2)
            .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
            .background(tab == value ? WebTheme.surface8 : Color.clear, in: RoundedRectangle(cornerRadius: JPRadius.s))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dot ? L("\(title)、未読あり", "\(title), unread") : title)
        .accessibilityAddTraits(tab == value ? [.isSelected] : [])
        .accessibilityIdentifier(id)
    }
}

/// 「[題]に誘う」のシート（リンク・LINE で送る・リンクをコピー・ほかのアプリ）
struct TripInviteSheet: View {
    let title: String
    let link: TripInviteLink?
    let failed: String?
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: JPSpace.m) {
            Text(TripShareText.inviteTitle(title.isEmpty ? L("旅行プラン", "this trip") : title))
                .font(JPFont.cardTitle)
                .foregroundStyle(WebTheme.foreground)
                .accessibilityAddTraits(.isHeader)
            Text(TripShareText.inviteNote)
                .font(JPFont.footnote)
                .foregroundStyle(WebTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
            if let url = link?.url {
                Text(url.absoluteString)
                    .font(JPFont.footnote.monospacedDigit())
                    .foregroundStyle(WebTheme.text3)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(JPSpace.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WebTheme.surface3, in: RoundedRectangle(cornerRadius: JPRadius.s))
                    .accessibilityIdentifier("tripShare.inviteURL")
                Button { sendByLine(url) } label: {
                    Text(L("LINE で送る", "Send with LINE"))
                        .font(JPFont.bodyEmphasis)
                        .foregroundStyle(WebTheme.accentText)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(WebTheme.accentFill, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tripShare.line")
                HStack(spacing: JPSpace.xs) {
                    TripOutlineButton(title: copied ? L("コピーしました", "Copied") : L("リンクをコピー", "Copy link"), fill: true) {
                        UIPasteboard.general.string = url.absoluteString
                        copied = true
                    }
                    ShareLink(item: url) {
                        Text(L("ほかのアプリ", "Other apps"))
                            .jpOutlineButton(.regular, tone: .plain, fullWidth: true)
                    }
                    .buttonStyle(.plain)
                }
            } else if let failed {
                Text(failed)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.danger)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 48)
            }
            TripOutlineButton(title: Labels.Common.close, fill: true) { dismiss() }
        }
        .padding(JPSpace.gutter)
        .webScreen()
        .presentationDetents([.medium])
        .accessibilityIdentifier("tripShare.inviteSheet")
    }

    /// LINE の「送る相手を選ぶ」を開く（入っていなければ共有のシートと同じく、ほかの道で送ってもらう）
    private func sendByLine(_ url: URL) {
        let text = "\(TripShareText.inviteTitle(title)) \(url.absoluteString)"
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let line = URL(string: "https://line.me/R/msg/text/?\(encoded)") else { return }
        openURL(line)
    }
}

/// 会話（「日程 | 会話」の会話）。DM と同じ吹き出しで、場所を足した通は札で出す
struct TripChatPane: View {
    let planId: String
    let plan: TripPlan
    let members: [TripMember]
    let resolveName: (TripItem) -> String
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var hidden: ModerationStore
    @EnvironmentObject private var connectivity: Connectivity
    @State private var messages: [TripChatMessage] = []
    @State private var phase: Phase = .loading
    @State private var draft = ""
    @State private var sending = false
    @State private var sendError: String?
    @State private var memberList: [TripMember] = []
    @Environment(\.scenePhase) private var scenePhase

    enum Phase: Equatable { case loading, loaded, failed }

    private var everyone: [TripMember] { memberList.isEmpty ? members : memberList }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: JPSpace.xs) {
                        switch phase {
                        case .loading:
                            JPLoadingState(kind: .bubbles)
                        case .failed:
                            ErrorBanner(title: Labels.Common.loadFailed,
                                        message: L("通信を確かめて、もう一度お試しください。", "Check your connection and try again.")) {
                                Task { await reload() }
                            }
                        case .loaded:
                            if visible.isEmpty {
                                Text(L("まだメッセージはありません。行きたい所や時間を話しましょう。",
                                       "No messages yet. Talk about where and when to go."))
                                    .font(JPFont.footnote)
                                    .foregroundStyle(WebTheme.text3)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.top, JPSpace.xl)
                            }
                            ForEach(visible) { message in
                                row(message).id(message.id)
                            }
                        }
                    }
                    .padding(.horizontal, JPSpace.gutter)
                    .padding(.vertical, JPSpace.s)
                }
                .onChange(of: messages.last?.id) { _, last in
                    if let last { withAnimation { proxy.scrollTo(last, anchor: .bottom) } }
                }
            }
            inputBar
        }
        .accessibilityIdentifier("tripShare.chat")
        // 1通の上限（500 字）を越えて打てない（DM の入力欄と同じ・2026-11-12 確かめ役の指摘10）
        .onChange(of: draft) { old, new in
            let kept = TripShareText.limitedDraft(old: old, new: new)
            if kept != new { draft = kept }
        }
        // 開いている間は 15 秒ごとに読み直す（プッシュが届かない端末でも会話が進む）
        .task(id: planId) {
            await reload()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if Task.isCancelled { break }
                if scenePhase == .active, !connectivity.isOffline { await reload(quiet: true) }
            }
        }
    }

    /// ブロックした人の通は出さない（サーバーも外すが、ブロックした直後の手元でも外す）
    private var visible: [TripChatMessage] {
        messages.filter { !hidden.blockedUserIds.contains($0.from) }
    }

    private func name(_ uid: String) -> String {
        guard let m = everyone.first(where: { $0.id == uid }) else { return L("名前未設定さん", "Unnamed") }
        return m.deleted == true ? L("退会したユーザー", "Deleted user") : m.name
    }

    @ViewBuilder
    private func row(_ message: TripChatMessage) -> some View {
        if let event = message.event {
            // 「ひがし茶屋街」「日程に足しました」「1日目」の札（真ん中寄せ・足した人の名前つき）。
            // 「日程に足しました」と「1日目」は余白で分ける（中黒で区切らない・2026-11-12）
            VStack(spacing: 2) {
                Text(name(message.from))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                Text(resolveName(event.item))
                    .font(JPFont.bodyEmphasis)
                    .foregroundStyle(WebTheme.foreground)
                HStack(spacing: 6) {
                    Text(TripShareText.eventAdded)
                        .font(JPFont.caption)
                    Text(TripShareText.eventDay(event.day))
                        .font(JPFont.caption.monospacedDigit())
                }
                .foregroundStyle(WebTheme.accent)
            }
            .padding(.horizontal, JPSpace.m)
            .padding(.vertical, JPSpace.xs)
            .frame(maxWidth: .infinity)
            .background(WebTheme.surface3, in: RoundedRectangle(cornerRadius: JPRadius.m))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("tripShare.event")
        } else if let text = message.text {
            VStack(alignment: message.mine ? .trailing : .leading, spacing: 2) {
                if !message.mine {
                    Text(name(message.from))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                        .padding(.horizontal, JPSpace.xxs)
                }
                DMBubble(text: text, mine: message.mine, time: nil)
            }
            .frame(maxWidth: .infinity, alignment: message.mine ? .trailing : .leading)
        }
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let sendError {
                Text(sendError)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.danger)
            }
            HStack(spacing: JPSpace.xs) {
                TextField(L("メッセージ", "Message"), text: $draft, axis: .vertical)
                    .font(JPFont.body)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .frame(minHeight: DMLook.fieldHeight)
                    .background(WebTheme.surface3, in: RoundedRectangle(cornerRadius: 22))
                    .accessibilityIdentifier("tripShare.field")
                Button { Task { await send() } } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(WebTheme.accentText)
                        .frame(width: DMLook.sendSize, height: DMLook.sendSize)
                        .background(WebTheme.accentFill, in: Circle())
                        .opacity(canSend ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel(L("送る", "Send"))
                .accessibilityIdentifier("tripShare.send")
            }
        }
        .padding(.horizontal, JPSpace.gutter)
        .padding(.vertical, JPSpace.xs)
        .background(WebTheme.background)
    }

    private var canSend: Bool {
        !sending && !connectivity.isOffline && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func reload(quiet: Bool = false) async {
        do {
            let page = try await environment.tripShare.chat(planId: planId)
            messages = page.messages
            memberList = page.members
            phase = .loaded
        } catch {
            if Task.isCancelled { return }
            if !quiet || phase != .loaded { phase = .failed }
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        sendError = nil
        defer { sending = false }
        do {
            let sent = try await environment.tripShare.send(planId: planId, text: text)
            messages.append(sent)
            draft = ""
        } catch {
            // 書いた文は欄に残す（送れなかった文を消さない）
            sendError = (error as? LocalizedError)?.errorDescription ?? L("送れませんでした。もう一度お試しください。", "Couldn't send. Please try again.")
        }
    }
}

/// 受信箱のプランの会話の1行（DM の行と同じ高さ・未読は真鍮の点と太字）
struct TripInboxRow: View {
    let item: TripInboxItem
    var me: String?

    var body: some View {
        HStack(spacing: JPSpace.s) {
            Image(systemName: "map")
                .font(.system(size: 20))
                .foregroundStyle(WebTheme.foreground)
                .frame(width: DMLook.rowAvatar, height: DMLook.rowAvatar)
                .background(WebTheme.surface3, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.title.isEmpty ? L("旅行プラン", "Trip") : item.title)
                        .font(JPFont.body.weight(unread ? .bold : .medium))
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(1)
                    // 題と人数は余白と色で分ける（中黒で区切らない・2026-11-12）
                    Text(TripShareText.memberCount(item.members.count))
                        .font(JPFont.caption.monospacedDigit())
                        .foregroundStyle(WebTheme.text3)
                        .fixedSize()
                }
                Text(TripShareText.inboxExcerpt(item))
                    .jpSystemFont(14, weight: unread ? .medium : .regular)
                    .foregroundStyle(unread ? WebTheme.text : WebTheme.text3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if unread { BrassDot() } else { Color.clear.frame(width: DMLook.dot, height: DMLook.dot) }
        }
        .frame(minHeight: DMLook.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel([unread ? L("未読", "Unread") : nil, item.title, TripShareText.inboxExcerpt(item)]
            .compactMap { $0 }.joined(separator: "、"))
    }

    private var unread: Bool { item.unread > 0 }
}

/// 受信箱からプランの会話を開く（プランの一覧を読んでから詳細を出す）
struct TripShareOpenView: View {
    let planId: String
    @StateObject private var model = TripPlansModel()
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Group {
            if model.plan(planId) != nil {
                TripPlanDetailView(planId: planId, model: model, startTab: .chat)
            } else if model.status == .failed {
                ErrorBanner(title: Labels.Common.loadFailed, message: L("通信を確かめて、もう一度お試しください。", "Check your connection and try again.")) {
                    Task { await model.load(environment: environment) }
                }
            } else if model.status == .loaded {
                ErrorBanner(message: L("プランが見つかりません", "Trip not found"))
            } else {
                JPLoadingState(kind: .rows).padding(.horizontal, JPSpace.gutter)
            }
        }
        .webScreen()
        .task { await model.load(environment: environment) }
    }
}
