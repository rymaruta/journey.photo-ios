import SwiftUI

/// 他の人のプロフィール。
struct UserProfileView: View {

    let userId: String

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model = UserProfileViewModel()
    @State private var showBlockConfirm = false
    @State private var showUnfollowConfirm = false
    @State private var tab: ProfileTab = .posts
    /// カバー写真が出せたか（板 31。出せなければ帯を出さない）
    @State private var hasCover = false
    @EnvironmentObject private var hidden: ModerationStore
    @EnvironmentObject private var toasts: ToastCenter

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                scroll
                    // **カバーは画面の上端から**（板 31: 時計の裏まで）。無い人は安全域の下から
                    .ignoresSafeArea(edges: hasCover ? .top : [])
                // 上のバーを透かしたので、カバーの上で戻る・「…」と時計が読めるよう
                // 上端だけ黒へ寄せる（押す操作は下へ通す）
                LinearGradient(colors: [Color.black.opacity(0.6), Color.black.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: geo.safeAreaInsets.top + 16)
                    .offset(y: -geo.safeAreaInsets.top)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .webScreen()
        // **上のバーは消さない**（`toolbar(.hidden)` で消すと、端から払って戻る操作まで
        // 効かなくなることがある）。見え方は既定（`.automatic`）のまま＝**一番上では
        // 透けてカバーの上に戻ると「…」だけ**（板 31）、流すと `webScreen` の黒が出る。
        // 常に透かすと、流した写真が時計や戻るの裏をそのまま通って読めなくなる
        // 題は出さない（名前は見出しにある）。次の画面の「戻る」の名前には使われる
        .navigationTitle(model.shownName ?? Labels.Navigation.profile)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 題は出さない（板 31）。空の `EmptyView` は捨てられて題が出ることがあるので、
            // 見えない1点を置く。画面の見出しは名前の字（`.isHeader`）が受け持つ
            ToolbarItem(placement: .principal) {
                Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
            }
            if auth.userId != nil && auth.userId != userId {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) { showBlockConfirm = true } label: {
                            Label(L("この人をブロック", "Block this person"), systemImage: "hand.raised")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .webToolbarIcon()
                            .accessibilityLabel(L("この人の操作", "More actions"))
                    }
                }
            }
        }
        .alert(L("この人をブロックしますか？", "Block this person?"), isPresented: $showBlockConfirm) {
            Button(L("ブロック", "Block"), role: .destructive) {
                Task { await model.block(userId: userId, environment: environment, store: hidden, toasts: toasts) }
            }
            Button(Labels.Common.cancel, role: .cancel) {}
        } message: {
            Text(L("おたがいの投稿・ストーリー・通知が見えなくなります。設定からいつでも解除できます。", "You won't see each other's posts, stories or notifications. You can undo this in Settings."))
        }
        .task(id: userId) {
            await model.load(userId: userId, environment: environment, viewerId: auth.userId)
        }
    }

    private var scroll: some View {
        ScrollView {
            // 板 31: 段の間は 16pt
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    ProfileCover(url: model.profile?.coverURL(cacheBust: model.cacheBust),
                                 reserve: hasCover) { hasCover = $0 }
                    header
                }
                // ストーリーハイライト（板 31）。**見られるのはフォロワーだけ**で、
                // そうでなければサーバーが0件を返し、この行は黙って消える
                // **フォローしたら読み直す**（見られるようになる）。**ブロックしたら出さない**
                if !hidden.blockedUserIds.contains(userId) {
                    HighlightsRow(userId: userId, isMine: false, reloadKey: model.isFollowing)
                }

                // 下線の札（板 31: 投稿 / マップ）。**マイページと同じ部品**。
                // 横に払う切り替えは付けない——マップの札の中身は地図で、横に動かすと地図が動く
                ProfileTabBar(tabs: ProfileTab.tabs(isMe: false), selection: $tab)

                if let message = model.errorMessage {
                    ErrorBanner(message: message) {
                        Task { await model.load(userId: userId, environment: environment, viewerId: auth.userId) }
                    }
                } else if model.photos.isEmpty && !model.isLoading {
                    ErrorBanner(message: L("公開された写真はまだありません", "No public photos yet"))
                } else if tab == .map {
                    // 相手のページでも「どこで撮ったか」を出す（モック11 と同じ並び）
                    MyPhotosMap(photos: model.photos)
                } else {
                    // 板 31: 隙間 4pt・角なし（マイページと同じ）
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(model.photos) { photo in
                            NavigationLink { PhotoDetailView(photo: photo, context: model.photos) } label: {
                                PhotoFrame(photo: photo, corner: 0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// 数字の札。**押して一覧を開けるのは、ログインしていて1人以上いるときだけ**
    /// （`FollowCounts.isTappable`）。一覧の口は認証が要るので、未ログインで
    /// 押せると赤字だけの行き止まりになる。
    @ViewBuilder
    private func followCount(value: Int, label: String, kind: FollowListView.Kind) -> some View {
        if FollowCounts.isTappable(signedIn: auth.userId != nil, count: value) {
            NavigationLink {
                FollowListView(userId: userId, kind: kind)
            } label: {
                countLabel(value: value, label: label)
            }
        } else {
            countLabel(value: value, label: label)
        }
    }

    /// 見出し（板 31）: 84pt のアイコン（黒い 3pt の縁）と右にフォローの札、その下に
    /// 明朝 26 の名前・「@ユーザー名 · 居住地」・ひとこと、数の1行。
    /// **マイページ（板 05c）と同じ部品**（`ProfileHandleLine`・`ProfileAbout`）
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                RemoteImage(url: model.profile?.avatarURL(cacheBust: model.cacheBust))
                    .frame(width: ProfileCover.avatarSize, height: ProfileCover.avatarSize)
                    .clipShape(Circle())
                    // **板どおり黒の 3pt の縁**（板 31）。本人が選んだ色の輪（`themeColor`）は
                    // 出さない——マイページ（板 05c）と揃える（owner の判断・2026-09-26）。
                    // 色はプロフィール編集で選べ、Web（`themeRingGradient`）には出る
                    .coverCutout(true)
                Spacer(minLength: 8)
                if auth.userId != nil && auth.userId != userId {
                    followButton
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(model.shownName ?? "—")
                        .font(JPFont.display(26, relativeTo: .title))
                        .foregroundStyle(Color.white)
                        .accessibilityAddTraits(.isHeader)
                    VerifiedBadge(isVerified: model.profile?.verified, nameSize: 26, relativeTo: .title, fit: .mincho)
                }
                if let line = ProfileLine.handleAndHome(username: model.profile?.username,
                                                        home: model.profile?.homeLocation) {
                    ProfileHandleLine(line: line)
                }
                ProfileAbout(status: model.profile?.statusText, bio: model.profile?.bio)
            }
            // 板 31: 「000 フォロワー　000 フォロー中　000 写真」（13px・数は等幅の白・間 20）
            HStack(spacing: 20) {
                followCount(value: model.followers, label: L("フォロワー", "followers"),
                            kind: .followers)
                followCount(value: model.following, label: L("フォロー中", "following"),
                            kind: .following)
                // **数え終わるまで出さない**（「0 写真」を一瞬見せない・取れなければ出さない）
                if let count = model.photoCount {
                    countLabel(value: count, label: L("写真", "photos"))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        // カバーがあればアイコンを下端に重ねる（板: 帯に 84pt の丸を 50pt）
        .padding(.top, hasCover ? -ProfileCover.avatarOverlap : 8)
    }

    /// 数の札の中身（数は等幅の白・名前は白72%）
    private func countLabel(value: Int, label: String) -> some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(JPFont.mono(13, relativeTo: .footnote))
                .foregroundStyle(Color.white)
            Text(label)
                .font(.footnote)
                .foregroundStyle(WebTheme.muted2)
        }
        .frame(minHeight: WebTheme.minTapTarget)
        .contentShape(Rectangle())
        // **押せる高さは 44pt のまま、並びの上では字の高さに近づける**
        // （マイページの数の札と同じ考え方）。上は字だけの段なので重なっても害は無い
        .padding(.vertical, -Self.countTapSlack)
        .accessibilityElement(children: .combine)
    }

    /// 数の札の、見た目より外へ押せる範囲を張り出す量（上下それぞれ）
    private static let countTapSlack: CGFloat = 10

    /// フォローの札（板 31: 高さ 36・13px の太字）。**押している状態を色で分ける**
    /// ——まだなら白地に墨の字、フォロー中なら白12%の地に白の字と縁。
    /// 🔴 `.borderedProminent` は使わない（`RootView` の `.tint` が白なので、
    /// 白地に白い字＝ただの白い帯になる。run 60 の実機の絵）
    private var followButton: some View {
        Button {
            // 外すときだけ確認を挟む（`unfollowConfirmation`）
            if model.isFollowing {
                showUnfollowConfirm = true
            } else {
                Task { await model.toggleFollow(userId: userId, environment: environment) }
            }
        } label: {
            Text(model.isFollowing ? L("フォロー中", "Following") : L("フォローする", "Follow"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(model.isFollowing ? Color.white : WebTheme.accentText)
                .padding(.horizontal, 14)
                .frame(minWidth: 44, minHeight: 36)
                .background(model.isFollowing ? Color.white.opacity(0.12) : Color.white.opacity(0.92),
                            in: Capsule())
                .overlay {
                    if model.isFollowing {
                        Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    }
                }
                // 見た目は 36pt、押せる高さは 44pt
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 4)
        // 送っている間は薄くする（押したことが見て分かる。二度押しは `disabled` で防ぐ）
        .opacity(model.isWorking ? 0.6 : 1)
        .disabled(model.isWorking)
        .unfollowConfirmation(isPresented: $showUnfollowConfirm) {
            Task { await model.toggleFollow(userId: userId, environment: environment) }
        }
    }
}

@MainActor
final class UserProfileViewModel: ObservableObject {

    @Published private(set) var profile: UserProfile?
    @Published private(set) var photos: [Photo] = []
    /// 公開写真の数。**数え終わるまで nil**（見出しの「写真」の数に使う）
    @Published private(set) var photoCount: Int?
    @Published private(set) var followers = 0
    @Published private(set) var following = 0
    @Published private(set) var isFollowing = false
    @Published private(set) var isLoading = false
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private(set) var cacheBust = ""

    func load(userId: String, environment: AppEnvironment, viewerId: String?) async {
        isLoading = true
        errorMessage = nil
        cacheBust = String(Int(Date().timeIntervalSince1970))
        defer { isLoading = false }

        do {
            profile = try await environment.profiles.publicProfile(userId: userId)
        } catch let error as APIError {
            // **「取れなかった」と「退会した」を混ぜない**
            if case .server(let status, _) = error, status == 404 {
                errorMessage = L("このユーザーは見つかりません（退会した可能性があります）", "This user was not found (they may have deleted their account)")
                return
            }
            errorMessage = error.errorDescription
            return
        } catch {
            errorMessage = Labels.Common.loadFailed
            return
        }

        let stats = try? await environment.social.followStats(userId: userId)
        if let stats {
            followers = stats.followers
            following = stats.following
        }
        if viewerId != nil {
            let ids = try? await environment.social.myFollowingIds()
            isFollowing = ids?.contains(userId) ?? false
        }
        // **その人の写真は公開 JSON から絞る。** 「ある人の公開写真」を返す
        // 口が api-user に無いため（Web も静的ページを書き出している）
        let all = try? await environment.gallery.fetchPhotos()
        if let all {
            photos = PhotoPinning.pinnedFirst(all.filter { ($0.userId ?? $0.uploadedBy) == userId },
                                      pinned: profile?.pinnedPhotoIds ?? [])
            photoCount = photos.count
        }
    }

    /// 画面に出す名前。
    ///
    /// 🔴 **プロフィールの名前だけを見ていた。** `UserProfile.name` は
    /// 名前が無いとき「ユーザー」を返す＝**nil にならない**ので、
    /// この人の写真に添えられている名前（`displayName`）まで降りてこない。
    /// run 58 の実機の絵では、ホームと写真詳細が `luzhj` を出しているのに
    /// **人のページだけ「ユーザー」**だった（写真詳細で直したのと同じ形が
    /// ここにも残っていた＝3か所目）。
    ///
    /// **まだ何も取れていないうちは nil**——「ユーザー」と出してから
    /// 名前に入れ替わると、読み込みの途中が壊れて見える
    var shownName: String? { AuthorName.forProfilePage(profile: profile, photos: photos) }

    func toggleFollow(userId: String, environment: AppEnvironment) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let result = isFollowing
                ? try await environment.social.unfollow(userId: userId)
                : try await environment.social.follow(userId: userId)
            isFollowing = result.following
            followers = result.followers
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("うまくいきませんでした", "That didn't work")
        }
    }

    func block(userId: String, environment: AppEnvironment, store: ModerationStore,
               toasts: ToastCenter) async {
        do {
            try await environment.moderation.block(userId: userId)
            store.block(userId)
            await environment.gallery.setHidden(
                userIds: store.blockedUserIds,
                photoIds: store.reportedPhotoIds
            )
            isFollowing = false
            photos = []
            photoCount = nil
            // **成功を赤字で出さない。** それまで `errorMessage` に入れて
            // いたので、うまくいった操作が「失敗」の見た目で出ていた
            toasts.show(L("ブロックしました。設定から解除できます。",
                          "Blocked. You can undo this in Settings."))
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("ブロックできませんでした", "Couldn't block")
        }
    }
}
