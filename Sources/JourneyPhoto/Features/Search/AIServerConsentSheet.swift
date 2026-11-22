import SwiftUI
import UIKit

/// サーバーの AI に初めて送る直前に1回だけ出す同意のシート（決まりは `AIServerConsent`・2026-11-22 判断）。
///
/// 写真の無い画面なので、板（DesignSystem「黒塗りの真鍮」）どおり、通知の説明（`PushPrimerView`）と同じ形にそろえる:
/// 地はシートの面（`WebTheme.sheet` #161617）、眉ラベルは真鍮、見出しは明朝、項目は本文 15 と 40 の角丸の箱の白い印、
/// 注記は 12 の text-3。主ボタンは真鍮の塗り（`accentFill`）に墨の「同意して続ける」、2番手は線のボタンの「やめる」（44）。
/// プライバシーポリシーのリンクは黒地の上の外へ出るリンクなので真鍮（出典と規約のリンクと同じ）
struct AIServerConsentSheet: View {

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
                    Text(AIServerConsentText.lead)
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
/// （`PhotoLibrary.presentLimitedPicker` と同じ探し方）。下へ払って閉じたら「やめる」と同じ（送らない）
@MainActor
enum AIServerConsentPresenter {

    static func present() async -> Bool {
        #if canImport(Darwin)
        guard let top = topController() else { return false }
        return await withCheckedContinuation { continuation in
            let once = Once(continuation)
            let host = UIHostingController(rootView: AnyView(EmptyView()))
            host.rootView = AnyView(AIServerConsentSheet(
                onAgree: { [weak host] in host?.dismiss(animated: true); once.finish(true) },
                onCancel: { [weak host] in host?.dismiss(animated: true); once.finish(false) }))
            host.view.backgroundColor = UIColor(WebTheme.sheet)
            host.modalPresentationStyle = .pageSheet
            if let sheet = host.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = JPRadius.xl
            }
            host.presentationController?.delegate = once
            top.present(host, animated: true)
        }
        #else
        return false
        #endif
    }

    #if canImport(Darwin)
    /// 答えを1回だけ返す（ボタンと払って閉じるの両方が来ても二度返さない）。払って閉じたら「やめる」
    private final class Once: NSObject, UIAdaptivePresentationControllerDelegate {
        private var continuation: CheckedContinuation<Bool, Never>?
        init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }
        func finish(_ ok: Bool) {
            continuation?.resume(returning: ok)
            continuation = nil
        }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { finish(false) }
    }

    private static func topController() -> UIViewController? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.isKeyWindow {
                var top = window.rootViewController
                while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
                return top
            }
        }
        return nil
    }
    #endif
}
