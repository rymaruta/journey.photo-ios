import SwiftUI

/// タグ・色・機材・いまの季節の写真（板 12）。どの入口から来ても同じ形。
///
/// 見出しは題とその下の小さい字（「12枚 · いまの季節」）、右上にシェア。
/// 本体は並び替えのチップ（人気／新着／撮影日）と、先頭の大きい1枚に
/// 撮影地・@投稿者・いいねを重ねた一覧（`PhotoGrid` の `captionsLead`）。
struct CollectionPhotosScreen: View {

    let title: String
    /// 小さい字の枚数のあとに添える一言（「いまの季節」「焦点距離 〜35mm」など）
    var note: String?
    let photos: [Photo]
    /// 集約の種類。**シェアで Web のページを指せるか**に使う（色・季節は nil）
    var kind: PhotoQuery.Collection?
    var isLoading = false
    /// 一覧の上に置く一言（機材の「ダイナミックな風景」）。
    /// 板 12 に寄せる前から画面の上にあった字で、**なぜこの写真が
    /// 並んでいるのか**を言う。無ければ出さない
    var lede: String?

    /// 板 12 は「人気」を選んだ形で描いてある
    @State private var sort: GallerySort = .popular

    private var sorted: [Photo] { sort.apply(photos) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let lede, !lede.isEmpty {
                    Text(lede)
                        .font(.subheadline)
                        .foregroundStyle(WebTheme.muted)
                        .padding(.horizontal, 16)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(GallerySort.collectionChoices) { option in
                            PillChip(title: option.chipLabel, selected: sort == option) {
                                sort = option
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if photos.isEmpty && !isLoading {
                    ErrorBanner(message: Labels.Gallery.empty)
                } else {
                    let list = sorted
                    PhotoGrid(photos: list, captionsLead: true) { photo in
                        PhotoDetailView(photo: photo, context: list)
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .webScreen()
        // 読み上げと次の画面の「戻る」に使う。見た目は下の2行の見出し
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(WebTheme.foreground)
                        .lineLimit(1)
                    let subtitle = CollectionScreen.subtitle(count: photos.count, note: note,
                                                             isLoading: isLoading)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(WebTheme.faint)
                            .lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: CollectionScreen.shareText(title: title, count: photos.count,
                                                           kind: kind, lead: sorted.first)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .webToolbarIcon()
                .accessibilityLabel(L("シェア", "Share"))
            }
        }
    }
}
