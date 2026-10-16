import SwiftUI

/// プロフィールの色を選ぶ欄（Web の見本8色＋パレットから自由に選ぶ丸と同じ）。
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
                        if index == ThemeColorLayout.rows.count - 1 {
                            customSwatch
                            noneButton
                        }
                    }
                }
            }
            // 透明な枠のぶん（上・左・下の 4）を戻す——先頭の丸の左端を見出しにそろえ、
            // 見出しとの見える間も 8 のまま。最後の行の下にも余りを残さない
            .padding(.leading, -ThemeColorLayout.inset)
            .padding(.vertical, -ThemeColorLayout.inset)
            // 2026-10-16 判断: 暗すぎる色も選べるまま・色は変えない。知らせるだけ（`ThemeColor.isHardToSeeOnBlack`）
            if ThemeColor.isHardToSeeOnBlack(themeColor) {
                Text(L("黒い地の上では見えにくい色です。このままでも保存できます",
                       "This color is hard to see on black. You can still save it."))
                    .font(.caption)
                    .foregroundStyle(WebTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 見本に無い色（ここで選んだ色・Web のパレットで選んだ色）が入っているか
    private var isCustom: Bool { ThemeColor.isCustom(themeColor) }

    /// **パレットから自由に選ぶ丸**（Web の `input type="color"` の丸と同じ見せ方）。
    /// 見本に無い色が入っていればその色で塗り、見本の丸と同じ外側の輪を付ける。
    /// 入っていなければ虹の丸（Web の `conic-gradient`）に白 30% の輪。
    ///
    /// 押せるのは端末の色選び（`ColorPicker`）。**その丸（見た目 約28）は 44 の枠いっぱいに
    /// 広げて、ほぼ透明にして下に敷く**——上の丸は `allowsHitTesting(false)` なので、
    /// 枠のどこを押しても色選びが開く。透明度を 0 にすると押せなくなる（UIKit は
    /// 0.01 未満の部品に当たりを渡さない）ので `pickerOpacity` を残す
    private var customSwatch: some View {
        ZStack {
            ColorPicker(L("プロフィールの色: 自由に選ぶ", "Profile color: pick any color"),
                        selection: Binding(
                            get: { Color(hex: themeColor) ?? Color(hex: ThemeColor.presets[0]) ?? .white },
                            // 同じ色が返ってきたときは書かない（押しただけで見本の色が「自由に選んだ色」に化けない）
                            set: { color in
                                let hex = ThemeColor.hex(of: color)
                                if hex != themeColor.lowercased() { themeColor = hex }
                            }),
                        supportsOpacity: false)
                .labelsHidden()
                .scaleEffect(ThemeColorLayout.target / ThemeColorLayout.pickerWell)
                .opacity(ThemeColorLayout.pickerOpacity)
                .accessibilityLabel(L("プロフィールの色: 自由に選ぶ", "Profile color: pick any color"))
                .accessibilityValue(isCustom ? themeColor.lowercased() : L("未選択", "Not chosen"))
                .accessibilityAddTraits(isCustom ? .isSelected : [])
            Circle()
                .fill(isCustom
                      ? AnyShapeStyle(Color(hex: themeColor) ?? .gray)
                      : AnyShapeStyle(AngularGradient(colors: ThemeColorLayout.rainbow.compactMap { Color(hex: $0) },
                                                      center: .center,
                                                      startAngle: .degrees(-90), endAngle: .degrees(270))))
                .frame(width: ThemeColorLayout.swatch, height: ThemeColorLayout.swatch)
                // 選んでいれば見本と同じ輪（白）、選んでいなければ白 30% の輪（Web の `ring-white/30`）——
                // 暗い色を選んでも丸の在りかが黒い地に消えない
                .overlay(Circle()
                    .strokeBorder(isCustom ? ThemeColorLayout.color(ThemeColorLayout.selectedRing) : Color.white.opacity(0.3),
                                  lineWidth: ThemeColorLayout.ringWidth)
                    .padding(-(ThemeColorLayout.ringGap + ThemeColorLayout.ringWidth)))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(width: ThemeColorLayout.target, height: ThemeColorLayout.target)
        .contentShape(Rectangle())
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
                // 選んでいれば真鍮の塗り＋墨（丸の輪と同じ決まり・2026-10-16 判断。`ThemeColorLayout.selected`）
                .foregroundStyle(themeColor.isEmpty ? ThemeColorLayout.color(ThemeColorLayout.noneSelectedText) : WebTheme.muted)
                .background(themeColor.isEmpty ? ThemeColorLayout.color(ThemeColorLayout.noneSelectedFill) : WebTheme.surface,
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
                    .strokeBorder(ThemeColorLayout.color(ThemeColorLayout.selectedRing), lineWidth: ThemeColorLayout.ringWidth)
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
    /// **選んでいる印の色（2026-10-16 判断: 真鍮）。** 見本8色の丸・「自由に選ぶ」丸の輪は
    /// 真鍮 `#C9A66B`、「なし」の札は真鍮の塗り（accent-fill `#B8955A`）＋墨の字（7.11:1）。
    /// 板は「白＝選択」だが、owner の好み「選んでいるものは真鍮」（CLAUDE.md）を取った。
    /// 欄は黒い地の上（プロフィールの編集）なので真鍮を置いてよい。以前は輪が白・「なし」が白の塗りで、
    /// 同じ欄の中で選択の色が割れないよう3つともそろえる
    static let selectedRing: UInt32 = BrandPalette.accent
    static let noneSelectedFill: UInt32 = BrandPalette.accentFill
    static let noneSelectedText: UInt32 = BrandPalette.ink
    /// 0xRRGGBB から色（`Color(hex:)` を使い回す）
    @MainActor static func color(_ rgb: UInt32) -> Color { Color(hex: ThemeColor.hex(rgb)) ?? .white }
    /// 端末の色選びの丸の見た目（ラベルを隠したとき 約28）。押せる枠 44 まで広げる倍率の元
    static let pickerWell: CGFloat = 28
    /// 下に敷いた色選びの透明度。**0.01 以上**（UIKit はそれ未満の部品に当たりを渡さない）
    static let pickerOpacity: Double = 0.02
    /// 「自由に選ぶ」の丸の虹（Web の `conic-gradient` と同じ並び）
    static let rainbow = ["#f87171", "#fbbf24", "#34d399", "#38bdf8", "#a78bfa", "#f472b6", "#f87171"]
    /// 1行の色の数
    static let columns = 4
    /// 行ごとの色。最後の行の後ろに「自由に選ぶ」の丸と「なし」が付く
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
            // 最後の行は「自由に選ぶ」の丸（枠 44）と「なし」のぶん広い
            CGFloat(row.count) * target + (index == rows.count - 1 ? target + noneWidth : 0)
        }.max().map { $0 - inset } ?? 0
    }
}

extension ThemeColor {
    /// 端末の色選びが返した色を保存の形 `#rrggbb`（小文字）に。
    /// 赤緑青の取り出しはストーリーの文字の「好きな色」と同じ `StoryCanvas.hex(of:)`
    /// （`UIColor.getRed` は拡張 sRGB で返す＝P3 の色は 0〜1 の外。そこで sRGB に詰めて丸める）
    @MainActor static func hex(of color: Color) -> String {
        hex(StoryCanvas.hex(of: color))
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
