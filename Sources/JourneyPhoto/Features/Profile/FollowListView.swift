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

    /// 「フォロワー N ／ フォロー中 N」（板 v2 FollowList の下線の切り替え）。
    /// 2026-10-31（#426）: マイページと同じ札（`ProfileTabBar`・`PagedTab`）。選んでいる方は真鍮の字と下線、
    /// 数は名前の右に SF の等幅数字（`ProfileTabBar.detail`）
    enum Kind: PagedTab {
        case following, followers

        /// 札の並び（フォロワー → フォロー中・板の順）
        static let order: [Kind] = [.followers, .following]

        var tabTitle: String { title }
        var tabIdentifier: String {
            switch self {
            case .following: return "followList.tab.following"
            case .followers: return "followList.tab.followers"
            }
        }

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
    /// 一覧の読み込みが「ログインしていない」で断られた。**失敗（赤）ではなく案内として出す**
    @State private var needsSignIn = false
    /// 案内の「ログイン」から開くログイン画面
    @State private var showSignIn = false
    /// ブロックした人を落とす写し。**前面が確定したときだけ取る**——描くたびに
    /// `hidden.blockedUserIds` で絞ると、行から開いた人のページでブロックした瞬間に
    /// 行（`NavigationLink`）が消えてページが閉じる（`ModerationSnapshot.users` の注記）
    @State private var dropped = ModerationSnapshot()
    @State private var front = FrontConfirm()
    @State private var frontSettle: Task<Void, Never>?

    private var current: Kind { picked ?? kind }
    /// 札で選んでいる方（押した・払ったのどちらも `picked` に書く）
    private var selection: Binding<Kind> {
        Binding(get: { current }, set: { picked = $0 })
    }
    /// 見えている高さ（札の中身の最低の高さ・`ProfileTabSection`）
    @State private var viewport: CGFloat = 0

    private func users(_ which: Kind) -> [FollowUser] { dropped.follows(lists[which]?.users ?? []) }
    private func total(_ which: Kind) -> Int { lists[which]?.total ?? 0 }

    var body: some View {
        // 2026-10-31 判断（#426）: `List` から縦の送り（`ScrollView`）に替え、切り替えをマイページと同じ札
        // （`ProfileTabSection`——下線が滑る・当たりが広い・中身を横にめくる）にした。フォロワーとフォロー中は
        // 一度に読むので（`load`）、横にめくった先もすぐ出る。行の見た目（64・区切り白 8%）は今までどおり
        ScrollView {
            ProfileTabSection(tabs: Kind.order, selection: selection, viewport: viewport, spacing: 0,
                              detail: { lists[$0].map { "\($0.total)" } }) { which in
                LazyVStack(alignment: .leading, spacing: 0) {
                    listContent(which)
                }
                .padding(.horizontal, ProfileV2.gutter)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            if height != viewport { viewport = height }
        }
        .webScreen()
        .navigationTitle(ownerName ?? current.title)
        .navigationBarTitleDisplayMode(.inline)
        // v2: 読み込みは行と同じ形の骨格（0.3 秒より早ければ出さない）
        .overlay(alignment: .top) {
            if isLoading && lists.isEmpty {
                JPLoadingState(kind: .rows)
                    .padding(.horizontal, ProfileV2.gutter)
                    .padding(.top, ProfileTabStyle.height + JPSpace.xs)
            }
        }
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
        // ログイン画面のシート（`SignInSheet`: 閉じるボタン・ログインできたら閉じる、を持つ共通の部品）。
        // 閉じたら読み直す——同じ人で入り直したときは `.task(id: auth.userId)` が走り直さない
        .sheet(isPresented: $showSignIn, onDismiss: { Task { await load() } }) {
            SignInSheet(reason: Self.signInLine(current))
        }
        // **戻ってきたらボタンの状態だけ読み直す。** 人のプロフィールでフォローを
        // 変えて戻ると、一覧のボタンが古いままだった（`.task(id:)` は走り直さない）
        .onAppear {
            switch front.appear() {
            case .first:
                dropped = hidden.snapshot
                appeared = true
            case .returning:
                frontSettle?.cancel()
                frontSettle = Task {
                    try? await Task.sleep(nanoseconds: FrontConfirm.settleNanoseconds)
                    guard !Task.isCancelled, front.confirm() else { return }
                    dropped = hidden.snapshot
                    Task { await refreshMyFollowing() }
                }
            }
        }
        .onDisappear {
            frontSettle?.cancel()
            frontSettle = nil
            front.disappear()
        }
    }

    /// 読み込みの失敗が「ログインしていない」か（2026-10-11 判断）。そうなら赤い失敗の文ではなく、
    /// ログインへの案内を出す——行き止まりを作らない（`SignInView` の注記と同じ考え）。
    /// **圏外・サーバーの失敗は混ぜない**（ログインしても直らない・`APIError` の注記）
    nonisolated static func needsSignIn(_ error: Error) -> Bool {
        (error as? APIError) == .notAuthenticated
    }

    /// 案内の1行。**エラーではないので赤にしない**（ふつうの文の色）
    nonisolated static func signInLine(_ kind: Kind) -> String {
        switch kind {
        case .followers: return L("ログインするとフォロワーを見られます", "Sign in to see followers")
        case .following: return L("ログインするとフォロー中の人を見られます", "Sign in to see who they follow")
        }
    }

    /// 未ログインの案内（2026-10-11）。文はふつうの色、ボタンは写真の無い画面の主ボタン
    /// （真鍮の塗り＋墨・`JPPillStyle.accent`・CLAUDE.md の owner の好み）
    private var signInPrompt: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Self.signInLine(current))
                .font(.subheadline)
                .foregroundStyle(WebTheme.muted2)
            Button {
                showSignIn = true
            } label: {
                Text(L("ログイン", "Sign in"))
                    .jpPillButton(.accent)
            }
            // 行の中のボタンは borderless（行全体が当たりにならないように）
            .buttonStyle(.borderless)
            .accessibilityIdentifier("followList.signIn")
        }
        .padding(.vertical, 8)
    }

    /// 札ごとの中身（`ProfileTabSection`）。**`current` ではなく渡された方で分ける**——選んでいない方も持ち続ける。
    /// 未ログイン・読めなかったは両方の札で同じ（`load` は2つを一度に読む）
    @ViewBuilder
    private func listContent(_ which: Kind) -> some View {
        let shown = users(which)
        let count = total(which)
        if needsSignIn {
            signInPrompt
        } else if let errorMessage {
            // v2 Components 06: 失敗は共通の並び（何が起きたか → もう一度）
            ErrorBanner(message: errorMessage, isBusy: isLoading) { Task { await load() } }
                .padding(.vertical, JPSpace.xs)
        } else if shown.isEmpty && !isLoading && count == 0 {
            EmptyState(message: L("まだいません", "No one yet"))
        }

        ForEach(shown) { user in
            row(user)
                // 板 v2 Components 05 の人の行: 64・アイコン 44・区切りは白 8%
                .frame(minHeight: JPHeight.tallRow)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline)
                }
        }

        // **一覧の長さと数え札は一致しない。** 50人で切ったぶん・一覧が
        // 追いついていないぶん・ブロックで落としたぶんがある
        // （api-user/src/follow.ts の注記）。黙って食い違わせない
        if count > shown.count {
            Text(L("全 \(count) 人のうち \(shown.count) 人を表示しています", "Showing \(shown.count) of \(count)"))
                .font(JPFont.caption.monospacedDigit())
                .foregroundStyle(WebTheme.text3)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.vertical, JPSpace.s)
        }
    }

    @ViewBuilder
    private func row(_ user: FollowUser) -> some View {
        HStack(spacing: 12) {
            if user.deleted == true {
                // 退会した人にはプロフィールへの導線も札も出さない
                person(user).foregroundStyle(WebTheme.text3)
            } else {
                // 縦の送りの中では字が色付きのリンクにならないよう、見た目は行のまま（`List` のときと同じ）
                NavigationLink { UserProfileView(userId: user.id) } label: { person(user) }
                    .buttonStyle(.plain)
                followButton(user)
            }
        }
    }

    private func person(_ user: FollowUser) -> some View {
        HStack(spacing: 12) {
            RemoteImage(url: user.deleted == true ? nil
                        : UserProfile.profileAssetURL(userId: user.id, suffix: nil, cacheBust: nil))
                .frame(width: 44, height: 44)
                .background(WebTheme.card)
                .clipShape(Circle())
            PersonNameLines(user: user)
            Spacer(minLength: 0)
        }
    }

    /// 「フォロー中」（線）／「フォローする」（白 94% の塗り）。**自分と、フォロー状態が
    /// 分からないときは出さない**。
    ///
    /// v2（板 FollowList・Components 01 の行の中の小ボタン）: 見た目 36・幅 96 以上・線は白 14%
    /// （`WebTheme.line`・v1 は 28%）。当たりは 44
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
                    .font(JPFont.footnote.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(isFollowing ? WebTheme.foreground : WebTheme.accentText)
                    .padding(.horizontal, 14)
                    .frame(minWidth: Self.followButtonMinWidth, minHeight: JPHeight.inlineButton)
                    .background(isFollowing ? Color.clear : WebTheme.accentBackground, in: Capsule())
                    .overlay(Capsule().strokeBorder(isFollowing ? WebTheme.line : Color.clear,
                                                    lineWidth: JPStroke.hairline))
                    // 見た目は 36pt、押せる高さは 44pt（`FollowPill` と同じ）
                    .padding(.vertical, ProfileV2.tapSlack(visible: JPHeight.inlineButton))
                    .contentShape(Rectangle())
            }
            // 行の中のボタンは borderless にしないと、行のどこを押しても反応する
            .buttonStyle(.borderless)
            .disabled(working.contains(user.id))
        }
    }

    /// フォローの札の最小の幅（板 v2 FollowList: 96）。「フォロー中」と「フォローする」で幅が揺れない
    nonisolated static let followButtonMinWidth: CGFloat = 96

    private func load() async {
        isLoading = true
        errorMessage = nil
        needsSignIn = false
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
        } catch where Self.needsSignIn(error) {
            needsSignIn = true
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
            // 前の人が押した失敗を、次の人の画面に出さない（成功の側は上で捨てている）
            guard auth.userId == viewer else { return }
            actionError = (error as? LocalizedError)?.errorDescription
                ?? L("もう一度お試しください", "Please try again")
        }
    }
}
