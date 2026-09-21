import SwiftUI

/// フォロー中 / フォロワーの一覧。
struct FollowListView: View {

    enum Kind {
        case following, followers

        var title: String {
            switch self {
            case .following: return L("フォロー中", "Following")
            case .followers: return L("フォロワー", "Followers")
            }
        }
    }

    let userId: String
    let kind: Kind

    @EnvironmentObject private var environment: AppEnvironment
    @State private var users: [FollowUser] = []
    @State private var total = 0
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            } else if users.isEmpty && !isLoading {
                Text(L("まだいません", "No one yet")).foregroundStyle(.secondary)
            }

            ForEach(users) { user in
                if user.deleted == true {
                    // 退会した人にはプロフィールへの導線を出さない
                    Text(user.displayName).foregroundStyle(.secondary)
                } else {
                    NavigationLink {
                        UserProfileView(userId: user.id)
                    } label: {
                        Text(user.displayName)
                    }
                }
            }

            // **一覧の長さと数え札は一致しない。** 50人で切ったぶん・一覧が
            // 追いついていないぶん・ブロックで落としたぶんがある
            // （api-user/src/follow.ts の注記）。黙って食い違わせない
            if total > users.count {
                Text(L("全 \(total) 人のうち \(users.count) 人を表示しています", "Showing \(users.count) of \(total)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let list = kind == .following
                ? try await environment.social.following(userId: userId)
                : try await environment.social.followers(userId: userId)
            users = list.users
            total = list.total
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? Labels.Common.loadFailed
        }
    }
}
