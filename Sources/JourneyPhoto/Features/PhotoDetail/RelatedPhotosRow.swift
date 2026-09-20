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
                    Text("近い写真").font(.subheadline.weight(.semibold))
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
            related = Self.pick(from: all, like: photo)
        }
    }

    /// 撮影地が同じものを先に、足りなければタグが重なるもので埋める。
    /// **自分自身は入れない。**
    static func pick(from photos: [Photo], like photo: Photo, limit: Int = 12) -> [Photo] {
        let others = photos.filter { $0.id != photo.id }
        var picked: [Photo] = []
        var seen = Set<String>()

        if let location = photo.location?.lowercased(), !location.isEmpty {
            for item in others where (item.location?.lowercased() ?? "") == location {
                if seen.insert(item.id).inserted { picked.append(item) }
            }
        }

        let tags = Set((photo.tags ?? []).map { $0.lowercased() })
        if !tags.isEmpty {
            for item in others where !tags.isDisjoint(with: Set((item.tags ?? []).map { $0.lowercased() })) {
                if picked.count >= limit { break }
                if seen.insert(item.id).inserted { picked.append(item) }
            }
        }

        return Array(picked.prefix(limit))
    }
}
