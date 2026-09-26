import SwiftUI

/// 入力と確定の部品（板 41〜47「はじめる・安全・設定」の列）。
///
/// **板は7画面とも同じ3つの形を使っている**——見出し付きの 48pt の欄、
/// 52pt のカプセル、下に固定したぼかしの帯。以前は画面ごとに書き分けて
/// いて、同じ「パスワードの欄」でもログインは枠付き・変更は素の行、と割れていた。

/// 見出し付きの入力欄（板: 12px・medium・白72% の見出し ＋ 48pt・角丸12・
/// 地6%・縁12% の欄）。複数行（通報の補足）は 88pt。
///
/// **字は文字の大きさの設定に追従させる**（`.caption` = 12・`.subheadline` = 15 が
/// 既定の大きさで板の px と同じ。固定の pt にすると、大きな文字の人だけ読めない）
struct JPField<Content: View>: View {

    let title: String
    var multiline = false
    let content: Content

    init(_ title: String, multiline: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.multiline = multiline
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(WebTheme.muted2)
                // 読み上げは欄の名前で言う（見出しと二重に読まない）
                .accessibilityHidden(true)
            content
                .font(.subheadline)
                .accessibilityLabel(title)
                .padding(.horizontal, 14)
                .padding(.vertical, multiline ? 12 : 0)
                .frame(maxWidth: .infinity, minHeight: multiline ? 88 : 48,
                       alignment: multiline ? .topLeading : .leading)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WebTheme.border, lineWidth: 1))
        }
    }
}

/// 52pt のカプセル（板の確定ボタン）。幅いっぱい・`.callout`（既定 16pt）semibold。
///
/// **`webPrimaryButton` は変えない。** そちらは約44pt で、プロフィールの
/// フォローなど行の中のボタンが使っている
enum JPPillStyle {
    /// 白 92% に墨の字（1画面に1つ）
    case primary
    /// 枠線（白28%）に白の字（「アカウントを作る」など2番手）
    case outline
    /// 赤の塗りに白の字（アカウントの削除だけ）
    case danger

    @MainActor var fill: Color {
        switch self {
        case .primary: return WebTheme.accentBackground
        case .outline: return Color.clear
        case .danger: return WebTheme.dangerFill
        }
    }
}

extension View {

    func jpPillButton(_ style: JPPillStyle = .primary) -> some View {
        self
            .font(.callout.weight(.semibold))
            .foregroundStyle(style == .primary ? WebTheme.accentText : Color.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(style.fill, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(style == .outline ? 0.28 : 0), lineWidth: 1))
            .contentShape(Capsule())
    }

    /// 下に固定する帯（板: 黒55%＋ぼかし＋上に白8% の線・余白 12/16/下）。
    /// `safeAreaInset(edge: .bottom)` の中身に付ける。下の余白は安全域の上に
    /// 足す分（板の 34 は家のバーの分なので、ここでは入れない）
    func jpBottomBar() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.55))
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            }
    }
}
