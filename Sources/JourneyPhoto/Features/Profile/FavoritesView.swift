import SwiftUI

/// お気に入り。いいねした写真を端末に覚えているので、**圏外でも一覧は出る**
/// （画像そのものは一度見たものだけ）。
struct FavoritesView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var favorites: FavoritesStore
    /// 取ってきた全部。
    @State private var all: [Photo] = []
    /// 画面に出す分。**描画のたびに絞らない。**
    ///
    /// 絞りを計算に変えると、詳細画面でハートを外した瞬間に
    /// 元の `NavigationLink` が `ForEach` から消え、**見ている詳細画面が
    /// その場で閉じる**（SwiftUI は押した先を、押した元の存在に紐付ける）。
    /// 絞り直すのは**戻ってきたとき**（`.onAppear`）。
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
                        NavigationLink { PhotoDetailView(photo: photo, context: photos) } label: {
                            RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
                                .aspectRatio(1, contentMode: .fill)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .webScreen()
        .navigationTitle(Labels.Navigation.favorites)
        .task { await load() }
        .refreshable { await load(force: true) }
        // **戻ってきたら絞り直す。** 詳細画面でハートを外したぶんは、
        // その画面を閉じたこの時点で消える（見ている最中には消さない）
        .onAppear { photos = all.filter { favorites.contains($0.id) } }
    }

    private func load(force: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        all = (try? await environment.gallery.fetchPhotos(force: force)) ?? []
        photos = all.filter { favorites.contains($0.id) }
    }
}
