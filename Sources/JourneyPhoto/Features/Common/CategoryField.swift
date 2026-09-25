import SwiftUI

/// カテゴリを選ぶ欄。投稿（`UploadView`）と編集（`EditPhotoView`）で使う。
///
/// **一覧に無い語のための入力も残す。** Web 側（`app/user/upload/page.tsx`）も
/// 「カテゴリ（一覧に無い語はここに）」を併せて置いている。選択肢に無い主題を
/// 撮る人を、チップの7つに閉じ込めない。
struct CategoryField: View {

    @Binding var category: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("カテゴリ", "Category"))
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(CategoryChoices.all, id: \.self) { choice in
                    chip(choice)
                }
            }
            TextField(L("カテゴリ（一覧に無い語はここに）", "Category (something else)"), text: $category)
                .textInputAutocapitalization(.never)
                .font(.callout)
        }
    }

    private func chip(_ choice: String) -> some View {
        let chosen = CategoryChoices.isChosen(current: category, choice: choice)
        return Button {
            category = CategoryChoices.toggle(current: category, choice: choice)
        } label: {
            Text(choice)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                // **選んでいるものは白の塗りに墨の字**（白＝選択）。以前は
                // AccentColor の 20% で、黒地の上ではほとんど見分けがつかなかった
                .foregroundStyle(chosen ? WebTheme.accentText : WebTheme.muted)
                .background(chosen ? WebTheme.accentBackground : WebTheme.surface,
                            in: Capsule())
        }
        .buttonStyle(.borderless)
        // **押せる状態を読み上げに載せる。** 見た目の色だけだと、
        // VoiceOver では選んだかどうかが分からない
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
