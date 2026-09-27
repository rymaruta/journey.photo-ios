import SwiftUI

/// 他の人のプロフィール（板 31）。
///
/// 並びはマイページ（板 05c）と同じ部品で組む: カバー（`ProfileCover`）に 84pt の
/// アイコンを重ね、名前・「@ユーザー名 · 居住地」・ひとことと自己紹介、数の1行、
/// ストーリーハイライト、下線の札（`ProfileTabBar`）、写真の格子。
///
/// **上のバーは見えなくするが、消さない。** 板はバーを出さずにカバーの上に「戻る」と
/// 「この人の操作」の丸を浮かせる。バーを隠して自前の「戻る」を置くと、画面の左端から
/// 払って戻る操作が効かなくなる（`MyPageView` はタブの根なので戻る先が無く、隠せる）。
/// だから地を透かし（`toolbarBackground(.hidden)`）、中央の題を塞ぐ。
/// iOS 26 ではバーの戻ると右の項目がガラスの丸で描かれる＝板と同じ形になる。
/// **それより前の iOS では丸の地が無い**（矢印と「…」だけがカバーの上に乗る）
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

    /// 板 31: 3列・隙間 4pt・角なし（マイページと同じ）
    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
    ]

    /// ログインしていて、自分以外で、ブロック中でないページか
    /// （フォロー・一覧の丸・ハイライト・ブロックはこの時だけ。`ProfileLine.canAct`）。
    /// ブロックはこの画面でも起きるので、`hidden` の中身を毎回見る
    private var canAct: Bool {
        ProfileLine.canAct(viewerId: auth.userId, userId: userId, blocked: hidden.blockedUserIds)
    }
    private var isBlocked: Bool { hidden.blockedUserIds.contains(userId) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                scroll
                    // カバーがあれば画面の上端から敷く（戻るの丸がカバーの上に乗る）。
                    // 無ければ帯も灰色の空き地も置かず、バーの下から始める
                    .ignoresSafeArea(edges: hasCover ? .top : [])
                // **時計とバーの裏に黒のぼかし**（マイページと同じ `TopBarScrim`）。
                // バーの地を透かしているので、敷かないと上へ送った写真が時計・戻る・
                // 「…」の真下を流れて読めない。iOS 17〜25 は丸に地が無く、明るい
                // カバーの上でも矢印が沈む
                TopBarScrim(topInset: geo.safeAreaInsets.top)
            }
        }
        .webScreen()
        // 題は戻る文字（次の画面）と読み上げのために持つ。見えるところには出さない
        .navigationTitle(model.shownName ?? Labels.Navigation.profile)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { toolbarItems }
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
            VStack(alignment: .leading, spacing: 16) {
                // 板: 見出し・数・ハイライトの間は 12pt、その下の札と格子は 16pt
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        ProfileCover(url: model.profile?.coverURL(cacheBust: model.cacheBust),
                                     reserve: hasCover) { hasCover = $0 }
                        header
                    }
                    if model.profile != nil {
                        counts
                        if canAct {
                            // 板 31 の丸の列。**無い人には何も出さない**（`ProfileSections.showsHighlights`）。
                            // 見られるのは本人とフォロワーだけなので、**フォローを変えたら
                            // 作り直して読み直す**（鍵が変わる）。そのままだと外した後も
                            // 輪が残り、押すと 404 になる
                            HighlightsRow(userId: userId, isMine: false)
                                .id(ProfileLine.highlightsKey(userId: userId,
                                                              isFollowing: model.isFollowing))
                        }
                    }
                }

                // **端末にしか無い札は出さない**（`ProfileTab.tabs`）
                ProfileTabBar(tabs: ProfileTab.tabs(isMe: false), selection: $tab)

                photoArea
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        // **中央は空けておく**（`AppHeader` と同じ塞ぎ方）。名前は下の見出しにある
        ToolbarItem(placement: .principal) {
            Color.clear.frame(width: 1, height: 1)
                .accessibilityHidden(true)
        }
        if canAct {
            ToolbarItem(placement: .topBarTrailing) {
                // **通報は置かない。** サーバーが受けるのは写真の通報だけ
                // （`POST /photos/{id}/report`）で、人を通報する口が無い。
                // 押しても何も起きない項目は作らない（写真の詳細から通報できる）
                Menu {
                    Button(role: .destructive) { showBlockConfirm = true } label: {
                        Label(L("この人をブロック", "Block this person"), systemImage: "hand.raised")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .webToolbarIcon()
                        .accessibilityLabel(L("この人の操作", "More actions"))
                }
            }
        }
    }

    @ViewBuilder
    private var photoArea: some View {
        if let message = model.errorMessage {
            ErrorBanner(message: message) {
                Task { await model.load(userId: userId, environment: environment, viewerId: auth.userId) }
            }
        } else if model.photos.isEmpty && model.photoCount == .failed {
            // **取れなかったのを「まだありません」と言わない**（数の札も「—」）
            ErrorBanner(message: Labels.Common.loadFailed) {
                Task { await model.load(userId: userId, environment: environment, viewerId: auth.userId) }
            }
        } else if model.photos.isEmpty && !model.isLoading {
            ErrorBanner(message: L("公開された写真はまだありません", "No public photos yet"))
        } else if tab == .map {
            // 相手のページでも「どこで撮ったか」を出す（モック11 と同じ並び）
            MyPhotosMap(photos: model.photos)
        } else {
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

    /// 見出し（板 31）: 84pt のアイコン（黒い 3pt の縁）と右に「フォローする」と
    /// フォロー一覧の丸、その下に明朝 26 の名前・「@ユーザー名 · 居住地」・ひとことと自己紹介
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
                HStack(spacing: 8) {
                    if canAct { followButton }
                    followListButton
                }
                .padding(.bottom, 4)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(model.shownName ?? "—")
                        .font(JPFont.display(26, relativeTo: .title))
                        .foregroundStyle(Color.white)
                    VerifiedBadge(isVerified: model.profile?.verified, nameSize: 26, relativeTo: .title)
                }
                // 公開プロフィールの口（`toPublicProfile`）が username と居住地を返す
                if let line = ProfileLine.handleAndHome(username: model.profile?.username,
                                                        home: model.profile?.homeLocation) {
                    ProfileHandleLine(line: line, showsPin: false)
                }
                // ひとことと自己紹介。**以前は自己紹介だけ**で、ひとことを出していなかった
                ForEach(ProfileLine.about(status: model.profile?.statusText,
                                          bio: model.profile?.bio), id: \.self) { text in
                    Text(text)
                        .font(.footnote)
                        .lineSpacing(4)
                        .foregroundStyle(WebTheme.muted2)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, hasCover ? -ProfileCover.avatarOverlap : 8)
    }

    /// 数の1行（板 31: 「000 フォロワー　000 フォロー中　000 写真」・数が先）。
    ///
    /// 写真の数は**下の格子に並べている枚数そのもの**（公開一覧からこの人のぶんを
    /// 選り分けたもの）。**読み終えるまで出さず、取れなければ「—」**（`PhotoCount`）。
    /// ブロックして一覧を伏せたあとも出さない。
    /// 押して一覧を開けるのは、ログインしていて1人以上いるときだけ
    /// （`FollowCounts.isTappable`）。一覧の口は認証が要るので、未ログインで
    /// 押せると赤字だけの行き止まりになる。
    private var counts: some View {
        HStack(spacing: 20) {
            ForEach(ProfileLine.counts(followers: model.followers, following: model.following,
                                       photos: isBlocked ? .pending : model.photoCount)) { item in
                switch item.kind {
                case .followers:
                    countLink(item, kind: .followers, count: model.followers)
                case .following:
                    countLink(item, kind: .following, count: model.following)
                case .photos:
                    countText(item)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func countLink(_ item: ProfileLine.Count, kind: FollowListView.Kind, count: Int) -> some View {
        if FollowCounts.isTappable(signedIn: auth.userId != nil, count: count) {
            NavigationLink {
                FollowListView(userId: userId, kind: kind)
            } label: {
                countText(item)
                    // 押せる高さは 44pt、並びの上では字の高さに近く詰める
                    .frame(minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
                    .padding(.vertical, -Self.countTapSlack)
            }
            .buttonStyle(.plain)
        } else {
            countText(item)
        }
    }

    private func countText(_ item: ProfileLine.Count) -> some View {
        HStack(spacing: 4) {
            Text(item.value)
                .font(JPFont.mono(13, relativeTo: .footnote))
                .foregroundStyle(Color.white)
            Text(item.label)
                .font(.footnote)
                .foregroundStyle(WebTheme.muted2)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    /// 数の札の、見た目より外へ押せる範囲を張り出す量（上下それぞれ）。
    /// 上下の 12pt の間に収まる量
    private static let countTapSlack: CGFloat = 10

    /// 「フォローする」（白地に墨）／「フォロー中」（白12% の地に白18% の縁）。板 31 の丸い札。
    ///
    /// 🔴 `.borderedProminent` は使わない——`RootView` の
    /// `.tint(WebTheme.foreground)` が白なので、白地に白い字＝
    /// **ただの白い帯**になる（run 60 の実機の絵で2か所そうだった）
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
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minWidth: 44, minHeight: 36)
                .background(model.isFollowing ? Color.white.opacity(0.12) : WebTheme.accentBackground,
                            in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(model.isFollowing ? 0.18 : 0),
                                                lineWidth: 1))
                // 見た目は 36pt、押せる高さは 44pt
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isWorking)
        .unfollowConfirmation(isPresented: $showUnfollowConfirm) {
            Task { await model.toggleFollow(userId: userId, environment: environment) }
        }
    }

    /// フォロー一覧を開く丸（板 31: 人と＋の印・44×36 の縁取り）。
    /// **開けるときだけ出す**（数の札と同じ `FollowCounts.isTappable`）——
    /// 開く先はフォロワーから、居なければフォロー中から（一覧の中で切り替えられる）
    @ViewBuilder
    private var followListButton: some View {
        let total = model.followers + model.following
        if FollowCounts.isTappable(signedIn: auth.userId != nil, count: total) {
            NavigationLink {
                FollowListView(userId: userId, kind: model.followers > 0 ? .followers : .following)
            } label: {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 36)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("フォロー一覧", "Followers and following"))
        }
    }
}

@MainActor
final class UserProfileViewModel: ObservableObject {

    @Published private(set) var profile: UserProfile?
    @Published private(set) var photos: [Photo] = []
    @Published private(set) var followers = 0
    @Published private(set) var following = 0
    @Published private(set) var isFollowing = false
    /// 写真の数を言えるか。**配列の長さを直接出さない**（読み込み中・失敗で 0 になる）
    @Published private(set) var photoCount: ProfileLine.PhotoCount = .pending
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
            photoCount = .loaded(photos.count)
        } else {
            // 前の回に取れていた一覧は残す（数もそのまま）。一度も取れていなければ「—」
            switch photoCount {
            case .loaded: break
            case .pending, .failed: photoCount = .failed
            }
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
            // **成功を赤字で出さない。** それまで `errorMessage` に入れて
            // いたので、うまくいった操作が「失敗」の見た目で出ていた
            toasts.show(L("ブロックしました。設定から解除できます。",
                          "Blocked. You can undo this in Settings."))
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? L("ブロックできませんでした", "Couldn't block")
        }
    }
}
