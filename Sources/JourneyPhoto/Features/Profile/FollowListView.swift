import SwiftUI

/// フォロー中 / フォロワーの一覧。
///
/// **並びはアーティファクト 34 の「フォロー一覧」**（2026-09-26）:
/// 題はその人の名前、下に「フォロワー N ／ フォロー中 N」の切り替え、
/// 行はアイコン・名前と @ユーザー名・フォローの札。@ユーザー名は一覧の応答が
/// 各行に持つ（2026-09-26 から）。無い人・退会した人は名前だけ（`PersonNameLines`）。
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
    @EnvironmentObject private var hidden: ModerationStore

    /// 切り替えで選んだ方。**nil のあいだは開いたときの `kind`**
    @State private var picked: Kind?
    @State private var lists: [Kind: SocialService.FollowList] = [:]
    /// 題に出す名前（取れなければ一覧の種類を題にする）
    @State private var ownerName: String?
    /// 自分がフォローしている人。**取れたときだけ札を出す**
    /// ——取れていないのに「フォローする」と出すと、既にフォロー中の人を押し直させる
    @State private var myFollowing: Set<String>?
    /// `myFollowing` を読んだときの人
    @State private var loadedFor: String?
    /// 一度出たか（戻ってきた回だけ読み直す）
    @State private var appeared = false
    /// この画面でフォローを押した回数（読み直しの古い答えで上書きしない目印）
    @State private var followEdits = 0
    /// いま送っている相手（二度押しで2回投げない）
    @State private var working: Set<String> = []
    /// 外す確認。**出すかどうかと相手は別々に持つ**——1つの Optional で兼ねると、
    /// 閉じる合図で相手が先に nil になり「外す」が黙って効かない（`AlbumsView` の注記と同じ）
    @State private var showUnfollow = false
    @State private var unfollowTargetId: String?
    /// フォローの操作に失敗した。**アラートで出す**（一覧の先頭の知らせは下に流すと見えない）
    @State private var actionError: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// ブロックした人を落とす写し。**出たとき（`onAppear`）だけ取る**——描くたびに
    /// `hidden.blockedUserIds` で絞ると、行から開いた人のページでブロックした瞬間に
    /// 行（`NavigationLink`）が消えてページが閉じる（`ModerationSnapshot.users` の注記）
    @State private var dropped = ModerationSnapshot()

    private var current: Kind { picked ?? kind }
    private var users: [FollowUser] { dropped.follows(lists[current]?.users ?? []) }
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
        .unfollowConfirmation(isPresented: $showUnfollow) {
            if let id = unfollowTargetId {
                unfollowTargetId = nil
                Task { await setFollowing(id, to: false) }
            }
        }
        .alert(L("うまくいきませんでした", "That didn't work"),
               isPresented: Binding(get: { actionError != nil },
                                    set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        // 見ている人が替わったら「フォロー中」の控えを捨てて読み直す（前の人の値で
        // ボタンを出さない）
        .task(id: auth.userId) {
            // **人が替わったときだけ**捨てる（戻るたびに捨てると札が消えてから出る・
            // 圏外で戻ると出ないまま）
            if loadedFor != auth.userId { myFollowing = nil }
            loadedFor = auth.userId
            await load()
        }
        .refreshable { await load() }
        // **戻ってきたらボタンの状態だけ読み直す。** 人のプロフィールでフォローを
        // 変えて戻ると、一覧のボタンが古いままだった（`.task(id:)` は走り直さない）
        .onAppear {
            dropped = hidden.snapshot
            if appeared { Task { await refreshMyFollowing() } }
            appeared = true
        }
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
            PersonNameLines(user: user)
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
                    unfollowTargetId = user.id
                    showUnfollow = true
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
                    // 見た目は 36pt、押せる高さは 44pt（`FollowPill` と同じ）
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
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
        } catch is CancellationError {
            // 取り消された（画面を離れた・引き下げの途中で描き直された）。失敗と言わない
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? Labels.Common.loadFailed
        }
        // `if let x = await …` は手元の構文の検査が読めないので、先に受けてから見る
        let ownerProfile = await owner
        if let name = ownerProfile?.displayName, !name.isEmpty {
            ownerName = name
        }
        await refreshMyFollowing()
    }

    /// 自分のフォロー先を読み直す（ボタンの「フォロー中」）。取れなかったら書かない
    private func refreshMyFollowing() async {
        guard let viewer = auth.userId else { return }
        let edits = followEdits
        // 始めた時点で送っている最中なら、答えはその送信を映していないことがある
        let startedIdle = working.isEmpty
        let ids = try? await environment.social.myFollowingIds()
        // 待っている間に人が替わっていたら書かない（引き下げの読み直しは
        // `.task(id:)` の取り消しに巻き込まれない）。**待っている間にこの画面で
        // フォローを押していたら書かない**（古い答えがボタンを元に戻す）
        // 送っている最中も書かない（先に着いた古い一覧で、押したボタンを戻さない）
        // **まだ一覧が無い（人が替わった直後など）なら、送信中でも書く**——書かないと
        // ボタンが全部消えたまま、戻るか引き下げるまで出なかった
        let empty = myFollowing == nil
        if let ids, auth.userId == viewer,
           empty || (followEdits == edits && startedIdle && working.isEmpty) {
            myFollowing = Set(ids)
        }
    }

    private func setFollowing(_ id: String, to follow: Bool) async {
        guard !working.contains(id) else { return }
        followEdits &+= 1
        working.insert(id)
        defer { working.remove(id) }
        // 押した人。**待っている間に人が替わったら、答えを次の人の一覧に混ぜない**
        let viewer = auth.userId
        do {
            let result = follow
                ? try await environment.social.follow(userId: id)
                : try await environment.social.unfollow(userId: id)
            guard auth.userId == viewer else { return }
            // **返ってきた状態を使う。** 自分で決めない
            if result.following {
                myFollowing?.insert(id)
            } else {
                myFollowing?.remove(id)
            }
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription
                ?? L("もう一度お試しください", "Please try again")
        }
    }
}
