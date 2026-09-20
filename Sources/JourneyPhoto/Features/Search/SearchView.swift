import SwiftUI

/// 探す。写真（題・撮影地・タグ）と人の両方を1画面で。
struct SearchView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var model = SearchViewModel()
    @State private var query = ""

    var body: some View {
        List {
            if !model.users.isEmpty {
                Section("人") {
                    ForEach(model.users) { user in
                        NavigationLink {
                            UserProfileView(userId: user.userId)
                        } label: {
                            HStack(spacing: 10) {
                                RemoteImage(url: user.avatarURL())
                                    .frame(width: 36, height: 36)
                                    .clipShape(Circle())
                                Text(user.name)
                            }
                        }
                    }
                }
            }

            if !model.photos.isEmpty {
                Section("写真") {
                    ForEach(model.photos) { photo in
                        NavigationLink {
                            PhotoDetailView(photo: photo)
                        } label: {
                            HStack(spacing: 10) {
                                RemoteImage(url: photo.gridImageURL)
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                // **題が無くても「無題」と名乗らせない。**
                                // 題も撮影地も無ければ、行は写真だけになる
                                VStack(alignment: .leading) {
                                    if !photo.displayTitle.isEmpty {
                                        Text(photo.displayTitle)
                                    }
                                    if let location = photo.location, !location.isEmpty {
                                        Text(location)
                                            .font(photo.displayTitle.isEmpty ? .body : .caption)
                                            .foregroundStyle(photo.displayTitle.isEmpty ? .primary : .secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if query.isEmpty {
                Section("よく使われているタグ") {
                    ForEach(model.popularTags, id: \.self) { tag in
                        Button(tag) { query = tag }
                    }
                }
            } else if model.users.isEmpty && model.photos.isEmpty && !model.isSearching {
                Text("見つかりませんでした").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("さがす")
        .searchable(text: $query, prompt: "撮影地・タグ・人")
        .task { await model.loadPhotos(environment: environment) }
        .onChange(of: query) { _, newValue in
            Task { await model.search(newValue, environment: environment) }
        }
    }
}

@MainActor
final class SearchViewModel: ObservableObject {

    @Published private(set) var photos: [Photo] = []
    @Published private(set) var users: [UserProfile] = []
    @Published private(set) var popularTags: [String] = []
    @Published private(set) var isSearching = false

    private var allPhotos: [Photo] = []
    /// 打つたびに投げない。**最後の打鍵から少し待つ**
    private var searchTask: Task<Void, Never>?

    func loadPhotos(environment: AppEnvironment) async {
        guard allPhotos.isEmpty else { return }
        allPhotos = (try? await environment.gallery.fetchPhotos()) ?? []
        popularTags = PhotoQuery.topTags(in: allPhotos)
    }

    func search(_ query: String, environment: AppEnvironment) async {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            photos = []
            users = []
            return
        }
        // 写真は手元の一覧から即座に絞る（往復しない）
        photos = PhotoQuery.match(allPhotos, query: trimmed)

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            users = (try? await environment.search.search(query: trimmed)) ?? []
        }
    }

}
