import SwiftUI

/// 設定の「お知らせ」の札（プッシュ通知の入切と、許可されていないときの注記）。
///
/// 2026-11-18 判断（案 B7・owner「まかせる」）: お知らせ（ベル）の画面の歯車から、設定のいちばん上ではなく
/// **お知らせの入切だけの画面**（`NotificationSettingsPage`）を開く。設定の画面と同じ札を2か所で使うので、
/// 入切の状態と処理を `SettingsView` からここへ移した（写しを作らない）。
/// 種類ごとの入切（あなたの旅／コメント、返信、フォロー／いいね・板 Settings）はサーバーに利用者ごとの好みが要るので、
/// まだ無い（作るときはこの札に足す）
struct PushSettingsGroup: View {

    /// 眉ラベル（設定の画面では「お知らせ」。お知らせだけの画面では題と重なるので nil）
    let title: String?

    @EnvironmentObject private var push: PushCenter
    @State private var wantsPush = false
    @State private var showDeniedHint = false
    /// 切り替えている最中。二度押しで登録と解除が交差しないようにする
    @State private var isApplying = false

    var body: some View {
        SettingsGroup(title) {
            JPToggleRow(title: L("プッシュ通知を受け取る", "Push notifications"),
                        detail: L("いいね、コメント、フォロー、ストーリーへの返信を、アプリを開いていなくても受け取れます。",
                                  "Get likes, comments, follows and story replies even when the app is closed."),
                        isOn: pushBinding)
                .disabled(isApplying)
                .accessibilityIdentifier("settings.push")
            if showDeniedHint {
                // **端末の許可は取り消せない。** 断られたあとは設定アプリへ
                // 行ってもらうしかない——黙って戻るだけだと「押しても何も
                // 起きない」に見える
                JPCardDivider()
                note(L("この端末で通知が許可されていません。iPhone の「設定 → 通知 → Journey Photo」から許可してください。",
                       "Notifications are off for this device. Allow them in Settings → Notifications → Journey Photo."),
                     color: WebTheme.text3)
            }
            if let message = push.errorMessage {
                JPCardDivider()
                note(message, color: WebTheme.danger)
            }
        }
        .task {
            await push.refreshAuthorization()
            // **本人の意思で見る。** 「預けられたか」で見ると、
            // シミュレータや圏外では必ず false になり、画面に入り直す
            // たびにオフへ戻る。端末の許可だけで見ると、オフにしたのに
            // 復活する（OS の許可は残る）
            wantsPush = push.isEnabled && push.isAuthorized
        }
        // **iOS の設定で許可を変えて戻ったら合わせ直す。** 開いたまま通知を切って戻ると、
        // 前面に戻ったときの読み直しで `isAuthorized` は倒れるのに、トグルが「入」のまま残った。
        // 切り替えの最中（`isApplying`）は `apply` が決めるので触らない。
        // 案内どおり許可して戻ったら、「許可されていません」の案内も下ろす
        .onChange(of: push.isAuthorized) { _, authorized in
            guard !isApplying else { return }
            wantsPush = push.isEnabled && authorized
            if authorized { showDeniedHint = false }
        }
        // **ほかの所から「受け取る」にしたときも合わせる**（Pro の「前の晩に知らせる」の
        // 「通知がオフのため届きません」を押した・2026-10-11）。端末の許可が前から
        // あると `isAuthorized` は変わらず、上だけではトグルが「切」のまま残る
        .onChange(of: push.isEnabled) { _, enabled in
            guard !isApplying else { return }
            wantsPush = enabled && push.isAuthorized
        }
    }

    /// 受け取る／受け取らないの切り替え。
    ///
    /// **`onChange` で拾わない。** 画面側から `wantsPush` を戻したときにも
    /// 発火し、**許可した直後に自分でオフへ戻す**（`enable()` の返りは APNs の
    /// トークンより先に来る）。押された瞬間だけを受ける形にする
    private var pushBinding: Binding<Bool> {
        Binding(get: { wantsPush },
                set: { on in
                    // **門は同期で閉じる。** `Task` の中で立てると、連打の
                    // 2発目が来る時点ではまだ開いている
                    guard !isApplying else { return }
                    isApplying = true
                    wantsPush = on
                    Task { await apply(on: on) }
                })
    }

    /// 受け取る／受け取らないを切り替える。
    /// 押されたあとの本体（門は呼ぶ側で閉じてある）。
    private func apply(on: Bool) async {
        showDeniedHint = false
        defer { isApplying = false }
        if on {
            // **許可されたかだけで決める。** 宛先を預け終えたかで見ると、
            // APNs のトークンは少し遅れて届くので**必ず false になる**
            // ——押した直後に自分でオフへ戻る
            let granted = await push.enable()
            wantsPush = granted
            showDeniedHint = !granted
        } else {
            await push.disable()
            wantsPush = false
        }
    }

    /// 札の中の注記（行ではない1文）
    private func note(_ text: String, color: Color) -> some View {
        Text(text)
            .font(JPFont.caption)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, JPSpace.s)
    }
}

/// お知らせ（ベル）の画面の歯車から開く、お知らせの入切だけの画面（2026-11-18 判断・案 B7）。
/// 前は設定のいちばん上（Pro の節）が開き、入切を探して下へ送る必要があった。設定の下の画面と同じ入れ物（`SettingsPage`）
struct NotificationSettingsPage: View {
    var body: some View {
        SettingsPage(SettingsOutline.Part.notifications.title ?? L("お知らせ", "Activity")) {
            PushSettingsGroup(title: nil)
        }
    }
}
