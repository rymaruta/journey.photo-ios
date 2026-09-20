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
                    ErrorBanner(message: Labels.Gallery.empty)
                } else {
                    grid(photos)
                }
            }
        }
        .navigationTitle(Labels.Navigation.gallery)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { PhotoMapView() } label: {
                    Image(systemName: "map")
                        .accessibilityLabel(Labels.Navigation.map)
                }
            }
        }
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    /// カテゴリの絞り込み。Web の `FilterBar` にあたる。
    /// **押し直すと外れる**（`role="switch"` と同じ振る舞い）。
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.categories, id: \.self) { category in
                    let selected = model.category == category
                    Button {
                        model.select(category: selected ? nil : category)
                    } label: {
                        Text(Labels.Category.name(category))
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                selected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.secondarySystemBackground)),
                                in: Capsule()
                            )
                            .foregroundStyle(selected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func grid(_ photos: [Photo]) -> some View {
        ScrollView {
            // **ストーリーはここに置かない。** 2026-09-20 に Web が
            // トップから外してマイページへ移した（投稿も閲覧もマイページに集める）
            if !model.categories.isEmpty {
                filterBar
            }
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(photos) { photo in
                    NavigationLink(value: photo.id) {
                        RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
                            .aspectRatio(1, contentMode: .fill)
                            .accessibilityLabel(photo.accessibilityText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationDestination(for: String.self) { id in
            if let photo = photos.first(where: { $0.id == id }) {
                PhotoDetailView(photo: photo, context: photos)
            }
        }
    }
}
