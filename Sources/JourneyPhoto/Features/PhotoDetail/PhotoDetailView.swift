import SwiftUI

struct PhotoDetailView: View {

    let photo: Photo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RemoteImage(url: photo.detailImageURL, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(photo.accessibilityText)

                VStack(alignment: .leading, spacing: 12) {
                    if !photo.displayTitle.isEmpty {
                        Text(photo.displayTitle)
                            .font(.title3.weight(.semibold))
                    }

                    if let location = photo.location, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(Array(photo.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(.body)
                    }

                    if let tags = photo.tags, !tags.isEmpty {
                        TagRow(tags: tags)
                    }

                    if let exif = photo.exif {
                        ExifRow(exif: exif)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 32)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TagRow: View {
    let tags: [String]
    var body: some View {
        // 横に流さず折り返す。タグは59種あり、長い並びは画面外に出る
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.secondarySystemBackground), in: Capsule())
            }
        }
    }
}

private struct ExifRow: View {
    let exif: Photo.Exif

    /// タプルには KeyPath を張れないので（`\.0` は書けない）、
    /// `ForEach` の id 用に小さな型を置く
    private struct Item: Identifiable {
        let id: String
        let value: String
    }

    private var items: [Item] {
        let candidates: [(String, String?)] = [
            ("カメラ", exif.camera),
            ("レンズ", exif.lens),
            ("絞り", exif.aperture),
            ("シャッター", exif.exposure),
            ("ISO", exif.iso.map { String($0) }),
            ("焦点距離", exif.focalLength),
        ]
        return candidates.compactMap { label, value in
            guard let value, !value.isEmpty else { return nil }
            return Item(id: label, value: value)
        }
    }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items) { item in
                    HStack {
                        Text(item.id).foregroundStyle(.secondary)
                        Spacer()
                        Text(item.value)
                    }
                    .font(.caption)
                }
            }
            .padding(.top, 8)
        }
    }
}

/// タグを折り返して並べる。iOS 17 の `Layout` で書く（`LazyVGrid` だと
/// 文字数の違うタグが不自然に伸びる）。
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
