import SwiftUI

/// 「作例・構図を重ねて撮る」を開くまでの流れ（2026-10-10 に `OfficialSpotView.openComposeGuide` から切り出した）。
///
/// 入口は2つ: 撮影スポットの頁（作例つき）と、投稿のシートの「構図を重ねて撮る」（作例なし）。
/// どちらも同じ流れを通る。
///
/// 2026-10-17 判断（owner）: **全員無料。** 以前は開く前にサーバーのプロフィールの `pro` を読み、
/// Pro でなければ Pro の案内（`PaywallView`）、読めなければ「つながりません」の知らせを出していた。
/// いまは**開く前にサーバーへ何も聞かない**——圏外でも、ログインしていなくても、押せばすぐ開く。
/// ログインが要るのは撮った1枚を「投稿」したときだけで、投稿画面（`UploadView`）がログインを求める
/// （写真への保存は端末の中だけで済む）。
///
/// 開いている間は開き直さない（素早い2回押しで全画面が開き直し、カメラの開始・停止が二重になる・2026-10-10）。
/// 撮る画面に渡すもの（作例の並び・始める1枚）は**開く時点で作る**（`make`・`ComposeGuide.Launch` の注記）。
@MainActor
final class ComposeGuideLauncher: ObservableObject {

    /// 撮る画面を開く頼み（`fullScreenCover(item:)`）。nil なら閉じている
    @Published var launch: ComposeGuide.Launch?

    /// 押した結果（試験に使う）
    enum Outcome: Equatable {
        case opened
        /// 開いている最中で何もしなかった
        case ignored
    }

    /// 入口を押した。誰でも撮る画面へ進む（Pro・ログイン・電波を問わない）
    /// - Parameter make: 撮る画面に渡す頼みを作る（開く時点で呼ぶ）
    @discardableResult
    func open(make: () -> ComposeGuide.Launch) -> Outcome {
        guard launch == nil else { return .ignored }
        launch = make()
        return .opened
    }
}

/// 撮る画面を出す（入口の画面に付ける）
struct ComposeGuidePresenter: ViewModifier {

    @ObservedObject var launcher: ComposeGuideLauncher
    /// 撮影地の名前（作例なしの入口は nil）
    let spotName: String?
    /// 撮った1枚を投稿へ進める（投稿のシートの入口・撮影スポットの作例の入口）。nil なら「投稿する」を出さない
    var onPost: ((CameraCapture) -> Void)?
    /// 撮る画面を閉じきった
    var onDismiss: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $launcher.launch, onDismiss: { onDismiss?() }) { launch in
                ComposeGuideView(spotName: spotName, samples: launch.samples, startIndex: launch.start, onPost: onPost)
            }
    }
}

extension View {
    /// 撮る画面（`ComposeGuidePresenter`）
    func composeGuidePresenter(_ launcher: ComposeGuideLauncher, spotName: String?,
                               onPost: ((CameraCapture) -> Void)? = nil,
                               onDismiss: (() -> Void)? = nil) -> some View {
        modifier(ComposeGuidePresenter(launcher: launcher, spotName: spotName, onPost: onPost, onDismiss: onDismiss))
    }
}
