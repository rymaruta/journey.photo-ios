import SwiftUI

/// 構図のシート（2026-10-10・「構図を重ねて撮る」）。撮る画面の「構図」の行から開く。
///
/// 板に構図のシートは無いので、板の決まりに合わせて作った（`/design-check`）:
/// - 地は投稿のシートと同じ #0d0d0e。見出し「構図」は明朝 18（明朝の下限）、右上に閉じる（44pt）
/// - 見出しの下に段へ飛ぶチップ（押すとその段まで送る）
/// - 段ごとに眉ラベル（11pt・真鍮＝黒地の上の手がかり・CLAUDE.md の owner の好み）
/// - 3列の札: 3:4 の小さな絵＋名前 13pt＋難しさ 12pt（本文系の最小）
/// - **選んでいる札は真鍮の縁 2pt＋チェック**（owner の決定 2026-10-10。黒地の上。色だけで伝えないよう
///   チェックの印と読み上げの「選択中」も付ける）
/// - 先頭の段「よく使う」に「なし」と最近の4つ。下に「線の濃さ」（0.15〜0.7・既定 0.35）
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

    /// シートの地（投稿のシートと同じ #0d0d0e）
    private static let sheetBackground = Color(red: 13 / 255, green: 13 / 255, blue: 14 / 255)

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 0) {
                    chips(proxy)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
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
            Text(L("構図", "Composition"))
                .font(JPFont.display(18, relativeTo: .headline))
                .foregroundStyle(WebTheme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(WebTheme.foreground)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
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
                            .overlay(Capsule().strokeBorder(WebTheme.border, lineWidth: 1))
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
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .jpEyebrow()
                .foregroundStyle(WebTheme.accent)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                if includesNone { card(nil) }
                ForEach(kinds) { kind in card(kind) }
            }
        }
        .id(id)
    }

    /// 札: 3:4 の小さな絵＋名前＋難しさ。選んでいる札は真鍮の縁 2pt＋チェック
    private func card(_ kind: CompositionKind?) -> some View {
        let isSelected = kind == selected
        return Button {
            onSelect(kind)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                CompositionThumbnail(kind: kind, variant: kind.map(variant) ?? 0, cornerRadius: 8)
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8).strokeBorder(WebTheme.accent, lineWidth: 2)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            ZStack {
                                Circle().fill(Color.black).frame(width: 16, height: 16)
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(WebTheme.accent)
                            }
                            .padding(5)
                        }
                    }
                Text(kind?.name ?? CompositionGuide.noneName)
                    .font(.footnote.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let kind {
                    Text(kind.difficulty.label)
                        .font(.caption)
                        .foregroundStyle(WebTheme.muted2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.map { L("\($0.name)、\($0.difficulty.label)", "\($0.name), \($0.difficulty.label)") }
                            ?? CompositionGuide.noneName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(kind?.tip ?? L("線を重ねません", "No lines"))
        .accessibilityIdentifier("composition.card.\(kind?.rawValue ?? "none")")
    }

    // MARK: - 線の濃さ

    private var opacityRow: some View {
        HStack(spacing: 12) {
            Text(L("線の濃さ", "Line opacity"))
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.7))
                .accessibilityHidden(true)
            Slider(value: $lineOpacity, in: CompositionGuide.lineOpacityRange)
                .tint(WebTheme.foreground)
                .accessibilityLabel(L("線の濃さ", "Line opacity"))
                .accessibilityValue("\(Int((CompositionGuide.clampedLineOpacity(lineOpacity) * 100).rounded()))%")
                .accessibilityIdentifier("composition.lineOpacity")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Self.sheetBackground)
        .overlay(alignment: .top) { Rectangle().fill(WebTheme.border).frame(height: 1) }
    }
}
