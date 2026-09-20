import SwiftUI

/// 他の人のプロフィール。
struct UserProfileView: View {

    let userId: String

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model = UserProfileViewModel()
    @State private var showBlockConfirm = false

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let message = model.errorMessage {
                    ErrorBanner(message: message) {
                        Task { await model.load(userId: userId, environment: environment, viewerId: auth.userId) }
                    }
                } else if model.photos.isEmpty && !model.isLoading {
                    ErrorBanner(message: "公開された写真はまだありません")
                } else {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(model.photos) { photo in
                            NavigationLink { PhotoDetailView(photo: photo) } label: {
                                RemoteImage(url: photo.gridImageURL)
                                    .aspectRatio(1, contentMode: .fill)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle(model.profile?.name ?? "プロフィール")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if auth.userId != nil && auth.userId != userId {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) { showBlockConfirm = true } label: {
                            Label("この人をブロック", systemImage: "hand.raised")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .alert("この人をブロックしますか？", isPresented: $showBlockConfirm) {
            Button("ブロック", role: .destructive) {
                Task { await model.block(userId: userId, environment: environment) }
            }
            Button("やめる", role: .cancel) {}
        } message: {
            Text("おたがいの投稿・ストーリー・通知が見えなくなります。設定からいつでも解除できます。")
        }
        .task(id: userId) {
            await model.load(userId: userId, environment: environment, viewerId: auth.userId)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RemoteImage(url: model.profile?.avatarURL(cacheBust: model.cacheBust))
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.profile?.name ?? "—").font(.headline)
                    HStack(spacing: 12) {
                        Text("フォロワー \(model.followers)")
                        Text("フォロー中 \(model.following)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let bio = model.profile?.bio, !bio.isEmpty {
                Text(bio).font(.callout)
            }

            if auth.userId != nil && auth.userId != userId {
                // **押している状態を色で分ける。** `.bordered` と
                // `.borderedProminent` は型が違うので三項演算子では書けない
                if model.isFollowing {
                    followButton.buttonStyle(.bordered)
                } else {
                    followButton.buttonStyle(.borderedProminent)
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
            Text(model.isFollowing ? "フォロー中" : "フォローする")
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
                errorMessage = "このユーザーは見つかりません（退会した可能性があります）"
                return
            }
            errorMessage = error.errorDescription
            return
        } catch {
            errorMessage = "読み込めませんでした"
            return
        }

        if let stats = try? await environment.social.followStats(userId: userId) {
            followers = stats.followers
            following = stats.following
        }
        if viewerId != nil, let ids = try? await environment.social.myFollowingIds() {
            isFollowing = ids.contains(userId)
        }
        // **その人の写真は公開 JSON から絞る。** 「ある人の公開写真」を返す
        // 口が api-user に無いため（Web も静的ページを書き出している）
        if let all = try? await environment.gallery.fetchPhotos() {
            photos = all.filter { ($0.userId ?? $0.uploadedBy) == userId }
        }
    }

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
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "うまくいきませんでした"
        }
    }

    func block(userId: String, environment: AppEnvironment) async {
        do {
            try await environment.moderation.block(userId: userId)
            isFollowing = false
            errorMessage = "ブロックしました。設定から解除できます。"
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "ブロックできませんでした"
        }
    }
}
