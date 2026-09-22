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
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            } else if users.isEmpty && !isLoading {
                Text(L("ブロックしている人はいません", "No one is blocked")).foregroundStyle(.secondary)
            }
            ForEach(users) { user in
                HStack {
                    Text(user.displayName)
                    Spacer()
                    Button(L("解除", "Unblock")) {
                        Task { await unblock(user.id) }
                    }
                    // 行の中のボタンは borderless にしないと、行のどこを
                    // 押しても反応する
                    .buttonStyle(.borderless)
                }
            }
        }
        .webScreen()
        .navigationTitle(L("ブロックした人", "Blocked people"))
        .task { await load() }
        .refreshable { await load() }
        .overlay { if isLoading { ProgressView() } }
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
