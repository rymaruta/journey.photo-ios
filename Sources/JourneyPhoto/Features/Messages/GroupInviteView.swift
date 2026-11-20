import SwiftUI

/// グループの招待（2026-11-20・札 #582・案の画面 6「知らない人からの招待」）。リクエストの一覧の招待の行から積む。
///
/// 入れた人をフォローしていない人には、グループは「招待」でリクエストの棚に入る（知らせは出さない）。
/// **参加するまで、話は1通も見えない**（見えるのはグループの名前・入れた人・人数だけ・写真も見えない）。
/// - 「参加する」は写真の無い画面の主ボタン＝真鍮の塗りに墨（DM の「承認」と同じ）。押すとそのまま会話を開く
/// - 「断る」は線のボタン。断ると、同じグループからは招待し直せない（相手には知らせない）
/// - 「…」からブロック（入れた人。ブロックの間柄の人からの招待は届かなくなる）
struct GroupInviteView: View {

    let invite: GroupInvite

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var hidden: ModerationStore
    @EnvironmentObject private var connectivity: Connectivity
    @EnvironmentObject private var store: DMInboxStore
    @Environment(\.dismiss) private var dismiss

    @State private var working = false
    @State private var errorMessage: String?
    @State private var showBlock = false
    /// 参加できた: この画面のまま会話に替える（積みを入れ替えない・戻ると一覧）
    @State private var joined = false

    var body: some View {
        if joined {
            GroupConversationView(groupId: invite.id, seed: invite.info, onLeft: { dismiss() })
        } else {
            inviteBody
        }
    }

    private var inviteBody: some View {
        ScrollView {
            VStack(spacing: JPSpace.s) {
                card
                Text(L("参加するまで、話は見えません", "You can't see the chat until you join"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, JPSpace.l)
                if let errorMessage {
                    DMNoteRow(text: errorMessage, error: true)
                        .accessibilityIdentifier("group.invite.error")
                }
            }
            .padding(.horizontal, JPSpace.gutter)
            .padding(.top, JPSpace.m)
        }
        .webScreen()
        .navigationTitle(L("招待", "Invite"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) { showBlock = true } label: {
                        Label(L("\(invite.invitedBy.name) さんをブロック", "Block \(invite.invitedBy.name)"), systemImage: "hand.raised")
                    }
                } label: {
                    Image(systemName: "ellipsis").webToolbarIcon().appHeaderHitArea()
                }
                .accessibilityLabel(L("その他の操作", "More"))
                .accessibilityIdentifier("group.invite.more")
            }
        }
        .alert(DMBlockText.title(invite.invitedBy.name), isPresented: $showBlock) {
            Button(L("ブロック", "Block"), role: .destructive) { Task { await block() } }
            Button(Labels.Common.cancel, role: .cancel) {}
        } message: {
            Text(DMBlockText.message)
        }
        .accessibilityIdentifier("group.invite")
    }

    /// 招待の札（surface-1 の地・白 8% の縁・角 16・内側 16。重ねた顔 72・明朝 19 の名前・入れた人と人数 13）
    private var card: some View {
        VStack(spacing: 10) {
            GroupFaces(faces: invite.info.faces, size: GroupLook.largeFaces)
            Text(GroupText.title(invite.info))
                .font(JPFont.rowTitle)
                .foregroundStyle(WebTheme.text)
                .multilineTextAlignment(.center)
            VStack(spacing: 2) {
                Text(GroupText.invitedLine(by: invite.invitedBy.name))
                Text(GroupText.groupSize(invite.info.memberCount))
                    .font(JPFont.footnote.monospacedDigit())
            }
            .font(JPFont.footnote)
            .foregroundStyle(WebTheme.text2)
            .multilineTextAlignment(.center)
            HStack(spacing: JPSpace.xs) {
                Button { Task { await decline() } } label: {
                    Text(L("断る", "Decline")).jpOutlineButton(.regular, tone: .plain, fullWidth: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("group.invite.decline")
                Button { Task { await join() } } label: {
                    HStack(spacing: JPSpace.xs) {
                        if working { ProgressView().tint(WebTheme.accentText) }
                        Text(L("参加する", "Join"))
                    }
                    .font(JPFont.bodyEmphasis)
                    .foregroundStyle(WebTheme.accentText)
                    .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                    .background(WebTheme.accentFill, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("group.invite.join")
            }
            .disabled(working || connectivity.isOffline)
            .padding(.top, JPSpace.xxs)
        }
        .padding(JPSpace.m)
        .frame(maxWidth: .infinity)
        .jpCardFace()
        .accessibilityElement(children: .contain)
    }

    private func join() async {
        guard !working else { return }
        working = true
        defer { working = false }
        errorMessage = nil
        do {
            try await environment.groups.join(invite.id)
            await store.refreshGroups(service: environment.groups, owner: auth.userId)
            joined = true
        } catch {
            errorMessage = GroupText.message(for: error, fallback: L("参加できませんでした", "Couldn't join"))
        }
    }

    private func decline() async {
        guard !working else { return }
        working = true
        defer { working = false }
        errorMessage = nil
        do {
            try await environment.groups.decline(invite.id)
            store.applyGroups { $0.removing(invite.id) }
            dismiss()
        } catch {
            errorMessage = GroupText.message(for: error, fallback: L("断れませんでした", "Couldn't decline"))
        }
    }

    private func block() async {
        errorMessage = nil
        do {
            try await hidden.blockAndHide(invite.invitedBy.id, environment: environment)
            store.applyGroups { $0.removing(invite.id) }
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("ブロックできませんでした", "Couldn't block")
        }
    }
}
