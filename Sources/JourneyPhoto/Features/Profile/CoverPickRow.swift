import SwiftUI

/// プロフィールの編集の「カバーにする写真」（#304・板 50 CoverPick・2026-10-18）。
///
/// 自分の投稿のうち全体に公開している写真から4枚（いいねの多い順／最近）。押すと上の帯がすぐ替わり
/// （編集の見本に入る）、ほかの人に見えるのは右上の「保存」のあと（編集のいままでの約束どおり）。
/// 眉ラベルは黒地の上なので真鍮。並べ方は選んでいる方を白い塗り（板どおり・ほかの画面の絞り込みと同じ形）。
/// 選んだ1枚は真鍮の輪（黒地の上）と、写真の上の白い印。いいねの数は出さない（競う数にしない）
struct CoverPickRow: View {
    /// 自分の写真（nil は読み込み中・読めなかった）
    let photos: [Photo]?
    @Binding var sort: CoverCandidates.Sort
    let selectedId: String?
    let disabled: Bool
    let onPick: (Photo) -> Void
    /// 投稿が無い人の「写真を投稿する」
    let onPost: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("カバーにする写真", "Cover from your posts"))
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                Spacer(minLength: 8)
                if let photos, !CoverCandidates.cover(photos, sort: sort).isEmpty {
                    sortPicker
                }
            }
            if let photos {
                let thumbs = CoverCandidates.cover(photos, sort: sort)
                if thumbs.isEmpty {
                    empty
                } else {
                    grid(thumbs)
                    Text(L("押すと、上の帯がすぐ替わります。ほかの人に見えるのは「保存」のあとです。",
                           "Tap to preview it above. Others see it after you tap Save."))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profileEdit.coverPick")
    }

    private var sortPicker: some View {
        HStack(spacing: 6) {
            ForEach(CoverCandidates.Sort.allCases) { option in
                let on = sort == option
                Button { sort = option } label: {
                    HStack(spacing: 4) {
                        if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                        Text(option.title)
                    }
                    .font(JPFont.caption.weight(.semibold))
                    .foregroundStyle(on ? WebTheme.accentText : WebTheme.muted)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(on ? WebTheme.accentBackground : Color.clear, in: Capsule())
                    .overlay(Capsule().strokeBorder(on ? Color.clear : WebTheme.line, lineWidth: 1))
                    // 見た目は 32、当たりは 44
                    .frame(minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("profileEdit.coverSort.\(option.rawValue)")
            }
        }
    }

    private func grid(_ thumbs: [Photo]) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(thumbs.enumerated()), id: \.element.id) { index, photo in
                let on = selectedId == photo.id
                Button { onPick(photo) } label: {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay { RemoteImage(url: photo.gridImageURL) }
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .topTrailing) {
                            if on {
                                // 写真の上なので白
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(WebTheme.accentText)
                                    .frame(width: 20, height: 20)
                                    .background(Color.white, in: Circle())
                                    .padding(4)
                            }
                        }
                        // 選んでいる1枚は真鍮の輪（黒地の上・2pt の隙間）
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(on ? WebTheme.accent : .clear, lineWidth: 2)
                            .padding(-4))
                        .frame(minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(disabled)
                .accessibilityLabel(L("\(sort.title)の \(index + 1) 枚目をカバーにする",
                                      "Use photo \(index + 1) (\(sort.title)) as cover"))
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("profileEdit.coverPick.\(index)")
            }
        }
        .padding(4)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("写真を投稿すると、いいねの多いものと最近のものがここに並びます。",
                   "Once you post photos, your most liked and most recent ones show up here."))
                .font(JPFont.footnote)
                .foregroundStyle(WebTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
            // 写真の無い画面の主ボタン＝真鍮の塗りに墨（owner の好み）
            Button(action: onPost) {
                Text(L("写真を投稿する", "Post a photo"))
                    .font(JPFont.body.weight(.semibold))
                    .foregroundStyle(WebTheme.accentText)
                    .padding(.horizontal, 16)
                    .frame(minHeight: WebTheme.minTapTarget)
                    .background(WebTheme.accentFill, in: Capsule())
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.m))
    }
}
