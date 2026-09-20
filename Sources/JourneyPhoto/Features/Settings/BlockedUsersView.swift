import SwiftUI

/// ブロックした人の一覧と解除。
///
/// **解除できる場所が要る。** ブロックだけできて外せないと、
/// 誤って押した人が戻せない。
struct BlockedUsersView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var moderation: ModerationStore
    @State private var users: [FollowUser] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            } else if users.isEmpty && !isLoading {
                Text("ブロックしている人はいません").foregroundStyle(.secondary)
            }
            ForEach(users) { user in
                HStack {
                    Text(user.displayName)
                    Spacer()
                    Button("解除") {
                        Task { await unblock(user.id) }
                    }
                    // 行の中のボタンは borderless にしないと、行のどこを
                    // 押しても反応する
                    .buttonStyle(.borderless)
                }
            }
        }
        .navigationTitle("ブロックした人")
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
            moderation.replaceBlocked(with: list.blockedIds)
            await apply()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "読み込めませんでした"
        }
    }

    /// 「見せない」を公開一覧の側へ渡し直す。
    private func apply() async {
        await environment.gallery.setHidden(
            userIds: moderation.blockedUserIds,
            photoIds: moderation.reportedPhotoIds
        )
    }

    private func unblock(_ userId: String) async {
        do {
            try await environment.moderation.unblock(userId: userId)
            moderation.unblock(userId)
            await apply()
            users.removeAll { $0.id == userId }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "解除できませんでした"
        }
    }
}
