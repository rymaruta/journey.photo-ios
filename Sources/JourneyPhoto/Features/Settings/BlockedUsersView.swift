import SwiftUI

/// ブロックした人の一覧と解除。
///
/// **解除できる場所が要る。** ブロックだけできて外せないと、
/// 誤って押した人が戻せない。
struct BlockedUsersView: View {

    @EnvironmentObject private var environment: AppEnvironment
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
                    .buttonStyle(.bordered)
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
            users = try await environment.moderation.blocks().users
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "読み込めませんでした"
        }
    }

    private func unblock(_ userId: String) async {
        do {
            try await environment.moderation.unblock(userId: userId)
            users.removeAll { $0.id == userId }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "解除できませんでした"
        }
    }
}
