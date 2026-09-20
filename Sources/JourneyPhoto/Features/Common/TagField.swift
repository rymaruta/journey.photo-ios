import SwiftUI

/// タグを選ぶ欄。投稿（`UploadView`）と編集（`EditPhotoView`）で使う。
///
/// **打つのではなく選ぶ。** 打つと表記が割れる（このサイトの弱点は
/// 「索引に載るタグ8種のうち日本語は1種」で、割れはそこを直接悪くする）。
/// 押し直すと外れる・打ちかけの文字で候補を絞る、という約束まで Web と揃える。
struct TagField: View {

    @Binding var tagsText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("タグ", "Tags"))
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(TagInput.suggest(TagChoices.all, current: tagsText), id: \.self) { tag in
                    chip(tag)
                }
            }
            TextField(L("タグ（カンマ区切り。打つと候補が絞れます）",
                        "Tags (comma separated; typing filters the chips)"), text: $tagsText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.callout)
        }
    }

    private func chip(_ tag: String) -> some View {
        let chosen = TagInput.has(tagsText, tag: tag)
        return Button {
            // **打ちかけの欠片を落としてから足す。** 落とさないと
            // `さく` と打って `桜` を押したときに `"さく, 桜"` になり、
            // **`さく` が写真のタグとして保存される**（絞りの目的と逆）
            tagsText = TagInput.toggle(
                TagInput.dropFragment(TagChoices.all, current: tagsText), tag: tag)
        } label: {
            Text(tag)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(chosen ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground),
                            in: Capsule())
        }
        .buttonStyle(.borderless)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
