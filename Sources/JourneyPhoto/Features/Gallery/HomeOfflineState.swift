import SwiftUI

/// ホームの「電波なし」（2026-11-12 判断・デザインの案 第2章「画面の状態とそろえ」・板 v2 Main）。
///
/// **電波が無くても一覧は消さない。** 前に見た写真（端末の控え）はそのまま出し、上に帯で知らせる
/// （今は読めないと一覧ごと中央の失敗に置き換わり、前に見た写真も見えなかった）。
/// 写真を見るまでの押す回数: 今 = 電波が戻るまで見られない → 0 回。読み直しは帯の「もう一度」1 回。
/// 確かめのダイアログは足さない。電波が戻れば押さなくても読み直す（`GalleryView` の `onChange`）
struct HomeOfflineBand: View {
    var isBusy = false
    let retry: () -> Void

    static var message: String { L("前に見た写真だけを出しています", "Showing photos you've already seen") }

    var body: some View {
        JPStateBand(kind: .offline, title: JPStateBand.offlineTitle, message: Self.message,
                    isBusy: isBusy, actionIdentifier: "home.offline.retry", action: retry)
            .padding(.horizontal, JPSpace.gutter)
            .padding(.top, JPSpace.s)
            .padding(.bottom, JPSpace.xs)
            .accessibilityIdentifier("home.offline.band")
    }
}

/// 電波が無く、**前に見た写真も1枚も無い**ときだけの中央の状態（消えた電波の印・見出し・説明・もう一度）
struct HomeOfflineState: View {
    var isBusy = false
    let retry: () -> Void

    static var message: String {
        L("前に見た写真もまだありません。電波の届く所で開くと並びます",
          "There are no saved photos yet. Open the app where you have a signal to see them.")
    }

    var body: some View {
        VStack(spacing: JPSpace.s) {
            JPStateIcon(symbol: JPStateIcon.offline)
            Text(JPStateBand.offlineTitle)
                .font(JPFont.stateTitle)
                .foregroundStyle(WebTheme.text)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(Self.message)
                .font(JPFont.body)
                .foregroundStyle(WebTheme.muted2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            RetryButton(isBusy: isBusy, action: retry)
                .padding(.top, JPSpace.xs)
        }
        .padding(.horizontal, JPSpace.xl)
        .padding(.top, JPSpace.emptyTop)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("home.offline.state")
    }
}
