import SwiftUI

/// 年表。撮影日（無ければ登録日）で「YYYY年 M月」に束ねる。
struct PhotoTimelineView: View {

    let photos: [Photo]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
            ForEach(PhotoTimeline.group(photos)) { section in
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                        ForEach(section.photos) { photo in
                            NavigationLink { PhotoDetailView(photo: photo) } label: {
                                RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
                                    .aspectRatio(1, contentMode: .fill)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text(section.title)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(.bar)
                }
            }
        }
    }
}
