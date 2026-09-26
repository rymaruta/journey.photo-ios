import SwiftUI

/// 「写真を投稿／ストーリーを投稿」の2択。
///
/// Web 側の `app/components/PostSheet.tsx` と対。owner:「写真を追加のとこで
/// 投稿かストーリーを選べるようにしたい」。
///
/// **入口は下の札の「投稿」1つ**（整理案 05c でマイページの「投稿する」を
/// 外した）——入口が2つあると、同じ2択を2か所に書くことになる。
struct PostSheet: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore

    /// 札の絵に敷く写真（板 21: 絵の後ろに写真・85%）。**本人の写真だけ**。無ければ地の色のまま
    @State private var thumbs: [URL] = []

    /// 選ばれたもの。閉じたあとに呼び手が開く
    let onSelect: (Kind) -> Void

    enum Kind {
        case photo
        case story
    }

    var body: some View {
        // 板 21: 下から出る短いシート。左に明朝の見出し、右に ×、2枚の札
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("投稿する", "Create"))
                    .font(JPFont.display(24, relativeTo: .title2))
                    .foregroundStyle(WebTheme.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(WebTheme.foreground)
                        .webTappable()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Labels.Common.close)
            }
            .padding(.leading, 4)
            choice(
                thumb: thumbs.first,
                title: L("写真を投稿", "Post a photo"),
                detail: L("撮影地やタグを付けて残します。ずっと出ます。", "Keep it with a place and tags. It stays."),
                systemImage: "photo",
                kind: .photo
            )
            choice(
                thumb: thumbs.dropFirst().first,
                title: L("ストーリーを投稿", "Post a story"),
                detail: L("24時間で消えます。見た人が分かります。", "Disappears in 24 hours. You can see who viewed it."),
                systemImage: "clock",
                kind: .story
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        // 文字を大きくしたときに切れないよう、全画面にも伸ばせる
        .presentationDetents([.height(320), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Self.sheetBackground)
        .task {
            // **自分が最近出した写真**（`PostSheetThumbs`）。取れない・まだ無いときは
            // 印だけの無地のまま——**他人の写真で埋めない**
            // ログインしていなければ聞きに行かない（無地のまま）
            guard let userId = auth.userId else { return }
            if let cached = PostSheetThumbs.cache.urls(for: userId) {
                thumbs = cached
                return
            }
            // **取れなかったときは控えない**（次に開いたときに取り直す）
            guard let mine = try? await environment.photos.myPhotos() else { return }
            let picked = PostSheetThumbs.pick(fromMine: mine)
            PostSheetThumbs.cache.store(picked, for: userId)
            thumbs = picked
        }
    }

    /// シートの地（板: #0d0d0e。通報のシートと同じ）
    private static let sheetBackground = Color(red: 13 / 255, green: 13 / 255, blue: 14 / 255)

    /// 板: 最小92pt・角丸18・地7%・縁12%、左に 52pt の角丸14 の絵、右に矢印
    private func choice(thumb: URL?, title: String, detail: String, systemImage: String, kind: Kind) -> some View {
        Button {
            // **閉じてから渡す。** 開いたまま次の画面を出すと重なる
            dismiss()
            onSelect(kind)
        } label: {
            HStack(spacing: 14) {
                Color.white.opacity(0.10)
                    .frame(width: 52, height: 52)
                    .overlay {
                        // 読めたときだけ敷く（読み込み中の回転や壊れた記号を出さない）
                        if let thumb {
                            AsyncImage(url: thumb) { phase in
                                if case .success(let image) = phase {
                                    image.resizable().aspectRatio(contentMode: .fill).opacity(0.85)
                                }
                            }
                        }
                    }
                    .overlay {
                        Image(systemName: systemImage)
                            .font(.system(size: 22))
                            .foregroundStyle(WebTheme.foreground)
                            .shadow(color: Color.black.opacity(0.8), radius: 3, x: 0, y: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(WebTheme.text)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(WebTheme.muted2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .accessibilityHidden(true)
            }
            .padding(16)
            // 押せる面を大きく取る（Web 側も 88px 以上で固定している）
            .frame(minHeight: 92)
            .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(WebTheme.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        // 実機の絵の道しるべ（`ScreenshotTests`）。**位置で探させない**
        .accessibilityIdentifier("post.choice.\(kind == .photo ? "photo" : "story")")
    }
}
