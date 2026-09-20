import SwiftUI

struct GalleryView: View {

    @StateObject private var model: GalleryViewModel = GalleryViewModel(gallery: PublicGalleryService())

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ErrorBanner(message: message) {
                    Task { await model.load() }
                }
            case .loaded(let photos):
                if photos.isEmpty {
                    ErrorBanner(message: "まだ写真がありません")
                } else {
                    grid(photos)
                }
            }
        }
        .navigationTitle("ギャラリー")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { PhotoMapView() } label: {
                    Image(systemName: "map")
                }
            }
        }
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    private func grid(_ photos: [Photo]) -> some View {
        ScrollView {
            StoriesRow()
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(photos) { photo in
                    NavigationLink(value: photo.id) {
                        RemoteImage(url: photo.gridImageURL)
                            .aspectRatio(1, contentMode: .fill)
                            .accessibilityLabel(photo.accessibilityText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationDestination(for: String.self) { id in
            if let photo = photos.first(where: { $0.id == id }) {
                PhotoDetailView(photo: photo)
            }
        }
    }
}
