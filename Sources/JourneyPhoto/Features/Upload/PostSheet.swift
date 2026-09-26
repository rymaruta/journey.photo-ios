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

    /// 選ばれたもの。閉じたあとに呼び手が開く
    let onSelect: (Kind) -> Void

    enum Kind {
        case photo
        case story
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                choice(
                    title: L("写真を投稿", "Post a photo"),
                    detail: L("撮影地やタグを付けて残します。ずっと出ます。", "Keep it with a place and tags. It stays."),
                    systemImage: "photo",
                    kind: .photo
                )
                choice(
                    title: L("ストーリーを投稿", "Post a story"),
                    detail: L("24時間で消えます。見た人が分かります。", "Disappears in 24 hours. You can see who viewed it."),
                    systemImage: "clock",
                    kind: .story
                )
                Spacer()
            }
            .padding(16)
            .navigationTitle(L("投稿する", "Create"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Labels.Common.close) { dismiss() }
                }
            }
        }
    }

    private func choice(title: String, detail: String, systemImage: String, kind: Kind) -> some View {
        Button {
            // **閉じてから渡す。** 開いたまま次の画面を出すと重なる
            dismiss()
            onSelect(kind)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            // 押せる面を大きく取る（Web 側も 88px 以上で固定している）
            .frame(minHeight: 88)
            .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        // 実機の絵の道しるべ（`ScreenshotTests`）。**位置で探させない**
        .accessibilityIdentifier("post.choice.\(kind == .photo ? "photo" : "story")")
    }
}
