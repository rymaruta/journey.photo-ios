import SwiftUI

/// 自分のページ。ログインしていなければログイン画面を出す。
struct MyPageView: View {

    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model = MyPageViewModel()
    @State private var tab: ProfileTab = .posts
    @State private var showPostSheet = false
    @State private var showPhotoUpload = false
    @State private var showStoryComposer = false
    /// ストーリーの行に「読み直せ」と言うための数
    @State private var storiesReload = 0
    /// 一度でもこの画面が出たか。**戻ってきた回だけ読み直す**ための印
    @State private var didAppear = false

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        Group {
            if auth.isResolving {
                // 確認が終わるまでログイン画面を出さない（ちらつきを作らない）
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if auth.userId == nil {
                SignInView(reason: nil)
            } else {
                content
            }
        }
        .navigationTitle(Labels.Navigation.mypage)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView() } label: {
                    Image(systemName: "gearshape")
                        .accessibilityLabel(L("設定", "Settings"))
                }
            }
        }
        .task(id: auth.userId) {
            guard auth.userId != nil else { return }
            await model.load()
        }
        // **戻ってきたら読み直す。** この画面から押して出る先
        // （プロフィール編集・写真の詳細）はどれも `NavigationLink` で、
        // 閉じる合図を受け取る口が無い。保存しても削除しても、
        // マイページは古いままだった。
        // 初回は `.task` が読むので、2度目以降だけ走らせる
        .onAppear {
            guard didAppear else { didAppear = true; return }
            guard auth.userId != nil else { return }
            Task { await model.load() }
        }
    }

    /// **段ごとに割ってある**（`UploadView` と同じ理由——長い ViewBuilder は
    /// 型検査が終わらなくなることがある。落ちたときに場所も分かりやすい）。
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let profile = model.profile {
                    header(profile)
                }
                postButton
                StoriesRow(reloadToken: storiesReload)
                shortcuts
                tabPicker
                photoArea
            }
        }
        .refreshable { await model.load() }
        .sheet(isPresented: $showPostSheet) {
            PostSheet { kind in
                switch kind {
                case .photo: showPhotoUpload = true
                case .story: showStoryComposer = true
                }
            }
        }
        .sheet(isPresented: $showPhotoUpload, onDismiss: { Task { await model.load() } }) {
            NavigationStack { UploadView() }
        }
        // **帰ってきたら読み直す。** `StoriesRow` は自分の `+` から出した
        // シートしか見ていないので、ここから出した回は投稿しても並ばなかった
        .sheet(isPresented: $showStoryComposer, onDismiss: { storiesReload += 1 }) {
            NavigationStack { StoryComposerView() }
        }
    }

    @ViewBuilder
    private func themeRing(_ hex: String?) -> some View {
        if let hex, let color = Color(hex: hex) {
            Circle().strokeBorder(color, lineWidth: 3)
        }
    }

    private func header(_ profile: UserProfile) -> some View {
        HStack(spacing: 12) {
            RemoteImage(url: profile.avatarURL(cacheBust: model.avatarCacheBust))
                .frame(width: 64, height: 64)
                .clipShape(Circle())
                // **本人が選んだ色を輪にする**（Web の `themeRingGradient` と
                // 同じ置き場所）。選んでいなければ輪を出さない
                .overlay(themeRing(profile.themeColor))
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

    private var postButton: some View {
        // **投稿の入口はここ1つ。** Web も 2026-09-20 に画面右下の
        // 「＋」を撤去して、マイページの「投稿する」に集めた
        Button {
            showPostSheet = true
        } label: {
            Label(L("投稿する", "Create"), systemImage: "plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal, 16)
    }

    private var shortcuts: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                NavigationLink(L("プロフィールを編集", "Edit profile")) { ProfileEditView() }
                    .buttonStyle(.bordered)
                NavigationLink(Labels.Navigation.albums) { AlbumsView() }
                    .buttonStyle(.bordered)
                NavigationLink(Labels.Navigation.favorites) { FavoritesView() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
        }
        .font(.footnote)
    }

    private var tabPicker: some View {
        Picker("", selection: $tab) {
            ForEach(ProfileTab.allCases) { tab in
                Text(tab.label).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var photoArea: some View {
        if let error = model.errorMessage {
            ErrorBanner(message: error) { Task { await model.load() } }
        } else if model.photos.isEmpty && !model.isLoading {
            ErrorBanner(message: L("まだ写真がありません", "No photos yet"))
        } else if tab == .timeline {
            PhotoTimelineView(photos: model.photos)
        } else {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(model.photos) { photo in
                    NavigationLink {
                        PhotoDetailView(photo: photo, fromPublicFeed: false, context: model.photos)
                    } label: {
                        gridCell(photo)
                    }
                    .buttonStyle(.plain)
                    // **長押しでピン留め**（Web の「先頭にピン留め」と同じ操作）。
                    // 一覧の見た目は変えず、操作だけ足す
                    .contextMenu {
                        let pinned = model.isPinned(photo.id)
                        Button {
                            Task { await model.setPinned(photo.id, pinned: !pinned) }
                        } label: {
                            Label(pinned ? L("ピン留めを解除", "Unpin")
                                         : L("先頭にピン留め", "Pin to top"),
                                  systemImage: pinned ? "pin.slash" : "pin")
                        }
                    }
                }
            }
        }
    }

    /// 一覧の1枚。**下書き（非公開）は一目で分かるようにする**
    /// ——公開したつもりの写真が出ていない、がいちばん困る。
    private func gridCell(_ photo: Photo) -> some View {
        ZStack(alignment: .topTrailing) {
            RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
                .aspectRatio(1, contentMode: .fill)
            if model.isPinned(photo.id) {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .padding(4)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(4)
                    .accessibilityLabel(L("ピン留め中", "Pinned"))
            }
            if photo.published == false {
                Text(L("下書き", "Draft"))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(4)
            }
        }
    }
}

@MainActor
final class MyPageViewModel: ObservableObject {

    @Published private(set) var profile: UserProfile?
    /// 留めている写真。**サーバーが返した一覧をそのまま持つ**
    /// （増減の結果は向こうが決める——3枚の上限も、消えた写真の掃除も）
    @Published private(set) var pinnedIds: [String] = []
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
            // 自分のページでも、留めた写真は先頭（他人から見えている並びと揃える）
            self.pinnedIds = self.profile?.pinnedPhotoIds ?? []
            self.photos = PhotoPinning.pinnedFirst(try await photos, pinned: self.pinnedIds)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? Labels.Common.loadFailed
        }
    }

    func isPinned(_ photoId: String) -> Bool { pinnedIds.contains(photoId) }

    /// ピン留めの増減。
    ///
    /// **画面を先に動かさない。** 3枚の上限はサーバーが持っていて
    /// （`userProfile.ts`）、断られたときにそのときの一覧も返ってくる。
    /// 先に動かすと「留まったように見えて、次の読み込みで戻る」になる。
    func setPinned(_ photoId: String, pinned: Bool) async {
        do {
            pinnedIds = try await profiles.setPinned(photoId: photoId, pinned: pinned)
            photos = PhotoPinning.pinnedFirst(photos, pinned: pinnedIds)
            errorMessage = nil
        } catch {
            // 上限（409）のときは、サーバーが「ピン留めは3枚までです」を返す
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? L("ピン留めを変えられませんでした", "Couldn't change the pin")
        }
    }
}
