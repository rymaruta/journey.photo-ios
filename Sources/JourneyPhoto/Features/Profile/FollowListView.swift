import SwiftUI

/// フォロー中 / フォロワーの一覧。
///
/// **並びはアーティファクト 34 の「フォロー一覧」**（2026-09-26）:
/// 題はその人の名前、下に「フォロワー N ／ フォロー中 N」の切り替え、
/// 行はアイコン・名前・フォローの札。板の @username は、この一覧の応答が
/// 持たないので出さない。
///
/// **呼び出し方は変えていない**（`userId` と最初に開く `kind`）。
/// マイページと人のプロフィールの2か所から開く。
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
    @EnvironmentObject private var auth: AuthStore

    /// 切り替えで選んだ方。**nil のあいだは開いたときの `kind`**
    @State private var picked: Kind?
    @State private var lists: [Kind: SocialService.FollowList] = [:]
    /// 題に出す名前（取れなければ一覧の種類を題にする）
    @State private var ownerName: String?
    /// 自分がフォローしている人。**取れたときだけ札を出す**
    /// ——取れていないのに「フォローする」と出すと、既にフォロー中の人を押し直させる
    @State private var myFollowing: Set<String>?
    /// いま送っている相手（二度押しで2回投げない）
    @State private var working: Set<String> = []
    @State private var unfollowTarget: FollowUser?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var current: Kind { picked ?? kind }
    private var users: [FollowUser] { lists[current]?.users ?? [] }
    private var total: Int { lists[current]?.total ?? 0 }

    var body: some View {
        List {
            tabs
                .listRowBackground(Color.clear)

            if let errorMessage {
                Text(errorMessage).foregroundStyle(WebTheme.danger).font(.callout)
            } else if users.isEmpty && !isLoading {
                Text(L("まだいません", "No one yet")).foregroundStyle(.secondary)
            }

            ForEach(users) { user in
                row(user)
            }

            // **一覧の長さと数え札は一致しない。** 50人で切ったぶん・一覧が
            // 追いついていないぶん・ブロックで落としたぶんがある
            // （api-user/src/follow.ts の注記）。黙って食い違わせない
            if total > users.count {
                Text(L("全 \(total) 人のうち \(users.count) 人を表示しています", "Showing \(users.count) of \(total)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .webScreen()
        .navigationTitle(ownerName ?? current.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading && lists.isEmpty { ProgressView() } }
        .unfollowConfirmation(isPresented: Binding(get: { unfollowTarget != nil },
                                                   set: { if !$0 { unfollowTarget = nil } })) {
            if let target = unfollowTarget {
                Task { await setFollowing(target.id, to: false) }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    /// 「フォロワー N ／ フォロー中 N」（板の下線の切り替え）
    private var tabs: some View {
        HStack(spacing: 0) {
            tab(.followers)
            tab(.following)
        }
    }

    private func tab(_ which: Kind) -> some View {
        let selected = current == which
        let count = lists[which]?.total
        return Button {
            picked = which
        } label: {
            VStack(spacing: 8) {
                Text(count.map { "\(which.title) \($0)" } ?? which.title)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? WebTheme.foreground : WebTheme.muted2)
                Rectangle()
                    .fill(selected ? WebTheme.foreground : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        // 同じ行に2つ並ぶので borderless（行全体が1つのボタンにならないように）
        .buttonStyle(.borderless)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func row(_ user: FollowUser) -> some View {
        HStack(spacing: 12) {
            if user.deleted == true {
                // 退会した人にはプロフィールへの導線も札も出さない
                person(user).foregroundStyle(.secondary)
            } else {
                NavigationLink { UserProfileView(userId: user.id) } label: { person(user) }
                followButton(user)
            }
        }
    }

    private func person(_ user: FollowUser) -> some View {
        HStack(spacing: 12) {
            RemoteImage(url: user.deleted == true ? nil
                        : UserProfile.profileAssetURL(userId: user.id, suffix: nil, cacheBust: nil))
                .frame(width: 44, height: 44)
                .background(WebTheme.surface)
                .clipShape(Circle())
            Text(user.displayName)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
        }
    }

    /// 「フォロー中」（枠線）／「フォローする」（白地）。**自分と、フォロー状態が
    /// 分からないときは出さない**
    @ViewBuilder
    private func followButton(_ user: FollowUser) -> some View {
        if let myFollowing, let me = auth.userId, user.id != me {
            let isFollowing = myFollowing.contains(user.id)
            Button {
                if isFollowing {
                    // 外すときだけ確認を挟む（`unfollowConfirmation`）
                    unfollowTarget = user
                } else {
                    Task { await setFollowing(user.id, to: true) }
                }
            } label: {
                // 余白と枠は中身の側に置く（外に付けると押せるのは文字だけ）
                Text(isFollowing ? L("フォロー中", "Following") : L("フォローする", "Follow"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isFollowing ? WebTheme.foreground : WebTheme.accentText)
                    .padding(.horizontal, 14)
                    .frame(minWidth: 44, minHeight: 36)
                    .background(isFollowing ? Color.clear : WebTheme.accentBackground, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(isFollowing ? 0.28 : 0), lineWidth: 1))
                    .contentShape(Capsule())
            }
            // 行の中のボタンは borderless にしないと、行のどこを押しても反応する
            .buttonStyle(.borderless)
            .disabled(working.contains(user.id))
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        // **切り替えの数を出すので、両方を一度に取る**
        async let followersList = environment.social.followers(userId: userId)
        async let followingList = environment.social.following(userId: userId)
        async let owner = try? environment.profiles.publicProfile(userId: userId)
        do {
            let (followers, following) = try await (followersList, followingList)
            lists = [.followers: followers, .following: following]
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? Labels.Common.loadFailed
        }
        // `if let x = await …` は手元の構文の検査が読めないので、先に受けてから見る
        let ownerProfile = await owner
        if let name = ownerProfile?.displayName, !name.isEmpty {
            ownerName = name
        }
        if auth.userId != nil {
            let ids = try? await environment.social.myFollowingIds()
            if let ids { myFollowing = Set(ids) }
        }
    }

    private func setFollowing(_ id: String, to follow: Bool) async {
        guard !working.contains(id) else { return }
        working.insert(id)
        defer { working.remove(id) }
        do {
            let result = follow
                ? try await environment.social.follow(userId: id)
                : try await environment.social.unfollow(userId: id)
            // **返ってきた状態を使う。** 自分で決めない
            if result.following {
                myFollowing?.insert(id)
            } else {
                myFollowing?.remove(id)
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? L("うまくいきませんでした", "That didn't work")
        }
    }
}
