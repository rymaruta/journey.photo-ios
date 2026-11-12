import SwiftUI

/// タグ・色・機材・いまの季節の写真の格子（**TagPhotos v2**）。
///
/// **2026-11-12 判断（デザインの案 第2章「画面の状態とそろえ」・1.1.83）**: 板が2つあり（v1 は 2 列・すき間 4・
/// 先頭 219）、コード（`PhotoGrid`・2 列・すき間 10・端 10・先頭 16:10・角 18）はどちらとも違った。
/// **v2 の 3 列・すき間 2・正方形・角なし**に寄せる——探すの格子・読み込みの骨格（`JPLoadingState`）と同じ物差し。
/// 先頭の1枚は**端まで広げて高さ 300**、撮影地・@投稿者・いいねを重ねる（`LeadCaption`）。
/// 一画面目の写真は 1+2+2 → 1+3+3 に増える
struct TagPhotoGrid<Destination: View>: View {

    let photos: [Photo]
    @ViewBuilder let destination: (Photo) -> Destination

    private static var leadHeight: CGFloat { TagPhotoGridMetrics.leadHeight }
    private static var columnCount: Int { TagPhotoGridMetrics.columnCount }
    private static var spacing: CGFloat { TagPhotoGridMetrics.spacing }

    var body: some View {
        let multiple = PhotoGroups.multiPhotoIds(photos)
        VStack(spacing: Self.spacing) {
            if let lead = photos.first {
                NavigationLink {
                    destination(lead)
                } label: {
                    Color.clear
                        .frame(height: Self.leadHeight)
                        .frame(maxWidth: .infinity)
                        .overlay {
                            DownsampledRemoteImage(url: lead.gridImageURL, contentMode: .fill,
                                                   aspectRatio: lead.aspectRatio.map { CGFloat($0) },
                                                   alignment: lead.gridAlignment,
                                                   assumedRatioLimit: PhotoFrame.assumedRatioLimit,
                                                   appearAnimation: .easeOut(duration: 0.15))
                        }
                        .clipped()
                        .overlay(alignment: .bottom) { LeadCaption(photo: lead) }
                        .contentShape(Rectangle())
                        .accessibilityLabel(lead.accessibilityText)
                }
                .buttonStyle(.plain)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing),
                                     count: Self.columnCount),
                      spacing: Self.spacing) {
                ForEach(photos.dropFirst()) { photo in
                    NavigationLink {
                        destination(photo)
                    } label: {
                        PhotoFrame(photo: photo, aspect: 1, corner: 0)
                            .overlay(alignment: .topTrailing) {
                                if multiple.contains(photo.id) {
                                    Image(systemName: "square.on.square")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.white)
                                        .shadow(radius: 3)
                                        .padding(JPSpace.xs)
                                        .accessibilityLabel(L("複数枚の投稿", "Multiple photos"))
                                }
                            }
                            .accessibilityLabel(photo.accessibilityText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// `TagPhotoGrid` の寸法（板 TagPhotos v2）
enum TagPhotoGridMetrics {
    /// 先頭の1枚の高さ（板 v2 の 300）
    nonisolated static let leadHeight: CGFloat = 300
    /// 格子の列とすき間（板 v2・探すの格子と同じ）
    nonisolated static let columnCount = 3
    nonisolated static let spacing: CGFloat = 2
}
