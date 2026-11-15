import SwiftUI

/// タグを選ぶ欄。投稿（`UploadView`）と編集（`EditPhotoView`）で使う。
///
/// **打つのではなく選ぶ。** 打つと表記が割れる（このサイトの弱点は
/// 「索引に載るタグ8種のうち日本語は1種」で、割れはそこを直接悪くする）。
/// 押し直すと外れる・打ちかけの文字で候補を絞る、という約束まで Web と揃える。
struct TagField: View {

    @Binding var tagsText: String
    /// 端末の AI のタグの候補（投稿の画面だけ・札 #622・2026-11-15 判断）。**先頭に並べ、真鍮のきらめきの印を付ける。**
    /// 札は増やさない（決まった選択肢の並べ替えだけ）。押すと今までどおり足す／外す。空なら今の並びのまま
    var suggested: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("タグ", "Tags"))
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: FormChip.spacing, lineSpacing: FormChip.lineSpacing) {
                ForEach(TagInput.suggest(PostSuggest.orderedChoices(suggested: suggested), current: tagsText),
                        id: \.self) { tag in
                    chip(tag)
                }
            }
            JPTextField(L("タグ（カンマ区切り。打つと候補が絞れます）",
                        "Tags (comma separated; typing filters the chips)"), text: $tagsText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.callout)
        }
    }

    private func chip(_ tag: String) -> some View {
        let chosen = TagInput.has(tagsText, tag: tag)
        let isIdea = !chosen && suggested.contains(tag)
        return Button {
            // **打ちかけの欠片を落としてから足す。** 落とさないと
            // `さく` と打って `桜` を押したときに `"さく, 桜"` になり、
            // **`さく` が写真のタグとして保存される**（絞りの目的と逆）
            tagsText = TagInput.toggle(
                TagInput.dropFragment(TagChoices.all, current: tagsText), tag: tag)
        } label: {
            HStack(spacing: 3) {
                // AI の候補の印（選ぶ前だけ。選んだら白の塗りに墨の字で「選んだ」だけを見せる）
                if isIdea {
                    Image(systemName: "sparkles")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WebTheme.accent)
                        .accessibilityHidden(true)
                }
                Text(tag)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            // **選んでいるものは白の塗りに墨の字**（白＝選択）。以前は
            // AccentColor の 20% で、黒地の上ではほとんど見分けがつかなかった
            .foregroundStyle(chosen ? WebTheme.accentText : WebTheme.muted)
            .formChipFace(fill: chosen ? WebTheme.accentBackground : WebTheme.surface)
        }
        .buttonStyle(.borderless)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityLabel(isIdea ? L("\(tag)、AI の候補", "\(tag), AI suggestion") : tag)
    }
}

/// 投稿・編集のタグとカテゴリの札の形（`TagField`・`CategoryField`）。
///
/// **2026-10-17 判断: 見た目 32・当たり 44**（板 DesignSystem 03「チップは見た目 32〜36 のまま、
/// 上下のパディングで当たりを 44 に」・板 EditPhoto の札 32）。それまでは字の高さ＋上下 5（約 26）で、
/// 当たりを札の間の半分（3pt）しか広げられず 44 に届かなかった。
///
/// 札の上下に 6 ずつ押せる余白を足し、**その 44 の箱を行の間 0 で積む**（`FlowLayout.lineSpacing`）。
/// 箱が重ならないので、隣の行の札の押し下げを奪わない。見える札の行の間は 6 → 12 に開く
enum FormChip {
    /// 見た目の札の高さ
    static let height: CGFloat = 32
    /// 札の上下に足す押せるだけの余白（32＋6＋6＝44）
    static let tapSlack: CGFloat = (WebTheme.minTapTarget - height) / 2
    /// 札の左右の間
    static let spacing: CGFloat = 6
    /// 行の間。当たりの箱（44）をそのまま積む
    static let lineSpacing: CGFloat = 0
    /// 当たりを左右へ広げる幅（札の間の半分。外へ広げて同じだけ詰め、並びは変えない）
    static let sideSlack: CGFloat = spacing / 2
    /// 見える札の最小の幅（2026-10-17）。左右の余り（3＋3）を足して当たりの幅も 44 にする。
    /// 1文字の札（「春」「海」）は字＋左右 10 で約 32 しかなく、当たりが約 38 だった
    static let minWidth: CGFloat = WebTheme.minTapTarget - sideSlack * 2
}

extension View {

    /// 札の面（塗りのカプセル・見た目 `FormChip.height`）と、上下 44 の当たり
    func formChipFace(fill: Color) -> some View {
        self
            .frame(minWidth: FormChip.minWidth, minHeight: FormChip.height)
            .background(fill, in: Capsule())
            // 字を大きくして札が 32 を超えても、上下に押せる余白が残る
            .padding(.vertical, FormChip.tapSlack)
            .padding(.horizontal, FormChip.sideSlack)
            .contentShape(Rectangle())
            .padding(.horizontal, -FormChip.sideSlack)
    }
}
