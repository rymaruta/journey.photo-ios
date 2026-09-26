import SwiftUI

/// ブロックした人の一覧と解除。
///
/// **解除できる場所が要る。** ブロックだけできて外せないと、
/// 誤って押した人が戻せない。
struct BlockedUsersView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var hidden: ModerationStore
    @State private var users: [FollowUser] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            // 板 45 の説明。**同じ言い方をアプリの他の入口（通報・プロフィール）でも使っている**
            Text(L("ブロックすると、おたがいの投稿・ストーリー・通知が見えなくなります。",
                   "Blocking hides each other's posts, stories and notifications."))
                .font(.caption)
                .foregroundStyle(WebTheme.muted2)
                .listRowBackground(Color.clear)
            if let errorMessage {
                Text(errorMessage).foregroundStyle(WebTheme.danger).font(.callout)
            } else if users.isEmpty && !isLoading {
                Text(L("ブロックしている人はいません", "No one is blocked")).foregroundStyle(.secondary)
            }
            ForEach(users) { user in
                HStack(spacing: 12) {
                    // 板はアイコンと名前でプロフィールへ。**退会した人には導線を出さない**
                    if user.deleted == true {
                        person(user)
                    } else {
                        NavigationLink { UserProfileView(userId: user.id) } label: { person(user) }
                    }
                    Button(L("解除", "Unblock")) {
                        Task { await unblock(user.id) }
                    }
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(minWidth: 44, minHeight: 36)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
                    // 行の中のボタンは borderless にしないと、行のどこを
                    // 押しても反応する
                    .buttonStyle(.borderless)
                    .foregroundStyle(WebTheme.foreground)
                }
            }
        }
        .webScreen()
        .navigationTitle(L("ブロックした人", "Blocked people"))
        .task { await load() }
        .refreshable { await load() }
        .overlay { if isLoading { ProgressView() } }
    }

    /// アイコンと名前（板の @username は、この一覧の応答が持たないので出さない）
    private func person(_ user: FollowUser) -> some View {
        HStack(spacing: 12) {
            RemoteImage(url: UserProfile.profileAssetURL(userId: user.id, suffix: nil, cacheBust: nil))
                .frame(width: 44, height: 44)
                .background(WebTheme.surface)
                .clipShape(Circle())
            Text(user.displayName)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let list = try await environment.moderation.blocks()
            users = list.users
            // **サーバーの一覧で上書きする。** 端末のぶんを足し合わせると、
            // 別の端末で解除したのに「見えないまま」になる
            hidden.replaceBlocked(with: list.blockedIds)
            await apply()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? Labels.Common.loadFailed
        }
    }

    /// 「見せない」を公開一覧の側へ渡し直す。
    private func apply() async {
        await environment.gallery.setHidden(
            userIds: hidden.blockedUserIds,
            photoIds: hidden.reportedPhotoIds
        )
    }

    private func unblock(_ userId: String) async {
        do {
            try await environment.moderation.unblock(userId: userId)
            hidden.unblock(userId)
            await apply()
            users.removeAll { $0.id == userId }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("解除できませんでした", "Couldn't unblock")
        }
    }
}
