import SwiftUI

/// 新しい操作のそばに置く小さな「使ってみてどう？」（札 #546・2026-11-11）。
///
/// 押すと意見を送るシート（`FeedbackSheet`）が開き、すぐ書ける（押す回数: 開く → 書く → 送る）。
/// 👍／👎 の2択は置かない（owner 2026-11-11「形式は自由記述」）。
///
/// 形: 黒地の上の1行。問いかけは text-2、押せる所は真鍮（黒地の上のリンク・owner の好み「デザインの箇所は白より真鍮」）。
/// 行ぜんたいが1つのボタンで、当たりは 44。読み上げは「使ってみてどう？ ひとこと送る」
struct FeedbackPrompt: View {

    /// どの画面のそばか（サーバーの `screen`）
    let screen: String

    @State private var showSheet = false

    var body: some View {
        Button { showSheet = true } label: {
            HStack(spacing: JPSpace.xs) {
                Text(L("使ってみてどう？", "How's it going?"))
                    .foregroundStyle(WebTheme.text2)
                Text(L("ひとこと送る", "Tell us"))
                    .foregroundStyle(WebTheme.accent)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WebTheme.accent)
                    .accessibilityHidden(true)
            }
            .font(JPFont.caption)
            .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("feedback.prompt")
        .sheet(isPresented: $showSheet) {
            FeedbackSheet(screen: screen)
        }
    }
}
