import SwiftUI

/// お気に入り。いいねした写真を端末に覚えているので、**圏外でも一覧は出る**
/// （画像そのものは一度見たものだけ）。
struct FavoritesView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var favorites: FavoritesStore
    @State private var photos: [Photo] = []
    @State private var isLoading = true

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        ScrollView {
            if photos.isEmpty && !isLoading {
                ErrorBanner(message: L("まだお気に入りがありません", "No liked photos yet"))
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(photos) { photo in
                        NavigationLink { PhotoDetailView(photo: photo) } label: {
                            RemoteImage(url: photo.gridImageURL)
                                .aspectRatio(1, contentMode: .fill)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(Labels.Navigation.favorites)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let all = (try? await environment.gallery.fetchPhotos()) ?? []
        photos = all.filter { favorites.contains($0.id) }
    }
}
