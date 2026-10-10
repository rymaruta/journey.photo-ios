import SwiftUI

/// 「作例・構図を重ねて撮る」（Pro）を開くまでの流れ（2026-10-10 に `OfficialSpotView.openComposeGuide` から切り出した）。
///
/// 入口は2つ: 撮影スポットの頁（作例つき）と、投稿のシートの「構図を重ねて撮る」（作例なし）。
/// どちらも同じ流れを通る:
/// 1. 確かめている間は入口を押せなくする（`checking`）。開いている・案内を出している間は開き直さない
///    （素早い2回押しで全画面が開き直し、カメラの開始・停止が二重になる・2026-10-10）
/// 2. Pro かどうかはサーバーのプロフィールで決める（`ComposeGuide.destination`）。
///    Pro なら撮る画面、そうでなければ Pro の案内、確かめられなければ知らせだけ
/// 3. 案内を閉じたときに「渡し終えた回数」が増えていれば Pro になったので、同じ頼みで開き直す
///    （`NameSideBadgeView` と同じ見分け方）
///
/// 撮る画面に渡すもの（作例の並び・始める1枚）は**開く時点で作る**（`make`）——案内を経て開き直すときも、
/// その時点の並びで作り直す（`ComposeGuide.Launch` の注記）。
@MainActor
final class ComposeGuideLauncher: ObservableObject {

    /// Pro かを確かめている最中（入口を押せなくする・回転を出す）
    @Published private(set) var checking = false
    /// 撮る画面を開く頼み（`fullScreenCover(item:)`）。nil なら閉じている
    @Published var launch: ComposeGuide.Launch?
    /// Pro の案内
    @Published var showPaywall = false

    /// 案内を経て開くときの頼み（案内で Pro になったら、これで開き直す）
    private var pending: (() -> ComposeGuide.Launch)?
    /// 案内を開いたときの「渡し終えた回数」
    private var deliveredAtPaywall = 0

    /// 押した結果（試験と、知らせを出すかの判断に使う）
    enum Outcome: Equatable {
        case opened
        case paywall
        /// Pro か確かめられなかった（圏外など）。呼ぶ側が知らせを出す
        case unreachable
        /// 確かめ中・開いている最中で何もしなかった
        case ignored
    }

    /// 入口を押した。
    /// - Parameters:
    ///   - previewUnlocked: 画面写真の試験の鍵（Debug のみ・`ComposeGuideAccess`）
    ///   - signedIn: ログインしているか
    ///   - deliveredRevision: いまの「渡し終えた回数」（`StoreService.deliveredRevision`）
    ///   - isPro: サーバーのプロフィールの `pro`（読めなければ nil）。ログインしていなければ呼ばない
    ///   - make: 撮る画面に渡す頼みを作る（開く時点で呼ぶ）
    @discardableResult
    func open(previewUnlocked: Bool, signedIn: Bool, deliveredRevision: Int,
              isPro: () async -> Bool?, make: @escaping () -> ComposeGuide.Launch) async -> Outcome {
        guard !checking, launch == nil, !showPaywall else { return .ignored }
        pending = make
        if previewUnlocked {
            launch = make()
            return .opened
        }
        checking = true
        defer { checking = false }
        let pro: Bool? = signedIn ? await isPro() : nil
        switch ComposeGuide.destination(signedIn: signedIn, isPro: pro) {
        case .camera:
            launch = make()
            return .opened
        case .paywall:
            deliveredAtPaywall = deliveredRevision
            showPaywall = true
            return .paywall
        case .unreachable:
            return .unreachable
        }
    }

    /// 案内を閉じた。Pro になっていれば（渡し終えた回数が増えた）、開き直す頼みを返す
    func paywallDismissed(deliveredRevision: Int) -> (() -> ComposeGuide.Launch)? {
        guard deliveredRevision != deliveredAtPaywall else { return nil }
        return pending
    }
}

/// 撮る画面と Pro の案内を出す（入口の画面に付ける）。案内で Pro になったら同じ頼みで開き直す
struct ComposeGuidePresenter: ViewModifier {

    @ObservedObject var launcher: ComposeGuideLauncher
    /// 撮影地の名前（作例なしの入口は nil）
    let spotName: String?
    /// 撮った1枚を投稿へ進める（投稿のシートの入口だけ）。nil なら「投稿する」を出さない
    var onPost: ((CameraCapture) -> Void)?
    /// 撮る画面を閉じきった
    var onDismiss: (() -> Void)?

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var toasts: ToastCenter

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $launcher.launch, onDismiss: { onDismiss?() }) { launch in
                ComposeGuideView(spotName: spotName, samples: launch.samples, startIndex: launch.start, onPost: onPost)
            }
            .fullScreenCover(isPresented: $launcher.showPaywall, onDismiss: {
                guard let make = launcher.paywallDismissed(deliveredRevision: store.deliveredRevision) else { return }
                Task { await ComposeGuidePresenter.request(launcher, make: make, auth: auth, store: store,
                                                           environment: environment, toasts: toasts) }
            }) {
                PaywallView()
            }
    }

    /// 入口から呼ぶ（環境のものを渡して `ComposeGuideLauncher.open` へ）
    static func request(_ launcher: ComposeGuideLauncher, make: @escaping () -> ComposeGuide.Launch,
                        auth: AuthStore, store: StoreService, environment: AppEnvironment,
                        toasts: ToastCenter) async {
        let profiles = environment.profiles
        let outcome = await launcher.open(previewUnlocked: ComposeGuideAccess.previewUnlocked,
                                          signedIn: auth.userId != nil,
                                          deliveredRevision: store.deliveredRevision,
                                          isPro: { (try? await profiles.myProfile())?.isPro },
                                          make: make)
        if outcome == .unreachable {
            toasts.show(Labels.Common.unreachable, kind: .failure)
        }
    }
}

extension View {
    /// 撮る画面と Pro の案内（`ComposeGuidePresenter`）
    func composeGuidePresenter(_ launcher: ComposeGuideLauncher, spotName: String?,
                               onPost: ((CameraCapture) -> Void)? = nil,
                               onDismiss: (() -> Void)? = nil) -> some View {
        modifier(ComposeGuidePresenter(launcher: launcher, spotName: spotName, onPost: onPost, onDismiss: onDismiss))
    }
}
