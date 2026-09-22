import SwiftUI

/// 他の人のプロフィール。
struct UserProfileView: View {

    let userId: String

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model = UserProfileViewModel()
    @State private var showBlockConfirm = false
    @State private var tab: ProfileTab = .posts
    @EnvironmentObject private var hidden: ModerationStore
    @EnvironmentObject private var toasts: ToastCenter

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                Picker("", selection: $tab) {
                    // **端末にしか無い札は出さない**（`ProfileTab.tabs`）
                    ForEach(ProfileTab.tabs(isMe: false)) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

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
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(model.photos) { photo in
                            NavigationLink { PhotoDetailView(photo: photo, context: model.photos) } label: {
                                PhotoFrame(photo: photo)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .webScreen()
        .navigationTitle(model.shownName ?? Labels.Navigation.profile)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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

    /// 数字の札。**押して一覧を開けるのは、ログインしていて1人以上いるときだけ**
    /// （`FollowCounts.isTappable`）。一覧の口は認証が要るので、未ログインで
    /// 押せると赤字だけの行き止まりになる。
    @ViewBuilder
    private func followCount(_ label: String, count: Int, kind: FollowListView.Kind) -> some View {
        if FollowCounts.isTappable(signedIn: auth.userId != nil, count: count) {
            NavigationLink {
                FollowListView(userId: userId, kind: kind)
            } label: {
                Text(label)
            }
        } else {
            Text(label)
        }
    }

    @ViewBuilder
    private func themeRing(_ hex: String?) -> some View {
        if let hex, let color = Color(hex: hex) {
            Circle().strokeBorder(color, lineWidth: 3)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RemoteImage(url: model.profile?.avatarURL(cacheBust: model.cacheBust))
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    // 本人が選んだ色を輪にする（Web の `themeRingGradient`）
                    .overlay(themeRing(model.profile?.themeColor))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(model.shownName ?? "—").font(.headline)
                        VerifiedBadge(isVerified: model.profile?.verified)
                    }
                    HStack(spacing: 12) {
                        followCount(
                            L("フォロワー \(model.followers)", "\(model.followers) followers"),
                            count: model.followers, kind: .followers
                        )
                        followCount(
                            L("フォロー中 \(model.following)", "\(model.following) following"),
                            count: model.following, kind: .following
                        )
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            if let bio = model.profile?.bio, !bio.isEmpty {
                Text(bio).font(.callout)
            }

            if auth.userId != nil && auth.userId != userId {
                // **押している状態を色で分ける。**
                // 🔴 `.borderedProminent` は使わない——`RootView` の
                // `.tint(WebTheme.foreground)` が白なので、白地に白い字＝
                // **ただの白い帯**になる（run 60 の実機の絵で2か所そうだった）。
                // 白地に黒い字は `webPrimaryButton()`
                if model.isFollowing {
                    followButton.buttonStyle(.bordered)
                } else {
                    followButton.webPrimaryButton().buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var followButton: some View {
        Button {
            Task { await model.toggleFollow(userId: userId, environment: environment) }
        } label: {
            Text(model.isFollowing ? L("フォロー中", "Following") : L("フォローする", "Follow"))
                .frame(maxWidth: .infinity)
        }
        .disabled(model.isWorking)
    }
}

@MainActor
final class UserProfileViewModel: ObservableObject {

    @Published private(set) var profile: UserProfile?
    @Published private(set) var photos: [Photo] = []
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
