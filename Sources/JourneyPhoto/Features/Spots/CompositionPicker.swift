import SwiftUI

/// 構図のシート（2026-10-10・「構図を重ねて撮る」）。撮る画面の「構図」の行から開く。
///
/// v2 の板 ComposeGuide の「構図のシート」の形（2026-10-14 に作り替えた）:
/// - 地は投稿のシートと同じ surface-2。見出し「構図」は明朝 22、右上に閉じる（白 8% の丸・44pt）
/// - 見出しの下に段へ飛ぶチップ（押すとその段まで送る）
/// - 段ごとに眉ラベル（11pt・真鍮＝黒地の上の手がかり・CLAUDE.md の owner の好み）
/// - **1行ずつの札**（v1 は3列の格子）: 小さな絵（3:4）＋名前 15＋難しさ 12（本文系の最小）
/// - **選んでいる札は真鍮の縁 2pt＋チェック**（owner の決定 2026-10-10。黒地の上。色だけで伝えないよう
///   チェックの印と読み上げの「選択中」も付ける）
/// - 先頭の段「よく使う」に「なし」と最近の4つ。下に「線の濃さ」（0.15〜0.7・既定 0.35）と今の %
/// - **札の右に作例写真**（2026-10-17 owner・`CompositionExampleThumb`。構図一覧の行と同じ形）
struct CompositionPicker: View {

    /// 選んでいる構図（nil は「なし」）
    let selected: CompositionKind?
    /// 最近の構図（新しい順）
    let recents: [CompositionKind]
    /// 構図ごとの向き（小さな絵に使う）
    let variant: (CompositionKind) -> Int
    @Binding var lineOpacity: Double
    /// 構図を選んだ（nil は「なし」）。選んだらシートを閉じる
    let onSelect: (CompositionKind?) -> Void

    @Environment(\.dismiss) private var dismiss

    /// シートの地（v2: 投稿のシートと同じ surface-2・`WebTheme.sheet`）
    @MainActor private static var sheetBackground: Color { WebTheme.sheet }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 0) {
                    chips(proxy)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            group(id: "recent", title: L("よく使う", "Recent"), kinds: recents, includesNone: true)
                            ForEach(CompositionSection.allCases) { section in
                                group(id: section.id, title: section.title, kinds: section.kinds, includesNone: false)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                    }
                }
            }
            opacityRow
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Self.sheetBackground)
        .preferredColorScheme(.dark)
    }

    // MARK: - 見出し

    private var header: some View {
        HStack {
            // v2: 見出しは明朝 22、閉じるは白 8% の丸（投稿のシートと同じ形）
            Text(L("構図", "Composition"))
                .font(JPFont.cardTitle)
                .foregroundStyle(WebTheme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(WebTheme.foreground)
                    .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Labels.Common.close)
            .accessibilityIdentifier("composition.close")
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.top, 16)
    }

    /// 段へ飛ぶチップ（表示の切り替えではなく送るだけ。白 7% の地・白の字、当たりは 44pt）
    private func chips(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CompositionSection.allCases) { section in
                    Button {
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(section.id, anchor: .top) }
                    } label: {
                        Text(section.chip)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(WebTheme.text)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 32)
                            .background(WebTheme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
                            // 見た目 32・当たり 44（板の決まり）
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(L("この段まで送ります", "Scrolls to this group"))
                    .accessibilityIdentifier("composition.chip.\(section.id)")
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - 段

    private func group(id: String, title: String, kinds: [CompositionKind], includesNone: Bool) -> some View {
        VStack(alignment: .leading, spacing: JPSpace.xs) {
            Text(title)
                .jpEyebrow()
                .foregroundStyle(WebTheme.accent)
                .accessibilityAddTraits(.isHeader)
            // v2 ComposeGuide の構図のシート: **1行ずつの札**（v1 は3列の格子）。名前と難しさが読みやすく、
            // 指も当てやすい
            VStack(spacing: JPSpace.xs) {
                if includesNone { card(nil) }
                ForEach(kinds) { kind in card(kind) }
            }
        }
        .id(id)
    }

    /// 札（v2: 最小 60・角 14・地は札の面・縁は白 8%）。左に小さな絵（3:4）、名前 15・難しさ 12。
    /// **選んでいる札は真鍮の縁 2pt＋右に真鍮のチェック**（owner の決定 2026-10-10・黒地の上。
    /// 色だけで伝えないよう、チェックの印と読み上げの「選択中」も付ける）
    private func card(_ kind: CompositionKind?) -> some View {
        let isSelected = kind == selected
        return Button {
            onSelect(kind)
            dismiss()
        } label: {
            HStack(spacing: JPSpace.s) {
                CompositionThumbnail(kind: kind, variant: kind.map(variant) ?? 0, cornerRadius: JPRadius.xs)
                    .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
                    .frame(width: Self.thumbBox, height: Self.thumbBox)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind?.name ?? CompositionGuide.noneName)
                        .font(JPFont.body.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let kind {
                        Text(kind.difficulty.label)
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.text3)
                    }
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(WebTheme.accent)
                        .accessibilityHidden(true)
                }
                // 2026-10-17 owner: 右に作例写真（どんな場面で使う構図か、撮る前に分かるように）
                if let kind { CompositionExampleThumb(kind: kind) }
            }
            .padding(.horizontal, JPSpace.s)
            .padding(.vertical, JPSpace.xxs)
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
            .background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.m))
            .overlay(RoundedRectangle(cornerRadius: JPRadius.m)
                .strokeBorder(isSelected ? WebTheme.accent : WebTheme.hairline,
                              lineWidth: isSelected ? JPStroke.emphasis : JPStroke.hairline))
            .contentShape(RoundedRectangle(cornerRadius: JPRadius.m))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.map { L("\($0.name)、\($0.difficulty.label)", "\($0.name), \($0.difficulty.label)") }
                            ?? CompositionGuide.noneName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(kind?.tip ?? L("線を重ねません", "No lines"))
        .accessibilityIdentifier("composition.card.\(kind?.rawValue ?? "none")")
    }

    /// 札の高さと小さな絵（3:4 を 44 の枠に）。板は 60 だが、右に作例写真（64）を置くので 72（2026-10-17）
    static let rowHeight: CGFloat = 72
    static let thumbBox: CGFloat = 44
    static let thumbSize = (width: CGFloat(33), height: CGFloat(44))

    // MARK: - 線の濃さ

    private var opacityRow: some View {
        HStack(spacing: 12) {
            Text(L("線の濃さ", "Line opacity"))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .accessibilityHidden(true)
            Slider(value: $lineOpacity, in: CompositionGuide.lineOpacityRange)
                .tint(WebTheme.foreground)
                .accessibilityLabel(L("線の濃さ", "Line opacity"))
                .accessibilityValue(lineOpacityText)
                .accessibilityIdentifier("composition.lineOpacity")
            // v2: 数を右に等幅で出す（板の「55%」）
            Text(lineOpacityText)
                .font(JPFont.mono(13, relativeTo: .footnote))
                .foregroundStyle(WebTheme.text)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, JPSpace.l)
        .padding(.vertical, JPSpace.s)
        .frame(minHeight: WebTheme.minTapTarget)
        .background(Self.sheetBackground)
        .overlay(alignment: .top) { Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline) }
    }

    private var lineOpacityText: String {
        "\(Int((CompositionGuide.clampedLineOpacity(lineOpacity) * 100).rounded()))%"
    }
}
