import SwiftUI

/// **眉ラベルと、右へ消えていく真鍮の 1px の線**（v2 の板 02 Eyebrow・Components 05 の節の見出し）。
///
/// 板の形: 11pt・SF 600・字間 0.14em の真鍮の字 → 10 のすき間 → 真鍮 55% から 0 へ消える 1px の線。
/// 右に添え書き（「2019 年から」など・12pt の text-3）を置ける。
///
/// **黒地の上だけ**（真鍮は写真の上では読めない・CLAUDE.md）。写真の上の眉ラベルは
/// `jpEyebrow()` を白で使う。
///
/// マイページの旅の記録（`TravelRecordView`）もこの部品を使う（字の太さは板の 600）
struct JPEyebrowLine: View {

    let text: String
    /// 読み上げの名前（英字の眉を日本語で読ませるとき）。無ければ `text`
    var spoken: String?
    /// 線の右に添える一言（「2019 年から」）
    var trailing: String?

    /// 線の濃さ（真鍮の 55% → 0）
    nonisolated static let lineStartOpacity = 0.55
    /// 字と線のすき間（板の gap 10）
    nonisolated static let gap: CGFloat = 10

    init(_ text: String, spoken: String? = nil, trailing: String? = nil) {
        self.text = text
        self.spoken = spoken
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: Self.gap) {
            Text(text)
                .jpEyebrow()
                .foregroundStyle(WebTheme.accent)
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel(spoken ?? text)
                .accessibilityAddTraits(.isHeader)
            LinearGradient(colors: [WebTheme.accent.opacity(Self.lineStartOpacity), WebTheme.accent.opacity(0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: JPStroke.hairline)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            if let trailing {
                Text(trailing)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.faint)
                    .lineLimit(1)
            }
        }
    }
}
