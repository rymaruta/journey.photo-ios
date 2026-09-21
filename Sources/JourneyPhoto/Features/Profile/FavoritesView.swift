import SwiftUI

/// お気に入り。いいねした写真を端末に覚えているので、**圏外でも一覧は出る**
/// （画像そのものは一度見たものだけ）。
struct FavoritesView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var favorites: FavoritesStore
    /// 取ってきた全部。**絞ったものを持たない。**
    ///
    /// 絞った配列を `@State` に置くと、この一覧から写真を開いて
    /// ハートを外して戻ってきても消えない（`.task` は戻りでは走らない）。
    /// 描くたびに絞れば、`FavoritesStore` が変わった時点で消える。
    @State private var all: [Photo] = []
    @State private var isLoading = true

    private var photos: [Photo] { all.filter { favorites.contains($0.id) } }

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
                        NavigationLink { PhotoDetailView(photo: photo, context: photos) } label: {
                            RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
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
        all = (try? await environment.gallery.fetchPhotos()) ?? []
    }
}
