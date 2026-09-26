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

    /// `Form` の行に JPField を置くときの行の作法（板は左右 16・区切り線なし）。
    /// **行の内側の余白を消す**——消さないと、同じ画面の札より欄が左右 20pt 狭く、
    /// 端が揃わない。**区切り線も消す**（`listRowBackground(.clear)` では消えない）
    func jpFormRow() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

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
            // 家のバーの下まで同じ色に（ぼかしも黒も安全域へ伸ばす）
            .background(Color.black.opacity(0.55), ignoresSafeAreaEdges: .bottom)
            .background(.ultraThinMaterial, ignoresSafeAreaEdges: .bottom)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            }
    }
}

// MARK: - 札と行（板 43 設定・47 通報）

/// 行を束ねる札（板: 角丸16・地 白7%・縁 白8%）。行の間の線は `JPCardDivider`
struct JPCard<Content: View>: View {

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// 札の中の行と行の間の線（板: 白8%・1pt）
struct JPCardDivider: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
    }
}

/// 札の上の小さい見出し（板: 12px・medium・白60%）
struct JPSectionTitle: View {

    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(WebTheme.faint)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 1つだけ選ぶ行（板 47 の理由: 最小54pt・右に 22pt の丸、選ぶと白い輪と点）。
///
/// **iOS 既定のチェックマークにしない**（板は丸）。読み上げは「選択中」で言う
struct JPRadioRow: View {

    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    Circle()
                        .strokeBorder(Color.white.opacity(selected ? 1 : 0.35), lineWidth: selected ? 2 : 1.5)
                    if selected {
                        Circle().fill(Color.white).frame(width: 10, height: 10)
                    }
                }
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 説明付きの入切の行（板: 15px の名前の下に 11px・白60% の説明、軌道は暗い真鍮）
struct JPToggleRow: View {

    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.text)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(WebTheme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // **軌道は暗い真鍮。** 既定の tint（白）だと、入れたときに白い軌道に
        // 白いつまみが乗り、入か切かが見えない
        .tint(WebTheme.accentDeep)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(minHeight: 54)
    }
}

/// 札の中の1行の見た目（板 43: 最小54pt・左に白72% のアイコン・15px の名前・
/// 11px の説明・右に値（等幅）と矢印）。押す口は呼ぶ側（NavigationLink・Link・
/// Button）が包む——包むときは `.buttonStyle(JPRowButtonStyle())`
struct JPRowLabel: View {

    let title: String
    var systemImage: String?
    var detail: String?
    /// 右に出す値（控えの大きさなど）。等幅
    var value: String?
    /// 矢印。行き先がある行に出す（押すとその場で効く行には出さない）。
    /// 例外はアカウントの削除——板は行き先があっても矢印を出さない
    var chevron = true
    /// 危ない行（アカウントの削除）はアイコンだけ赤（板どおり、名前は白のまま）
    var iconColor: Color = WebTheme.muted2

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 17))
                    .foregroundStyle(iconColor)
                    .frame(width: 24)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.text)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(WebTheme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let value {
                Text(value)
                    .font(JPFont.mono(13, relativeTo: .footnote))
                    .foregroundStyle(WebTheme.faint)
                    .lineLimit(1)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }
}

/// 札の中の行を押したときの手応え（押している間だけ行の地を白6%に）。
///
/// **`.plain` では足りない。** List の行は押すと灰色になったが、`.plain` は字が
/// 少し薄くなるだけで、押せる行と表示だけの行の見分けがつかなかった
struct JPRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.06 : 0))
    }
}
