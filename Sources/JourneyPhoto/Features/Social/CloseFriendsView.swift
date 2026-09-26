import SwiftUI

/// 「親しい友達」を選ぶ（モック4-7 の3つ目の宛先）。
///
/// **相手には知らせない。** 入れたことも外したことも通知しない——
/// 知らせると「外された」が分かってしまう。画面にもそう書く。
///
/// 選ぶ先は**自分がフォローしている人**。知らない人を入れる口は作らない
/// （探して入れる形にすると、覚えのない相手が並ぶ画面になる）。
///
/// ただし**既に選んでいる人は、フォロー中に居なくても並べる**
/// （`CloseFriendsRows`）。並べないと外せない。
struct CloseFriendsView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore

    @State private var following: [FollowUser] = []
    /// 選んでいるが、フォロー中の一覧に居ない人（外したい人が居る場所）
    @State private var others: [FollowUser] = []
    @State private var chosen: Set<String> = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// いま送っている相手（二度押しで2回投げない）
    @State private var working: Set<String> = []

    var body: some View {
        List {
            Section {
                Text(L("選んだ人だけがストーリーを見られます。相手には知らせません。",
                       "Only people you pick can see it. They aren't told."))
                    .font(.footnote)
                    .foregroundStyle(WebTheme.muted2)
            }
            .listRowBackground(Color.clear)

            if let errorMessage {
                Section {
                    ErrorBanner(message: errorMessage) { Task { await load() } }
                }
                .listRowBackground(Color.clear)
            } else if isLoading {
                Section { ProgressView().frame(maxWidth: .infinity) }
                    .listRowBackground(Color.clear)
            } else if following.isEmpty && others.isEmpty {
                Section {
                    // **「まだ誰もいない」と「読めなかった」を分ける**
                    Text(L("フォローしている人がまだいません。フォローすると、ここから選べます。",
                           "You're not following anyone yet."))
                        .font(.subheadline)
                        .foregroundStyle(WebTheme.muted2)
                }
                .listRowBackground(Color.clear)
            } else {
                if !others.isEmpty {
                    Section {
                        ForEach(others) { user in
                            row(user)
                        }
                    } header: {
                        Text(L("フォロー中の一覧に出ない人", "Not in your following list"))
                    } footer: {
                        Text(L("フォローを外した人などです。星を外すと、ストーリーが見えなくなります。",
                               "People you unfollowed, for example. Remove the star to hide your stories from them."))
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(following) { user in
                        row(user)
                    }
                } header: {
                    Text(L("選んだ人 \(chosen.count)", "\(chosen.count) picked"))
                }
                .listRowBackground(Color.clear)
            }
        }
        .webScreen()
        .navigationTitle(L("親しい友達", "Close friends"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func row(_ user: FollowUser) -> some View {
        let picked = chosen.contains(user.id)
        return Button {
            Task { await toggle(user.id) }
        } label: {
            HStack(spacing: 12) {
                RemoteImage(url: UserProfile.profileAssetURL(userId: user.id, suffix: nil, cacheBust: nil),
                            placeholderSymbol: "person.crop.circle.fill")
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                Text(user.displayName)
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.foreground)
                Spacer()
                Image(systemName: picked ? "star.fill" : "star")
                    .foregroundStyle(picked ? WebTheme.accent : WebTheme.faint)
            }
            .frame(minHeight: WebTheme.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(working.contains(user.id))
        .opacity(working.contains(user.id) ? 0.5 : 1)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        guard let me = auth.userId else { return }
        let list = try? await environment.social.following(userId: me)
        let ids = try? await environment.social.closeFriendIds()
        // **どちらかが引けなければ選べない。** 一覧だけ出すと、選んでいる人が
        // 「選んでいない」に見え、フォロー外の人は並ばない＝外せない
        guard let list, let ids else {
            errorMessage = Labels.Common.loadFailed
            return
        }
        let rows = CloseFriendsRows.split(following: list.users, chosen: ids)
        following = rows.following
        chosen = Set(ids)
        others = await names(of: rows.others)
    }

    /// フォロー外の人の名前。**引けなくても行は出す**（名前より外せることが先）
    private func names(of ids: [String]) async -> [FollowUser] {
        let profiles = environment.profiles
        let found = await withTaskGroup(of: (String, String?).self) { group in
            for id in ids {
                group.addTask {
                    let profile = try? await profiles.publicProfile(userId: id)
                    return (id, profile?.displayName ?? profile?.username)
                }
            }
            var names: [String: String] = [:]
            for await (id, name) in group {
                if let name { names[id] = name }
            }
            return names
        }
        return ids.map { FollowUser(id: $0, name: found[$0], deleted: nil) }
    }

    /// **返ってきた状態を使う。** 自分で反転すると、失敗した回に
    /// 画面だけ選ばれたことになる
    private func toggle(_ userId: String) async {
        guard !working.contains(userId) else { return }
        working.insert(userId)
        defer { working.remove(userId) }
        let wanted = !chosen.contains(userId)
        guard let now = try? await environment.social.setCloseFriend(userId: userId, wanted: wanted) else {
            errorMessage = L("保存できませんでした", "Couldn't save")
            return
        }
        if now { chosen.insert(userId) } else { chosen.remove(userId) }
    }
}
