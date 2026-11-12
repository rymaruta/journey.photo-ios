import SwiftUI
import UIKit
#if canImport(SafariServices)
import SafariServices
#endif

/// 使い方（Web の `/help`・2026-11-12 札 #517・owner「使い方を優先的に作りたいな」）。
///
/// 中身は Web の頁（機能ごとに絵1枚と3行）。アプリの入口は **設定 → ヘルプと規約 → 使い方 の1か所だけ**
/// （資料「説明なしで分かるアプリ」の決まり。ほかの画面に入口を増やさない・`HelpEntryTests` が見張る）。
///
/// 2026-11-12 判断: **アプリの中の Safari（`SFSafariViewController`）で開く。** 頼まれた形は「規約と同じ開き方」
/// だったが、規約の行は `Link`（Safari のアプリへ出る）だった。資料の推奨は「アプリの中の Safari の窓」で、
/// 読み終えたら「閉じる」で設定に戻れる方が迷わない（Safari のアプリへ出ると、戻るのに左上の小さな戻るが要る）。
/// 規約の開き方は変えていない。
enum HelpLink {
    static var url: URL { AppConfig.siteBaseURL.appendingPathComponent("help") }
    static var title: String { L("使い方", "How to use") }
    static var detail: String { L("機能ごとに、絵と3行で", "Each feature in a picture and three lines") }
}

/// アプリの中の Safari の窓。「閉じる」で呼び手の `fullScreenCover` を閉じる。
/// Linux の模型（Shims）には SafariServices が無いので、中身だけを分ける（型は1つ）
struct InAppSafariView: View {
    let url: URL

    var body: some View {
        #if canImport(SafariServices)
        SafariController(url: url)
        #else
        EmptyView()
        #endif
    }
}

#if canImport(SafariServices)
private struct SafariController: UIViewControllerRepresentable {

    let url: URL

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        // 帯は黒、押せる字は真鍮（黒い地の上だけ・板 DesignSystem）
        controller.preferredBarTintColor = .black
        controller.preferredControlTintColor = UIColor(WebTheme.accent)
        controller.dismissButtonStyle = .close
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: { dismiss() })
    }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        private let dismiss: () -> Void

        init(dismiss: @escaping () -> Void) {
            self.dismiss = dismiss
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            dismiss()
        }
    }
}
#endif
