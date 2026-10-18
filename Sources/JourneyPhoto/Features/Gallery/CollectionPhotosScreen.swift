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
    /// 一覧の上に置く一言（機材の「広く写す」）。
    /// 板 12 に寄せる前から画面の上にあった字で、**なぜこの写真が
    /// 並んでいるのか**を言う。無ければ出さない
    var lede: String?
    /// 読み込めなかった回の出口。**渡されたときだけ**、0枚を
    /// 「読み込めませんでした」＋「もう一度試す」で出す（「該当する写真がありません」と分ける）
    var retry: (() -> Void)?
    /// 題の上の眉（「COLOR」「GEAR」「THIS SEASON」）。無ければ集約の種類から決める
    /// （`CollectionScreen.eyebrow(for:)`）。どちらも無ければ眉を出さない
    var eyebrow: String?
    /// 眉の読み上げ（英字の眉を日本語で読ませる）
    var eyebrowSpoken: String?

    /// 板 12 は「人気」を選んだ形で描いてある
    @State private var sort: GallerySort = .popular
    @EnvironmentObject private var hidden: ModerationStore
    /// 一覧から落とす「見せない」の写し。**前面が確定したときだけ取る**。
    /// 探すの色・機材・季節は、探す側が詳細を積んでいる間は読み直さない（開いている
    /// 詳細を閉じないため）ので、ここで落とさないとブロックした人の写真が並び続ける。
    /// 戻るスワイプ途中の `onAppear` で即適用すると、押した元が消えて詳細が閉じる
    @State private var dropped = ModerationSnapshot()
    @State private var front = FrontConfirm()
    @State private var frontSettle: Task<Void, Never>?

    private var shown: [Photo] { dropped.visible(photos) }
    private var sorted: [Photo] { sort.apply(shown) }

    /// 一覧の上の見出し。**v2（2026-10-14・TagPhotos の板）**: 眉（真鍮）→ 明朝 32 の題 →
    /// 13 の text-2 の枚数の一行。以前はバーの中央に 16 の題と 12 の枚数を2行で出していた
    /// ——題が小さく、何の一覧かが写真より先に読めなかった
    private var heading: some View {
        VStack(alignment: .leading, spacing: JPSpace.xxs) {
            if let mark = eyebrowMark {
                Text(mark.text)
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                    .accessibilityLabel(mark.spoken)
            }
            Text(title)
                .font(JPFont.photoTitle)
                .foregroundStyle(WebTheme.text)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            // 読み込めずに0枚の回も枚数を出さない（数えていないものを「0枚」と言わない）
            let subtitle = CollectionScreen.subtitle(count: shown.count, note: note,
                                                     isLoading: isLoading || (retry != nil && photos.isEmpty))
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(JPFont.footnote.monospacedDigit())
                    .foregroundStyle(WebTheme.text2)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, JPSpace.gutter)
    }

    /// 眉の字と読み上げ（渡されたもの → 集約の種類から）
    private var eyebrowMark: (text: String, spoken: String)? {
        if let eyebrow { return (eyebrow, eyebrowSpoken ?? eyebrow) }
        return CollectionScreen.eyebrow(for: kind)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JPSpace.s) {
                heading
                if let lede, !lede.isEmpty {
                    Text(lede)
                        .font(JPFont.body)
                        .foregroundStyle(WebTheme.text2)
                        .padding(.horizontal, JPSpace.gutter)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: JPSpace.xs) {
                        ForEach(GallerySort.collectionChoices) { option in
                            PillChip(title: option.chipLabel, selected: sort == option) {
                                sort = option
                            }
                        }
                    }
                    .padding(.horizontal, JPSpace.gutter)
                }
                // 札の押せる余白（上下 5）の分だけ詰め、並びの見た目の間隔は前のまま
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
            .padding(.top, JPSpace.xxs)
            .padding(.bottom, JPSpace.xl)
        }
        .webScreen()
        .onAppear {
            switch front.appear() {
            case .first:
                dropped = hidden.snapshot
            case .returning:
                frontSettle?.cancel()
                frontSettle = Task {
                    try? await Task.sleep(nanoseconds: FrontConfirm.settleNanoseconds)
                    guard !Task.isCancelled else { return }
                    if front.confirm() { dropped = hidden.snapshot }
                }
            }
        }
        .onDisappear {
            frontSettle?.cancel()
            frontSettle = nil
            front.disappear()
        }
        // 読み上げと次の画面の「戻る」に使う。見た目は一覧の上の見出し（`heading`）。
        // バーの中央は空けておく（題を2か所に出さない）
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
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
