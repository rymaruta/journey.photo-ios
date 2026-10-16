import SwiftUI

/// 「通知がオフのため届きません」の行（板 Settings の F31 の行: 真鍮 8% の地・真鍮の字と線の絵・矢印）。
///
/// Pro の「前の晩に知らせる」（`LightAlertSettingsRows`）に在ったものを、すれちがいの設定でも
/// 使うので部品に出した（2026-10-16 判断・写しを作らない）。押したときの処理（許可を求める・設定アプリを開く）は
/// 呼ぶ側が持つ。札（`JPCard`）の中に置く
struct PushOffNoticeRow: View {

    let notice: LightAlertPushNotice
    var isBusy = false
    let identifier: String
    let action: () -> Void

    var body: some View {
        // 🔴 **地はボタンに付けず、後ろに別の層として敷く**（2026-10-16・owner の実機で、帯の上の2つの角が
        // 丸く抜けて札の地が見えていた）。コードは矩形の `.background` だったが、ボタンに付けた地は
        // OS の側で角を丸められうる。ただの `Rectangle` を `ZStack` の下に置けば、角は札（`JPCard`）の
        // 切り抜きだけが決める
        ZStack {
            // 板 v2 の brass-soft（#1C170E・真鍮 8% を黒に重ねた値）。選択は担わない、案内の帯の色
            Rectangle()
                .fill(WebTheme.accentSoft)
                .accessibilityHidden(true)
            pushNoticeButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pushNoticeButton: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "bell.slash")
                    .font(.system(size: 18))
                    .frame(width: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(notice.title)
                        .font(JPFont.bodyEmphasis)
                    Text(notice.detail)
                        .font(JPFont.caption)
                        // 板 v2: 帯の中の説明も真鍮（85%）。真鍮 8% の地の上で 5.9:1
                        .foregroundStyle(WebTheme.accent.opacity(LightAlertSettingsStyle.noticeDetailOpacity))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(WebTheme.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(isBusy)
        .accessibilityElement(children: .combine)
        .accessibilityHint(notice.hint)
        .accessibilityIdentifier(identifier)
    }
}
