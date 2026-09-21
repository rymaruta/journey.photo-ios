import SwiftUI

/// 検索結果の格子（提案の絵・2026-09-21）。
///
/// 1枚ごとに**題・撮影地・いいねの数**を重ねる。一覧（ホーム）と違って、
/// ここは「探している人」が見る場所なので、**手がかりを多く**出す。
struct SearchGrid: View {

    let photos: [Photo]

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(photos) { photo in
                NavigationLink {
                    PhotoDetailView(photo: photo, context: photos)
                } label: {
                    tile(photo)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private func tile(_ photo: Photo) -> some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
            }
            .overlay(alignment: .bottomLeading) { caption(photo) }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityLabel(photo.accessibilityText)
    }

    @ViewBuilder
    private func caption(_ photo: Photo) -> some View {
        let title = photo.displayTitle
        let place = (photo.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let likes = photo.likes ?? 0
        // **何も無い写真に帯を出さない**（空の黒帯は写真を欠けさせる）
        if !title.isEmpty || !place.isEmpty || likes > 0 {
            VStack(alignment: .leading, spacing: 3) {
                if !title.isEmpty {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WebTheme.foreground)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    if !place.isEmpty {
                        Image(systemName: "mappin.circle.fill")
                            .font(.caption2)
                        Text(place)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    // **0 のときは出さない。** 「まだ誰も押していない」は
                    // 探している人に要らない情報で、写真の邪魔になる
                    if likes > 0 {
                        Image(systemName: "heart")
                            .font(.caption2)
                        Text("\(likes)")
                            .font(.caption)
                    }
                }
                .foregroundStyle(Color.white.opacity(0.85))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.75)],
                               startPoint: .top, endPoint: .bottom)
            )
        }
    }
}
