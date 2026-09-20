import SwiftUI

/// 自分のページ。ログインしていなければログイン画面を出す。
struct MyPageView: View {

    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model = MyPageViewModel()

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        Group {
            if auth.userId == nil {
                SignInView(reason: nil)
            } else {
                content
            }
        }
        .navigationTitle("マイページ")
        .toolbar {
            if auth.userId != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("ログアウト") { Task { await auth.signOut() } }
                }
            }
        }
        .task(id: auth.userId) {
            guard auth.userId != nil else { return }
            await model.load()
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let profile = model.profile {
                    header(profile)
                }

                if let error = model.errorMessage {
                    ErrorBanner(message: error) { Task { await model.load() } }
                } else if model.photos.isEmpty && !model.isLoading {
                    ErrorBanner(message: "まだ写真がありません")
                } else {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(model.photos) { photo in
                            NavigationLink { PhotoDetailView(photo: photo) } label: {
                                ZStack(alignment: .topTrailing) {
                                    RemoteImage(url: photo.gridImageURL)
                                        .aspectRatio(1, contentMode: .fill)
                                    // 下書き（非公開）は一目で分かるようにする。
                                    // 公開したつもりの写真が出ていない、が
                                    // いちばん困る
                                    if photo.published == false {
                                        Text("下書き")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.ultraThinMaterial, in: Capsule())
                                            .padding(4)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .refreshable { await model.load() }
    }

    private func header(_ profile: UserProfile) -> some View {
        HStack(spacing: 12) {
            RemoteImage(url: profile.avatarURL(cacheBust: model.avatarCacheBust))
                .frame(width: 64, height: 64)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).font(.headline)
                if let bio = profile.bio, !bio.isEmpty {
                    Text(bio).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

@MainActor
final class MyPageViewModel: ObservableObject {

    @Published private(set) var profile: UserProfile?
    @Published private(set) var photos: [Photo] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    /// アイコンは固定キーで中身が差し替わる（サーバーは `no-store`）。
    /// 読み直すたびに別の URL にして、古い絵が残らないようにする。
    private(set) var avatarCacheBust = ""

    private let profiles: ProfileService
    private let photoService: PhotoService

    init() {
        let api = APIClient(tokenProvider: CognitoTokenProvider())
        self.profiles = ProfileService(api: api)
        self.photoService = PhotoService(api: api)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        avatarCacheBust = String(Int(Date().timeIntervalSince1970))
        do {
            async let profile = self.profiles.myProfile()
            async let photos = self.photoService.myPhotos()
            self.profile = try await profile
            self.photos = try await photos
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "読み込めませんでした"
        }
    }
}
