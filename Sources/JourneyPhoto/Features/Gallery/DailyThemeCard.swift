import SwiftUI

/// 今日のテーマ（モック1 の「今日のミッション」）。
///
/// **通信をしない。** テーマは日付から決まり（`DailyTheme`）、参加したか
/// どうかは自分の写真を見て決める。サーバーにテーマを配る口も、参加を
/// 数える口も無いので、**参加人数のような数は出さない**。
struct DailyThemeCard: View {

    /// 自分の写真（参加したかの判定に使う）
    let myPhotos: [Photo]

    private var theme: DailyTheme.Theme { DailyTheme.today() }
    private var joined: Bool { DailyTheme.hasJoined(theme, myPhotos: myPhotos) }

    /// **細い帯1本**（整理案 01c・2026-09-26）。
    ///
    /// 以前はフィードの先頭に高さ200pt近い札（眉・題・説明・大きなボタン・
    /// 背景の写真）を置いていて、開いた瞬間に写真が見えなかった。
    /// 1枚目の写真の後ろに、題・タグ・参加の口だけを1行で置く。
    /// 説明文（`theme.prompt`）は読み上げにだけ残す
    var body: some View {
        HStack(spacing: 10) {
            Text(L("今日のテーマ", "Today's theme"))
                .jpEyebrow()
                .foregroundStyle(WebTheme.accent)
                .lineLimit(1)
                .fixedSize()
            Text(theme.title)
                .font(JPFont.rowTitle)
                .foregroundStyle(WebTheme.foreground)
                .lineLimit(1)
            Text("#\(theme.tag)")
                .font(.caption)
                .foregroundStyle(WebTheme.muted2)
                .lineLimit(1)
            Spacer(minLength: 4)
            if joined {
                // **参加済みは「押せない印」にする。** 同じ日に何度も
                // 促さない（写真は自分の写真から確かめたもの）
                Label(L("参加済み", "Joined"), systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WebTheme.muted2)
                    .fixedSize()
                    .padding(.trailing, 8)
            } else {
                Button {
                    MissionRouter.shared.join(tag: theme.tag)
                } label: {
                    Text(L("参加する", "Join"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WebTheme.accentText)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(WebTheme.foreground, in: Capsule())
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .frame(minHeight: WebTheme.minTapTarget)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(minHeight: 52)
        .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityHint(theme.prompt)
        .padding(.horizontal, 16)
    }
}
