import SwiftUI

/// 「この写真に近いもの」。同じ撮影地 → 同じタグ、の順に拾う。
struct RelatedPhotosRow: View {

    let photo: Photo

    @EnvironmentObject private var environment: AppEnvironment
    @State private var related: [Photo] = []

    var body: some View {
        Group {
            if !related.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("近い写真", "Similar photos")).font(.subheadline.weight(.semibold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(related) { item in
                                NavigationLink {
                                    PhotoDetailView(photo: item)
                                } label: {
                                    RemoteImage(url: item.gridImageURL)
                                        .frame(width: 96, height: 96)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .task(id: photo.id) {
            let all = (try? await environment.gallery.fetchPhotos()) ?? []
            related = PhotoQuery.related(to: photo, from: all)
        }
    }
}
