import SwiftUI
import UIKit

/// サーバーの AI に初めて送る直前に1回だけ出す同意のシート（決まりは `AIServerConsent`・2026-11-22 判断）。
///
/// 写真の無い画面なので、板（DesignSystem「黒塗りの真鍮」）どおり、通知の説明（`PushPrimerView`）と同じ形にそろえる:
/// 地はシートの面（`WebTheme.sheet` #161617）、眉ラベルは真鍮、見出しは明朝、項目は本文 15 と 40 の角丸の箱の白い印、
/// 注記は 12 の text-3。主ボタンは真鍮の塗り（`accentFill`）に墨の「同意して続ける」、2番手は線のボタンの「やめる」（44）。
/// プライバシーポリシーのリンクは黒地の上の外へ出るリンクなので真鍮（出典と規約のリンクと同じ）
struct AIServerConsentSheet: View {

    /// どこから聞くか（頭の文を言い分ける）
    var context: AIServerConsent.Context = .send
    let onAgree: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JPSpace.l) {
                VStack(alignment: .leading, spacing: JPSpace.xs) {
                    Text(AIServerConsentText.eyebrow)
                        .jpEyebrow()
                        .foregroundStyle(WebTheme.accent)
                    Text(AIServerConsentText.title)
                        .font(JPFont.cardTitle)
                        .foregroundStyle(WebTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("aiConsent.title")
                    Text(AIServerConsentText.lead(context))
                        .font(JPFont.body)
                        .foregroundStyle(WebTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: JPSpace.m) {
                    point("text.bubble", AIServerConsentText.askItem)
                    point("map", AIServerConsentText.tripItem)
                    point("lock", AIServerConsentText.notSentItem)
                }
                VStack(alignment: .leading, spacing: JPSpace.xxs) {
                    Text(AIServerConsentText.revokeNote)
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                    Link(destination: LegalConsent.privacyURL) {
                        Text(AIServerConsentText.privacyLink)
                            .font(JPFont.footnote)
                            .underline()
                            .foregroundStyle(WebTheme.accent)
                            .frame(minHeight: WebTheme.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("aiConsent.privacy")
                }
            }
            .padding(.horizontal, JPSpace.xl)
            .padding(.top, JPSpace.section)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: JPSpace.xs) {
                Button(action: onAgree) {
                    Text(AIServerConsentText.agree).jpPillButton(.accent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("aiConsent.agree")
                Button(action: onCancel) {
                    Text(AIServerConsentText.cancel).jpPillButton(.outline)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("aiConsent.cancel")
            }
            .padding(.horizontal, JPSpace.xl)
            .padding(.top, JPSpace.xs)
            .padding(.bottom, JPSpace.xs)
            .background(WebTheme.sheet)
        }
        .scrollContentBackground(.hidden)
        .background(WebTheme.sheet, ignoresSafeAreaEdges: .all)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("aiConsent.sheet")
    }

    private func point(_ systemImage: String, _ text: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .foregroundStyle(WebTheme.foreground)
                .frame(width: PushPrimerLayout.iconTile, height: PushPrimerLayout.iconTile)
                .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: JPRadius.field))
                .accessibilityHidden(true)
            Text(text)
                .font(JPFont.body)
                .foregroundStyle(WebTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 同意のシートを、いちばん上に出ている画面の上に出して答えを待つ（2026-11-22 判断）。
///
/// サーバーへ送る道は、AI に頼むの全画面、旅行プランの頼みのシート、組み直しのシート、裏で作る旅行プラン（`TripAIJobs`）と
/// 置き場がばらばらで、SwiftUI の `.sheet` を1か所に付けるとシートの上に出せない。UIKit でいちばん上の画面から出す
/// （`PhotoLibrary.presentLimitedPicker` と同じ探し方）。
///
/// **返事は必ず1回返す**（2026-11-22 確かめ役の指摘: 返らないと `AIServerConsent` の待ちが残り、AI の道が全部止まる）:
/// - ボタン（同意して続ける、やめる）、下へ払って閉じた（やめると同じ）
/// - 下の画面ごとプログラムで閉じられた（払った知らせは来ない）→ 消えたときに見る（`ConsentHost.viewDidDisappear`・`gone`）
/// - 出し損ねた（最前面が別のものを出している途中など）→ 出し終わりと 1 秒後に、出ていなければ「やめる」
/// - 最前面が出る途中、閉じる途中なら少し待って探し直す（`settleTries` 回まで。落ち着かなければ「やめる」）
/// - それでも返らなければ `AIServerConsent.answerTimeout` で解ける
@MainActor
enum AIServerConsentPresenter {

    /// 最前面が出る途中、閉じる途中のとき、探し直す回数と間（合わせて約 1.5 秒）
    static let settleTries = 15
    static let settleInterval: UInt64 = 100_000_000

    /// 消えたシートが「もう戻らない」か（閉じられた、下の画面ごと閉じられた）。別の画面が上に出ただけなら false
    nonisolated static func gone(isBeingDismissed: Bool, hasPresenter: Bool, presenterDismissing: Bool) -> Bool {
        isBeingDismissed || !hasPresenter || presenterDismissing
    }

    /// 最前面を探し直すか: 最前面が出る途中、閉じる途中、最前面より上に閉じる途中の画面がある（探すときに飛ばした）、
    /// 最前面が動きの途中（`transitionCoordinator` がある）。2026-11-22 確かめ役の指摘: 頼みのシートが閉じる途中だと
    /// 最前面はその下で止まり、すぐ出して UIKit に断られていた（利用者はシートを見ないまま「AI に送らなかった」になる）
    nonisolated static func mustSettle(isBeingPresented: Bool, isBeingDismissed: Bool,
                                       skippedDismissing: Bool = false, inTransition: Bool = false) -> Bool {
        isBeingPresented || isBeingDismissed || skippedDismissing || inTransition
    }

    static func present(_ context: AIServerConsent.Context, handle: AIConsentSheetHandle) async -> Bool {
        #if canImport(Darwin)
        var found = topController()
        var tries = 0
        while let f = found, mustSettle(isBeingPresented: f.top.isBeingPresented, isBeingDismissed: f.top.isBeingDismissed,
                                        skippedDismissing: f.skippedDismissing, inTransition: f.top.transitionCoordinator != nil) {
            guard tries < settleTries else { return false }
            tries += 1
            try? await Task.sleep(nanoseconds: settleInterval)
            found = topController()
        }
        guard let top = found?.top else { return false }
        return await withCheckedContinuation { continuation in
            let once = AIConsentOnce(continuation)
            let delegate = DismissDelegate(once)
            let host = ConsentHost(rootView: AnyView(EmptyView()))
            host.keep = delegate
            host.onGone = { handle.close = nil; once.finish(false) }
            // 時間切れなど、ボタン以外の理由で返事を返したときに閉じる口（`AIServerConsent.request`）
            handle.close = { [weak host] in host?.dismiss(animated: true) }
            host.rootView = AnyView(AIServerConsentSheet(
                context: context,
                onAgree: { [weak host] in handle.close = nil; host?.dismiss(animated: true); once.finish(true) },
                onCancel: { [weak host] in handle.close = nil; host?.dismiss(animated: true); once.finish(false) }))
            host.view.backgroundColor = UIColor(WebTheme.sheet)
            host.modalPresentationStyle = .pageSheet
            if let sheet = host.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = JPRadius.xl
            }
            host.presentationController?.delegate = delegate
            top.present(host, animated: true) { [weak host] in
                if host?.presentingViewController == nil { handle.closeIfOpen(); once.finish(false) }
            }
            // 出し損ねると UIKit は出し終わりを呼ばないことがある。1 秒後に出ていなければ「やめる」
            Task { @MainActor [weak host] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !once.isDone else { return }
                if host == nil || host?.presentingViewController == nil {
                    // 遅れて出てきても残さない
                    handle.closeIfOpen()
                    once.finish(false)
                }
            }
        }
        #else
        return false
        #endif
    }

    #if canImport(Darwin)
    /// 下へ払って閉じたら「やめる」
    private final class DismissDelegate: NSObject, UIAdaptivePresentationControllerDelegate {
        private let once: AIConsentOnce
        init(_ once: AIConsentOnce) { self.once = once }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            once.finish(false)
        }
    }

    /// 消えたときに、閉じられたかを見る（下の画面ごと閉じられると、払った知らせは来ない）
    private final class ConsentHost: UIHostingController<AnyView> {
        var onGone: (() -> Void)?
        /// 払った知らせの受け手を持っておく（`presentationController.delegate` は弱い参照）
        var keep: AnyObject?
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            let parentDismissing = presentingViewController?.isBeingDismissed ?? false
            if AIServerConsentPresenter.gone(isBeingDismissed: isBeingDismissed, hasPresenter: presentingViewController != nil,
                                             presenterDismissing: parentDismissing) {
                onGone?()
                return
            }
            // 閉じる動きの直後は、まだ下の画面を指していることがある。次の回で外れていれば閉じられた
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.presentingViewController == nil { self.onGone?() }
            }
        }
    }

    /// いちばん上の画面と、その上に閉じる途中の画面があって飛ばしたか
    private static func topController() -> (top: UIViewController, skippedDismissing: Bool)? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.isKeyWindow {
                guard var top = window.rootViewController else { return nil }
                while let next = top.presentedViewController {
                    if next.isBeingDismissed { return (top, true) }
                    top = next
                }
                return (top, false)
            }
        }
        return nil
    }
    #endif
}
