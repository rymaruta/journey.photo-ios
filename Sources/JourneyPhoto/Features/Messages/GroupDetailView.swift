import SwiftUI

/// グループの詳しい画面（2026-11-20・札 #582・案の画面 3「人を足す、抜ける」）。会話の見出し・右の丸い i から積む。
///
/// - 上に重ねた顔 72・名前（明朝 20）・「名前を付ける」（誰でも変えられる・変えた人の名前が会話に残る）
/// - 「人を足す」（誰でも・選ぶ画面は新しいメッセージと同じ `DMNewMessageView`）。足せるのは足す人がフォローしている人
/// - メンバー（作った人に「作った人」の札・自分がブロックした人に「ブロック中」）と招待中の人
/// - **外せるのは作った人だけ**: 人の行を左に払うと「外す」（確かめは出す・外された人は自分で戻れない）
/// - 知らせ（このグループだけ止められる・既定はオン・設定の画面には足さない）・通報・グループを抜ける（確かめは出す）
///
/// 色: 危険の行は板の danger（`WebTheme.danger`）。確かめのダイアログは系統の部品のまま（板の決まり）
struct GroupDetailView: View {

    let groupId: String
    /// 会話の画面が読めていた詳しい中身（読み直すまで出す）
    let seed: GroupMembership?
    let info: GroupInfo?
    /// 名前を引く表（招待した人など）
    var names: [String: String] = [:]
    /// 名前・人・知らせが変わった（会話の画面の見出しを合わせる）
    let onChange: (GroupMembership) -> Void
    /// 抜けた
    let onLeft: () -> Void

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var connectivity: Connectivity

    @State private var membership: GroupMembership?
    @State private var failed = false
    @State private var working = false
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showAdd = false
    @State private var confirmLeave = false
    @State private var removeTarget: GroupMember?
    @State private var showReport = false
    @State private var profileTarget: String?

    /// 開いている間に外された・グループが無くなった（読み直しでメンバーでなくなった）。操作を出さない
    @State private var gone = false

    private var current: GroupMembership? { gone ? nil : (membership ?? seed) }
    private var group: GroupInfo? { current?.group ?? info }

    var body: some View {
        List {
            headerSection
                .profileListRow()
            if let current {
                if current.seatsLeft > 0 {
                    addRow.profileListRow(divider: true)
                }
                ForEach(current.members) { member in
                    memberRow(member, owner: current.isOwner)
                        .profileListRow(divider: true)
                        .swipeActions(allowsFullSwipe: false) {
                            if current.isOwner && member.id != auth.userId {
                                Button(role: .destructive) { removeTarget = member } label: {
                                    Label(L("外す", "Remove"), systemImage: "person.badge.minus")
                                }
                            }
                        }
                }
                ForEach(current.invited) { invitee in
                    invitedRow(invitee, owner: current.isOwner)
                        .profileListRow(divider: true)
                        .swipeActions(allowsFullSwipe: false) {
                            if current.isOwner {
                                Button(role: .destructive) {
                                    Task { await removeInvite(invitee) }
                                } label: {
                                    Label(L("招待を取り消す", "Cancel invite"), systemImage: "xmark")
                                }
                            }
                        }
                }
                muteRow(current).profileListRow(divider: true)
                reportRow.profileListRow(divider: true)
                leaveRow.profileListRow(divider: true)
            } else if gone {
                // 外されたら操作を出さず、外された形にする（自分で戻れない・会話の画面は送れない形になる）
                EmptyState(icon: nil, title: L("グループから外されました", "You were removed from this group"),
                           message: L("外されるまでの話は会話の画面で読めます。", "You can still read the chat up to now."))
                    .accessibilityIdentifier("group.detail.gone")
                    .profileListRow()
            } else if failed {
                ErrorBanner(title: Labels.Common.loadFailed, message: DMText.loadFailedMessage) {
                    Task { await load() }
                }
                .profileListRow()
            } else {
                JPLoadingState(kind: .people).profileListRow()
            }
            if let errorMessage {
                DMNoteRow(text: errorMessage, error: true).profileListRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .webScreen()
        .navigationTitle(L("グループ", "Group"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if let notice {
                DMActionToast(text: notice)
                    .padding(.top, JPSpace.xs)
                    .task(id: notice) {
                        try? await Task.sleep(for: DMActionToast.duration)
                        if !Task.isCancelled, self.notice == notice { self.notice = nil }
                    }
            }
        }
        .navigationDestination(item: $profileTarget) { userId in
            UserProfileView(userId: userId)
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                if let current {
                    DMNewMessageView(mode: .add(present: current.present, seatsLeft: current.seatsLeft),
                                     groupId: groupId,
                                     onPick: { _ in },
                                     onGroup: { ready in
                                         showAdd = false
                                         if let m = ready.change.detail.membership { apply(m) }
                                         notice = ready.notice
                                     })
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
                    }
                }
            }
        }
        .alert(group?.name == nil ? L("名前を付ける", "Name the group") : L("名前を変える", "Rename"), isPresented: $showRename) {
            TextField(L("グループの名前", "Group name"), text: $renameText)
            Button(Labels.Common.save) {
                let name = renameText
                Task { await rename(name) }
            }
            Button(Labels.Common.cancel, role: .cancel) {}
        } message: {
            Text(L("名前はメンバー全員に見えます。空にすると名前を外します。", "Everyone in the group sees the name. Leave it empty to remove it."))
        }
        .alert(L("グループを抜けますか", "Leave this group?"), isPresented: $confirmLeave) {
            Button(L("抜ける", "Leave"), role: .destructive) { Task { await leave() } }
            Button(Labels.Common.cancel, role: .cancel) {}
        } message: {
            Text(L("自分では戻れません。会話は受信箱から消えます", "You can't rejoin by yourself. The chat is removed from your inbox."))
        }
        .alert(removeTarget.map { L("\($0.name) さんを外しますか", "Remove \($0.name)?") } ?? "",
               isPresented: Binding(get: { removeTarget != nil }, set: { if !$0 { removeTarget = nil } }),
               presenting: removeTarget) { target in
            Button(L("外す", "Remove"), role: .destructive) { Task { await remove(target) } }
            Button(Labels.Common.cancel, role: .cancel) {}
        } message: { _ in
            Text(L("外された人は、自分では戻れません。外されるまでの話は読めます。",
                   "They can't rejoin by themselves. They can still read the chat up to now."))
        }
        .sheet(isPresented: $showReport) {
            ReportSheet(photoId: "", ownerId: nil,
                        group: .init(groupId: groupId, messageId: nil, authorName: nil, text: nil))
        }
        .task(id: groupId) { await load() }
        .accessibilityIdentifier("group.detail")
    }

    // MARK: - 上

    private var headerSection: some View {
        VStack(spacing: 6) {
            GroupFaces(faces: group?.faces ?? [], size: GroupLook.largeFaces)
            Text(group.map(GroupText.title) ?? "")
                .font(JPFont.display(20, relativeTo: .title3))
                .foregroundStyle(WebTheme.text)
                .multilineTextAlignment(.center)
            if let count = group?.memberCount, count > 0 {
                Text(GroupText.memberCount(count))
                    .font(JPFont.caption.monospacedDigit())
                    .foregroundStyle(WebTheme.text3)
            }
            Button {
                renameText = group?.name ?? ""
                showRename = true
            } label: {
                Text(group?.name == nil ? L("名前を付ける", "Name the group") : L("名前を変える", "Rename"))
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.accent)
                    .frame(minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(working || connectivity.isOffline || current == nil)
            .accessibilityIdentifier("group.rename")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, JPSpace.xs)
        .padding(.bottom, JPSpace.xs)
    }

    // MARK: - 行

    private var addRow: some View {
        Button { showAdd = true } label: {
            HStack(spacing: JPSpace.s) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WebTheme.text2)
                    .frame(width: GroupLook.addCircle, height: GroupLook.addCircle)
                    .overlay(Circle().strokeBorder(WebTheme.outline, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                Text(L("人を足す", "Add people"))
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.text)
                Spacer(minLength: 0)
            }
            .frame(minHeight: GroupLook.infoRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(connectivity.isOffline)
        .accessibilityIdentifier("group.add")
    }

    private func memberRow(_ member: GroupMember, owner: Bool) -> some View {
        let isMe = member.id == auth.userId
        return Button { if !isMe { profileTarget = member.id } } label: {
            HStack(spacing: JPSpace.s) {
                DMAvatar(userId: member.id, size: GroupLook.addCircle)
                Text(isMe ? L("あなた", "You") : DMText.name(member.name, deleted: false))
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if member.owner { tag(L("作った人", "Creator")) }
                if member.blocked { tag(L("ブロック中", "Blocked")) }
            }
            .frame(minHeight: GroupLook.infoRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: L("外す", "Remove")) {
            if owner && !isMe { removeTarget = member }
        }
        .accessibilityIdentifier("group.member")
    }

    private func invitedRow(_ invitee: GroupInvitee, owner: Bool) -> some View {
        HStack(spacing: JPSpace.s) {
            DMAvatar(userId: invitee.id, size: GroupLook.addCircle)
                .opacity(0.6)
            Text(DMText.name(invitee.name, deleted: false))
                .font(JPFont.body)
                .foregroundStyle(WebTheme.text2)
                .lineLimit(1)
            Spacer(minLength: 0)
            tag(L("招待中", "Invited"))
        }
        .frame(minHeight: GroupLook.infoRowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("group.invitee")
    }

    /// 行の右の小さな札（12・text-3・白 14% の縁・角 8）
    private func tag(_ text: String) -> some View {
        Text(text)
            .font(JPFont.caption)
            .foregroundStyle(WebTheme.text3)
            .padding(.horizontal, 6)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(WebTheme.line, lineWidth: JPStroke.hairline))
    }

    private func muteRow(_ current: GroupMembership) -> some View {
        Toggle(isOn: Binding(get: { !current.muted }, set: { on in Task { await setMuted(!on) } })) {
            Text(L("知らせ", "Notifications"))
                .font(JPFont.body)
                .foregroundStyle(WebTheme.text)
        }
        // 軌道は暗い真鍮（板の入切の行と同じ・`JPToggleRow`）
        .tint(WebTheme.accentDeep)
        .disabled(working || connectivity.isOffline)
        .frame(minHeight: GroupLook.infoRowHeight)
        .accessibilityHint(L("このグループの知らせだけを止めます", "Mutes notifications for this group only"))
        .accessibilityIdentifier("group.mute")
    }

    private var reportRow: some View {
        Button { showReport = true } label: {
            Text(L("通報する", "Report"))
                .font(JPFont.body)
                .foregroundStyle(WebTheme.text)
                .frame(maxWidth: .infinity, minHeight: GroupLook.infoRowHeight, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("group.report")
    }

    private var leaveRow: some View {
        Button { confirmLeave = true } label: {
            Text(L("グループを抜ける", "Leave group"))
                .font(JPFont.body)
                .foregroundStyle(WebTheme.danger)
                .frame(maxWidth: .infinity, minHeight: GroupLook.infoRowHeight, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(working || connectivity.isOffline)
        .accessibilityIdentifier("group.leave")
    }

    // MARK: - 操作

    private func load() async {
        do {
            let detail = try await environment.groups.detail(groupId)
            guard let m = detail.membership else {
                // メンバーではなくなった（外された）: 外された形に替える
                gone = true
                return
            }
            membership = m
            failed = false
            gone = false
        } catch let refused as DMService.Refused where refused.status == 404 {
            // グループが無くなった・見られない
            gone = true
        } catch {
            if current == nil { failed = true }
        }
    }

    private func apply(_ m: GroupMembership) {
        membership = m
        onChange(m)
    }

    private func rename(_ raw: String) async {
        let trimmed = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(GroupRules.nameMax))
        guard !working else { return }
        working = true
        defer { working = false }
        errorMessage = nil
        do {
            let detail = try await environment.groups.rename(groupId, to: trimmed.isEmpty ? nil : trimmed)
            if let m = detail.membership { apply(m) }
        } catch {
            errorMessage = GroupText.message(for: error, fallback: L("名前を変えられませんでした", "Couldn't rename"))
        }
    }

    private func setMuted(_ muted: Bool) async {
        guard !working else { return }
        working = true
        defer { working = false }
        errorMessage = nil
        do {
            let detail = try await environment.groups.setMuted(groupId, muted)
            if let m = detail.membership { apply(m) }
        } catch {
            errorMessage = GroupText.message(for: error, fallback: L("知らせを変えられませんでした", "Couldn't change notifications"))
        }
    }

    private func remove(_ member: GroupMember) async {
        guard !working else { return }
        working = true
        defer { working = false }
        errorMessage = nil
        do {
            try await environment.groups.removeMember(groupId, userId: member.id)
            await load()
            if let membership { onChange(membership) }
        } catch {
            errorMessage = GroupText.message(for: error, fallback: L("外せませんでした", "Couldn't remove"))
        }
    }

    private func removeInvite(_ invitee: GroupInvitee) async {
        guard !working else { return }
        working = true
        defer { working = false }
        errorMessage = nil
        do {
            try await environment.groups.removeMember(groupId, userId: invitee.id)
            await load()
            if let membership { onChange(membership) }
        } catch {
            errorMessage = GroupText.message(for: error, fallback: L("取り消せませんでした", "Couldn't cancel"))
        }
    }

    private func leave() async {
        guard let me = auth.userId, !working else { return }
        working = true
        defer { working = false }
        errorMessage = nil
        do {
            try await environment.groups.removeMember(groupId, userId: me)
            onLeft()
        } catch {
            errorMessage = GroupText.message(for: error, fallback: L("抜けられませんでした", "Couldn't leave"))
        }
    }
}
