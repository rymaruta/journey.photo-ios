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
    /// 読み込めなかった回の出口。**渡されたときだけ**、0枚を
    /// 「読み込めませんでした」＋「もう一度試す」で出す（「該当する写真がありません」と分ける）
    var retry: (() -> Void)?

    /// 板 12 は「人気」を選んだ形で描いてある
    @State private var sort: GallerySort = .popular
    @EnvironmentObject private var hidden: ModerationStore
    /// 一覧から落とす「見せない」の写し。**戻ってきたとき（`onAppear`）に取る**。
    /// 探すの色・機材・季節は、探す側が詳細を積んでいる間は読み直さない（開いている
    /// 詳細を閉じないため）ので、ここで落とさないとブロックした人の写真が並び続ける
    @State private var dropped = ModerationSnapshot()

    private var shown: [Photo] { dropped.visible(photos) }
    private var sorted: [Photo] { sort.apply(shown) }

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
                // 札の押せる余白（上下 4）の分だけ詰め、並びの見た目の間隔は前のまま
                .padding(.vertical, -PillChip.tapSlack)

                // 読めなかった回は `photos` が空（ブロックで伏せた0枚とは分ける）
                if photos.isEmpty && !isLoading, let retry {
                    ErrorBanner(message: Labels.Common.loadFailed, retry: retry)
                } else if shown.isEmpty && !isLoading {
                    EmptyState(message: Labels.Gallery.empty)
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
        .onAppear { dropped = hidden.snapshot }
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
                    // 読み込めずに0枚の回も枚数を出さない（数えていないものを「0枚」と言わない）
                    let subtitle = CollectionScreen.subtitle(count: shown.count, note: note,
                                                             isLoading: isLoading || (retry != nil && photos.isEmpty))
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(WebTheme.faint)
                            .lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: CollectionScreen.shareText(title: title, count: shown.count,
                                                           kind: kind, lead: CollectionScreen.shareLead(sorted),
                                                           photos: shown)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .webToolbarIcon()
                .accessibilityLabel(L("シェア", "Share"))
            }
        }
    }
}
