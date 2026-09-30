import SwiftUI

/// プロフィールの色を選ぶ欄（Web の見本8色と同じ）。
struct ThemeColorField: View {

    @Binding var themeColor: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("プロフィールの色", "Profile color"))
                .font(.caption)
                .foregroundStyle(.secondary)
            // **丸は Web と同じ 36、押せる枠は 44、並びの間は 0**（見える間は 8。Web は 10）。
            // 8色＋「なし」を1行に並べると 44×9＝396 で、フォームの行（393pt 幅の端末で約313〜329）
            // に入らず、端末ごとに違うところで割れる。**4色ずつ2行に決めて並べる**（`ThemeColorLayout`）
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(ThemeColorLayout.rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 0) {
                        ForEach(row, id: \.self) { hex in
                            swatch(hex)
                        }
                        if index == ThemeColorLayout.rows.count - 1 { noneButton }
                    }
                }
            }
            // 透明な枠のぶん（上・左・下の 4）を戻す——先頭の丸の左端を見出しにそろえ、
            // 見出しとの見える間も 8 のまま。最後の行の下にも余りを残さない
            .padding(.leading, -ThemeColorLayout.inset)
            .padding(.vertical, -ThemeColorLayout.inset)
        }
    }

    /// **選ばない**に戻せるようにする（押しても何も起きない状態を作らない）
    private var noneButton: some View {
        Button {
            themeColor = ""
        } label: {
            Text(L("なし", "None"))
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(themeColor.isEmpty ? WebTheme.accentText : WebTheme.muted)
                .background(themeColor.isEmpty ? WebTheme.accentBackground : WebTheme.surface,
                            in: Capsule())
                // 札（高さ約26）の外側だけ広げる（`background` より後ろ＝見た目は変えない）
                .webTappable()
        }
        .buttonStyle(.borderless)
        // 丸の枠の余白 4 と足して、丸と札の見える間を 8 以上に
        .padding(.leading, ThemeColorLayout.inset)
        .accessibilityAddTraits(themeColor.isEmpty ? .isSelected : [])
    }

    private func swatch(_ hex: String) -> some View {
        let chosen = themeColor.lowercased() == hex
        return Button {
            themeColor = hex
        } label: {
            Circle()
                .fill(Color(hex: hex) ?? .gray)
                .frame(width: ThemeColorLayout.swatch, height: ThemeColorLayout.swatch)
                // 選んだ印は **外側の輪**（Web の `ring-2 ring-offset-2`）。間 2・輪 2 で、
                // 枠の余白 4 にちょうど収まる（輪の外径 44＝押せる枠）
                .overlay(Circle()
                    .strokeBorder(.primary, lineWidth: ThemeColorLayout.ringWidth)
                    .padding(-(ThemeColorLayout.ringGap + ThemeColorLayout.ringWidth))
                    .opacity(chosen ? 1 : 0))
                .frame(width: ThemeColorLayout.target, height: ThemeColorLayout.target)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(L("色 \(hex)", "Color \(hex)"))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// 色の丸の寸法と並べ方（`ThemeColorField`）。
enum ThemeColorLayout {
    /// 丸の見た目（Web の `w-9 h-9`＝36）
    static let swatch: CGFloat = 36
    /// 押せる枠（44）。枠どうしは間 0 で並べる（重ならない・見える間は 8）
    static let target: CGFloat = 44
    /// 丸の周りの透明な余白（片側）
    static var inset: CGFloat { (target - swatch) / 2 }
    /// 選んだ印の輪と丸の間・輪の太さ（Web の `ring-offset-2`・`ring-2`）。足して `inset` に収める
    static let ringGap: CGFloat = 2
    static let ringWidth: CGFloat = 2
    /// 1行の色の数
    static let columns = 4
    /// 行ごとの色。最後の行の後ろに「なし」が付く
    static var rows: [[String]] {
        stride(from: 0, to: ThemeColor.presets.count, by: columns).map {
            Array(ThemeColor.presets[$0..<min($0 + columns, ThemeColor.presets.count)])
        }
    }
    /// 「なし」の札の押せる幅の見積もり（字 2つ＋左右 10 の札を 44 の枠に入れ、左に 4 空ける）。
    /// 英語の「None」でも札は約 52
    static let noneWidth: CGFloat = 56
    /// いちばん広い行の幅（左の余白 4 を戻したあと）
    static var widestRow: CGFloat {
        rows.enumerated().map { index, row in
            CGFloat(row.count) * target + (index == rows.count - 1 ? noneWidth : 0)
        }.max().map { $0 - inset } ?? 0
    }
}

extension Color {
    /// `#rrggbb` から。読めない値は nil（**既定色に化かさない**——
    /// 化かすと「保存できていないのに色が付いて見える」）。
    init?(hex: String) {
        guard let rgb = ThemeColor.rgb(hex) else { return nil }
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
