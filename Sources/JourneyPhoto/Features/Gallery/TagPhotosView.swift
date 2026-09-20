import SwiftUI

/// タグ・撮影地・カテゴリで絞った一覧。
///
/// Web 側の `/tag/*`・`/location/*`・`/category/*` にあたる。あちらは
/// 検索に載せるための静的ページだが、アプリでは絞り込みの結果として出す。
struct TagPhotosView: View {

    /// 絞り込みの条件。中身は `PhotoQuery.Collection`（画面を持たない層に置いて、
    /// Linux 上の `swift test` で検証できるようにしてある）。
    let kind: PhotoQuery.Collection

    @EnvironmentObject private var environment: AppEnvironment
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
                ErrorBanner(message: Labels.Gallery.empty)
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
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let all = (try? await environment.gallery.fetchPhotos()) ?? []
        photos = PhotoQuery.photos(all, in: kind)
    }
}
