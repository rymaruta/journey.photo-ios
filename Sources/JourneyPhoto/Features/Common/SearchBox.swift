import SwiftUI

extension View {

    /// **探す欄の地と縁**（v2・2026-10-14・Search の板: 左右 14・最小 44・地 surface-2（#161617）・縁 白 8%・角 12）。
    /// 探すの上の欄（`SearchView.searchField`）と、撮影スポットの一覧の欄（`SearchBox`）で同じ（札 #524 で切り出した）
    func jpSearchBoxFace() -> some View {
        self
            .padding(.horizontal, 14)
            // 最小44（板）。大きな文字の設定では字に合わせて伸ばす（固定だと上下が欠ける）
            .frame(minHeight: WebTheme.minTapTarget)
            .background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: JPRadius.field))
            .overlay(RoundedRectangle(cornerRadius: JPRadius.field).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
    }
}

/// 画面の中で一覧を絞る探す欄（虫眼鏡・字・消す「×」）。見た目は探すの上の欄と同じ（`jpSearchBoxFace`）。
///
/// 2026-11-11 判断（札 #524）: `.searchable` は使わない。押し進めた画面では題の下に畳まれ、引き下げないと
/// 出ない（触って分からない）。探すの上の欄と同じ形を一覧の上に常に出す
struct SearchBox: View {

    let prompt: String
    @Binding var text: String
    /// 実機の絵・UI テストの道しるべ（字の欄）。「×」は `<identifier>.clear`
    var identifier: String = "searchBox.field"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17))
                .foregroundStyle(WebTheme.text3)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(WebTheme.foreground)
                .autocorrectionDisabled()
                .accessibilityIdentifier(identifier)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    // 押せる幅は 44pt（探すの上の欄の「×」と同じ）
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(WebTheme.text3)
                        .webTappable()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("消す", "Clear"))
                .accessibilityIdentifier("\(identifier).clear")
            }
        }
        .jpSearchBoxFace()
    }
}
