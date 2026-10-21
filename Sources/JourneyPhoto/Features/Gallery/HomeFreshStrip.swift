import SwiftUI

/// ホームの「みんなの新しい写真」の1段（2026-10-21・全画面の点検。並びの規則は `HomeFreshPhotos`）。
///
/// 置き場所はストーリーの列のすぐ下・上の札（旅・季節・今日のテーマ）と作例の棚より上
/// ——最初の画面に、利用者が投稿した写真を必ず見せる（写真が主役）。
///
/// 見た目（板 Main・デザインシステム「黒塗りの真鍮」に合わせた）:
/// - 見出しは節の見出しの眉だけ（真鍮の「NEW」と消える線・黒地の上）＋右に「すべて見る ›」。
///   明朝の題は置かない——段の背を低くして、下の札も最初の画面に残す
/// - 写真は角丸の縦長（4:5）を横に流す。写真の上には字を置かない（題の帯も切る・小さいので読めない）
/// - 写真の下に作者の名前（12pt・text-2）。写真の上ではないので黒地の字
/// - 押すと写真の詳細（前後は段の並び）
struct HomeFreshStrip: View {

    let photos: [Photo]
    /// 「すべて見る」（呼ぶ側が「新着」に切り替えて、下の一覧へ送る）
    let onSeeAll: () -> Void

    /// 写真1枚の幅（4:5 で高さ 150。次の写真の端が見えて、横に流せると分かる幅）
    nonisolated static let tileWidth: CGFloat = 120
    nonisolated static let tileAspect: CGFloat = 4.0 / 5.0

    var body: some View {
        VStack(alignment: .leading, spacing: JPSpace.xs) {
            JPSectionHeading(eyebrow: "NEW", spoken: L("みんなの新しい写真", "New photos")) {
                Button(action: onSeeAll) {
                    MoreLink(text: L("すべて見る", "See all"))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.fresh.all")
            }
            .padding(.horizontal, JPSpace.gutter)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: WebTheme.gridSpacing) {
                    ForEach(photos) { photo in
                        NavigationLink {
                            PhotoDetailView(photo: photo, context: photos)
                        } label: {
                            tile(photo)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, JPSpace.gutter)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.fresh")
    }

    private func tile(_ photo: Photo) -> some View {
        let byline = HomeFreshPhotos.byline(photo)
        return VStack(alignment: .leading, spacing: JPSpace.xxs) {
            PhotoTile(photo: photo, aspect: Self.tileAspect, showsCaption: false)
            if let byline {
                Text(byline)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(width: Self.tileWidth, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([photo.accessibilityText, byline].compactMap { $0 }.joined(separator: " · "))
    }
}
