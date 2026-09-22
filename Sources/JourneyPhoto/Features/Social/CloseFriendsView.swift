import SwiftUI

/// 「親しい友達」を選ぶ（モック4-7 の3つ目の宛先）。
///
/// **相手には知らせない。** 入れたことも外したことも通知しない——
/// 知らせると「外された」が分かってしまう。画面にもそう書く。
///
/// 選ぶ先は**自分がフォローしている人**。知らない人を入れる口は作らない
/// （探して入れる形にすると、覚えのない相手が並ぶ画面になる）。
struct CloseFriendsView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore

    @State private var following: [FollowUser] = []
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
            } else if following.isEmpty {
                Section {
                    // **「まだ誰もいない」と「読めなかった」を分ける**
                    Text(L("フォローしている人がまだいません。フォローすると、ここから選べます。",
                           "You're not following anyone yet."))
                        .font(.subheadline)
                        .foregroundStyle(WebTheme.muted2)
                }
                .listRowBackground(Color.clear)
            } else {
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
                    .foregroundStyle(picked ? Color.yellow : WebTheme.faint)
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
        // **一覧が引けなければ選べない。** 印だけ出すと、押した結果が
        // どこにも残らない画面になる
        guard let list else {
            errorMessage = Labels.Common.loadFailed
            return
        }
        following = list.users
        chosen = Set(ids ?? [])
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
