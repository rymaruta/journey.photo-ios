import SwiftUI

/// 設定の「公開範囲とプライバシー」の1行: **AI への送信に同意する**（2026-11-22 判断・審査 5.1.2(i)・決まりは `AIServerConsent`）。
///
/// - オフにすると同意を取り消す。次にサーバーの AI へ送る前に、同意のシートでまた聞く
/// - オンにすると、送る前と同じ同意のシートを出す（ここで黙って同意にしない。何を送るかを読んでから決める）
/// - 確かめのダイアログは出さない（取り消しは戻せる操作。CLAUDE.md「聞く・選ばせるのは最小に」）
/// - 置き場は「検索エンジンにプロフィールを表示しない」の下（自分の情報をどこへ出すかの札）。入切は同じ `JPToggleRow`
struct AIServerConsentSettingRow: View {

    @ObservedObject private var consent = AIServerConsent.shared

    var body: some View {
        JPCardDivider()
        JPToggleRow(title: AIServerConsentText.settingTitle, detail: AIServerConsentText.settingDetail, isOn: binding)
            .accessibilityIdentifier("settings.aiConsent")
    }

    private var binding: Binding<Bool> {
        Binding(get: { consent.isAccepted }, set: { on in
            if on {
                Task { _ = await consent.request(.settings) }
            } else {
                consent.revoke()
            }
        })
    }
}
