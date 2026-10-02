import SwiftUI

/// 「誰に見せる？」のシート（ストーリー作成のかんたん版・owner 2026-10-02）。
///
/// 前は投稿画面の下に「フォロワーが見られます」の行と、スイッチ2つ（自分用に残す・返信を許可）が
/// 並んでいた。**それをここへ移した。** 値は投稿画面の状態そのもの（`keepInArchive`・`allowReplies`）で、
/// このシートは新しい値を持たない。
///
/// 🔴 **2026-10-02 判断: 範囲をサーバーが受け取るまで、親しい友達は出さない。**
/// ストーリーはフォロワーだけが見る作りで（2026-09-22・owner の判断。`api-user/src/storyVisibility.ts`）、
/// サーバーは公開範囲を受け取らない（`StoryService.createRecord`）。選べない行を出すと迷わせる
/// （かんたん版の狙いに反する）ので、「フォロワーに届きます」の説明1行だけにする。
/// サーバーが受けるようになったら、ここに選ぶ口を足して `CloseFriendsView` へつなぐ。
///
/// 地は黒、行の面は #121212 相当（`WebTheme.surface`）。トグルのオンは暗い真鍮（#796440）。
/// 写真の無いシートなので、主ボタン「決める」は accent-fill（#B8955A）に墨（owner の好み「白より真鍮」）。
struct StoryAudienceSheet: View {

    @Binding var allowReplies: Bool
    @Binding var keepInArchive: Bool
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("誰に見せる？", "Who can see it?"))
                .font(JPFont.display(22, relativeTo: .title2))
                .foregroundStyle(WebTheme.text)
                .padding(.top, 24)

            // 届く相手の説明（選ぶ口ではない・ラジオなし）
            HStack(spacing: 10) {
                Image(systemName: "person.2")
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.muted2)
                    .accessibilityHidden(true)
                Text(L("フォロワーに届きます", "Goes to your followers"))
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.text)
            }
            .accessibilityElement(children: .combine)

            VStack(spacing: 0) {
                toggleRow(title: L("返信を受け取る", "Receive replies"), detail: nil, isOn: $allowReplies)
                Divider().overlay(WebTheme.border)
                // **ハイライトに入れられるのは残したものだけ**（`api-user/src/highlights.ts`）。既定は残さない
                toggleRow(title: L("24時間後も自分用に残す", "Keep for me after 24 hours"),
                          detail: L("ハイライトに入れられます", "You can add it to highlights"),
                          isOn: $keepInArchive)
            }
            .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 14))

            Spacer(minLength: 8)

            Button(action: onDone) {
                Text(L("決める", "Done"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(WebTheme.accentText)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    // 写真の無いシートの主ボタンは accent-fill に墨（owner の好み「白より真鍮」）
                    .background(WebTheme.accentFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WebTheme.background)
    }

    private func toggleRow(title: String, detail: String?, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.text)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(WebTheme.muted2)
                }
            }
        }
        // **軌道は暗い真鍮。** 既定（白）だと白い軌道に白いつまみが乗る
        .tint(WebTheme.accentDeep)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 56)
    }
}
