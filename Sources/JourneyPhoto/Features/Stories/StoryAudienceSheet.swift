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
/// 地は黒、行は共通の札（`JPCard`・v2 の surface-1）。トグルのオンは暗い真鍮（#796440）。
/// 写真の無いシートなので、主ボタン「決める」は accent-fill（#B8955A）に墨（owner の好み「白より真鍮」）。
struct StoryAudienceSheet: View {

    @Binding var allowReplies: Bool
    @Binding var keepInArchive: Bool
    /// 「撮影地の位置を付ける」（2026-10-18・投稿と同じ人ごとの覚え。書くのは作る画面）
    @Binding var attachesLocation: Bool
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("誰に見せる？", "Who can see it?"))
                .font(JPFont.cardTitle)
                .foregroundStyle(WebTheme.text)
                .padding(.top, 24)

            // 届く相手の説明（選ぶ口ではない・ラジオなし）
            HStack(spacing: 10) {
                Image(systemName: "person.2")
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.text2)
                    .accessibilityHidden(true)
                Text(L("フォロワーに届きます", "Goes to your followers"))
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.text)
            }
            .accessibilityElement(children: .combine)

            // v2: 共通の札と入切の行（`JPCard`・`JPToggleRow`・軌道は暗い真鍮）。返信を切ったら何が起きるかを一行で
            // （v2 StoryComposer の「切ると、見る人に返信欄と ♡ が出ません」）
            JPCard {
                JPToggleRow(title: L("返信を受け取る", "Receive replies"),
                            detail: L("切ると、見る人に返信欄と ♡ が出ません",
                                      "If off, viewers won't see the reply field or ♡"),
                            isOn: $allowReplies)
                JPCardDivider()
                // **ハイライトに入れられるのは残したものだけ**（`api-user/src/highlights.ts`）。既定は残さない
                JPToggleRow(title: L("24時間後も自分用に残す", "Keep for me after 24 hours"),
                            detail: L("ハイライトに入れられます", "You can add it to highlights"),
                            isOn: $keepInArchive)
                JPCardDivider()
                // 投稿の画面と同じ切り替え・同じ言葉（`UploadDetails`）。値も投稿と共有する
                JPToggleRow(title: UploadDetails.locationToggleTitle,
                            detail: StoryLocationText.toggleNote(attaches: attachesLocation),
                            isOn: $attachesLocation)
                    .accessibilityIdentifier("story.attachLocation")
            }

            Spacer(minLength: 8)

            Button(action: onDone) {
                Text(L("決める", "Done"))
                    // 写真の無いシートの主ボタンは accent-fill に墨（owner の好み「白より真鍮」・v2 の 50）
                    .jpPillButton(.main(onPhoto: false))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("story.audience.done")
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WebTheme.background)
    }
}
